//! Real Sapling transactions from other eras, fetched from lightwalletd (zec.rocks mirrors),
//! as research/proofsets/oracle does for Orchard: compact blocks with the SAPLING pool over sampled
//! height windows -> txids of transactions with Sapling spends or outputs -> GetTransaction.
//! Output: a raw.bin-format file (height u32 | txid [32] | len u32 | bytes).

use std::{
    fs::OpenOptions,
    io::{BufWriter, Write},
    path::Path,
    sync::Arc,
};

use anyhow::{anyhow, Result};
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
struct CompactSpend {
    #[prost(bytes = "vec", tag = "1")]
    nf: Vec<u8>,
}
#[derive(Clone, PartialEq, prost::Message)]
struct CompactOutput {
    #[prost(bytes = "vec", tag = "1")]
    cmu: Vec<u8>,
}
#[derive(Clone, PartialEq, prost::Message)]
struct CompactTx {
    #[prost(bytes = "vec", tag = "2")]
    txid: Vec<u8>,
    #[prost(message, repeated, tag = "4")]
    spends: Vec<CompactSpend>,
    #[prost(message, repeated, tag = "5")]
    outputs: Vec<CompactOutput>,
}
#[derive(Clone, PartialEq, prost::Message)]
struct CompactBlock {
    #[prost(uint64, tag = "2")]
    height: u64,
    #[prost(message, repeated, tag = "7")]
    vtx: Vec<CompactTx>,
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

struct Lwd(tonic::client::Grpc<Channel>);

impl Lwd {
    async fn connect(url: &str) -> Result<Self> {
        let ep = Channel::from_shared(url.to_string())?
            .tls_config(ClientTlsConfig::new().with_webpki_roots())?
            .connect_timeout(std::time::Duration::from_secs(10))
            .timeout(std::time::Duration::from_secs(60))
            .tcp_keepalive(Some(std::time::Duration::from_secs(15)));
        let ch = tokio::time::timeout(std::time::Duration::from_secs(20), ep.connect()).await.map_err(|_| anyhow!("connect timeout"))??;
        Ok(Self(tonic::client::Grpc::new(ch)))
    }
    async fn raw_tx(&mut self, txid: &[u8; 32]) -> Result<RawTransaction> {
        self.0.ready().await?;
        let path = format!("{SERVICE}/GetTransaction").parse()?;
        let q = TxFilter { block: None, index: 0, hash: txid.to_vec() };
        Ok(self.0.unary(tonic::Request::new(q), path, tonic_prost::ProstCodec::default()).await?.into_inner())
    }
    async fn blocks(&mut self, start: u64, end: u64) -> Result<Vec<CompactBlock>> {
        self.0.ready().await?;
        let path = format!("{SERVICE}/GetBlockRange").parse()?;
        let req = BlockRange {
            start: Some(BlockId { height: start, hash: vec![] }),
            end: Some(BlockId { height: end, hash: vec![] }),
            pool_types: vec![2], // SAPLING
        };
        let mut s = self.0.server_streaming::<_, CompactBlock, _>(tonic::Request::new(req), path, tonic_prost::ProstCodec::default()).await?.into_inner();
        let mut out = vec![];
        while let Some(b) = s.message().await? {
            out.push(b);
        }
        Ok(out)
    }
}

fn urls() -> Vec<String> {
    std::env::var("LWD")
        .unwrap_or_else(|_| "https://zec.rocks:443,https://na.zec.rocks:443,https://eu.zec.rocks:443".into())
        .split(',')
        .map(str::to_string)
        .collect()
}

/// For each start height: scan `blocks` blocks, keep up to `per_window` txs with Sapling
/// spends or outputs (all spend-carrying txs first), fetch them, append to `out`.
pub async fn fetch(starts: Vec<u64>, blocks: u64, per_window: usize, conc: usize, out: &Path) -> Result<()> {
    let mut lwd = Lwd::connect(&urls()[0]).await?;
    let mut want: Vec<(u64, [u8; 32])> = vec![];
    for &h in &starts {
        let mut txs: Vec<(u64, [u8; 32], usize, usize)> = vec![];
        let mut s = h;
        while s < h + blocks {
            let e = (s + 199).min(h + blocks - 1);
            let mut got = None;
            for attempt in 0..5u64 {
                match lwd.blocks(s, e).await {
                    Ok(b) => {
                        got = Some(b);
                        break;
                    }
                    Err(err) => {
                        eprintln!("blocks {s}..{e} attempt {attempt}: {err}");
                        tokio::time::sleep(std::time::Duration::from_secs(2 + 3 * attempt)).await;
                        lwd = Lwd::connect(&urls()[(attempt as usize + 1) % urls().len()]).await?;
                    }
                }
            }
            for b in got.ok_or_else(|| anyhow!("blocks {s}..{e} failed"))? {
                for tx in b.vtx {
                    if !tx.spends.is_empty() || !tx.outputs.is_empty() {
                        txs.push((b.height, tx.txid.as_slice().try_into()?, tx.spends.len(), tx.outputs.len()));
                    }
                }
            }
            s = e + 1;
        }
        // prefer spend-carrying txs (spend proofs are the scarcer kind), keep chain order otherwise
        let total = txs.len();
        // FETCH_PREFER=outputs: output-only txs first (e.g. Sprout->Sapling migration txs,
        // which carry Groth16 JoinSplits)
        if std::env::var("FETCH_PREFER").as_deref() == Ok("outputs") {
            txs.sort_by_key(|t| (t.2 != 0, t.0));
        } else {
            txs.sort_by_key(|t| (t.2 == 0, t.0));
        }
        txs.truncate(per_window);
        let (sp, op): (usize, usize) = txs.iter().fold((0, 0), |a, t| (a.0 + t.2, a.1 + t.3));
        eprintln!("window {h}..{}: {total} sapling txs, keeping {} ({sp} spends, {op} outputs)", h + blocks - 1, txs.len());
        want.extend(txs.into_iter().map(|t| (t.0, t.1)));
    }
    eprintln!("fetching {} txs, concurrency {conc}", want.len());
    let todo = Arc::new(tokio::sync::Mutex::new(want.into_iter()));
    let (txc, mut rx) = tokio::sync::mpsc::channel::<(u64, [u8; 32], Vec<u8>)>(1024);
    let mut workers = vec![];
    for w in 0..conc {
        let todo = todo.clone();
        let txc = txc.clone();
        workers.push(tokio::spawn(async move {
            let mut lwd: Option<Lwd> = None;
            loop {
                let Some((h, id)) = todo.lock().await.next() else { return Ok::<(), anyhow::Error>(()) };
                for attempt in 0..6u64 {
                    if lwd.is_none() {
                        let u = urls();
                        match Lwd::connect(&u[(w + attempt as usize) % u.len()]).await {
                            Ok(c) => lwd = Some(c),
                            Err(_) => {
                                tokio::time::sleep(std::time::Duration::from_secs(2 + 3 * attempt)).await;
                                continue;
                            }
                        }
                    }
                    let r = tokio::time::timeout(std::time::Duration::from_secs(40), lwd.as_mut().unwrap().raw_tx(&id)).await;
                    match r.map_err(|_| anyhow!("timeout")).and_then(|x| x) {
                        Ok(r) => {
                            txc.send((h, id, r.data)).await.ok();
                            break;
                        }
                        Err(e) => {
                            eprintln!("worker {w} attempt {attempt}: {e}");
                            lwd = None;
                            tokio::time::sleep(std::time::Duration::from_secs(1 + 2 * attempt)).await;
                        }
                    }
                }
            }
        }));
    }
    drop(txc);
    let mut f = BufWriter::new(OpenOptions::new().create(true).append(true).open(out)?);
    let mut n = 0;
    while let Some((h, id, b)) = rx.recv().await {
        f.write_all(&(h as u32).to_le_bytes())?;
        f.write_all(&id)?;
        f.write_all(&(b.len() as u32).to_le_bytes())?;
        f.write_all(&b)?;
        n += 1;
        if n % 500 == 0 {
            eprintln!("fetched {n}");
        }
    }
    f.flush()?;
    for w in workers {
        w.await??;
    }
    eprintln!("fetched {n} txs -> {}", out.display());
    Ok(())
}
