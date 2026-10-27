//! Minimal lightwalletd client (pattern copied from node/follow/lwd): block hash per height
//! (GetTreeState) and raw mined transactions by txid (GetTransaction). Transport only.
//! Requests are spread round-robin over several public servers, at most `MAX_IN_FLIGHT`
//! at a time, with retries and back-off on errors.
use anyhow::{anyhow, Context, Result};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use tonic::transport::{Channel, ClientTlsConfig};

pub const SERVERS: &[&str] = &[
    "https://na.zec.rocks:443",
    "https://eu.zec.rocks:443",
    "https://ap.zec.rocks:443",
    "https://zec.rocks:443",
];
const SERVICE: &str = "/cash.z.wallet.sdk.rpc.CompactTxStreamer";
pub const MAX_IN_FLIGHT: usize = 16;

#[derive(Clone, PartialEq, prost::Message)]
pub struct BlockId {
    #[prost(uint64, tag = "1")]
    pub height: u64,
    #[prost(bytes = "vec", tag = "2")]
    pub hash: Vec<u8>,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct ChainSpec {}

#[derive(Clone, PartialEq, prost::Message)]
pub struct TreeState {
    #[prost(uint64, tag = "2")]
    pub height: u64,
    #[prost(string, tag = "3")]
    pub hash: String,
}

/// The leading fields of a CompactBlock (the rest is skipped by prost).
#[derive(Clone, PartialEq, prost::Message)]
pub struct CompactBlockHead {
    #[prost(uint64, tag = "2")]
    pub height: u64,
    #[prost(bytes = "vec", tag = "3")]
    pub hash: Vec<u8>,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct TxFilter {
    #[prost(message, optional, tag = "1")]
    pub block: Option<BlockId>,
    #[prost(uint64, tag = "2")]
    pub index: u64,
    #[prost(bytes = "vec", tag = "3")]
    pub hash: Vec<u8>,
}

#[derive(Clone, PartialEq, prost::Message)]
pub struct RawTransaction {
    #[prost(bytes = "vec", tag = "1")]
    pub data: Vec<u8>,
    #[prost(uint64, tag = "2")]
    pub height: u64,
}

#[derive(Clone)]
pub struct Pool {
    chans: Arc<std::sync::Mutex<Vec<tonic::client::Grpc<Channel>>>>,
    urls: Arc<Vec<&'static str>>,
    next: Arc<AtomicUsize>,
    pub sem: Arc<tokio::sync::Semaphore>,
}

impl Pool {
    pub async fn connect() -> Result<Self> {
        let mut chans = vec![];
        // LWD_SERVERS=url,url overrides the server list.
        let list: Vec<&'static str> = match std::env::var("LWD_SERVERS") {
            Ok(v) => v.split(',').map(|s| &*Box::leak(s.to_string().into_boxed_str())).collect(),
            Err(_) => SERVERS.to_vec(),
        };
        let mut urls = vec![];
        for s in list {
            match Self::open(s).await {
                Ok(g) => {
                    chans.push(g);
                    urls.push(s);
                }
                Err(e) => eprintln!("lwd: {s} unavailable: {e}"),
            }
        }
        if chans.is_empty() {
            return Err(anyhow!("no lightwalletd server reachable"));
        }
        Ok(Pool { chans: Arc::new(std::sync::Mutex::new(chans)), urls: Arc::new(urls), next: Arc::new(AtomicUsize::new(0)), sem: Arc::new(tokio::sync::Semaphore::new(MAX_IN_FLIGHT)) })
    }

    async fn open(s: &'static str) -> Result<tonic::client::Grpc<Channel>> {
        let ch = Channel::from_static(s).tls_config(ClientTlsConfig::new().with_webpki_roots())?.connect().await?;
        Ok(tonic::client::Grpc::new(ch).max_decoding_message_size(64 << 20))
    }

    async fn unary<Req, Resp>(&self, method: &str, req: Req) -> Result<Resp>
    where
        Req: prost::Message + Clone + Send + Sync + 'static,
        Resp: prost::Message + Default + Send + Sync + 'static,
    {
        let _permit = self.sem.acquire().await?;
        let mut last = None;
        for attempt in 0..8u32 {
            let k = self.next.fetch_add(1, Ordering::Relaxed) % self.urls.len();
            let mut g = self.chans.lock().unwrap()[k].clone();
            let fut = async {
                g.ready().await?;
                let path = format!("{SERVICE}/{method}").parse()?;
                let resp = g.unary(tonic::Request::new(req.clone()), path, tonic_prost::ProstCodec::default()).await?;
                Ok(resp.into_inner())
            };
            // A request that hangs must not hold its in-flight slot forever.
            let r: Result<Resp> = match tokio::time::timeout(std::time::Duration::from_secs(12), fut).await {
                Ok(r) => r,
                Err(_) => Err(anyhow!("timeout on channel {k}")),
            };
            if let Err(e) = &r {
                eprintln!("lwd: {method} attempt {attempt}: {e} ({})", self.urls[k]);
                // A connection that stalls is replaced by a fresh one.
                if let Ok(fresh) = Self::open(self.urls[k]).await {
                    self.chans.lock().unwrap()[k] = fresh;
                }
            }
            match r {
                Ok(v) => return Ok(v),
                Err(e) => {
                    last = Some(e);
                    tokio::time::sleep(std::time::Duration::from_millis(250 << attempt.min(5))).await;
                }
            }
        }
        Err(last.unwrap()).context(format!("lwd {method} failed after retries"))
    }

    pub async fn latest(&self) -> Result<u64> {
        let id: BlockId = self.unary("GetLatestBlock", ChainSpec {}).await?;
        Ok(id.height)
    }

    /// Block hash (display hex) at a height. Before Sapling z_gettreestate has no answer,
    /// so the (small) compact block is asked for instead.
    pub async fn block_hash(&self, h: u64) -> Result<String> {
        if h < 419_200 {
            let cb: CompactBlockHead = self.unary("GetBlock", BlockId { height: h, hash: vec![] }).await?;
            anyhow::ensure!(cb.height == h && cb.hash.len() == 32, "compact block for wrong height");
            let mut d = cb.hash.clone();
            d.reverse();
            return Ok(hex::encode(d));
        }
        let ts: TreeState = self.unary("GetTreeState", BlockId { height: h, hash: vec![] }).await?;
        anyhow::ensure!(ts.height == h, "tree state for wrong height");
        Ok(ts.hash)
    }

    /// Raw transaction bytes and mined height for a txid in internal byte order.
    pub async fn raw_tx(&self, txid_internal: [u8; 32]) -> Result<(Vec<u8>, u64)> {
        let rt: RawTransaction =
            self.unary("GetTransaction", TxFilter { block: None, index: 0, hash: txid_internal.to_vec() }).await?;
        Ok((rt.data, rt.height))
    }
}
