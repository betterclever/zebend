//! Every mainnet Orchard/Ironwood bundle since NU6.3 (Ironwood activation, height 3,428,143):
//!
//!   scan  [START] [END]   ../data/txids.txt   height txid orchard_actions ironwood_actions
//!   fetch [CONCURRENCY]   ../data/raw.bin     raw transactions (resumable, append-only)
//!   build [CHUNK]         ../data/chunks/c#####/*.bin   Bend verifier inputs (post-NU6.3, CHUNK per dir)
//!                         ../data/other/*.bin           bundles of older circuits (if any)
//!                         ../data/official.txt          the official orchard verdict per bundle
//!
//! Instances are computed exactly as node/tx's oracle does (independently of orchard's
//! `Instance` type); every bundle is also checked with the official `Bundle::verify_proof`.

use std::{
    collections::{HashMap, HashSet},
    fs::{self, File, OpenOptions},
    io::{BufRead, BufReader, BufWriter, Read, Write},
    path::Path,
    sync::Arc,
    time::Instant,
};

use anyhow::{anyhow, Context, Result};
use ff::PrimeField;
use group::{Curve, GroupEncoding};
use orchard::{
    bundle::{Authorized, BundleVersion},
    circuit::{OrchardCircuitVersion, VerifyingKey},
    ProtocolVersion,
};
use pasta_curves::{arithmetic::CurveAffine, pallas};
use rayon::prelude::*;
use tonic::transport::{Channel, ClientTlsConfig};
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::{BlockHeight, BranchId, MainNetwork};

const DATA: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../data");
const SERVICE: &str = "/cash.z.wallet.sdk.rpc.CompactTxStreamer";
const IRONWOOD_ACTIVATION: u64 = 3_428_143;

// ---------------------------------------------------------------- lightwalletd

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
struct CompactAction {
    #[prost(bytes = "vec", tag = "1")]
    nullifier: Vec<u8>,
}
#[derive(Clone, PartialEq, prost::Message)]
struct CompactTx {
    #[prost(bytes = "vec", tag = "2")]
    txid: Vec<u8>,
    #[prost(message, repeated, tag = "6")]
    actions: Vec<CompactAction>,
    #[prost(message, repeated, tag = "9")]
    ironwood_actions: Vec<CompactAction>,
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

impl From<Channel> for Lwd {
    fn from(c: Channel) -> Self {
        Self(tonic::client::Grpc::new(c))
    }
}

impl Lwd {
    async fn connect(url: &str) -> Result<Self> {
        let ep = Channel::from_shared(url.to_string())?
            .tls_config(ClientTlsConfig::new().with_webpki_roots())?
            .connect_timeout(std::time::Duration::from_secs(10))
            .timeout(std::time::Duration::from_secs(30))
            .tcp_keepalive(Some(std::time::Duration::from_secs(15)));
        let ch = tokio::time::timeout(std::time::Duration::from_secs(20), ep.connect()).await.map_err(|_| anyhow!("connect timeout"))??;
        Ok(Self(tonic::client::Grpc::new(ch)))
    }
    async fn unary<Q, R>(&mut self, m: &'static str, q: Q) -> Result<R>
    where
        Q: prost::Message + Send + Sync + 'static,
        R: prost::Message + Default + Send + Sync + 'static,
    {
        self.0.ready().await?;
        let path = format!("{SERVICE}/{m}").parse()?;
        Ok(self.0.unary(tonic::Request::new(q), path, tonic_prost::ProstCodec::default()).await?.into_inner())
    }
    async fn tip(&mut self) -> Result<u64> {
        Ok(self.unary::<_, BlockId>("GetLatestBlock", ChainSpec {}).await?.height)
    }
    async fn raw_tx(&mut self, txid: &[u8; 32]) -> Result<RawTransaction> {
        self.unary("GetTransaction", TxFilter { block: None, index: 0, hash: txid.to_vec() }).await
    }
    async fn blocks(&mut self, start: u64, end: u64) -> Result<Vec<CompactBlock>> {
        self.0.ready().await?;
        let path = format!("{SERVICE}/GetBlockRange").parse()?;
        let req = BlockRange {
            start: Some(BlockId { height: start, hash: vec![] }),
            end: Some(BlockId { height: end, hash: vec![] }),
            pool_types: vec![3, 4], // ORCHARD, IRONWOOD
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
}

fn lwd_url() -> String {
    lwd_urls()[0].clone()
}

/// Comma-separated LWD endpoints; fetch workers spread across them to share load.
fn lwd_urls() -> Vec<String> {
    std::env::var("LWD")
        .unwrap_or_else(|_| "https://zec.rocks:443,https://na.zec.rocks:443,https://eu.zec.rocks:443".into())
        .split(',')
        .map(str::to_string)
        .collect()
}

// ---------------------------------------------------------------- scan

async fn scan(start: u64, end: Option<u64>) -> Result<()> {
    let mut lwd = Lwd::connect(&lwd_url()).await?;
    let end = match end {
        Some(e) => e,
        None => lwd.tip().await?,
    };
    let path = Path::new(DATA).join("txids.txt");
    let mut out = BufWriter::new(File::create(&path)?);
    writeln!(out, "# scan {start}..{end}")?;
    let (mut txs, mut oa, mut ia) = (0u64, 0u64, 0u64);
    let t = Instant::now();
    let mut h = start;
    while h <= end {
        let e = (h + 999).min(end);
        let mut blocks = None;
        for attempt in 0..5 {
            match lwd.blocks(h, e).await {
                Ok(b) => {
                    blocks = Some(b);
                    break;
                }
                Err(err) => {
                    eprintln!("blocks {h}..{e} attempt {attempt}: {err}");
                    tokio::time::sleep(std::time::Duration::from_secs(2 + 3 * attempt)).await;
                    lwd = Lwd::connect(&lwd_url()).await?;
                }
            }
        }
        let blocks = blocks.ok_or_else(|| anyhow!("blocks {h}..{e} failed"))?;
        anyhow::ensure!(blocks.len() as u64 == e - h + 1, "got {} blocks for {h}..{e}", blocks.len());
        for b in &blocks {
            for tx in &b.vtx {
                let (o, i) = (tx.actions.len(), tx.ironwood_actions.len());
                if o + i > 0 {
                    writeln!(out, "{} {} {o} {i}", b.height, hex::encode(&tx.txid))?;
                    txs += 1;
                    oa += o as u64;
                    ia += i as u64;
                }
            }
        }
        if (e - start) % 10_000 < 1000 {
            eprintln!("scanned to {e}: {txs} txs, {oa} orchard + {ia} ironwood actions ({:.0}s)", t.elapsed().as_secs_f64());
        }
        h = e + 1;
    }
    writeln!(out, "# done {txs} txs {oa} orchard_actions {ia} ironwood_actions")?;
    eprintln!("done {start}..{end}: {txs} txs, {oa} orchard + {ia} ironwood actions");
    Ok(())
}

// ---------------------------------------------------------------- fetch

fn read_txids() -> Result<Vec<(u64, [u8; 32])>> {
    let f = BufReader::new(File::open(Path::new(DATA).join("txids.txt"))?);
    let mut v = vec![];
    for line in f.lines() {
        let line = line?;
        if line.starts_with('#') {
            continue;
        }
        let mut it = line.split_whitespace();
        let h: u64 = it.next().unwrap().parse()?;
        let id: [u8; 32] = hex::decode(it.next().unwrap())?.try_into().map_err(|_| anyhow!("txid"))?;
        v.push((h, id));
    }
    Ok(v)
}

/// raw.bin records: height u32 | txid [32] | len u32 | bytes
fn read_raw(mut f: impl Read, mut each: impl FnMut(u64, [u8; 32], Vec<u8>) -> Result<()>) -> Result<()> {
    let mut hdr = [0u8; 40];
    loop {
        match f.read_exact(&mut hdr) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(()),
            Err(e) => return Err(e.into()),
        }
        let h = u32::from_le_bytes(hdr[0..4].try_into().unwrap()) as u64;
        let id: [u8; 32] = hdr[4..36].try_into().unwrap();
        let n = u32::from_le_bytes(hdr[36..40].try_into().unwrap()) as usize;
        let mut b = vec![0u8; n];
        if f.read_exact(&mut b).is_err() {
            return Ok(()); // truncated tail from an interrupted run; refetched next time
        }
        each(h, id, b)?;
    }
}

async fn fetch(conc: usize) -> Result<()> {
    let want = read_txids()?;
    let raw_path = Path::new(DATA).join("raw.bin");
    let mut have: HashSet<[u8; 32]> = HashSet::new();
    let mut good_len = 0u64;
    if raw_path.exists() {
        read_raw(BufReader::new(File::open(&raw_path)?), |_, id, b| {
            have.insert(id);
            good_len += 40 + b.len() as u64;
            Ok(())
        })?;
        // drop any truncated tail
        OpenOptions::new().write(true).open(&raw_path)?.set_len(good_len)?;
    }
    let todo: Vec<(u64, [u8; 32])> = want.into_iter().filter(|(_, id)| !have.contains(id)).collect();
    eprintln!("fetch: {} already present, {} to fetch, concurrency {conc}", have.len(), todo.len());
    let todo = Arc::new(tokio::sync::Mutex::new(todo.into_iter()));
    let (tx, mut rx) = tokio::sync::mpsc::channel::<(u64, [u8; 32], Vec<u8>)>(1024);
    let mut workers = vec![];
    for w in 0..conc {
        let todo = todo.clone();
        let tx = tx.clone();
        workers.push(tokio::spawn(async move {
            let mut lwd = None;
            loop {
                let Some((h, id)) = todo.lock().await.next() else { return Ok::<(), anyhow::Error>(()) };
                let mut done = false;
                for attempt in 0..6u64 {
                    if lwd.is_none() {
                        let urls = lwd_urls();
                        match Lwd::connect(&urls[(w + attempt as usize) % urls.len()]).await {
                            Ok(c) => lwd = Some(c),
                            Err(e) => {
                                eprintln!("worker {w} connect: {e}");
                                tokio::time::sleep(std::time::Duration::from_secs(2 + 3 * attempt)).await;
                                continue;
                            }
                        }
                    }
                    let r = tokio::time::timeout(std::time::Duration::from_secs(40), lwd.as_mut().unwrap().raw_tx(&id)).await;
                    let r = r.map_err(|_| anyhow!("request timeout")).and_then(|x| x);
                    match r {
                        Ok(r) => {
                            tx.send((h, id, r.data)).await.ok();
                            done = true;
                            break;
                        }
                        Err(e) => {
                            eprintln!("worker {w} tx {} attempt {attempt}: {e}", hex::encode(id));
                            lwd = None;
                            tokio::time::sleep(std::time::Duration::from_secs(1 + 2 * attempt)).await;
                        }
                    }
                }
                if !done {
                    eprintln!("GAVE UP {}", hex::encode(id));
                }
            }
        }));
    }
    drop(tx);
    let mut f = BufWriter::new(OpenOptions::new().create(true).append(true).open(&raw_path)?);
    let (mut n, mut bytes) = (0u64, 0u64);
    let t = Instant::now();
    while let Some((h, id, b)) = rx.recv().await {
        f.write_all(&(h as u32).to_le_bytes())?;
        f.write_all(&id)?;
        f.write_all(&(b.len() as u32).to_le_bytes())?;
        f.write_all(&b)?;
        n += 1;
        bytes += b.len() as u64;
        if n % 5000 == 0 {
            f.flush()?;
            eprintln!("fetched {n} ({:.0} tx/s, {:.0} MB)", n as f64 / t.elapsed().as_secs_f64(), bytes as f64 / 1e6);
        }
    }
    f.flush()?;
    for w in workers {
        w.await??;
    }
    eprintln!("fetch done: {n} new txs, {:.0} MB in {:.0}s", bytes as f64 / 1e6, t.elapsed().as_secs_f64());
    Ok(())
}

// ---------------------------------------------------------------- build

fn affine_xy(bytes: &[u8; 32]) -> Result<(pallas::Base, pallas::Base)> {
    let p = Option::<pallas::Point>::from(pallas::Point::from_bytes(bytes)).ok_or_else(|| anyhow!("not a point"))?;
    let c: pasta_curves::arithmetic::Coordinates<pallas::Affine> =
        Option::from(p.to_affine().coordinates()).ok_or_else(|| anyhow!("identity"))?;
    Ok((*c.x(), *c.y()))
}

/// The `disableCrossAddress` instance row (orchard `Instance::from_parts` + `Flags::from_byte`).
fn cross_address_disabled(version: BundleVersion, flags: u8) -> bool {
    let enabled = match version.protocol_version() {
        ProtocolVersion::InsecureV1 | ProtocolVersion::V2 => true,
        ProtocolVersion::V3 => flags & 0b100 != 0,
    };
    !enabled
}

/// halo2/verifier's bundle format: n_actions u32 | 10 u32 | proof_len u32 | proof | instances (32 B each)
fn bundle_bytes(proof: &[u8], inst: &[[pallas::Base; 10]]) -> Vec<u8> {
    let mut b = Vec::with_capacity(12 + proof.len() + inst.len() * 320);
    b.extend((inst.len() as u32).to_le_bytes());
    b.extend(10u32.to_le_bytes());
    b.extend((proof.len() as u32).to_le_bytes());
    b.extend(proof);
    for a in inst {
        for v in a {
            b.extend(v.to_repr());
        }
    }
    b
}

struct Item {
    height: u64,
    txid: [u8; 32],
    pool: &'static str,
    version: OrchardCircuitVersion,
    actions: usize,
    file: Vec<u8>,
    official: bool,
}

fn instances_of(b: &orchard::Bundle<Authorized, zcash_protocol::value::ZatBalance>) -> Result<Vec<[pallas::Base; 10]>> {
    let bv = b.bundle_version();
    let flags = b.flags().to_byte(bv).ok_or_else(|| anyhow!("flags"))?;
    let fe = |x: [u8; 32]| Option::<pallas::Base>::from(pallas::Base::from_repr(x)).unwrap();
    let mut inst = vec![];
    for a in b.actions() {
        let cv = a.cv_net().to_bytes();
        let rk: [u8; 32] = a.rk().into();
        let (cvx, cvy) = affine_xy(&cv)?;
        let (rkx, rky) = affine_xy(&rk)?;
        inst.push([
            fe(b.anchor().to_bytes()),
            cvx,
            cvy,
            fe(a.nullifier().to_bytes()),
            rkx,
            rky,
            fe(a.cmx().to_bytes()),
            pallas::Base::from((flags & 1) as u64),
            pallas::Base::from(((flags >> 1) & 1) as u64),
            pallas::Base::from(cross_address_disabled(bv, flags) as u64),
        ]);
    }
    Ok(inst)
}

fn items_of(height: u64, txid: [u8; 32], raw: &[u8], vks: &HashMap<String, VerifyingKey>) -> Result<Vec<Item>> {
    let branch = BranchId::for_height(&MainNetwork, BlockHeight::from_u32(height as u32));
    let tx = Transaction::read(raw, branch).with_context(|| format!("parse {}", hex::encode(txid)))?;
    let mut out = vec![];
    let bundles: Vec<(&'static str, &orchard::Bundle<Authorized, zcash_protocol::value::ZatBalance>)> =
        [("orchard", tx.orchard_bundle()), ("ironwood", tx.ironwood_bundle())]
            .into_iter()
            .filter_map(|(n, b)| b.map(|b| (n, b)))
            .collect();
    for (pool, b) in bundles {
        let bv = b.bundle_version();
        let inst = instances_of(b)?;
        let version = bv.circuit_version();
        let vk = vks.get(&format!("{version:?}")).ok_or_else(|| anyhow!("no vk {version:?}"))?;
        let official = b.verify_proof(vk).is_ok();
        out.push(Item {
            height,
            txid,
            pool,
            version,
            actions: b.actions().len(),
            file: bundle_bytes(b.authorization().proof().as_ref(), &inst),
            official,
        });
    }
    Ok(out)
}

/// Part `part` of `parts`: records whose index i in raw.bin has i % parts == part (txids are
/// deduplicated within a part; scan output has no duplicates). Writes chunks/p<part>c#####/,
/// other/, and official_p<part>.txt, so parts are independent and each fits the heavy.sh caps.
fn build(chunk: usize, part: usize, parts: usize) -> Result<()> {
    let t = Instant::now();
    let mut vks: HashMap<String, VerifyingKey> = HashMap::new();
    for v in [OrchardCircuitVersion::InsecurePreNu6_2, OrchardCircuitVersion::FixedPostNu6_2, OrchardCircuitVersion::PostNu6_3] {
        vks.insert(format!("{v:?}"), VerifyingKey::build(v));
    }
    eprintln!("verifying keys built in {:.1}s", t.elapsed().as_secs_f64());
    let chunks = Path::new(DATA).join("chunks");
    let other = Path::new(DATA).join("other");
    fs::create_dir_all(&chunks)?;
    fs::create_dir_all(&other)?;
    let prefix = format!("p{part:02}c");
    for e in fs::read_dir(&chunks)? {
        let e = e?;
        if e.file_name().to_string_lossy().starts_with(&prefix) {
            fs::remove_dir_all(e.path())?;
        }
    }
    let mut official = BufWriter::new(File::create(Path::new(DATA).join(format!("official_p{part:02}.txt")))?);
    writeln!(official, "# file official_ok actions circuit height txid pool")?;

    let mut batch: Vec<(u64, [u8; 32], Vec<u8>)> = vec![];
    let (mut n_tx, mut n_b, mut n_a, mut n_ok, mut in_chunk, mut chunk_no, mut n_other) = (0u64, 0u64, 0u64, 0u64, 0usize, 0usize, 0u64);
    let mut seen: HashSet<[u8; 32]> = HashSet::new();
    let mut verify_secs = 0.0f64;
    let mut flush = |batch: &mut Vec<(u64, [u8; 32], Vec<u8>)>| -> Result<()> {
        let tv = Instant::now();
        let results: Vec<Result<Vec<Item>>> = batch.par_iter().map(|(h, id, raw)| items_of(*h, *id, raw, &vks)).collect();
        verify_secs += tv.elapsed().as_secs_f64();
        for r in results {
            let items = r?;
            n_tx += 1;
            for it in items {
                n_b += 1;
                n_a += it.actions as u64;
                n_ok += it.official as u64;
                let name = format!("{}_{}.{}.bin", it.height, &hex::encode(it.txid)[..16], it.pool);
                let rel = if it.version == OrchardCircuitVersion::PostNu6_3 {
                    if in_chunk == chunk {
                        chunk_no += 1;
                        in_chunk = 0;
                    }
                    let d = chunks.join(format!("p{part:02}c{chunk_no:05}"));
                    if in_chunk == 0 {
                        fs::create_dir_all(&d)?;
                    }
                    in_chunk += 1;
                    format!("chunks/p{part:02}c{chunk_no:05}/{name}")
                } else {
                    n_other += 1;
                    format!("other/{:?}.p{part:02}.{name}", it.version)
                };
                fs::write(Path::new(DATA).join(&rel), &it.file)?;
                writeln!(official, "{rel} {} {} {:?} {} {} {}", it.official as u8, it.actions, it.version, it.height, hex::encode(it.txid), it.pool)?;
            }
        }
        batch.clear();
        eprintln!("built {n_tx} txs, {n_b} bundles, {n_a} actions, official ok {n_ok}/{n_b} ({:.0}s)", t.elapsed().as_secs_f64());
        Ok(())
    };
    let mut idx = 0usize;
    read_raw(BufReader::new(File::open(Path::new(DATA).join("raw.bin"))?), |h, id, b| {
        idx += 1;
        if (idx - 1) % parts != part {
            return Ok(());
        }
        if seen.insert(id) {
            batch.push((h, id, b));
        }
        if batch.len() >= 4096 {
            flush(&mut batch)?;
        }
        Ok(())
    })?;
    flush(&mut batch)?;
    writeln!(official, "# total txs {n_tx} bundles {n_b} actions {n_a} official_ok {n_ok} other_circuits {n_other} official_verify_cpu_s {verify_secs:.1}")?;
    official.flush()?;
    eprintln!(
        "build done: {n_tx} txs, {n_b} bundles ({n_other} older circuits), {n_a} actions; official ok {n_ok}/{n_b}; parse+verify {verify_secs:.1}s wall (rayon, all cores)"
    );
    Ok(())
}

// ---------------------------------------------------------------- rust batch timing

/// Times the official orchard BatchValidator over all post-NU6.3 bundles (proofs only), for comparison.
fn rust_batch(threads: usize, limit: usize) -> Result<()> {
    let pool = rayon::ThreadPoolBuilder::new().num_threads(threads).build()?;
    let vk = VerifyingKey::build(OrchardCircuitVersion::PostNu6_3);
    let mut bundles = vec![];
    read_raw(BufReader::new(File::open(Path::new(DATA).join("raw.bin"))?), |h, _id, raw| {
        let branch = BranchId::for_height(&MainNetwork, BlockHeight::from_u32(h as u32));
        let tx = Transaction::read(&raw[..], branch)?;
        for b in [tx.orchard_bundle(), tx.ironwood_bundle()].into_iter().flatten() {
            if b.bundle_version().circuit_version() == OrchardCircuitVersion::PostNu6_3 && bundles.len() < limit {
                bundles.push(b.clone());
            }
        }
        Ok(())
    })?;
    let t = Instant::now();
    let ok = pool.install(|| {
        bundles
            .par_chunks(64)
            .map(|c| {
                let mut v = halo2_proofs::plonk::BatchVerifier::new();
                for b in c {
                    let inst: Vec<Vec<Vec<pallas::Base>>> =
                        instances_of(b).unwrap().iter().map(|i| vec![i.to_vec()]).collect();
                    v.add_proof(inst, b.authorization().proof().as_ref().to_vec());
                }
                v.finalize(vk.oracle_params(), vk.oracle_vk())
            })
            .all(|x| x)
    });
    let s = t.elapsed().as_secs_f64();
    println!("rust halo2 BatchVerifier threads={threads}: {} bundles, all ok {ok}, {s:.1}s = {:.0} bundles/s", bundles.len(), bundles.len() as f64 / s);
    Ok(())
}

// ---------------------------------------------------------------- signature sample

/// Writes a seeded random sample of N fully shielded txs (no transparent inputs, so the ZIP 244
/// shielded sighash needs no spent-output context) to ../data/sigs/ as node/tx's tx_main inputs
/// (tx_<k>.bin + an empty tx_<k>.ctx). sigs/expected.txt lists each tx's network txid and its
/// Orchard-protocol action counts; every signature is expected to verify, since mainnet
/// consensus accepted these transactions.
fn sigsample(n: usize, seed: u64) -> Result<()> {
    let dir = Path::new(DATA).join("sigs");
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir)?;
    let mut all: Vec<(u64, [u8; 32], Vec<u8>)> = vec![];
    read_raw(BufReader::new(File::open(Path::new(DATA).join("raw.bin"))?), |h, id, b| {
        all.push((h, id, b));
        Ok(())
    })?;
    // splitmix64 Fisher-Yates, so the sample is reproducible from the seed
    let mut s = seed;
    let mut next = || {
        s = s.wrapping_add(0x9e3779b97f4a7c15);
        let mut z = s;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
        z ^ (z >> 31)
    };
    for i in (1..all.len()).rev() {
        let j = (next() % (i as u64 + 1)) as usize;
        all.swap(i, j);
    }
    let mut exp = BufWriter::new(File::create(dir.join("expected.txt"))?);
    let (mut k, mut skipped) = (0usize, 0usize);
    for (h, id, raw) in all {
        if k == n {
            break;
        }
        let branch = BranchId::for_height(&MainNetwork, BlockHeight::from_u32(h as u32));
        let tx = Transaction::read(&raw[..], branch)?;
        if tx.transparent_bundle().is_some_and(|t| !t.vin.is_empty()) {
            skipped += 1;
            continue;
        }
        let txid: [u8; 32] = *tx.txid().as_ref();
        anyhow::ensure!(txid == id, "txid mismatch");
        let oa = tx.orchard_bundle().map_or(0, |b| b.actions().len());
        let ia = tx.ironwood_bundle().map_or(0, |b| b.actions().len());
        writeln!(exp, "tx_{k} {h} {} {oa} {ia}", hex::encode(txid))?;
        fs::write(dir.join(format!("tx_{k}.bin")), &raw)?;
        fs::write(dir.join(format!("tx_{k}.ctx")), [0u8; 8])?;
        k += 1;
    }
    exp.flush()?;
    eprintln!("sigsample: wrote {k} fully shielded txs (skipped {skipped} with transparent inputs), seed {seed}");
    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    let a: Vec<String> = std::env::args().collect();
    let arg = |i: usize| a.get(i).map(|s| s.parse::<u64>()).transpose();
    fs::create_dir_all(DATA)?;
    match a.get(1).map(String::as_str) {
        Some("scan") => scan(arg(2)?.unwrap_or(IRONWOOD_ACTIVATION), arg(3)?).await,
        Some("fetch") => fetch(arg(2)?.unwrap_or(16) as usize).await,
        Some("build") => build(arg(2)?.unwrap_or(64) as usize, arg(3)?.unwrap_or(0) as usize, arg(4)?.unwrap_or(1) as usize),
        Some("rust-batch") => rust_batch(arg(2)?.unwrap_or(1) as usize, arg(3)?.unwrap_or(u64::MAX) as usize),
        Some("sigsample") => sigsample(arg(2)?.unwrap_or(2000) as usize, arg(3)?.unwrap_or(2026)),
        _ => Err(anyhow!("usage: scan [START] [END] | fetch [CONC] | build [CHUNK] [PART] [PARTS] | rust-batch [THREADS] [LIMIT] | sigsample [N] [SEED]")),
    }
}
