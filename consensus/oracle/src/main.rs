//! Ground truth for Zebend's consensus rules (mainnet, via lightwalletd).
//!
//!   meta H                      chain metadata (Orchard / Ironwood tree sizes) at block H
//!   sync POOL FROM TO OUT       stream compact blocks; write every POOL (orchard|ironwood)
//!                               output as (height u32 LE, cm_x 32) in tree order to OUT
//!   trees POOL H1 H2 ...        the chain's own tree state (size, root) at those heights
//!   hist LEAVES REC OUT         per-block root history from a leaf file (REC = record size:
//!                               36 for `sync` files, 68 for node/state leaves.bin):
//!                               "height size root" after every block that added leaves,
//!                               plus "-1 0 <empty root>"
//!   coinbase FROM TO OUT        transparent outputs of each block's coinbase (tx index 0)
//!                               and the per-tx fee field: "h value script" / "h fee f"
use std::{fs, io::Write};

use anyhow::{anyhow, ensure, Context, Result};
use incrementalmerkletree::{frontier::CommitmentTree, frontier::Frontier, Hashable, Level};
use orchard::tree::MerkleHashOrchard;
use tonic::transport::{Channel, ClientTlsConfig};

const SERVER: &str = "https://zec.rocks:443";
const SERVICE: &str = "/cash.z.wallet.sdk.rpc.CompactTxStreamer";

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
struct TxOut {
    #[prost(uint64, tag = "1")]
    value: u64,
    #[prost(bytes = "vec", tag = "2")]
    script: Vec<u8>,
}
#[derive(Clone, PartialEq, prost::Message)]
struct CompactTx {
    #[prost(uint64, tag = "1")]
    index: u64,
    #[prost(uint32, tag = "3")]
    fee: u32,
    #[prost(message, repeated, tag = "6")]
    actions: Vec<CompactAction>,
    #[prost(message, repeated, tag = "8")]
    vout: Vec<TxOut>,
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
    #[prost(string, tag = "6")]
    orchard_tree: String,
    #[prost(string, tag = "7")]
    ironwood_tree: String,
}

#[derive(Clone, PartialEq, prost::Message)]
struct GetSubtreeRootsArg {
    #[prost(uint32, tag = "1")]
    start_index: u32,
    #[prost(int32, tag = "2")]
    shielded_protocol: i32,
    #[prost(uint32, tag = "3")]
    max_entries: u32,
}
#[derive(Clone, PartialEq, prost::Message)]
struct SubtreeRoot {
    #[prost(bytes = "vec", tag = "2")]
    root_hash: Vec<u8>,
    #[prost(uint64, tag = "4")]
    completing_block_height: u64,
}

const POOL_TRANSPARENT: i32 = 1;
const POOL_ORCHARD: i32 = 3;
const POOL_IRONWOOD: i32 = 4;

struct Lwd(tonic::client::Grpc<Channel>);

impl Lwd {
    async fn connect() -> Result<Self> {
        let ch = Channel::from_static(SERVER)
            .tls_config(ClientTlsConfig::new().with_webpki_roots())?
            .connect()
            .await
            .context("connecting to lightwalletd")?;
        Ok(Self(tonic::client::Grpc::new(ch).max_decoding_message_size(64 << 20)))
    }
    async fn unary<Req: prost::Message + Send + Sync + 'static, Resp: prost::Message + Default + Send + Sync + 'static>(
        &mut self,
        method: &str,
        req: Req,
    ) -> Result<Resp> {
        self.0.ready().await?;
        let path = format!("{SERVICE}/{method}").parse()?;
        Ok(self.0.unary(tonic::Request::new(req), path, tonic_prost::ProstCodec::default()).await?.into_inner())
    }
    async fn blocks(&mut self, start: u64, end: u64, pools: Vec<i32>, mut f: impl FnMut(&CompactBlock) -> Result<()>) -> Result<()> {
        self.0.ready().await?;
        let path = format!("{SERVICE}/GetBlockRange").parse()?;
        let req = BlockRange {
            start: Some(BlockId { height: start, hash: vec![] }),
            end: Some(BlockId { height: end, hash: vec![] }),
            pool_types: pools,
        };
        let mut s = self
            .0
            .server_streaming::<_, CompactBlock, _>(tonic::Request::new(req), path, tonic_prost::ProstCodec::default())
            .await?
            .into_inner();
        while let Some(b) = s.message().await? {
            f(&b)?;
        }
        Ok(())
    }
}

fn parse_tree(hex_tree: &str) -> Result<CommitmentTree<MerkleHashOrchard, 32>> {
    let bytes = hex::decode(hex_tree)?;
    let mut r = bytes.as_slice();
    fn take<'a>(r: &mut &'a [u8], n: usize) -> Result<&'a [u8]> {
        ensure!(r.len() >= n, "short tree state");
        let (a, b) = r.split_at(n);
        *r = b;
        Ok(a)
    }
    fn node(r: &mut &[u8]) -> Result<Option<MerkleHashOrchard>> {
        match take(r, 1)?[0] {
            0 => Ok(None),
            1 => Ok(Some(Option::from(MerkleHashOrchard::from_bytes(take(r, 32)?.try_into()?)).ok_or_else(|| anyhow!("bad node"))?)),
            f => Err(anyhow!("bad flag {f}")),
        }
    }
    let left = node(&mut r)?;
    let right = node(&mut r)?;
    let n = take(&mut r, 1)?[0] as usize;
    ensure!(n < 253, "large parent count");
    let parents = (0..n).map(|_| node(&mut r)).collect::<Result<Vec<_>>>()?;
    CommitmentTree::from_parts(left, right, parents).map_err(|_| anyhow!("malformed tree"))
}

fn pool_id(p: &str) -> Result<i32> {
    match p {
        "orchard" => Ok(POOL_ORCHARD),
        "ironwood" => Ok(POOL_IRONWOOD),
        _ => Err(anyhow!("pool must be orchard or ironwood")),
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    let a: Vec<String> = std::env::args().collect();
    let n = |i: usize| -> Result<u64> { Ok(a[i].parse()?) };
    match a.get(1).map(String::as_str) {
        Some("meta") => {
            let mut l = Lwd::connect().await?;
            let h = n(2)?;
            l.blocks(h, h, vec![POOL_ORCHARD, POOL_IRONWOOD], |b| {
                let m = b.chain_metadata.clone().unwrap_or_default();
                println!("height {} orchard_size {} ironwood_size {}", b.height, m.orchard_commitment_tree_size, m.ironwood_commitment_tree_size);
                Ok(())
            })
            .await
        }
        Some("sync") => {
            // Resumable and chunk-atomic: a chunk is appended only after its leaf count equals
            // the chain's tree size at the chunk's last block; a failed stream is retried on a
            // fresh connection. On resume, the file must hold exactly the chain's tree size at FROM-1.
            let pool = pool_id(&a[2])?;
            let (from, to) = (n(3)?, n(4)?);
            let path = &a[5];
            let have = fs::metadata(path).map(|m| m.len()).unwrap_or(0);
            ensure!(have % 36 == 0, "leaf file length not a multiple of 36");
            let mut count: u64 = have / 36;
            let mut out = fs::OpenOptions::new().create(true).append(true).open(path)?;
            let t = std::time::Instant::now();
            let step: u64 = 5_000;
            let mut s = from;
            while s <= to {
                let e = (s + step - 1).min(to);
                let mut ok = None;
                for attempt in 1..=8 {
                    let mut buf: Vec<u8> = Vec::new();
                    let mut last = (0u64, 0u32);
                    let mut c = count;
                    // A stalled stream (seen in practice) times out and is retried.
                    let res = tokio::time::timeout(std::time::Duration::from_secs(300), async {
                        let mut l = Lwd::connect().await?;
                        l.blocks(s, e, vec![pool], |b| {
                            if b.height == s && s > 1 {
                                // nothing: size before s is checked below via the chunk total
                            }
                            for tx in &b.vtx {
                                let acts = if pool == POOL_ORCHARD { &tx.actions } else { &tx.ironwood_actions };
                                for act in acts {
                                    ensure!(act.cmx.len() == 32, "bad cmx at {}", b.height);
                                    buf.extend_from_slice(&(b.height as u32).to_le_bytes());
                                    buf.extend_from_slice(&act.cmx);
                                    c += 1;
                                }
                            }
                            if let Some(m) = &b.chain_metadata {
                                let size = if pool == POOL_ORCHARD { m.orchard_commitment_tree_size } else { m.ironwood_commitment_tree_size };
                                last = (b.height, size);
                            }
                            Ok(())
                        })
                        .await
                    })
                    .await
                    .unwrap_or_else(|_| Err(anyhow!("timed out after 300 s")));
                    match res {
                        Ok(()) if last.0 == e && last.1 as u64 == c => {
                            ok = Some((buf, c));
                            break;
                        }
                        Ok(()) => eprintln!("chunk {s}..{e} attempt {attempt}: count {c} vs chain {} at {}; retrying", last.1, last.0),
                        Err(err) => eprintln!("chunk {s}..{e} attempt {attempt}: {err}; retrying"),
                    }
                    tokio::time::sleep(std::time::Duration::from_secs(3 * attempt)).await;
                }
                let (buf, c) = ok.ok_or_else(|| anyhow!("chunk {s}..{e} failed 8 times"))?;
                out.write_all(&buf)?;
                out.flush()?;
                count = c;
                eprintln!("..{e}: {count} leaves (= chain tree size) {:.0}s", t.elapsed().as_secs_f64());
                s = e + 1;
            }
            println!("synced {count} leaves through height {to}");
            Ok(())
        }
        Some("trees") => {
            let pool = &a[2];
            let mut l = Lwd::connect().await?;
            for h in &a[3..] {
                let ts: TreeState = l.unary("GetTreeState", BlockId { height: h.parse()?, hash: vec![] }).await?;
                let hx = if pool == "orchard" { &ts.orchard_tree } else { &ts.ironwood_tree };
                let tree = parse_tree(hx)?;
                println!("{} {} {}", ts.height, tree.size(), hex::encode(tree.root().to_bytes()));
            }
            Ok(())
        }
        Some("hist") => {
            let rec: usize = a[3].parse()?;
            let bytes = fs::read(&a[2])?;
            ensure!(bytes.len() % rec == 0, "leaf file length");
            let mut f = Frontier::<MerkleHashOrchard, 32>::empty();
            let mut out = std::io::BufWriter::new(fs::File::create(&a[4])?);
            writeln!(out, "-1 0 {}", hex::encode(MerkleHashOrchard::empty_root(Level::from(32)).to_bytes()))?;
            let mut size: u64 = 0;
            let recs: Vec<&[u8]> = bytes.chunks_exact(rec).collect();
            for (i, r) in recs.iter().enumerate() {
                let h = u32::from_le_bytes(r[0..4].try_into()?);
                let leaf = Option::from(MerkleHashOrchard::from_bytes(r[4..36].try_into()?)).ok_or_else(|| anyhow!("bad leaf"))?;
                ensure!(f.append(leaf), "tree full");
                size += 1;
                let last_of_block = recs.get(i + 1).map_or(true, |n| u32::from_le_bytes(n[0..4].try_into().unwrap()) != h);
                if last_of_block {
                    writeln!(out, "{h} {size} {}", hex::encode(f.root().to_bytes()))?;
                }
            }
            out.flush()?;
            println!("{size} leaves");
            Ok(())
        }
        Some("subtrees") => {
            // The chain's level-16 subtree roots (2^16 leaves each): "index height root".
            let proto = if a[2] == "orchard" { 1 } else { 2 };
            let mut l = Lwd::connect().await?;
            l.0.ready().await?;
            let path = format!("{SERVICE}/GetSubtreeRoots").parse()?;
            let req = GetSubtreeRootsArg { start_index: 0, shielded_protocol: proto, max_entries: 0 };
            let mut st = l
                .0
                .server_streaming::<_, SubtreeRoot, _>(tonic::Request::new(req), path, tonic_prost::ProstCodec::default())
                .await?
                .into_inner();
            let mut out = std::io::BufWriter::new(fs::File::create(&a[3])?);
            let mut i = 0u32;
            while let Some(r) = st.message().await? {
                writeln!(out, "{i} {} {}", r.completing_block_height, hex::encode(&r.root_hash))?;
                i += 1;
            }
            out.flush()?;
            println!("{i} subtree roots");
            Ok(())
        }
        Some("coinbase") => {
            let (from, to) = (n(2)?, n(3)?);
            let mut out = std::io::BufWriter::new(fs::File::create(&a[4])?);
            let mut l = Lwd::connect().await?;
            l.blocks(from, to, vec![POOL_TRANSPARENT, POOL_ORCHARD, POOL_IRONWOOD], |b| {
                for tx in &b.vtx {
                    if tx.index == 0 {
                        for o in &tx.vout {
                            writeln!(out, "{} out {} {}", b.height, o.value, hex::encode(&o.script))?;
                        }
                    } else {
                        writeln!(out, "{} fee {}", b.height, tx.fee)?;
                    }
                }
                Ok(())
            })
            .await?;
            out.flush()?;
            Ok(())
        }
        _ => {
            eprintln!("usage: meta H | sync POOL FROM TO OUT | trees POOL H.. | hist LEAVES REC OUT | coinbase FROM TO OUT");
            Ok(())
        }
    }
}
