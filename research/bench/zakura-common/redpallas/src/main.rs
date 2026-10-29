//! research/sigbatch/oracle's Rust baseline for batched RedPallas verification, rebuilt on the
//! Zakura Common crates (zakura-reddsa, zakura-primitives). Read-only on research/sigbatch/data:
//!
//!   rust THREADS   as research/sigbatch/oracle
//!   verify FILE..  the batch verdict for each chunk file (e.g. data/tamper_*.bin)
//!
//! The original's notes follow.
//!
//!   extract N      ../data/chunk_*.bin: every spend-auth and binding signature of every fully
//!                  shielded tx in research/proofsets/data/sigs, N items per chunk (a tx never splits)
//!   rust THREADS   reddsa batch verification of all chunks (bvk derived from cv_net and
//!                  valueBalance inside the timed region, as Bend does)
//!   tamper K FIELD I  writes ../data/tamper_<field>_<I>.bin: chunk K with one byte of item I changed
//!                  (FIELD R, s, msg, vk, vb (valueBalance), cv (first cv of a binding item))
//!
//! Item record (all integers u32 LE):
//!   kind (0 spend-auth, 1 binding) | ncv | vb_lo | vb_hi | R[32] | s[32] | msg[32] | vk[32] | cv[32]*ncv
//! For spend-auth items vk = rk and ncv = 0; for binding items vk is zero and the verifier
//! derives bvk = Σ cv_net − [valueBalance] V itself.
use std::{
    fs,
    time::Instant,
};

use anyhow::{anyhow, Result};
use group::{Group, GroupEncoding};
use pasta_curves::pallas;
use rayon::prelude::*;
use reddsa::{batch, orchard as rp, Signature, VerificationKeyBytes};

const DATA: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../sigbatch/data");

/// Orchard value-commitment base V (compressed), as zcash/tx/consts.bend V_CV.
const V_CV: [u8; 32] = [
    0x67, 0x43, 0xf9, 0x3a, 0x6e, 0xbd, 0xa7, 0x2a, 0x8c, 0x7c, 0x5a, 0x2b, 0x7f, 0xa3, 0x04, 0xfe,
    0x32, 0xb2, 0x9b, 0x4f, 0x70, 0x6a, 0xa8, 0xf7, 0x42, 0x0f, 0x3d, 0x8e, 0x7a, 0x59, 0x70, 0x2f,
];

struct Item {
    binding: bool,
    vb: i64,
    r: [u8; 32],
    s: [u8; 32],
    msg: [u8; 32],
    vk: [u8; 32],
    cvs: Vec<[u8; 32]>,
}


fn decode(b: &[u8]) -> Result<Vec<Item>> {
    let u = |at: usize| u32::from_le_bytes(b[at..at + 4].try_into().unwrap());
    let a32 = |at: usize| -> [u8; 32] { b[at..at + 32].try_into().unwrap() };
    let n = u(0) as usize;
    let mut at = 4;
    let mut out = Vec::with_capacity(n);
    for _ in 0..n {
        let (kind, ncv) = (u(at), u(at + 4) as usize);
        let vb = (u(at + 8) as u64 | (u(at + 12) as u64) << 32) as i64;
        let (r, s, msg, vk) = (a32(at + 16), a32(at + 48), a32(at + 80), a32(at + 112));
        at += 144;
        let cvs = (0..ncv).map(|j| a32(at + 32 * j)).collect();
        at += 32 * ncv;
        out.push(Item { binding: kind == 1, vb, r, s, msg, vk, cvs });
    }
    anyhow::ensure!(at == b.len(), "trailing bytes");
    Ok(out)
}



fn chunks() -> Result<Vec<std::path::PathBuf>> {
    let mut v: Vec<_> = fs::read_dir(DATA)?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.file_name().is_some_and(|n| n.to_string_lossy().starts_with("chunk_")))
        .collect();
    v.sort();
    Ok(v)
}

fn bvk(it: &Item) -> Result<[u8; 32]> {
    let mut sum = pallas::Point::identity();
    for c in &it.cvs {
        sum += Option::<pallas::Point>::from(pallas::Point::from_bytes(c)).ok_or(anyhow!("bad cv"))?;
    }
    let v = Option::<pallas::Point>::from(pallas::Point::from_bytes(&V_CV)).unwrap();
    let mag = pallas::Scalar::from(it.vb.unsigned_abs());
    let vbs = if it.vb < 0 { -mag } else { mag };
    Ok((sum - v * vbs).to_bytes())
}

/// reddsa batch verification of one chunk; true if the whole batch verifies.
fn verify_chunk(items: &[Item]) -> Result<bool> {
    let mut v = batch::Verifier::<rp::SpendAuth, rp::Binding>::new();
    for it in items {
        let mut sig = [0u8; 64];
        sig[..32].copy_from_slice(&it.r);
        sig[32..].copy_from_slice(&it.s);
        if it.binding {
            v.queue(batch::Item::from_binding(VerificationKeyBytes::<rp::Binding>::from(bvk(it)?), Signature::from(sig), &it.msg));
        } else {
            v.queue(batch::Item::from_spendauth(VerificationKeyBytes::<rp::SpendAuth>::from(it.vk), Signature::from(sig), &it.msg));
        }
    }
    Ok(v.verify(rand::rng()).is_ok())
}

fn rust(threads: usize) -> Result<()> {
    let paths = chunks()?;
    // Inputs are read and decoded before timing (the Bend runs also exclude file reading).
    let data: Vec<Vec<Item>> = paths.iter().map(|p| decode(&fs::read(p)?)).collect::<Result<_>>()?;
    let n: usize = data.iter().map(|d| d.len()).sum();
    let pool = rayon::ThreadPoolBuilder::new().num_threads(threads).build()?;
    let t = Instant::now();
    let oks: Vec<bool> = pool.install(|| data.par_iter().map(|d| verify_chunk(d).unwrap_or(false)).collect());
    let s = t.elapsed().as_secs_f64();
    let bad: Vec<usize> = oks.iter().enumerate().filter(|(_, o)| !**o).map(|(i, _)| i).collect();
    println!("rust reddsa batch threads={threads}: {} chunks, {n} signatures, rejected chunks {:?}, {s:.2}s = {:.0} sigs/s", data.len(), bad, n as f64 / s);
    Ok(())
}


fn main() -> Result<()> {
    let a: Vec<String> = std::env::args().collect();
    let num = |i: usize| a.get(i).map(|s| s.parse::<usize>()).transpose();
    match a.get(1).map(String::as_str) {
        Some("rust") => rust(num(2)?.unwrap_or(1)),
        Some("verify") => {
            for f in &a[2..] {
                println!("{f}: rust batch verifies {}", verify_chunk(&decode(&fs::read(f)?)?)?);
            }
            Ok(())
        }
        _ => Err(anyhow!("usage: rust THREADS | verify FILE...")),
    }
}
