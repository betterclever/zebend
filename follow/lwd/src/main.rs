//! Transport and labelled oracle helper for `zebend follow`. It verifies nothing.
//!
//!   follow-lwd tip                 latest block height lightwalletd knows
//!   follow-lwd tree H [H ...]      chain's Ironwood tree root and size at each height
//!                                  (an oracle value, printed only for cross-checking)
//!   follow-lwd rawtx TXID [...]    raw transaction bytes (hex) for a txid in internal byte order,
//!                                  used to supply transparent prevouts for ZIP 244 sighashes
use anyhow::{anyhow, ensure, Context, Result};
use incrementalmerkletree::frontier::CommitmentTree;
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
struct ChainSpec {}

#[derive(Clone, PartialEq, prost::Message)]
struct TreeState {
    #[prost(uint64, tag = "2")]
    height: u64,
    #[prost(string, tag = "3")]
    hash: String,
    #[prost(string, tag = "7")]
    ironwood_tree: String,
}

#[derive(Clone, PartialEq, prost::Message)]
struct TxFilter {
    #[prost(message, optional, tag = "1")]
    block: Option<BlockId>,
    #[prost(uint64, tag = "2")]
    index: u64,
    #[prost(bytes = "vec", tag = "3")]
    hash: Vec<u8>,
}

#[derive(Clone, PartialEq, prost::Message)]
struct RawTransaction {
    #[prost(bytes = "vec", tag = "1")]
    data: Vec<u8>,
    #[prost(uint64, tag = "2")]
    height: u64,
}

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
        Ok(Self { grpc: tonic::client::Grpc::new(channel).max_decoding_message_size(64 << 20) })
    }

    async fn unary<Req, Resp>(&mut self, method: &str, req: Req) -> Result<Resp>
    where
        Req: prost::Message + Send + Sync + 'static,
        Resp: prost::Message + Default + Send + Sync + 'static,
    {
        self.grpc.ready().await?;
        let path = format!("{SERVICE}/{method}").parse()?;
        let resp = self.grpc.unary(tonic::Request::new(req), path, tonic_prost::ProstCodec::default()).await?;
        Ok(resp.into_inner())
    }
}

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

#[tokio::main]
async fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let mut lwd = Lwd::connect().await?;
    match args.get(1).map(String::as_str) {
        Some("tip") => {
            let id: BlockId = lwd.unary("GetLatestBlock", ChainSpec {}).await?;
            println!("tip {}", id.height);
        }
        // Requests run concurrently (up to 32 in flight on the one channel); output lines
        // are keyed by height / txid, so their order does not matter.
        Some("tree") => {
            for chunk in args[2..].chunks(32) {
                let mut set = tokio::task::JoinSet::new();
                for h in chunk {
                    let (mut c, h) = (Lwd { grpc: lwd.grpc.clone() }, h.clone());
                    set.spawn(async move {
                        let ts: TreeState = c.unary("GetTreeState", BlockId { height: h.parse()?, hash: vec![] }).await?;
                        if ts.ironwood_tree.is_empty() {
                            return anyhow::Ok(format!("height {h} none"));
                        }
                        let t = parse_tree_state(&ts.ironwood_tree)?;
                        Ok(format!("height {} size {} root {}", ts.height, t.size(), hex::encode(t.root().to_bytes())))
                    });
                }
                while let Some(r) = set.join_next().await {
                    println!("{}", r??);
                }
            }
        }
        Some("rawtx") => {
            for chunk in args[2..].chunks(32) {
                let mut set = tokio::task::JoinSet::new();
                for id in chunk {
                    let (mut c, id) = (Lwd { grpc: lwd.grpc.clone() }, id.clone());
                    set.spawn(async move {
                        let hash = hex::decode(&id)?;
                        let rt: RawTransaction = c.unary("GetTransaction", TxFilter { block: None, index: 0, hash }).await?;
                        anyhow::Ok(format!("rawtx {id} height {} hex {}", rt.height, hex::encode(&rt.data)))
                    });
                }
                while let Some(r) = set.join_next().await {
                    println!("{}", r??);
                }
            }
        }
        _ => eprintln!("usage: follow-lwd tip | tree H... | rawtx TXID..."),
    }
    Ok(())
}
