//! Ground truth for Zebend's shielded-state component.
//!
//!   sync [from] [to]   stream mainnet compact blocks from lightwalletd and write every
//!                      Ironwood output's (height, cm_x, ρ) to out/leaves.bin in tree order
//!   trees h1 h2 ...    fetch the chain's own Ironwood tree state at those heights
//!   roots              recompute those roots in Rust from out/leaves.bin and compare
//!   consts             export Sinsemilla Q, the 1024 S generators, empty roots, and
//!                      MerkleCRH test vectors for the Bend implementation
//!
//! The output note's ρ is the nullifier spent in the same Action, so each compact
//! Ironwood action carries exactly the (cm_x, ρ) pair a leaf needs; the tree itself only
//! commits to cm_x.

use std::{fs, io::Write};

use anyhow::{anyhow, ensure, Context, Result};
use ff::PrimeField;
use group::Curve;
use incrementalmerkletree::{frontier::CommitmentTree, frontier::Frontier, Hashable, Level};
use orchard::tree::MerkleHashOrchard;
use pasta_curves::{arithmetic::CurveAffine, pallas};
use tonic::transport::{Channel, ClientTlsConfig};

const SERVER: &str = "https://zec.rocks:443";
/// NU6.3 (Ironwood) mainnet activation height, ZIP 258.
const IRONWOOD_ACTIVATION: u64 = 3_428_143;
const SERVICE: &str = "/cash.z.wallet.sdk.rpc.CompactTxStreamer";
const LEAF_RECORD: usize = 68;

#[derive(Clone, PartialEq, prost::Message)]
struct BlockId {
    #[prost(uint64, tag = "1")]
    height: u64,
    #[prost(bytes = "vec", tag = "2")]
    hash: Vec<u8>,
}

#[derive(Clone, PartialEq, prost::Message)]
struct BlockRange {
    #[prost(message, optional, tag = "1")]
    start: Option<BlockId>,
    #[prost(message, optional, tag = "2")]
    end: Option<BlockId>,
    #[prost(int32, repeated, tag = "3")]
    pool_types: Vec<i32>,
}

#[derive(Clone, PartialEq, prost::Message)]
struct ChainSpec {}

#[derive(Clone, PartialEq, prost::Message)]
struct ChainMetadata {
    #[prost(uint32, tag = "2")]
    orchard_commitment_tree_size: u32,
    #[prost(uint32, tag = "3")]
    ironwood_commitment_tree_size: u32,
}

#[derive(Clone, PartialEq, prost::Message)]
struct CompactAction {
    #[prost(bytes = "vec", tag = "1")]
    nullifier: Vec<u8>,
    #[prost(bytes = "vec", tag = "2")]
    cmx: Vec<u8>,
}

#[derive(Clone, PartialEq, prost::Message)]
struct CompactTx {
    #[prost(message, repeated, tag = "9")]
    ironwood_actions: Vec<CompactAction>,
}

#[derive(Clone, PartialEq, prost::Message)]
struct CompactBlock {
    #[prost(uint64, tag = "2")]
    height: u64,
    #[prost(message, repeated, tag = "7")]
    vtx: Vec<CompactTx>,
    #[prost(message, optional, tag = "8")]
    chain_metadata: Option<ChainMetadata>,
}

#[derive(Clone, PartialEq, prost::Message)]
struct TreeState {
    #[prost(uint64, tag = "2")]
    height: u64,
    #[prost(string, tag = "3")]
    hash: String,
    #[prost(string, tag = "7")]
    ironwood_tree: String,
}

const POOL_TYPE_IRONWOOD: i32 = 4;

struct Lwd {
    grpc: tonic::client::Grpc<Channel>,
}

impl Lwd {
    async fn connect() -> Result<Self> {
        let channel = Channel::from_static(SERVER)
            .tls_config(ClientTlsConfig::new().with_webpki_roots())?
            .connect()
            .await
            .context("connecting to lightwalletd")?;
        let grpc = tonic::client::Grpc::new(channel).max_decoding_message_size(64 << 20);
        Ok(Self { grpc })
    }

    async fn unary<Req, Resp>(&mut self, method: &str, req: Req) -> Result<Resp>
    where
        Req: prost::Message + Send + Sync + 'static,
        Resp: prost::Message + Default + Send + Sync + 'static,
    {
        self.grpc.ready().await?;
        let path = format!("{SERVICE}/{method}").parse()?;
        let resp = self
            .grpc
            .unary(tonic::Request::new(req), path, tonic_prost::ProstCodec::default())
            .await?;
        Ok(resp.into_inner())
    }

    async fn tip(&mut self) -> Result<u64> {
        let id: BlockId = self.unary("GetLatestBlock", ChainSpec {}).await?;
        Ok(id.height)
    }

    async fn tree_state(&mut self, height: u64) -> Result<TreeState> {
        self.unary("GetTreeState", BlockId { height, hash: vec![] }).await
    }

    /// Streams `[start, end]`, calling `on_block` for each compact block in order.
    async fn blocks(&mut self, start: u64, end: u64, mut on_block: impl FnMut(&CompactBlock) -> Result<()>) -> Result<()> {
        self.grpc.ready().await?;
        let path = format!("{SERVICE}/GetBlockRange").parse()?;
        let req = BlockRange {
            start: Some(BlockId { height: start, hash: vec![] }),
            end: Some(BlockId { height: end, hash: vec![] }),
            pool_types: vec![POOL_TYPE_IRONWOOD],
        };
        let mut stream = self
            .grpc
            .server_streaming::<_, CompactBlock, _>(tonic::Request::new(req), path, tonic_prost::ProstCodec::default())
            .await?
            .into_inner();
        while let Some(b) = stream.message().await? {
            on_block(&b)?;
        }
        Ok(())
    }
}

fn hex32(b: &[u8]) -> String {
    hex::encode(b)
}

fn base_hex(f: &pallas::Base) -> String {
    hex::encode(f.to_repr())
}

fn point_hex(p: &pallas::Point) -> (String, String) {
    let a = p.to_affine();
    let c = a.coordinates().unwrap();
    (base_hex(c.x()), base_hex(c.y()))
}

/// Parses a zcashd-format `CommitmentTree` (lightwalletd `TreeState.ironwoodTree`).
fn parse_tree_state(hex_tree: &str) -> Result<CommitmentTree<MerkleHashOrchard, 32>> {
    let bytes = hex::decode(hex_tree)?;
    let mut r = bytes.as_slice();
    fn take<'a>(r: &mut &'a [u8], n: usize) -> Result<&'a [u8]> {
        ensure!(r.len() >= n, "truncated tree state");
        let (a, b) = r.split_at(n);
        *r = b;
        Ok(a)
    }
    fn node(r: &mut &[u8]) -> Result<Option<MerkleHashOrchard>> {
        match take(r, 1)?[0] {
            0 => Ok(None),
            1 => {
                let b: [u8; 32] = take(r, 32)?.try_into().unwrap();
                Ok(Some(Option::from(MerkleHashOrchard::from_bytes(&b)).ok_or_else(|| anyhow!("non-canonical node"))?))
            }
            f => Err(anyhow!("bad optional flag {f}")),
        }
    }
    let left = node(&mut r)?;
    let right = node(&mut r)?;
    let n = match take(&mut r, 1)?[0] {
        n @ 0..=252 => n as usize,
        253 => u16::from_le_bytes(take(&mut r, 2)?.try_into().unwrap()) as usize,
        _ => return Err(anyhow!("parent count too large")),
    };
    let parents = (0..n).map(|_| node(&mut r)).collect::<Result<Vec<_>>>()?;
    ensure!(r.is_empty(), "trailing bytes in tree state");
    CommitmentTree::from_parts(left, right, parents).map_err(|_| anyhow!("malformed tree state"))
}

fn read_leaves() -> Result<Vec<(u32, [u8; 32], [u8; 32])>> {
    let b = fs::read("out/leaves.bin").context("out/leaves.bin (run `sync` first)")?;
    ensure!(b.len() % LEAF_RECORD == 0, "leaves.bin length");
    Ok(b.chunks_exact(LEAF_RECORD)
        .map(|c| (u32::from_le_bytes(c[0..4].try_into().unwrap()), c[4..36].try_into().unwrap(), c[36..68].try_into().unwrap()))
        .collect())
}

async fn sync(from: u64, to: Option<u64>) -> Result<()> {
    fs::create_dir_all("out")?;
    let mut lwd = Lwd::connect().await?;
    let tip = lwd.tip().await?;
    let to = to.unwrap_or(tip).min(tip);
    println!("syncing Ironwood leaves for blocks {from}..={to} (tip {tip}) from {SERVER}");
    let mut out = fs::File::create("out/leaves.bin")?;
    let mut count: u64 = 0;
    let mut last_size: Option<u32> = None;
    let mut blocks_seen = 0u64;
    let t = std::time::Instant::now();
    const CHUNK: u64 = 20_000;
    let mut start = from;
    while start <= to {
        let end = (start + CHUNK - 1).min(to);
        let mut next_expected = start;
        let mut attempt = 0;
        loop {
            let res = lwd
                .blocks(next_expected, end, |b| {
                    ensure!(b.height == next_expected, "out-of-order block {} (expected {next_expected})", b.height);
                    for tx in &b.vtx {
                        for a in &tx.ironwood_actions {
                            ensure!(a.cmx.len() == 32 && a.nullifier.len() == 32, "bad action at {}", b.height);
                            out.write_all(&(b.height as u32).to_le_bytes())?;
                            out.write_all(&a.cmx)?;
                            out.write_all(&a.nullifier)?;
                            count += 1;
                        }
                    }
                    if let Some(m) = &b.chain_metadata {
                        if m.ironwood_commitment_tree_size != 0 || count == 0 {
                            last_size = Some(m.ironwood_commitment_tree_size);
                        }
                    }
                    next_expected += 1;
                    blocks_seen += 1;
                    Ok(())
                })
                .await;
            match res {
                Ok(()) => break,
                Err(e) if attempt < 5 => {
                    attempt += 1;
                    eprintln!("  stream error at {next_expected} ({e}); reconnecting (attempt {attempt})");
                    lwd = Lwd::connect().await?;
                }
                Err(e) => return Err(e),
            }
        }
        println!("  ..{end}: {count} Ironwood leaves, chain says tree size {last_size:?} ({:.0?})", t.elapsed());
        start = end + 1;
    }
    out.flush()?;
    fs::write("out/sync.txt", format!("from {from}\nto {to}\nblocks {blocks_seen}\nleaves {count}\nchain_tree_size {}\n", last_size.unwrap_or(0)))?;
    println!("done: {blocks_seen} blocks, {count} leaves, chain-reported tree size {last_size:?}, {:.1?}", t.elapsed());
    Ok(())
}

async fn trees(heights: Vec<u64>) -> Result<()> {
    let mut lwd = Lwd::connect().await?;
    let mut lines = String::new();
    for h in heights {
        let ts = lwd.tree_state(h).await?;
        if ts.ironwood_tree.is_empty() {
            println!("height {h}: no Ironwood tree state");
            continue;
        }
        let tree = parse_tree_state(&ts.ironwood_tree)?;
        let root = tree.root().to_bytes();
        println!("height {} size {} root {}", ts.height, tree.size(), hex32(&root));
        lines += &format!("{} {} {}\n", ts.height, tree.size(), hex32(&root));
    }
    fs::create_dir_all("out")?;
    fs::write("out/treestates.txt", lines)?;
    Ok(())
}

fn roots() -> Result<()> {
    let leaves = read_leaves()?;
    let states = fs::read_to_string("out/treestates.txt")?;
    let mut f = Frontier::<MerkleHashOrchard, 32>::empty();
    let mut appended = 0usize;
    let mut all = true;
    let t = std::time::Instant::now();
    for line in states.lines() {
        let mut it = line.split_whitespace();
        let (h, size, root) = (it.next().unwrap(), it.next().unwrap().parse::<usize>()?, it.next().unwrap());
        ensure!(size <= leaves.len(), "tree state at {h} has {size} leaves, only {} synced", leaves.len());
        while appended < size {
            let cmx = Option::from(MerkleHashOrchard::from_bytes(&leaves[appended].1)).ok_or_else(|| anyhow!("non-canonical cmx"))?;
            ensure!(f.append(cmx), "tree full");
            appended += 1;
        }
        let ours = hex32(&f.root().to_bytes());
        let ok = ours == root;
        all &= ok;
        println!("height {h} size {size}: rust root {ours} {}", if ok { "MATCH" } else { "MISMATCH" });
    }
    println!("rust frontier rebuild: {appended} leaves in {:.1?}; all match: {all}", t.elapsed());
    ensure!(all, "rust roots disagree with the chain");
    Ok(())
}

fn consts() -> Result<()> {
    fs::create_dir_all("out")?;
    let mut s = String::new();
    // Q for the MerkleCRH domain: hash_to_curve("z.cash:SinsemillaQ")("z.cash:Orchard-MerkleCRH").
    use pasta_curves::arithmetic::CurveExt;
    let q = pallas::Point::hash_to_curve(sinsemilla::Q_PERSONALIZATION)(b"z.cash:Orchard-MerkleCRH");
    let (qx, qy) = point_hex(&q);
    s += &format!("Q_x {qx}\nQ_y {qy}\n");
    for (j, (x, y)) in sinsemilla::SINSEMILLA_S.iter().enumerate() {
        s += &format!("S{j}_x {}\nS{j}_y {}\n", base_hex(x), base_hex(y));
    }
    for l in 0..=32u8 {
        s += &format!("empty{l} {}\n", hex32(&MerkleHashOrchard::empty_root(Level::from(l)).to_bytes()));
    }
    // MerkleCRH vectors: pseudo-random canonical inputs at several levels.
    let mut x = pallas::Base::from(7u64);
    for i in 0..16u8 {
        let l = MerkleHashOrchard::from_bytes(&{ x = x.square() + pallas::Base::from(i as u64 + 1); x }.to_repr()).unwrap();
        let r = MerkleHashOrchard::from_bytes(&{ x = x.square() + pallas::Base::from(3); x }.to_repr()).unwrap();
        let level = (i * 2) % 32;
        let h = MerkleHashOrchard::combine(Level::from(level), &l, &r);
        s += &format!("crh{i} {level} {} {} {}\n", hex32(&l.to_bytes()), hex32(&r.to_bytes()), hex32(&h.to_bytes()));
    }
    fs::write("out/sinsemilla_consts.txt", s)?;
    println!("wrote out/sinsemilla_consts.txt (Q, 1024 S generators, 33 empty roots, 16 MerkleCRH vectors)");
    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let num = |i: usize| args.get(i).map(|s| s.parse::<u64>()).transpose();
    match args.get(1).map(String::as_str) {
        Some("sync") => sync(num(2)?.unwrap_or(IRONWOOD_ACTIVATION), num(3)?).await,
        Some("trees") => trees(args[2..].iter().map(|s| s.parse()).collect::<Result<_, _>>()?).await,
        Some("roots") => roots(),
        Some("consts") => consts(),
        Some("tip") => {
            let mut lwd = Lwd::connect().await?;
            println!("{}", lwd.tip().await?);
            Ok(())
        }
        _ => Err(anyhow!("usage: state-oracle sync [from] [to] | trees h.. | roots | consts | tip")),
    }
}

