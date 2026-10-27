//! Minimal lightwalletd gRPC client (field numbers from lightwalletd's compact_formats.proto /
//! service.proto, as vendored in zcash/tx/oracle/proto).

use anyhow::{anyhow, Result};
use tonic::transport::{Channel, ClientTlsConfig};

pub const SERVICE: &str = "/cash.z.wallet.sdk.rpc.CompactTxStreamer";
pub const POOL_TRANSPARENT: i32 = 1;
pub const POOL_SAPLING: i32 = 2;
pub const PROTO_SAPLING: i32 = 0;

#[derive(Clone, PartialEq, prost::Message)]
pub struct BlockId {
    #[prost(uint64, tag = "1")]
    pub height: u64,
    #[prost(bytes = "vec", tag = "2")]
    pub hash: Vec<u8>,
}
#[derive(Clone, PartialEq, prost::Message)]
pub struct BlockRange {
    #[prost(message, optional, tag = "1")]
    pub start: Option<BlockId>,
    #[prost(message, optional, tag = "2")]
    pub end: Option<BlockId>,
    #[prost(int32, repeated, tag = "3")]
    pub pool_types: Vec<i32>,
}
#[derive(Clone, PartialEq, prost::Message)]
pub struct ChainSpec {}
#[derive(Clone, PartialEq, prost::Message)]
pub struct ChainMetadata {
    #[prost(uint32, tag = "1")]
    pub sapling_commitment_tree_size: u32,
    #[prost(uint32, tag = "2")]
    pub orchard_commitment_tree_size: u32,
}
#[derive(Clone, PartialEq, prost::Message)]
pub struct CompactSaplingSpend {
    #[prost(bytes = "vec", tag = "1")]
    pub nf: Vec<u8>,
}
#[derive(Clone, PartialEq, prost::Message)]
pub struct CompactSaplingOutput {
    #[prost(bytes = "vec", tag = "1")]
    pub cmu: Vec<u8>,
}
#[derive(Clone, PartialEq, prost::Message)]
pub struct CompactTxIn {
    #[prost(bytes = "vec", tag = "1")]
    pub prevout_txid: Vec<u8>,
    #[prost(uint32, tag = "2")]
    pub prevout_index: u32,
}
#[derive(Clone, PartialEq, prost::Message)]
pub struct CompactTx {
    #[prost(uint64, tag = "1")]
    pub index: u64,
    #[prost(bytes = "vec", tag = "2")]
    pub txid: Vec<u8>,
    #[prost(message, repeated, tag = "4")]
    pub spends: Vec<CompactSaplingSpend>,
    #[prost(message, repeated, tag = "5")]
    pub outputs: Vec<CompactSaplingOutput>,
    #[prost(message, repeated, tag = "7")]
    pub vin: Vec<CompactTxIn>,
}
#[derive(Clone, PartialEq, prost::Message)]
pub struct CompactBlock {
    #[prost(uint64, tag = "2")]
    pub height: u64,
    #[prost(bytes = "vec", tag = "3")]
    pub hash: Vec<u8>,
    #[prost(bytes = "vec", tag = "6")]
    pub header: Vec<u8>,
    #[prost(message, repeated, tag = "7")]
    pub vtx: Vec<CompactTx>,
    #[prost(message, optional, tag = "8")]
    pub chain_metadata: Option<ChainMetadata>,
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
#[derive(Clone, PartialEq, prost::Message)]
pub struct TreeState {
    #[prost(uint64, tag = "2")]
    pub height: u64,
    #[prost(string, tag = "3")]
    pub hash: String,
    #[prost(string, tag = "5")]
    pub sapling_tree: String,
}
#[derive(Clone, PartialEq, prost::Message)]
pub struct GetSubtreeRootsArg {
    #[prost(uint32, tag = "1")]
    pub start_index: u32,
    #[prost(int32, tag = "2")]
    pub shielded_protocol: i32,
    #[prost(uint32, tag = "3")]
    pub max_entries: u32,
}
#[derive(Clone, PartialEq, prost::Message)]
pub struct SubtreeRoot {
    #[prost(bytes = "vec", tag = "2")]
    pub root_hash: Vec<u8>,
    #[prost(bytes = "vec", tag = "3")]
    pub completing_block_hash: Vec<u8>,
    #[prost(uint64, tag = "4")]
    pub completing_block_height: u64,
}

pub struct Lwd(pub tonic::client::Grpc<Channel>);

/// Comma-separated LWD endpoints (env LWD), default the three zec.rocks servers.
pub fn urls() -> Vec<String> {
    std::env::var("LWD")
        .unwrap_or_else(|_| "https://zec.rocks:443,https://na.zec.rocks:443,https://eu.zec.rocks:443".into())
        .split(',')
        .map(str::to_string)
        .collect()
}

impl Lwd {
    pub async fn connect(url: &str) -> Result<Self> {
        let ep = Channel::from_shared(url.to_string())?
            .tls_config(ClientTlsConfig::new().with_webpki_roots())?
            .connect_timeout(std::time::Duration::from_secs(10))
            .tcp_keepalive(Some(std::time::Duration::from_secs(15)));
        let ch = tokio::time::timeout(std::time::Duration::from_secs(20), ep.connect()).await.map_err(|_| anyhow!("connect timeout"))??;
        Ok(Self(tonic::client::Grpc::new(ch).max_decoding_message_size(256 << 20)))
    }
    pub async fn any() -> Result<Self> {
        let mut last = anyhow!("no endpoints");
        for attempt in 0..6 {
            for u in urls() {
                match Self::connect(&u).await {
                    Ok(l) => return Ok(l),
                    Err(e) => last = e,
                }
            }
            tokio::time::sleep(std::time::Duration::from_secs(2 + 2 * attempt)).await;
        }
        Err(last)
    }
    pub async fn unary<Q, R>(&mut self, m: &'static str, q: Q) -> Result<R>
    where
        Q: prost::Message + Send + Sync + 'static,
        R: prost::Message + Default + Send + Sync + 'static,
    {
        self.0.ready().await?;
        let path = format!("{SERVICE}/{m}").parse()?;
        Ok(self.0.unary(tonic::Request::new(q), path, tonic_prost::ProstCodec::default()).await?.into_inner())
    }
    pub async fn raw_tx(&mut self, txid: &[u8; 32]) -> Result<RawTransaction> {
        self.unary("GetTransaction", TxFilter { block: None, index: 0, hash: txid.to_vec() }).await
    }
    pub async fn tree_state(&mut self, h: u64) -> Result<TreeState> {
        self.unary("GetTreeState", BlockId { height: h, hash: vec![] }).await
    }
    pub async fn blocks(&mut self, start: u64, end: u64, pools: Vec<i32>) -> Result<Vec<CompactBlock>> {
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
        let mut out = vec![];
        while let Some(b) = s.message().await? {
            out.push(b);
        }
        Ok(out)
    }
    pub async fn subtree_roots(&mut self, proto: i32) -> Result<Vec<SubtreeRoot>> {
        self.0.ready().await?;
        let path = format!("{SERVICE}/GetSubtreeRoots").parse()?;
        let req = GetSubtreeRootsArg { start_index: 0, shielded_protocol: proto, max_entries: 0 };
        let mut st = self
            .0
            .server_streaming::<_, SubtreeRoot, _>(tonic::Request::new(req), path, tonic_prost::ProstCodec::default())
            .await?
            .into_inner();
        let mut v = vec![];
        while let Some(r) = st.message().await? {
            v.push(r);
        }
        Ok(v)
    }
}

/// Fetch blocks start..=end with retries across endpoints (fresh connection per attempt, 300 s cap).
pub async fn blocks_retry(start: u64, end: u64, pools: Vec<i32>, worker: usize) -> Result<Vec<CompactBlock>> {
    let us = urls();
    let mut last = anyhow!("unreachable");
    for attempt in 0..10usize {
        let url = &us[(worker + attempt) % us.len()];
        let r = tokio::time::timeout(std::time::Duration::from_secs(300), async {
            let mut l = Lwd::connect(url).await?;
            l.blocks(start, end, pools.clone()).await
        })
        .await
        .map_err(|_| anyhow!("stream timeout"))
        .and_then(|x| x);
        match r {
            Ok(b) if b.len() as u64 == end - start + 1 => return Ok(b),
            Ok(b) => last = anyhow!("got {} blocks for {start}..{end}", b.len()),
            Err(e) => last = e,
        }
        eprintln!("blocks {start}..{end} attempt {attempt} via {url}: {last}");
        tokio::time::sleep(std::time::Duration::from_secs(2 + 3 * attempt as u64)).await;
    }
    Err(last)
}
