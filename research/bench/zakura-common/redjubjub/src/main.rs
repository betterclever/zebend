//! zcash/sapling/oracle's `rust THREADS` RedJubjub baseline, on the Zakura Common crates.
//!
//!   rust THREADS [DIR]   same two lines as the upstream oracle (one redjubjub::batch::Verifier
//!                        per chunk, rayon over chunks; single verification), plus the batch
//!                        shape Zakura itself uses (below). DIR defaults to zcash/sapling/data/sigs.
//!   verdicts FILE        one single-verification verdict (1/0) per item of a chunk file:
//!                        diff against verdicts_NNNN.txt / tampermix_verdicts_NNNN.txt
//!
//! Chunk format and bvk computation: as zcash/sapling/oracle/src/sigs.rs (decoding untimed,
//! bvk inside the timed region).
//!
//! Zakura's path (zakura-consensus primitives/sapling.rs -> sapling_crypto::BatchValidator):
//! the signatures of each tower batch go into one redjubjub::batch::Verifier, verified with
//! thread_rng before the batch's proofs. A batch flushes once its weight (spends + outputs per
//! bundle, at least 1) reaches 64 (MAX_BATCH_SIZE), or after 100 ms. Batches run on rayon.

use std::{
    fs,
    path::{Path, PathBuf},
    time::Instant,
};

use anyhow::{anyhow, ensure, Result};
use group::GroupEncoding;
use rand_chacha::ChaCha20Rng;
use rand_core::SeedableRng;
use rayon::prelude::*;
use redjubjub::{Binding, Signature, SpendAuth, VerificationKey, VerificationKeyBytes};

const SIGS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../zcash/sapling/data/sigs");
const MAX_BATCH_SIZE: usize = 64;

struct Dec {
    kind: u32, // 0 spend-auth, 1 binding
    nsp: usize,
    nout: usize,
    vb: i64,
    sig: [u8; 64],
    msg: [u8; 32],
    vk: [u8; 32],
    /// None when a cv does not decode (tamper sets): every verification of it then fails
    cvs: Option<Vec<jubjub::ExtendedPoint>>,
}

fn decode_chunk(b: &[u8]) -> Result<Vec<Dec>> {
    let u = |o: usize| u32::from_le_bytes(b[o..o + 4].try_into().unwrap());
    let n = u(0) as usize;
    let mut o = 4;
    let mut v = Vec::with_capacity(n);
    for _ in 0..n {
        let kind = u(o);
        let ncv = u(o + 4);
        let vb = (u(o + 8) as u64 | ((u(o + 12) as u64) << 32)) as i64;
        let (nsp, nout) = ((ncv & 0xffff) as usize, (ncv >> 16) as usize);
        let f = |k: usize| -> [u8; 32] { b[o + 16 + 32 * k..o + 48 + 32 * k].try_into().unwrap() };
        let mut sig = [0u8; 64];
        sig[..32].copy_from_slice(&f(0));
        sig[32..].copy_from_slice(&f(1));
        let cvs = (0..nsp + nout).map(|k| Option::<jubjub::ExtendedPoint>::from(jubjub::ExtendedPoint::from_bytes(&f(4 + k)))).collect();
        v.push(Dec { kind, nsp, nout, vb, sig, msg: f(2), vk: f(3), cvs });
        o += 16 + 128 + 32 * (nsp + nout);
    }
    ensure!(o == b.len(), "chunk length mismatch");
    Ok(v)
}

fn chunk_paths(dir: &Path) -> Result<Vec<PathBuf>> {
    let mut v: Vec<PathBuf> = fs::read_dir(dir)?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.file_name().unwrap().to_string_lossy().starts_with("chunk_"))
        .collect();
    v.sort();
    Ok(v)
}

fn i64_to_fr(v: i64) -> jubjub::Fr {
    if v >= 0 {
        jubjub::Fr::from(v as u64)
    } else {
        -jubjub::Fr::from(v.unsigned_abs())
    }
}

/// bvk = sum(cv_spend) - sum(cv_output) - [valueBalance] V   (protocol spec 4.13)
fn bvk(d: &Dec) -> Option<[u8; 32]> {
    let cvs = d.cvs.as_ref()?;
    let v = jubjub::ExtendedPoint::from(sapling_crypto::constants::VALUE_COMMITMENT_VALUE_GENERATOR);
    let mut acc = jubjub::ExtendedPoint::identity();
    for c in &cvs[..d.nsp] {
        acc += c;
    }
    for c in &cvs[d.nsp..] {
        acc -= c;
    }
    acc -= v * i64_to_fr(d.vb);
    Some(acc.to_bytes())
}

/// false when the binding key can't be formed (a cv doesn't decode): the batch then fails.
fn queue(v: &mut redjubjub::batch::Verifier, d: &Dec) -> bool {
    if d.kind == 0 {
        v.queue((VerificationKeyBytes::<SpendAuth>::from(d.vk), Signature::<SpendAuth>::from(d.sig), &d.msg));
    } else {
        let Some(b) = bvk(d) else { return false };
        v.queue((VerificationKeyBytes::<Binding>::from(b), Signature::<Binding>::from(d.sig), &d.msg));
    }
    true
}

fn single(d: &Dec) -> bool {
    if d.kind == 0 {
        VerificationKey::<SpendAuth>::try_from(d.vk).map(|k| k.verify(&d.msg, &Signature::from(d.sig)).is_ok()).unwrap_or(false)
    } else {
        bvk(d).and_then(|b| VerificationKey::<Binding>::try_from(b).ok()).map(|k| k.verify(&d.msg, &Signature::from(d.sig)).is_ok()).unwrap_or(false)
    }
}

/// Zakura's batches: whole bundles (a tx's spend-auth sigs then its binding sig), flushed when
/// the summed weight (nsp + nout, at least 1, per bundle) reaches MAX_BATCH_SIZE.
fn zakura_batches(chunks: &[Vec<Dec>]) -> Vec<Vec<&Dec>> {
    let (mut out, mut cur, mut w) = (vec![], vec![], 0usize);
    for d in chunks.iter().flatten() {
        cur.push(d);
        if d.kind == 1 {
            w += (d.nsp + d.nout).max(1);
            if w >= MAX_BATCH_SIZE {
                out.push(std::mem::take(&mut cur));
                w = 0;
            }
        }
    }
    if !cur.is_empty() {
        out.push(cur);
    }
    out
}

fn rust(threads: usize, dir: &Path) -> Result<()> {
    let pool = rayon::ThreadPoolBuilder::new().num_threads(threads).build()?;
    let chunks: Vec<Vec<Dec>> = chunk_paths(dir)?.iter().map(|p| decode_chunk(&fs::read(p)?)).collect::<Result<_>>()?;
    let n: usize = chunks.iter().map(|c| c.len()).sum();
    let t = Instant::now();
    let oks: Vec<bool> = pool.install(|| {
        chunks
            .par_iter()
            .enumerate()
            .map(|(k, c)| {
                let mut v = redjubjub::batch::Verifier::new();
                c.iter().all(|d| queue(&mut v, d)) && v.verify(ChaCha20Rng::seed_from_u64(k as u64)).is_ok()
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
    let ok: usize = pool.install(|| chunks.par_iter().flat_map(|c| c.par_iter()).map(|d| single(d) as usize).sum());
    let ts = t.elapsed().as_secs_f64();
    println!("rust single threads={threads}: {n} sigs, {ok} valid, {ts:.3}s = {:.0} sigs/s", n as f64 / ts);
    let batches = zakura_batches(&chunks);
    let t = Instant::now();
    let ok = pool.install(|| {
        batches.par_iter().all(|b| {
            let mut v = redjubjub::batch::Verifier::new();
            b.iter().all(|d| queue(&mut v, d)) && v.verify(rand::rng()).is_ok()
        })
    });
    let tz = t.elapsed().as_secs_f64();
    println!(
        "zakura batch(weight {MAX_BATCH_SIZE}) threads={threads}: {} batches, {n} sigs, all ok {ok}, {tz:.3}s = {:.0} sigs/s",
        batches.len(),
        n as f64 / tz
    );
    Ok(())
}

fn verdicts(path: &str) -> Result<()> {
    let items = decode_chunk(&fs::read(path)?)?;
    let v: Vec<bool> = items.par_iter().map(single).collect();
    for x in v {
        println!("{}", x as u8);
    }
    Ok(())
}

fn main() -> Result<()> {
    let a: Vec<String> = std::env::args().collect();
    match a.get(1).map(String::as_str) {
        Some("rust") => rust(a.get(2).map(|s| s.parse()).transpose()?.unwrap_or(1), Path::new(a.get(3).map(String::as_str).unwrap_or(SIGS))),
        Some("verdicts") => verdicts(a.get(2).ok_or_else(|| anyhow!("FILE"))?),
        _ => Err(anyhow!("usage: rust THREADS [DIR] | verdicts FILE")),
    }
}
