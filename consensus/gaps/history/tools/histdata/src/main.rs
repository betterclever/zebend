//! histdata: per-block inputs for the ZIP 221 history-tree leaves, from lightwalletd.
//!
//!   leaves NET FROM TO OUT    NET = main|test. Starts from the chain's tree states at FROM-1
//!                             (GetTreeState: Sapling, Orchard, Ironwood frontiers), streams compact
//!                             blocks FROM..TO and writes, per block, a 144-byte record:
//!                             u32 height | block hash 32 (internal order) | final Sapling root 32 |
//!                             final Orchard root 32 | final Ironwood root 32 (LE field repr) |
//!                             u32 #txs with Sapling spends/outputs | u32 #txs with Orchard actions |
//!                             u32 #txs with Ironwood actions.
//!                             Every block's resulting tree sizes are checked against the block's
//!                             chainMetadata (sapling/orchard/ironwood commitment tree size).
//!   roots NET H...            "h sapling orchard ironwood" roots of GetTreeState(H) (cross-check)
use std::{fs, io::Write};

use anyhow::{anyhow, ensure, Context, Result};
use incrementalmerkletree::{frontier::CommitmentTree, frontier::Frontier, Hashable, Level};
use orchard::tree::MerkleHashOrchard;
use sapling::Node;
use tonic::transport::{Channel, ClientTlsConfig};

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
    #[prost(uint32, tag = "1")]
    sapling_commitment_tree_size: u32,
    #[prost(uint32, tag = "2")]
    orchard_commitment_tree_size: u32,
    #[prost(uint32, tag = "3")]
    ironwood_commitment_tree_size: u32,
}
#[derive(Clone, PartialEq, prost::Message)]
struct Spend {
    #[prost(bytes = "vec", tag = "1")]
    nf: Vec<u8>,
}
#[derive(Clone, PartialEq, prost::Message)]
struct Output {
    #[prost(bytes = "vec", tag = "1")]
    cmu: Vec<u8>,
}
#[derive(Clone, PartialEq, prost::Message)]
struct Action {
    #[prost(bytes = "vec", tag = "1")]
    nullifier: Vec<u8>,
    #[prost(bytes = "vec", tag = "2")]
    cmx: Vec<u8>,
}
#[derive(Clone, PartialEq, prost::Message)]
struct CompactTx {
    #[prost(uint64, tag = "1")]
    index: u64,
    #[prost(message, repeated, tag = "4")]
    spends: Vec<Spend>,
    #[prost(message, repeated, tag = "5")]
    outputs: Vec<Output>,
    #[prost(message, repeated, tag = "6")]
    actions: Vec<Action>,
    #[prost(message, repeated, tag = "9")]
    ironwood_actions: Vec<Action>,
}
#[derive(Clone, PartialEq, prost::Message)]
struct CompactBlock {
    #[prost(uint64, tag = "2")]
    height: u64,
    #[prost(bytes = "vec", tag = "3")]
    hash: Vec<u8>,
    #[prost(message, repeated, tag = "7")]
    vtx: Vec<CompactTx>,
    #[prost(message, optional, tag = "8")]
    chain_metadata: Option<ChainMetadata>,
}
#[derive(Clone, PartialEq, prost::Message)]
struct TreeState {
    #[prost(uint64, tag = "2")]
    height: u64,
    #[prost(string, tag = "5")]
    sapling_tree: String,
    #[prost(string, tag = "6")]
    orchard_tree: String,
    #[prost(string, tag = "7")]
    ironwood_tree: String,
}

struct Lwd(tonic::client::Grpc<Channel>);

impl Lwd {
    async fn connect(net: &str) -> Result<Self> {
        let url = if net == "test" { "https://testnet.zec.rocks:443" } else { "https://zec.rocks:443" };
        let ch = Channel::from_shared(url.to_string())?
            .tls_config(ClientTlsConfig::new().with_webpki_roots())?
            .connect()
            .await
            .context("connecting to lightwalletd")?;
        Ok(Self(tonic::client::Grpc::new(ch).max_decoding_message_size(256 << 20)))
    }
    async fn tree_state(&mut self, h: u64) -> Result<TreeState> {
        self.0.ready().await?;
        let path = format!("{SERVICE}/GetTreeState").parse()?;
        Ok(self
            .0
            .unary(tonic::Request::new(BlockId { height: h, hash: vec![] }), path, tonic_prost::ProstCodec::default())
            .await?
            .into_inner())
    }
    async fn blocks(&mut self, start: u64, end: u64, mut f: impl FnMut(&CompactBlock) -> Result<()>) -> Result<()> {
        self.0.ready().await?;
        let path = format!("{SERVICE}/GetBlockRange").parse()?;
        let req = BlockRange {
            start: Some(BlockId { height: start, hash: vec![] }),
            end: Some(BlockId { height: end, hash: vec![] }),
            pool_types: vec![2, 3, 4],
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

fn parse_tree<H: Clone>(hex_tree: &str, from: impl Fn([u8; 32]) -> Option<H>) -> Result<CommitmentTree<H, 32>> {
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
    let mut node = |r: &mut &[u8]| -> Result<Option<H>> {
        match take(r, 1)?[0] {
            0 => Ok(None),
            1 => Ok(Some(from(take(r, 32)?.try_into()?).ok_or_else(|| anyhow!("bad node"))?)),
            f => Err(anyhow!("bad flag {f}")),
        }
    };
    let left = node(&mut r)?;
    let right = node(&mut r)?;
    let n = take(&mut r, 1)?[0] as usize;
    ensure!(n < 253, "large parent count");
    let parents = (0..n).map(|_| node(&mut r)).collect::<Result<Vec<_>>>()?;
    ensure!(r.is_empty(), "trailing tree bytes");
    CommitmentTree::from_parts(left, right, parents).map_err(|_| anyhow!("malformed tree"))
}

fn sap_node(b: [u8; 32]) -> Option<Node> {
    Option::from(Node::from_bytes(b))
}
fn orch_node(b: [u8; 32]) -> Option<MerkleHashOrchard> {
    Option::from(MerkleHashOrchard::from_bytes(&b))
}

struct Trees {
    sap: Frontier<Node, 32>,
    orch: Frontier<MerkleHashOrchard, 32>,
    iw: Frontier<MerkleHashOrchard, 32>,
}

async fn trees_at(l: &mut Lwd, h: u64) -> Result<Trees> {
    let ts = l.tree_state(h).await?;
    ensure!(ts.height == h, "tree state height {} != {}", ts.height, h);
    Ok(Trees {
        sap: parse_tree(&ts.sapling_tree, sap_node)?.to_frontier(),
        orch: parse_tree(&ts.orchard_tree, orch_node)?.to_frontier(),
        iw: parse_tree(&ts.ironwood_tree, orch_node)?.to_frontier(),
    })
}

fn sap_root(f: &Frontier<Node, 32>) -> [u8; 32] {
    f.value().map_or_else(|| Node::empty_root(Level::from(32)), |_| f.root()).to_bytes()
}
fn orch_root(f: &Frontier<MerkleHashOrchard, 32>) -> [u8; 32] {
    f.value().map_or_else(|| MerkleHashOrchard::empty_root(Level::from(32)), |_| f.root()).to_bytes()
}
fn size<H>(f: &Frontier<H, 32>) -> u64 {
    f.value().map_or(0, |v| u64::from(v.position()) + 1)
}

#[tokio::main]
async fn main() -> Result<()> {
    let a: Vec<String> = std::env::args().collect();
    match a.get(1).map(String::as_str) {
        Some("roots") => {
            let mut l = Lwd::connect(&a[2]).await?;
            for h in &a[3..] {
                let t = trees_at(&mut l, h.parse()?).await?;
                println!("{h} {} {} {}", hex::encode(sap_root(&t.sap)), hex::encode(orch_root(&t.orch)), hex::encode(orch_root(&t.iw)));
            }
            Ok(())
        }
        Some("leaves") => {
            let net = a[2].clone();
            let (from, to): (u64, u64) = (a[3].parse()?, a[4].parse()?);
            let path = &a[5];
            let mut l = Lwd::connect(&net).await?;
            let mut t = trees_at(&mut l, from - 1).await?;
            let mut out = std::io::BufWriter::new(fs::File::create(path)?);
            let (mut sr, mut or, mut ir) = (sap_root(&t.sap), orch_root(&t.orch), orch_root(&t.iw));
            let tm = std::time::Instant::now();
            let step = 2000u64;
            let mut s = from;
            while s <= to {
                let e = (s + step - 1).min(to);
                let mut ok = None;
                for attempt in 1..=8u64 {
                    let mut buf = Vec::new();
                    let mut tt = Trees { sap: t.sap.clone(), orch: t.orch.clone(), iw: t.iw.clone() };
                    let (mut sr2, mut or2, mut ir2) = (sr, or, ir);
                    let mut next = s;
                    let res = tokio::time::timeout(std::time::Duration::from_secs(600), async {
                        if attempt > 1 {
                            l = Lwd::connect(&net).await?;
                        }
                        l.blocks(s, e, |b| {
                            ensure!(b.height == next, "block {} out of order (want {next})", b.height);
                            next += 1;
                            let (mut ns, mut no, mut ni) = (0u32, 0u32, 0u32);
                            let (mut cs, mut co, mut ci) = (false, false, false);
                            for tx in &b.vtx {
                                if !tx.spends.is_empty() || !tx.outputs.is_empty() {
                                    ns += 1;
                                }
                                if !tx.actions.is_empty() {
                                    no += 1;
                                }
                                if !tx.ironwood_actions.is_empty() {
                                    ni += 1;
                                }
                                for o in &tx.outputs {
                                    ensure!(tt.sap.append(sap_node(o.cmu.clone().try_into().map_err(|_| anyhow!("cmu len"))?).ok_or_else(|| anyhow!("bad cmu"))?), "full");
                                    cs = true;
                                }
                                for o in &tx.actions {
                                    ensure!(tt.orch.append(orch_node(o.cmx.clone().try_into().map_err(|_| anyhow!("cmx len"))?).ok_or_else(|| anyhow!("bad cmx"))?), "full");
                                    co = true;
                                }
                                for o in &tx.ironwood_actions {
                                    ensure!(tt.iw.append(orch_node(o.cmx.clone().try_into().map_err(|_| anyhow!("cmx len"))?).ok_or_else(|| anyhow!("bad cmx"))?), "full");
                                    ci = true;
                                }
                            }
                            let m = b.chain_metadata.clone().ok_or_else(|| anyhow!("no chain metadata at {}", b.height))?;
                            ensure!(
                                size(&tt.sap) == m.sapling_commitment_tree_size as u64
                                    && size(&tt.orch) == m.orchard_commitment_tree_size as u64
                                    && size(&tt.iw) == m.ironwood_commitment_tree_size as u64,
                                "tree sizes at {}: ours {} {} {} chain {} {} {}",
                                b.height, size(&tt.sap), size(&tt.orch), size(&tt.iw),
                                m.sapling_commitment_tree_size, m.orchard_commitment_tree_size, m.ironwood_commitment_tree_size
                            );
                            if cs { sr2 = sap_root(&tt.sap); }
                            if co { or2 = orch_root(&tt.orch); }
                            if ci { ir2 = orch_root(&tt.iw); }
                            ensure!(b.hash.len() == 32, "hash len");
                            buf.extend_from_slice(&(b.height as u32).to_le_bytes());
                            buf.extend_from_slice(&b.hash);
                            buf.extend_from_slice(&sr2);
                            buf.extend_from_slice(&or2);
                            buf.extend_from_slice(&ir2);
                            buf.extend_from_slice(&ns.to_le_bytes());
                            buf.extend_from_slice(&no.to_le_bytes());
                            buf.extend_from_slice(&ni.to_le_bytes());
                            Ok(())
                        })
                        .await?;
                        ensure!(next == e + 1, "stream ended at {next}, want {}", e + 1);
                        Ok::<_, anyhow::Error>(())
                    })
                    .await
                    .unwrap_or_else(|_| Err(anyhow!("timeout")));
                    match res {
                        Ok(()) => {
                            ok = Some((buf, tt, sr2, or2, ir2));
                            break;
                        }
                        Err(err) => {
                            eprintln!("chunk {s}..{e} attempt {attempt}: {err:#}");
                            tokio::time::sleep(std::time::Duration::from_secs(3 * attempt)).await;
                        }
                    }
                }
                let (buf, tt, a1, a2, a3) = ok.ok_or_else(|| anyhow!("chunk {s}..{e} failed"))?;
                out.write_all(&buf)?;
                t = tt;
                (sr, or, ir) = (a1, a2, a3);
                eprintln!("..{e} {:.0}s sapling {} orchard {} ironwood {}", tm.elapsed().as_secs_f64(), size(&t.sap), size(&t.orch), size(&t.iw));
                s = e + 1;
            }
            out.flush()?;
            // the final roots must equal the chain's own tree state at TO
            let c = trees_at(&mut l, to).await?;
            ensure!(sap_root(&c.sap) == sr && orch_root(&c.orch) == or && orch_root(&c.iw) == ir, "final roots differ from GetTreeState({to})");
            println!("wrote {} blocks {from}..{to}; final roots equal GetTreeState({to})", to - from + 1);
            Ok(())
        }
        _ => {
            eprintln!("usage: leaves main|test FROM TO OUT | roots main|test H...");
            Ok(())
        }
    }
}
