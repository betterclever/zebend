//! Chain data: Sapling leaves + nullifiers (sync), subtree roots, tree states, Rust tree rebuild.

use std::{
    collections::BTreeMap,
    fs::{self, File, OpenOptions},
    io::{BufWriter, Write},
    path::Path,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
    time::Instant,
};

use anyhow::{anyhow, ensure, Result};
use incrementalmerkletree::{frontier::CommitmentTree, frontier::Frontier, Hashable, Level};
use sapling::Node;

use crate::lwd::{self, Lwd, POOL_SAPLING, PROTO_SAPLING};
use crate::DATA;

pub async fn meta(h: u64) -> Result<()> {
    let mut l = Lwd::any().await?;
    for b in l.blocks(h, h, vec![POOL_SAPLING]).await? {
        let m = b.chain_metadata.clone().unwrap_or_default();
        let outs: usize = b.vtx.iter().map(|t| t.outputs.len()).sum();
        let spends: usize = b.vtx.iter().map(|t| t.spends.len()).sum();
        println!(
            "height {} sapling_size {} orchard_size {} txs {} outputs {outs} spends {spends} header_len {} hash {}",
            b.height,
            m.sapling_commitment_tree_size,
            m.orchard_commitment_tree_size,
            b.vtx.len(),
            b.header.len(),
            hex::encode(&b.hash)
        );
    }
    Ok(())
}

struct Chunk {
    s: u64,
    start_size: u64,
    end_size: u64,
    leaves: Vec<u8>,
    nfs: Vec<u8>,
}

fn chunk_of(s: u64, e: u64, blocks: &[lwd::CompactBlock]) -> Result<Chunk> {
    ensure!(blocks.len() as u64 == e - s + 1, "block count");
    let (mut leaves, mut nfs) = (vec![], vec![]);
    let mut start_size = None;
    let mut size = 0u64;
    for (i, b) in blocks.iter().enumerate() {
        ensure!(b.height == s + i as u64, "non-contiguous heights at {}", b.height);
        let m = b.chain_metadata.as_ref().ok_or_else(|| anyhow!("no chain metadata at {}", b.height))?;
        let mut n = 0u64;
        for tx in &b.vtx {
            for sp in &tx.spends {
                ensure!(sp.nf.len() == 32, "bad nf at {}", b.height);
                nfs.extend_from_slice(&(b.height as u32).to_le_bytes());
                nfs.extend_from_slice(&sp.nf);
            }
            for o in &tx.outputs {
                ensure!(o.cmu.len() == 32, "bad cmu at {}", b.height);
                leaves.extend_from_slice(&(b.height as u32).to_le_bytes());
                leaves.extend_from_slice(&o.cmu);
                n += 1;
            }
        }
        let after = m.sapling_commitment_tree_size as u64;
        match start_size {
            None => {
                ensure!(after >= n, "tree size {after} < outputs {n} at {}", b.height);
                start_size = Some(after - n);
            }
            Some(_) => ensure!(after == size + n, "tree size {after} != {size} + {n} at {}", b.height),
        }
        size = after;
    }
    Ok(Chunk { s, start_size: start_size.unwrap(), end_size: size, leaves, nfs })
}

/// Resumable, chunk-atomic, concurrent sync. Progress in sapling_sync.progress: "next_height leaves nfs".
pub async fn sync(from: u64, to: u64, workers: usize) -> Result<()> {
    let dir = Path::new(DATA);
    let (lp, np, pp) = (dir.join("sapling_leaves.bin"), dir.join("sapling_nfs.bin"), dir.join("sapling_sync.progress"));
    let (mut next, mut count, mut nnf) = (from, 0u64, 0u64);
    if let Ok(s) = fs::read_to_string(&pp) {
        let v: Vec<u64> = s.split_whitespace().map(|x| x.parse().unwrap()).collect();
        (next, count, nnf) = (v[0], v[1], v[2]);
        eprintln!("resuming at {next}: {count} leaves, {nnf} nullifiers");
    } else {
        let _ = fs::remove_file(&lp);
        let _ = fs::remove_file(&np);
    }
    OpenOptions::new().create(true).write(true).open(&lp)?.set_len(count * 36)?;
    OpenOptions::new().create(true).write(true).open(&np)?.set_len(nnf * 36)?;
    let mut lf = OpenOptions::new().append(true).open(&lp)?;
    let mut nf = OpenOptions::new().append(true).open(&np)?;
    let step: u64 = std::env::var("STEP").ok().and_then(|s| s.parse().ok()).unwrap_or(2000);
    let first = next;
    let nchunks = if to >= first { (to - first) / step + 1 } else { 0 };
    let ctr = Arc::new(AtomicU64::new(0));
    let written = Arc::new(AtomicU64::new(0));
    let (tx, mut rx) = tokio::sync::mpsc::channel::<Result<Chunk>>(64);
    for w in 0..workers {
        let (ctr, written, tx) = (ctr.clone(), written.clone(), tx.clone());
        tokio::spawn(async move {
            loop {
                let k = ctr.fetch_add(1, Ordering::SeqCst);
                if k >= nchunks {
                    return;
                }
                while k > written.load(Ordering::SeqCst) + 4 * workers as u64 {
                    tokio::time::sleep(std::time::Duration::from_millis(200)).await;
                }
                let s = first + k * step;
                let e = (s + step - 1).min(to);
                let r = match lwd::blocks_retry(s, e, vec![POOL_SAPLING], w).await {
                    Ok(b) => chunk_of(s, e, &b),
                    Err(e) => Err(e),
                };
                if tx.send(r).await.is_err() {
                    return;
                }
            }
        });
    }
    drop(tx);
    let t = Instant::now();
    let mut pending: BTreeMap<u64, Chunk> = BTreeMap::new();
    let mut done = 0u64;
    while let Some(r) = rx.recv().await {
        let c = r?;
        pending.insert(c.s, c);
        while let Some(c) = pending.remove(&next) {
            ensure!(c.start_size == count, "chunk at {} starts at tree size {} but we have {count} leaves", c.s, c.start_size);
            lf.write_all(&c.leaves)?;
            nf.write_all(&c.nfs)?;
            lf.sync_data()?;
            nf.sync_data()?;
            count = c.end_size;
            nnf += c.nfs.len() as u64 / 36;
            next = (c.s + step).min(to + 1);
            fs::write(&pp, format!("{next} {count} {nnf}\n"))?;
            done += 1;
            written.store(done, Ordering::SeqCst);
            if done % 25 == 0 || next > to {
                eprintln!("..{}: {count} leaves (= chain tree size), {nnf} nfs, {:.0}s", next - 1, t.elapsed().as_secs_f64());
            }
        }
    }
    ensure!(next == to + 1, "sync stopped at {next}");
    println!("synced through {to}: {count} leaves, {nnf} nullifiers");
    Ok(())
}

pub async fn subtrees() -> Result<()> {
    let mut l = Lwd::any().await?;
    let roots = l.subtree_roots(PROTO_SAPLING).await?;
    let mut out = BufWriter::new(File::create(Path::new(DATA).join("sapling_subtrees.txt"))?);
    for (i, r) in roots.iter().enumerate() {
        writeln!(out, "{i} {} {}", r.completing_block_height, hex::encode(&r.root_hash))?;
    }
    out.flush()?;
    println!("{} sapling subtree roots", roots.len());
    Ok(())
}

pub fn parse_tree(hex_tree: &str) -> Result<CommitmentTree<Node, 32>> {
    let bytes = hex::decode(hex_tree)?;
    if bytes.is_empty() {
        return Ok(CommitmentTree::empty());
    }
    let mut r = bytes.as_slice();
    fn take<'a>(r: &mut &'a [u8], n: usize) -> Result<&'a [u8]> {
        ensure!(r.len() >= n, "short tree state");
        let (a, b) = r.split_at(n);
        *r = b;
        Ok(a)
    }
    fn node(r: &mut &[u8]) -> Result<Option<Node>> {
        match take(r, 1)?[0] {
            0 => Ok(None),
            1 => Ok(Some(Option::from(Node::from_bytes(take(r, 32)?.try_into()?)).ok_or_else(|| anyhow!("bad node"))?)),
            f => Err(anyhow!("bad flag {f}")),
        }
    }
    let left = node(&mut r)?;
    let right = node(&mut r)?;
    let n = take(&mut r, 1)?[0] as usize;
    ensure!(n < 253, "large parent count");
    let parents = (0..n).map(|_| node(&mut r)).collect::<Result<Vec<_>>>()?;
    ensure!(r.is_empty(), "trailing tree bytes");
    CommitmentTree::from_parts(left, right, parents).map_err(|_| anyhow!("malformed tree"))
}

/// GetTreeState at each height -> "height size roothex" (plus the block's final sapling root
/// from the compact block header, when the server includes the header).
pub async fn trees(hs: &[u64]) -> Result<()> {
    let mut l = Lwd::any().await?;
    let mut out = BufWriter::new(File::create(Path::new(DATA).join("sapling_trees.txt"))?);
    for &h in hs {
        let ts = l.tree_state(h).await?;
        let tree = parse_tree(&ts.sapling_tree)?;
        let root = hex::encode(tree.root().to_bytes());
        let b = l.blocks(h, h, vec![POOL_SAPLING]).await?;
        let hdr = b.first().map(|b| b.header.clone()).unwrap_or_default();
        // header: version 4 | prev 32 | merkle 32 | hashFinalSaplingRoot 32 (LE, as the hash) ...
        let fsr = if hdr.len() >= 100 { hex::encode(&hdr[68..100]) } else { "-".into() };
        let chk = if fsr == "-" { "nohdr" } else if fsr == root { "header_match" } else { "HEADER_MISMATCH" };
        writeln!(out, "{} {} {root}", ts.height, tree.size())?;
        println!("{} {} {root} {chk}", ts.height, tree.size());
    }
    out.flush()?;
    Ok(())
}

/// Rebuild the Sapling tree from sapling_leaves.bin in Rust (single thread, Frontier<Node,32>);
/// check every level-16 subtree root and every tree-state root; print timings.
pub fn rebuild() -> Result<()> {
    let dir = Path::new(DATA);
    let len = fs::metadata(dir.join("sapling_leaves.bin"))?.len() as usize;
    ensure!(len % 36 == 0);
    let n = len / 36;
    let t0 = Instant::now();
    // streamed decode (the 2.7 GB file is never held in memory next to the decoded leaves)
    let mut leaves: Vec<(u32, Node)> = Vec::with_capacity(n);
    {
        use std::io::Read;
        let mut r = std::io::BufReader::with_capacity(1 << 22, File::open(dir.join("sapling_leaves.bin"))?);
        let mut rec = [0u8; 36];
        for _ in 0..n {
            r.read_exact(&mut rec)?;
            leaves.push((u32::from_le_bytes(rec[0..4].try_into().unwrap()), Option::from(Node::from_bytes(rec[4..36].try_into().unwrap())).expect("non-canonical cmu")));
        }
    }
    eprintln!("decoded {n} leaves in {:.2}s", t0.elapsed().as_secs_f64());
    let subs: Vec<(u64, String)> = fs::read_to_string(dir.join("sapling_subtrees.txt"))
        .unwrap_or_default()
        .lines()
        .map(|l| {
            let v: Vec<&str> = l.split_whitespace().collect();
            (v[1].parse().unwrap(), v[2].to_string())
        })
        .collect();
    let trees: Vec<(u64, u64, String)> = fs::read_to_string(dir.join("sapling_trees.txt"))
        .unwrap_or_default()
        .lines()
        .map(|l| {
            let v: Vec<&str> = l.split_whitespace().collect();
            (v[0].parse().unwrap(), v[1].parse().unwrap(), v[2].to_string())
        })
        .collect();

    // (a) level-16 subtree roots: each full 2^16 block of leaves hashed bottom-up with
    // sapling's MerkleCRH (Node::combine), one subtree per task; 1 thread and 18 threads.
    use rayon::prelude::*;
    let sub_root = |c: &[(u32, Node)]| -> Node {
        let mut lvl: Vec<Node> = c.iter().map(|x| x.1).collect();
        for l in 0..16u8 {
            lvl = lvl.chunks(2).map(|p| Node::combine(Level::from(l), &p[0], &p[1])).collect();
        }
        lvl[0]
    };
    let full: Vec<&[(u32, Node)]> = leaves.chunks(1 << 16).filter(|c| c.len() == 1 << 16).collect();
    let mut chunk_roots = vec![];
    let thread_list: Vec<usize> = if std::env::var("FRONTIER_ONLY").is_ok() { vec![] } else { vec![1, 18] };
    for threads in thread_list {
        let pool = rayon::ThreadPoolBuilder::new().num_threads(threads).build()?;
        let t = Instant::now();
        chunk_roots = pool.install(|| full.par_iter().map(|c| sub_root(c)).collect::<Vec<Node>>());
        println!("level-16 subtree roots: {} subtrees, {threads} thread(s): {:.2}s", chunk_roots.len(), t.elapsed().as_secs_f64());
    }
    let mut sub_ok = 0;
    for (i, r) in chunk_roots.iter().enumerate() {
        if let Some((_, want)) = subs.get(i) {
            ensure!(&hex::encode(r.to_bytes()) == want, "subtree {i} root mismatch");
            sub_ok += 1;
        }
    }
    println!("{sub_ok} of {} computed subtree roots match the chain's GetSubtreeRoots ({} listed)", chunk_roots.len(), subs.len());

    // (b) full append-only Frontier rebuild with root checks at tree-state heights.
    let t = Instant::now();
    let mut f = Frontier::<Node, 32>::empty();
    let mut checks = trees.iter().filter(|x| x.1 > 0).peekable();
    let mut tree_ok = 0;
    for (i, (h, leaf)) in leaves.iter().enumerate() {
        f.append(*leaf);
        let last_of_block = leaves.get(i + 1).map_or(true, |n| n.0 != *h);
        if last_of_block {
            while let Some((th, ts, root)) = checks.peek() {
                if (i + 1) as u64 == *ts && *h as u64 <= *th {
                    ensure!(&hex::encode(f.root().to_bytes()) == root, "tree root mismatch at height {th}");
                    tree_ok += 1;
                    checks.next();
                } else if *ts <= (i + 1) as u64 {
                    checks.next(); // size beyond; reported as unchecked
                } else {
                    break;
                }
            }
        }
    }
    let t_full = t.elapsed().as_secs_f64();
    println!("frontier rebuild: {n} leaves in {t_full:.2}s single-thread ({:.0} leaves/s); final root {}; {tree_ok} tree-state roots matched", n as f64 / t_full, hex::encode(f.root().to_bytes()));
    let _ = Node::empty_root(Level::from(32));
    Ok(())
}
