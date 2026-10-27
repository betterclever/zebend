//! Real mainnet Sapling signatures: scan / fetch / build chunks + official per-signature verdicts,
//! tamper sets, and the Rust (redjubjub) baseline timings.

use std::{
    collections::HashSet,
    fs::{self, File, OpenOptions},
    io::{BufRead, BufReader, BufWriter, Read, Write},
    path::{Path, PathBuf},
    sync::Arc,
    time::Instant,
};

use anyhow::{anyhow, bail, ensure, Result};
use group::GroupEncoding;
use rand_chacha::ChaCha20Rng;
use rand_core::{Rng, SeedableRng};
use rayon::prelude::*;
use redjubjub::{Binding, Signature, SpendAuth, VerificationKey, VerificationKeyBytes};

use crate::lwd::{self, Lwd, POOL_SAPLING, POOL_TRANSPARENT};
use crate::txutil;
use crate::DATA;

pub fn data() -> PathBuf {
    Path::new(DATA).to_path_buf()
}
fn sigdir() -> PathBuf {
    data().join("sigs")
}

// ---------------------------------------------------------------- scan

/// Appends to sig_txids.txt every tx with a Sapling spend or output in windows of WINDOW blocks
/// every STRIDE blocks of FROM..=TO: "height txid n_spends n_outputs n_tin".
pub async fn scan(from: u64, to: u64, window: u64, stride: u64) -> Result<()> {
    let path = data().join("sig_txids.txt");
    let mut out = BufWriter::new(OpenOptions::new().create(true).append(true).open(&path)?);
    writeln!(out, "# scan {from}..{to} window {window} stride {stride}")?;
    let (mut txs, mut sp, mut op) = (0u64, 0u64, 0u64);
    let t = Instant::now();
    let mut h = from;
    while h <= to {
        let e = (h + window - 1).min(to);
        let blocks = lwd::blocks_retry(h, e, vec![POOL_SAPLING, POOL_TRANSPARENT], 0).await?;
        for b in &blocks {
            for tx in &b.vtx {
                let (s, o) = (tx.spends.len(), tx.outputs.len());
                if s + o > 0 {
                    writeln!(out, "{} {} {s} {o} {}", b.height, hex::encode(&tx.txid), tx.vin.len())?;
                    txs += 1;
                    sp += s as u64;
                    op += o as u64;
                }
            }
        }
        h += stride;
    }
    out.flush()?;
    eprintln!("scan {from}..{to}: {txs} txs, {sp} spends, {op} outputs ({:.0}s)", t.elapsed().as_secs_f64());
    Ok(())
}

// ---------------------------------------------------------------- fetch

pub fn read_txids(name: &str) -> Result<Vec<(u64, [u8; 32])>> {
    let f = BufReader::new(File::open(data().join(name))?);
    let mut v = vec![];
    let mut seen = HashSet::new();
    for line in f.lines() {
        let line = line?;
        if line.starts_with('#') || line.trim().is_empty() {
            continue;
        }
        // tolerate a partially written last line (the scan may still be appending)
        let w: Vec<&str> = line.split_whitespace().collect();
        if w.len() < 5 {
            continue;
        }
        let Ok(h) = w[0].parse::<u64>() else { continue };
        let Some(id) = hex::decode(w[1]).ok().and_then(|b| <[u8; 32]>::try_from(b).ok()) else { continue };
        if seen.insert(id) {
            v.push((h, id));
        }
    }
    Ok(v)
}

/// raw file records: height u32 | txid [32] | len u32 | bytes   (same as proofsets/oracle)
pub fn read_raw(mut f: impl Read, mut each: impl FnMut(u64, [u8; 32], Vec<u8>) -> Result<()>) -> Result<()> {
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
            return Ok(());
        }
        each(h, id, b)?;
    }
}

pub async fn fetch(list: &str, raw: &str, conc: usize) -> Result<()> {
    let want = read_txids(list)?;
    let raw_path = data().join(raw);
    let mut have: HashSet<[u8; 32]> = HashSet::new();
    let mut good_len = 0u64;
    if raw_path.exists() {
        read_raw(BufReader::new(File::open(&raw_path)?), |_, id, b| {
            have.insert(id);
            good_len += 40 + b.len() as u64;
            Ok(())
        })?;
        OpenOptions::new().write(true).open(&raw_path)?.set_len(good_len)?;
    }
    let todo: Vec<(u64, [u8; 32])> = want.into_iter().filter(|(_, id)| !have.contains(id)).collect();
    eprintln!("fetch: {} present, {} to fetch, concurrency {conc}", have.len(), todo.len());
    let todo = Arc::new(tokio::sync::Mutex::new(todo.into_iter()));
    let (tx, mut rx) = tokio::sync::mpsc::channel::<(u64, [u8; 32], Vec<u8>)>(1024);
    let mut workers = vec![];
    for w in 0..conc {
        let todo = todo.clone();
        let tx = tx.clone();
        workers.push(tokio::spawn(async move {
            let mut l: Option<Lwd> = None;
            loop {
                let Some((h, id)) = todo.lock().await.next() else { return };
                let mut done = false;
                for attempt in 0..8u64 {
                    if l.is_none() {
                        let us = lwd::urls();
                        match Lwd::connect(&us[(w + attempt as usize) % us.len()]).await {
                            Ok(c) => l = Some(c),
                            Err(e) => {
                                eprintln!("worker {w} connect: {e}");
                                tokio::time::sleep(std::time::Duration::from_secs(2 + 3 * attempt)).await;
                                continue;
                            }
                        }
                    }
                    let r = tokio::time::timeout(std::time::Duration::from_secs(40), l.as_mut().unwrap().raw_tx(&id)).await;
                    match r.map_err(|_| anyhow!("timeout")).and_then(|x| x) {
                        Ok(r) => {
                            tx.send((if h == 0 { r.height } else { h }, id, r.data)).await.ok();
                            done = true;
                            break;
                        }
                        Err(e) => {
                            eprintln!("worker {w} tx {} attempt {attempt}: {e}", hex::encode(id));
                            l = None;
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
        w.await?;
    }
    eprintln!("fetch done: {n} new txs, {:.0} MB in {:.0}s", bytes as f64 / 1e6, t.elapsed().as_secs_f64());
    Ok(())
}

// ---------------------------------------------------------------- items

#[derive(Clone)]
pub struct Item {
    pub kind: u32, // 0 spend-auth, 1 binding
    pub nsp: u32,
    pub nout: u32,
    pub vb: i64,
    pub r: [u8; 32],
    pub s: [u8; 32],
    pub msg: [u8; 32],
    pub vk: [u8; 32],
    pub cvs: Vec<[u8; 32]>,
}

impl Item {
    pub fn encode(&self, out: &mut Vec<u8>) {
        out.extend(self.kind.to_le_bytes());
        out.extend((self.nsp | (self.nout << 16)).to_le_bytes());
        out.extend((self.vb as u64 as u32).to_le_bytes());
        out.extend(((self.vb as u64 >> 32) as u32).to_le_bytes());
        out.extend(self.r);
        out.extend(self.s);
        out.extend(self.msg);
        out.extend(self.vk);
        for c in &self.cvs {
            out.extend(c);
        }
    }
    pub fn len(&self) -> usize {
        16 + 128 + 32 * self.cvs.len()
    }
    /// Verdict straight from the item bytes, using redjubjub (VerificationKey::try_from + verify).
    pub fn verify(&self) -> bool {
        let mut sig = [0u8; 64];
        sig[..32].copy_from_slice(&self.r);
        sig[32..].copy_from_slice(&self.s);
        if self.kind == 0 {
            match VerificationKey::<SpendAuth>::try_from(self.vk) {
                Ok(k) => k.verify(&self.msg, &Signature::<SpendAuth>::from(sig)).is_ok(),
                Err(_) => false,
            }
        } else {
            let Some(bvk) = self.bvk() else { return false };
            match VerificationKey::<Binding>::try_from(bvk) {
                Ok(k) => k.verify(&self.msg, &Signature::<Binding>::from(sig)).is_ok(),
                Err(_) => false,
            }
        }
    }
    pub fn cv_points(&self) -> Option<Vec<jubjub::ExtendedPoint>> {
        self.cvs.iter().map(|c| Option::<jubjub::ExtendedPoint>::from(jubjub::ExtendedPoint::from_bytes(c))).collect()
    }
    pub fn bvk(&self) -> Option<[u8; 32]> {
        let p = self.cv_points()?;
        let ns = self.nsp as usize;
        Some(txutil::bvk(&p[..ns], &p[ns..], self.vb))
    }
}

pub fn decode_chunk(b: &[u8]) -> Result<Vec<Item>> {
    let u = |o: usize| u32::from_le_bytes(b[o..o + 4].try_into().unwrap());
    let n = u(0) as usize;
    let mut o = 4;
    let mut v = Vec::with_capacity(n);
    for _ in 0..n {
        let kind = u(o);
        let ncv = u(o + 4);
        let vb = (u(o + 8) as u64 | ((u(o + 12) as u64) << 32)) as i64;
        let (nsp, nout) = (ncv & 0xffff, ncv >> 16);
        let f = |k: usize| -> [u8; 32] { b[o + 16 + 32 * k..o + 48 + 32 * k].try_into().unwrap() };
        let cvs = (0..(nsp + nout) as usize).map(|k| f(4 + k)).collect();
        let it = Item { kind, nsp, nout, vb, r: f(0), s: f(1), msg: f(2), vk: f(3), cvs };
        o += it.len();
        v.push(it);
    }
    ensure!(o == b.len(), "chunk length mismatch");
    Ok(v)
}

struct TxItems {
    height: u64,
    txid: [u8; 32],
    version: u32,
    items: Vec<Item>,
    official: Vec<bool>,
}

enum TxOut {
    Items(TxItems),
    Skip(&'static str),
}

/// Parse a raw tx, compute the shielded sighash with zcash_primitives, and verify every Sapling
/// signature with redjubjub (spend-auth: rk; binding: bvk from cvs and valueBalance).
fn tx_items(h: u64, id: [u8; 32], raw: &[u8]) -> Result<TxOut> {
    let tx = txutil::parse(h, raw)?;
    ensure!(*tx.txid().as_ref() == id, "txid mismatch at {h} {}", hex::encode(id));
    let version = txutil::version_num(&tx);
    if version > 5 {
        return Ok(TxOut::Skip("v6"));
    }
    if version == 5 && txutil::n_tin(&tx) > 0 {
        return Ok(TxOut::Skip("v5 with transparent inputs (needs prevouts)"));
    }
    let Some(b) = tx.sapling_bundle() else { return Ok(TxOut::Skip("no sapling bundle")) };
    let msg = txutil::shielded_sighash(&tx, txutil::Ctx::default())?;
    let vb: i64 = (*b.value_balance()).into();
    let mut items = vec![];
    let mut official = vec![];
    let mut spend_cvs = vec![];
    let mut out_cvs = vec![];
    for sp in b.shielded_spends() {
        let sig: [u8; 64] = sp.spend_auth_sig().clone().into();
        let rk: [u8; 32] = sp.rk().clone().into();
        official.push(sp.rk().verify(&msg, sp.spend_auth_sig()).is_ok());
        items.push(Item { kind: 0, nsp: 0, nout: 0, vb: 0, r: sig[..32].try_into()?, s: sig[32..].try_into()?, msg, vk: rk, cvs: vec![] });
        spend_cvs.push(*sp.cv().as_inner());
    }
    for o in b.shielded_outputs() {
        out_cvs.push(*o.cv().as_inner());
    }
    let bsig: [u8; 64] = b.authorization().binding_sig.clone().into();
    let bvk = txutil::bvk(&spend_cvs, &out_cvs, vb);
    official.push(match VerificationKey::<Binding>::try_from(bvk) {
        Ok(k) => k.verify(&msg, &b.authorization().binding_sig).is_ok(),
        Err(_) => false,
    });
    let cvs: Vec<[u8; 32]> = b.shielded_spends().iter().map(|s| s.cv().to_bytes()).chain(b.shielded_outputs().iter().map(|o| o.cv().to_bytes())).collect();
    items.push(Item {
        kind: 1,
        nsp: spend_cvs.len() as u32,
        nout: out_cvs.len() as u32,
        vb,
        r: bsig[..32].try_into()?,
        s: bsig[32..].try_into()?,
        msg,
        vk: [0; 32],
        cvs,
    });
    // The bytes we write must give the same verdict on their own.
    for (it, ok) in items.iter().zip(&official) {
        ensure!(it.verify() == *ok, "item re-verification disagrees in {}", hex::encode(id));
    }
    Ok(TxOut::Items(TxItems { height: h, txid: id, version, items, official }))
}

pub const CHUNK_MAX: usize = 8192;

/// Builds sigs/chunk_XXXX.bin + verdicts_XXXX.txt + manifest.txt from sig_raw.bin.
/// Txs are taken in chain order; at most MAX_SIGS signatures in total.
pub fn build(max_sigs: usize) -> Result<()> {
    let dir = sigdir();
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir)?;
    let mut recs: Vec<(u64, [u8; 32], Vec<u8>)> = vec![];
    let mut seen = HashSet::new();
    read_raw(BufReader::new(File::open(data().join("sig_raw.bin"))?), |h, id, b| {
        if seen.insert(id) {
            recs.push((h, id, b));
        }
        Ok(())
    })?;
    recs.sort_by_key(|r| r.0);
    eprintln!("{} raw txs", recs.len());
    let t = Instant::now();
    let results: Vec<Result<TxOut>> = recs.par_iter().map(|(h, id, raw)| tx_items(*h, *id, raw)).collect();
    eprintln!("parsed + sighash + official verify: {:.1}s (rayon)", t.elapsed().as_secs_f64());
    let mut man = BufWriter::new(File::create(dir.join("manifest.txt"))?);
    writeln!(man, "# chunk index txid(internal byte order, = lightwalletd/hash order) height version kind(0 spend-auth, 1 binding)")?;
    let mut chunk: Vec<u8> = vec![];
    let mut verd = String::new();
    let (mut nchunk, mut in_chunk) = (0usize, 0usize);
    let mut stats = std::collections::BTreeMap::<String, u64>::new();
    let mut skips = std::collections::BTreeMap::<&'static str, u64>::new();
    let mut total = 0usize;
    let mut bad = 0u64;
    let flush = |chunk: &mut Vec<u8>, verd: &mut String, nchunk: &mut usize, in_chunk: &mut usize| -> Result<()> {
        if *in_chunk == 0 {
            return Ok(());
        }
        let mut f = (*in_chunk as u32).to_le_bytes().to_vec();
        f.extend_from_slice(chunk);
        fs::write(dir.join(format!("chunk_{:04}.bin", *nchunk)), &f)?;
        fs::write(dir.join(format!("verdicts_{:04}.txt", *nchunk)), &*verd)?;
        chunk.clear();
        verd.clear();
        *nchunk += 1;
        *in_chunk = 0;
        Ok(())
    };
    for r in results {
        let tx = match r? {
            TxOut::Skip(why) => {
                *skips.entry(why).or_default() += 1;
                continue;
            }
            TxOut::Items(t) => t,
        };
        if total + tx.items.len() > max_sigs {
            break;
        }
        if in_chunk + tx.items.len() > CHUNK_MAX {
            flush(&mut chunk, &mut verd, &mut nchunk, &mut in_chunk)?;
        }
        ensure!(tx.items.len() <= CHUNK_MAX, "tx with {} signatures", tx.items.len());
        for (it, ok) in tx.items.iter().zip(&tx.official) {
            it.encode(&mut chunk);
            verd.push_str(if *ok { "1\n" } else { "0\n" });
            bad += !*ok as u64;
            writeln!(man, "{nchunk} {in_chunk} {} {} {} {}", hex::encode(tx.txid), tx.height, tx.version, it.kind)?;
            *stats.entry(format!("v{} {}", tx.version, if it.kind == 0 { "spend-auth" } else { "binding" })).or_default() += 1;
            in_chunk += 1;
            total += 1;
        }
        *stats.entry(format!("v{} txs", tx.version)).or_default() += 1;
    }
    flush(&mut chunk, &mut verd, &mut nchunk, &mut in_chunk)?;
    man.flush()?;
    println!("built {nchunk} chunks, {total} signatures ({bad} officially invalid)");
    for (k, v) in &stats {
        println!("  {k}: {v}");
    }
    for (k, v) in &skips {
        println!("  skipped {k}: {v} txs");
    }
    Ok(())
}

pub fn chunk_paths() -> Result<Vec<PathBuf>> {
    let mut v: Vec<PathBuf> = fs::read_dir(sigdir())?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.file_name().unwrap().to_string_lossy().starts_with("chunk_"))
        .collect();
    v.sort();
    Ok(v)
}

/// Byte range of field `f` within an encoded item at offset o.
fn field_range(it: &Item, f: &str) -> Result<(usize, usize)> {
    Ok(match f {
        "vb" => (8, 8),
        "R" => (16, 32),
        "s" => (48, 32),
        "msg" => (80, 32),
        "vk" => (112, 32),
        "cv" => {
            ensure!(!it.cvs.is_empty(), "item has no cv");
            (144, 32 * it.cvs.len())
        }
        _ => bail!("field must be R|s|msg|vk|vb|cv"),
    })
}

fn item_offsets(items: &[Item]) -> Vec<usize> {
    let mut o = 4;
    items
        .iter()
        .map(|it| {
            let x = o;
            o += it.len();
            x
        })
        .collect()
}

/// tamper K FIELD I [BYTE] [MASK]: flip one byte of item I in FIELD of chunk K.
pub fn tamper(k: usize, field: &str, i: usize, byte: Option<usize>, mask: Option<u8>) -> Result<()> {
    let p = sigdir().join(format!("chunk_{k:04}.bin"));
    let mut b = fs::read(&p)?;
    let items = decode_chunk(&b)?;
    ensure!(i < items.len(), "item index");
    let off = item_offsets(&items)[i];
    let (fo, fl) = field_range(&items[i], field)?;
    let byte = byte.unwrap_or(0) % fl;
    let mask = mask.unwrap_or(0x01);
    b[off + fo + byte] ^= mask;
    let items2 = decode_chunk(&b)?;
    let v = items2[i].verify();
    let out = sigdir().join(format!("tamper_{field}_{k}_{i}.bin"));
    fs::write(&out, &b)?;
    println!("{} item {i} field {field} byte {byte} ^= {mask:#04x}: rust verdict {}", out.display(), v as u8);
    Ok(())
}

/// tampermix N SEED: for chunks 0..N, flip one random byte of a random field in ~5% of items.
pub fn tampermix(n: usize, seed: u64) -> Result<()> {
    let mut rng = ChaCha20Rng::seed_from_u64(seed);
    let fields = ["R", "s", "msg", "vk", "vb", "cv"];
    for (k, p) in chunk_paths()?.iter().take(n).enumerate() {
        let mut b = fs::read(p)?;
        let items = decode_chunk(&b)?;
        let offs = item_offsets(&items);
        let mut log = String::new();
        let mut flipped = 0;
        for (i, it) in items.iter().enumerate() {
            if rng.next_u32() % 20 != 0 {
                continue;
            }
            let mut f = fields[(rng.next_u32() % 6) as usize];
            if f == "cv" && it.cvs.is_empty() {
                f = "R";
            }
            let (fo, fl) = field_range(it, f)?;
            let byte = (rng.next_u32() as usize) % fl;
            let mask = 1u8 << (rng.next_u32() % 8);
            b[offs[i] + fo + byte] ^= mask;
            log.push_str(&format!("{i} {f} {byte} {mask}\n"));
            flipped += 1;
        }
        let items2 = decode_chunk(&b)?;
        let verd: Vec<bool> = items2.par_iter().map(|it| it.verify()).collect();
        let s: String = verd.iter().map(|v| if *v { "1\n" } else { "0\n" }).collect();
        fs::write(sigdir().join(format!("tampermix_{k:04}.bin")), &b)?;
        fs::write(sigdir().join(format!("tampermix_verdicts_{k:04}.txt")), s)?;
        fs::write(sigdir().join(format!("tampermix_flips_{k:04}.txt")), log)?;
        println!("tampermix_{k:04}: {} items, {flipped} flipped, {} invalid", items2.len(), verd.iter().filter(|v| !**v).count());
    }
    Ok(())
}

struct Dec {
    kind: u32,
    sig: [u8; 64],
    msg: [u8; 32],
    vk: [u8; 32],
    nsp: usize,
    vb: i64,
    cvs: Vec<jubjub::ExtendedPoint>,
}

/// Rust baseline: batch verification (redjubjub::batch::Verifier, one per chunk) and single
/// verification throughput, on a rayon pool of THREADS. Decoding of chunk bytes (incl. cv points)
/// is untimed; bvk computation is inside the timed region.
pub fn rust(threads: usize) -> Result<()> {
    let pool = rayon::ThreadPoolBuilder::new().num_threads(threads).build()?;
    let mut chunks: Vec<Vec<Dec>> = vec![];
    for p in chunk_paths()? {
        let items = decode_chunk(&fs::read(&p)?)?;
        chunks.push(
            items
                .iter()
                .map(|it| {
                    let mut sig = [0u8; 64];
                    sig[..32].copy_from_slice(&it.r);
                    sig[32..].copy_from_slice(&it.s);
                    Dec { kind: it.kind, sig, msg: it.msg, vk: it.vk, nsp: it.nsp as usize, vb: it.vb, cvs: it.cv_points().expect("cv decode") }
                })
                .collect(),
        );
    }
    let n: usize = chunks.iter().map(|c| c.len()).sum();
    let bvk_of = |d: &Dec| txutil::bvk(&d.cvs[..d.nsp], &d.cvs[d.nsp..], d.vb);
    let t = Instant::now();
    let oks: Vec<bool> = pool.install(|| {
        chunks
            .par_iter()
            .enumerate()
            .map(|(k, c)| {
                let mut v = redjubjub::batch::Verifier::new();
                for d in c {
                    if d.kind == 0 {
                        v.queue((VerificationKeyBytes::<SpendAuth>::from(d.vk), Signature::<SpendAuth>::from(d.sig), &d.msg));
                    } else {
                        v.queue((VerificationKeyBytes::<Binding>::from(bvk_of(d)), Signature::<Binding>::from(d.sig), &d.msg));
                    }
                }
                v.verify(ChaCha20Rng::seed_from_u64(k as u64)).is_ok()
            })
            .collect()
    });
    let tb = t.elapsed().as_secs_f64();
    println!(
        "rust batch threads={threads}: {} chunks, {n} sigs, all chunks ok {}, {tb:.3}s = {:.0} sigs/s",
        chunks.len(),
        oks.iter().all(|x| *x),
        n as f64 / tb
    );
    let t = Instant::now();
    let ok: usize = pool.install(|| {
        chunks
            .par_iter()
            .flat_map(|c| c.par_iter())
            .map(|d| {
                (if d.kind == 0 {
                    VerificationKey::<SpendAuth>::try_from(d.vk).map(|k| k.verify(&d.msg, &Signature::from(d.sig)).is_ok()).unwrap_or(false)
                } else {
                    VerificationKey::<Binding>::try_from(bvk_of(d)).map(|k| k.verify(&d.msg, &Signature::from(d.sig)).is_ok()).unwrap_or(false)
                }) as usize
            })
            .sum()
    });
    let ts = t.elapsed().as_secs_f64();
    println!("rust single threads={threads}: {n} sigs, {ok} valid, {ts:.3}s = {:.0} sigs/s", n as f64 / ts);
    Ok(())
}
