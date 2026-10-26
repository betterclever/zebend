//! tv-oracle: ground truth for Zebend's transparent-input validation.
//!
//!   tv-oracle check FILE.ztv                 expect lines (r <k> <verdicts>) to stdout
//!   tv-oracle annotate FILE.ztv...           (re)write .expect/.sighash/.meta next to each file
//!   tv-oracle stats DIR...                   recompute verdicts and print data-set statistics
//!   tv-oracle bench DIR...                   oracle throughput, 1 thread and all threads
//!   tv-oracle tip | hashes H...              lightwalletd: tip height / block hash per height
//!   tv-oracle count CAP BLOCK...             per block: inputs that build would take
//!   tv-oracle build ERA OUTDIR CACHEDIR CAP LIST   records from full blocks ("height path" lines)
//!   tv-oracle tamper SEED N OUTDIR FILE.ztv...     one-mutation records with recomputed verdicts
mod lwd;
mod oracle;
mod raw;
mod tamper;

use anyhow::{anyhow, bail, ensure, Context, Result};
use rayon::prelude::*;
use raw::{Prev, Record};
use std::collections::{BTreeMap, HashMap};
use std::path::{Path, PathBuf};
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::{BranchId, MAIN_NETWORK};

pub const MAINNET_FLAGS: u32 = 1 | 512; // P2SH | CHECKLOCKTIMEVERIFY

/// Split a raw block into raw transactions (lengths found by zcash_primitives' parser).
fn block_txs(blk: &[u8], height: u32) -> Result<Vec<Vec<u8>>> {
    let mut p = 140;
    let sl = raw::read_cs(blk, &mut p)? as usize;
    p += sl;
    let n = raw::read_cs(blk, &mut p)? as usize;
    let branch = BranchId::for_height(&MAIN_NETWORK, height.into());
    let mut out = Vec::with_capacity(n);
    for _ in 0..n {
        let mut cur = std::io::Cursor::new(&blk[p..]);
        Transaction::read(&mut cur, branch).map_err(|e| anyhow!("block {height}: tx parse: {e}"))?;
        let len = cur.position() as usize;
        out.push(blk[p..p + len].to_vec());
        p += len;
    }
    ensure!(p == blk.len(), "block {height}: trailing bytes");
    Ok(out)
}

/// The txs of a block that the data set takes: non-coinbase with >= 1 transparent input,
/// in block order, skipping any tx that would push the block past `cap` inputs.
fn select(txs: &[Vec<u8>], cap: usize) -> (Vec<(Vec<u8>, raw::Layout)>, usize, usize) {
    let (mut sel, mut taken, mut skipped_txs, mut skipped_ins) = (vec![], 0, 0, 0);
    for t in txs.iter().skip(1) {
        let lay = match raw::layout(t) {
            Ok(l) => l,
            Err(_) => continue,
        };
        if lay.vin.is_empty() || lay.is_coinbase() {
            continue;
        }
        if taken + lay.vin.len() > cap {
            skipped_txs += 1;
            skipped_ins += lay.vin.len();
            continue;
        }
        taken += lay.vin.len();
        sel.push((t.clone(), lay));
    }
    (sel, skipped_txs, skipped_ins)
}

fn ztv_files(args: &[String]) -> Result<Vec<PathBuf>> {
    let mut v = vec![];
    for a in args {
        let p = PathBuf::from(a);
        if p.is_dir() {
            for e in std::fs::read_dir(&p)? {
                let e = e?.path();
                if e.extension().map_or(false, |x| x == "ztv") {
                    v.push(e);
                }
            }
        } else {
            v.push(p);
        }
    }
    v.sort();
    Ok(v)
}

fn sig_hash_types(sig: &[u8]) -> Vec<u8> {
    // Hash-type bytes of DER-looking signature pushes in a scriptSig.
    let mut v = vec![];
    if let Ok(ops) = raw::parse_ops(sig) {
        for o in ops {
            if let Some((off, len)) = o.data {
                if (9..=73).contains(&len) && sig[off] == 0x30 && sig[off + 1] as usize == len - 3 {
                    v.push(sig[off + len - 1]);
                }
            }
        }
    }
    v
}

fn annotate(path: &Path) -> Result<(usize, usize, usize)> {
    let recs = raw::read_file(path)?;
    let outs: Vec<_> = recs.par_iter().map(oracle::check).collect();
    let (mut e, mut s, mut m) = (String::new(), String::new(), String::new());
    let (mut n_in, mut n_ok) = (0, 0);
    for (k, (r, o)) in recs.iter().zip(&outs).enumerate() {
        e += &oracle::expect_line(k, o);
        e.push('\n');
        oracle::sighash_lines(k, o, &mut s);
        let types: String = match raw::layout(&r.tx) {
            Ok(_) => r.prevs.iter().map(|p| raw::spk_letter(&p.spk)).collect(),
            Err(_) => "?".into(),
        };
        m += &format!("r {k} h {} v {} txid {} types {}", r.height, o.version, o.txid, types);
        if let Some(err) = &o.tx_error {
            m += &format!(" txerror {}", err.replace(' ', "_"));
        }
        m.push('\n');
        n_in += o.ok.len();
        n_ok += o.ok.iter().filter(|&&b| b).count();
    }
    std::fs::write(path.with_extension("expect"), e)?;
    std::fs::write(path.with_extension("sighash"), s)?;
    std::fs::write(path.with_extension("meta"), m)?;
    Ok((recs.len(), n_in, n_ok))
}

pub fn write_chunks(outdir: &Path, era: &str, recs: &[Record]) -> Result<Vec<PathBuf>> {
    std::fs::create_dir_all(outdir)?;
    let mut k = 0;
    while outdir.join(format!("{era}_{k}.ztv")).exists() {
        k += 1;
    }
    let mut files = vec![];
    let mut cur: Vec<Record> = vec![];
    let mut size = 8;
    let flush = |cur: &mut Vec<Record>, k: &mut usize, files: &mut Vec<PathBuf>| -> Result<()> {
        if cur.is_empty() {
            return Ok(());
        }
        let p = outdir.join(format!("{era}_{k}.ztv"));
        raw::write_file(&p, cur)?;
        files.push(p);
        *k += 1;
        cur.clear();
        Ok(())
    };
    for r in recs {
        if !cur.is_empty() && (cur.len() >= 400 || size + r.size() > 1_000_000) {
            flush(&mut cur, &mut k, &mut files)?;
            size = 8;
        }
        size += r.size();
        cur.push(r.clone());
    }
    flush(&mut cur, &mut k, &mut files)?;
    Ok(files)
}

fn txid_of(raw_tx: &[u8], height: u64) -> Result<[u8; 32]> {
    let lay = raw::layout(raw_tx)?;
    if lay.version <= 4 {
        return Ok(raw::sha256d(raw_tx));
    }
    let tx = Transaction::read(raw_tx, BranchId::for_height(&MAIN_NETWORK, (height as u32).into()))?;
    Ok(*tx.txid().as_ref())
}

async fn fetch_prevs(pool: &lwd::Pool, cache: &Path, ids: Vec<[u8; 32]>) -> Result<HashMap<[u8; 32], Vec<u8>>> {
    std::fs::create_dir_all(cache)?;
    let mut have = HashMap::new();
    let mut need = vec![];
    for id in ids {
        let mut d = id;
        d.reverse();
        let f = cache.join(format!("{}.tx", hex::encode(d)));
        match std::fs::read(&f) {
            Ok(b) => {
                have.insert(id, b);
            }
            Err(_) => need.push((id, f)),
        }
    }
    eprintln!("  prevouts: {} cached, {} to fetch", have.len(), need.len());
    let mut set = tokio::task::JoinSet::new();
    for (id, f) in need {
        let pool = pool.clone();
        set.spawn(async move {
            let (b, h) = pool.raw_tx(id).await?;
            ensure!(txid_of(&b, h)? == id, "lightwalletd returned a tx with a different txid");
            std::fs::write(&f, &b)?;
            anyhow::Ok((id, b))
        });
    }
    let mut done = 0;
    while let Some(r) = set.join_next().await {
        let (id, b) = r??;
        have.insert(id, b);
        done += 1;
        if done % 2000 == 0 {
            eprintln!("  fetched {done}");
        }
    }
    Ok(have)
}

async fn build(era: &str, outdir: &Path, cache: &Path, cap: usize, list: &Path) -> Result<()> {
    let mut blocks = vec![];
    for l in std::fs::read_to_string(list)?.lines() {
        let mut it = l.split_whitespace();
        let h: u32 = it.next().ok_or_else(|| anyhow!("bad list"))?.parse()?;
        let p = PathBuf::from(it.next().ok_or_else(|| anyhow!("bad list"))?);
        blocks.push((h, p));
    }
    blocks.sort();
    let per_block: Vec<Result<(u32, Vec<(Vec<u8>, raw::Layout)>, usize, usize)>> = blocks
        .par_iter()
        .map(|(h, p)| {
            let b = std::fs::read(p)?;
            let txs = block_txs(&b, *h)?;
            let (sel, st, si) = select(&txs, cap);
            Ok((*h, sel, st, si))
        })
        .collect();
    let mut sel_all = vec![];
    let (mut skt, mut ski) = (0, 0);
    for r in per_block {
        let (h, sel, st, si) = r?;
        skt += st;
        ski += si;
        for (t, l) in sel {
            sel_all.push((h, t, l));
        }
    }
    let mut ids: Vec<[u8; 32]> = sel_all.iter().flat_map(|(_, _, l)| l.vin.iter().map(|i| i.prev_hash)).collect();
    ids.sort();
    ids.dedup();
    eprintln!("{era}: {} blocks, {} txs, {} inputs (cap {cap}: skipped {skt} txs / {ski} inputs)", blocks.len(), sel_all.len(), sel_all.iter().map(|x| x.2.vin.len()).sum::<usize>());
    let pool = lwd::Pool::connect().await?;
    let prevs = fetch_prevs(&pool, cache, ids).await?;
    let mut layouts: HashMap<[u8; 32], raw::Layout> = HashMap::new();
    let mut recs = vec![];
    for (h, t, l) in sel_all {
        let mut ps = vec![];
        for i in &l.vin {
            let pl = match layouts.get(&i.prev_hash) {
                Some(x) => x,
                None => {
                    let x = raw::layout(&prevs[&i.prev_hash])?;
                    layouts.entry(i.prev_hash).or_insert(x)
                }
            };
            let o = pl.vout.get(i.prev_n as usize).with_context(|| "prevout index out of range")?;
            let pb = &prevs[&i.prev_hash];
            ps.push(Prev { amount: o.value, spk: pb[o.script_off..o.script_off + o.script_len].to_vec() });
        }
        recs.push(Record { height: h, flags: MAINNET_FLAGS, tx: t, prevs: ps });
    }
    let files = write_chunks(outdir, era, &recs)?;
    let (mut nr, mut ni, mut nok) = (0, 0, 0);
    for f in &files {
        let (a, b, c) = annotate(f)?;
        nr += a;
        ni += b;
        nok += c;
    }
    println!("{era}: wrote {} files, {nr} records, {ni} inputs, {nok} valid, {} invalid", files.len(), ni - nok);
    Ok(())
}

fn stats(files: &[PathBuf]) -> Result<()> {
    let mut per_era: BTreeMap<String, [usize; 4]> = BTreeMap::new(); // records, inputs, valid, files
    let mut per_ver: BTreeMap<(String, u32), usize> = BTreeMap::new();
    let mut per_class: BTreeMap<String, usize> = BTreeMap::new();
    let mut per_era_class: BTreeMap<(String, char), usize> = BTreeMap::new();
    let mut ht_hist: BTreeMap<(String, u8), usize> = BTreeMap::new();
    let mut call_none = 0;
    let mut calls = 0;
    let mut js = (0, 0); // v2 txs with joinsplits, their inputs
    let mut single_oob = vec![];
    let mut invalid = vec![];
    let mut tx_err = 0;
    let mut nonstd_flags = 0;
    for f in files {
        let recs = raw::read_file(f)?;
        let outs: Vec<_> = recs.par_iter().map(oracle::check).collect();
        let fname = f.file_name().unwrap().to_string_lossy().to_string();
        for (k, (r, o)) in recs.iter().zip(&outs).enumerate() {
            let era = raw::era_of(r.height).to_string();
            let e = per_era.entry(era.clone()).or_default();
            e[0] += 1;
            e[1] += o.ok.len();
            e[2] += o.ok.iter().filter(|&&b| b).count();
            if k == 0 {
                e[3] += 1;
            }
            if r.flags != MAINNET_FLAGS {
                nonstd_flags += 1;
            }
            *per_ver.entry((era.clone(), o.version)).or_default() += o.ok.len();
            if o.tx_error.is_some() {
                tx_err += 1;
            }
            for (i, b) in o.ok.iter().enumerate() {
                if !b {
                    invalid.push(format!("{fname} r {k} in {i} h {} txid {} {}", r.height, o.txid, o.tx_error.clone().unwrap_or_default()));
                }
            }
            if let Ok(lay) = raw::layout(&r.tx) {
                if raw::n_joinsplits(&r.tx, &lay) > 0 {
                    js.0 += 1;
                    js.1 += lay.vin.len();
                }
                for (i, txin) in lay.vin.iter().enumerate() {
                    let sig = &r.tx[txin.script_off..txin.script_off + txin.script_len];
                    let spk = &r.prevs[i].spk;
                    *per_class.entry(raw::detail_class(spk, sig)).or_default() += 1;
                    *per_era_class.entry((era.clone(), raw::spk_letter(spk))).or_default() += 1;
                    for ht in sig_hash_types(sig) {
                        *ht_hist.entry((era.clone(), ht)).or_default() += 1;
                        if ht & 0x1f == 3 && i >= lay.vout.len() {
                            single_oob.push(format!("{fname} r {k} in {i} h {} v {} ht {ht:02x} valid {}", r.height, lay.version, o.ok[i]));
                        }
                    }
                }
            }
            for c in &o.calls {
                calls += 1;
                if c.2.is_none() {
                    call_none += 1;
                }
            }
        }
    }
    let tot = per_era.values().fold([0; 4], |a, b| [a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3]]);
    println!("TOTAL files {} records {} inputs {} valid {} invalid {} (tx-level errors {tx_err}, records with non-mainnet flags {nonstd_flags})", tot[3], tot[0], tot[1], tot[2], tot[1] - tot[2]);
    println!("\n# per era: records inputs valid invalid | k s p m o");
    for (e, v) in &per_era {
        let c = |l| per_era_class.get(&(e.clone(), l)).copied().unwrap_or(0);
        println!("{e:14} {:7} {:7} {:7} {:5} | k {} s {} p {} m {} o {}", v[0], v[1], v[2], v[1] - v[2], c('k'), c('s'), c('p'), c('m'), c('o'));
    }
    println!("\n# inputs per (era, tx version)");
    for ((e, v), n) in &per_ver {
        println!("{e:14} v{v} {n}");
    }
    let mut vt: BTreeMap<u32, usize> = BTreeMap::new();
    for ((_, v), n) in &per_ver {
        *vt.entry(*v).or_default() += n;
    }
    println!("totals by version: {vt:?}");
    println!("\n# inputs per script class");
    for (c, n) in &per_class {
        println!("{n:8} {c}");
    }
    println!("\n# hash-type bytes of signatures in scriptSigs, per era");
    let mut cur = String::new();
    let mut line = String::new();
    for ((e, h), n) in &ht_hist {
        if *e != cur {
            if !cur.is_empty() {
                println!("{cur:14}{line}");
            }
            cur = e.clone();
            line.clear();
        }
        line += &format!(" {h:02x}:{n}");
    }
    println!("{cur:14}{line}");
    println!("\nv2 txs with JoinSplits: {} ({} inputs)", js.0, js.1);
    println!("signature checks: {calls}, sighash callback failures (None): {call_none}");
    println!("SIGHASH_SINGLE signatures with input index >= #outputs: {}", single_oob.len());
    for s in single_oob.iter().take(20) {
        println!("  {s}");
    }
    println!("invalid inputs: {}", invalid.len());
    for s in invalid.iter().take(50) {
        println!("  {s}");
    }
    Ok(())
}

fn bench(files: &[PathBuf]) -> Result<()> {
    let mut recs = vec![];
    for f in files {
        recs.extend(raw::read_file(f)?);
    }
    let n_in: usize = recs.iter().map(|r| r.prevs.len()).sum();
    let t = std::time::Instant::now();
    let pool1 = rayon::ThreadPoolBuilder::new().num_threads(1).build()?;
    let v1: usize = pool1.install(|| recs.iter().map(|r| oracle::check(r).ok.len()).sum());
    let d1 = t.elapsed().as_secs_f64();
    let t = std::time::Instant::now();
    let vn: usize = recs.par_iter().map(|r| oracle::check(r).ok.len()).sum();
    let dn = t.elapsed().as_secs_f64();
    assert_eq!(v1, vn);
    println!("records {} inputs {n_in}", recs.len());
    println!("1 thread: {d1:.2}s = {:.0} inputs/s", n_in as f64 / d1);
    println!("{} threads: {dn:.2}s = {:.0} inputs/s", rayon::current_num_threads(), n_in as f64 / dn);
    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    let a: Vec<String> = std::env::args().collect();
    match a.get(1).map(String::as_str) {
        Some("check") => {
            let recs = raw::read_file(Path::new(&a[2]))?;
            let outs: Vec<_> = recs.par_iter().map(oracle::check).collect();
            for (k, o) in outs.iter().enumerate() {
                println!("{}", oracle::expect_line(k, o));
            }
        }
        Some("annotate") => {
            for f in ztv_files(&a[2..])? {
                let (r, i, ok) = annotate(&f)?;
                println!("{} records {r} inputs {i} valid {ok}", f.display());
            }
        }
        #[cfg(feature = "cxx")]
        Some("cxxcompare") => {
            let files = ztv_files(&a[2..])?;
            let (mut n, mut agree, mut rust_ok, mut cxx_ok) = (0usize, 0usize, 0usize, 0usize);
            let mut diffs = vec![];
            let t = std::time::Instant::now();
            for f in &files {
                let recs = raw::read_file(f)?;
                let res: Vec<_> = recs.par_iter().map(|r| (oracle::check(r).ok, oracle::check_with(r, oracle::Interp::Cxx).ok)).collect();
                for (k, (a1, b1)) in res.iter().enumerate() {
                    for (i, (x, y)) in a1.iter().zip(b1).enumerate() {
                        n += 1;
                        rust_ok += *x as usize;
                        cxx_ok += *y as usize;
                        if x == y {
                            agree += 1;
                        } else {
                            diffs.push(format!("{} r {k} in {i} rust {x} cxx {y}", f.display()));
                        }
                    }
                }
            }
            println!("files {} inputs {n} agree {agree} disagree {} (rust valid {rust_ok}, cxx valid {cxx_ok}) in {:.1}s", files.len(), n - agree, t.elapsed().as_secs_f64());
            for d in diffs.iter().take(50) {
                println!("  {d}");
            }
        }
        Some("stats") => stats(&ztv_files(&a[2..])?)?,
        Some("bench") => bench(&ztv_files(&a[2..])?)?,
        Some("tip") => {
            let pool = lwd::Pool::connect().await?;
            println!("tip {}", pool.latest().await?);
        }
        Some("rawtx") => {
            let pool = lwd::Pool::connect().await?;
            for id in &a[2..] {
                let mut b: [u8; 32] = hex::decode(id)?.try_into().map_err(|_| anyhow!("txid"))?;
                b.reverse();
                let t = std::time::Instant::now();
                let (tx, h) = pool.raw_tx(b).await?;
                println!("{id} height {h} len {} in {:.2}s", tx.len(), t.elapsed().as_secs_f64());
            }
        }
        Some("hashes") => {
            let pool = lwd::Pool::connect().await?;
            let mut set = tokio::task::JoinSet::new();
            for h in &a[2..] {
                let (pool, h) = (pool.clone(), h.parse::<u64>()?);
                set.spawn(async move { anyhow::Ok((h, pool.block_hash(h).await?)) });
            }
            while let Some(r) = set.join_next().await {
                let (h, hash) = r??;
                println!("h {h} {hash}");
            }
        }
        Some("count") => {
            let cap: usize = a[2].parse()?;
            let rows: Vec<String> = a[3..]
                .par_iter()
                .map(|p| {
                    let h: u32 = Path::new(p).file_stem().unwrap().to_string_lossy().parse()?;
                    let txs = block_txs(&std::fs::read(p)?, h)?;
                    let (sel, st, si) = select(&txs, cap);
                    anyhow::Ok(format!("{h} {} {} {st} {si}", sel.len(), sel.iter().map(|x| x.1.vin.len()).sum::<usize>()))
                })
                .collect::<Result<_>>()?;
            for r in rows {
                println!("{r}");
            }
        }
        Some("build") => {
            build(&a[2], Path::new(&a[3]), Path::new(&a[4]), a[5].parse()?, Path::new(&a[6])).await?;
        }
        Some("tamper") => {
            tamper::run(a[2].parse()?, a[3].parse()?, Path::new(&a[4]), &ztv_files(&a[5..])?)?;
            for f in ztv_files(&[a[4].clone()])? {
                annotate(&f)?;
            }
        }
        _ => bail!("usage: see the header of src/main.rs"),
    }
    Ok(())
}
