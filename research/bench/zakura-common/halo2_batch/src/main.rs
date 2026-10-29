//! research/proofsets/oracle's `rust-batch` Halo 2 baseline, rebuilt on the Zakura Common crates
//! (zakura-orchard, zakura-halo2-proofs, zakura-primitives, all 4.0.0), plus Zakura's own batching.
//! Reads research/proofsets/data/raw.bin; post-NU6.3 bundles only, as the original.
//!
//!   rust-batch THREADS [LIMIT] [PART] [PARTS]
//!       proofs only, par_chunks(64): batches of 64 bundles, as the original (same bundle
//!       selection, record index % PARTS == PART, same order)
//!   actions-batch THREADS [LIMIT] [PART] [PARTS]
//!       proofs only, cut as Zakura cuts (zakura-consensus batch_control: flush once a batch holds
//!       >= 64 actions), the batches verified in parallel on a THREADS-wide rayon pool
//!   zakura-batch THREADS [LIMIT]
//!       Zakura's whole path: orchard BatchValidator (proof + RedPallas signatures), batches cut at
//!       >= 64 actions. Fully shielded txs only: with no transparent inputs the ZIP 244 shielded
//!       sighash is the txid, so no spent outputs are needed (as research/sigbatch)
//!   check N
//!       verdicts on the first N bundles, each mode: all accepted; then one proof byte flipped in
//!       one bundle (every mode rejects) and one bundle's sighash changed (zakura-batch rejects)
//!
//! Every mode builds the key as Zakura does: VerifyingKey::build(PostNu6_3), then
//! prepare_batch_validation() (a no-op without halo2's `orbits` feature, as in Zakura's build).
//! Bundles are read and parsed before timing; the timed region is batching + verification.
use std::{fs::File, io::{BufReader, Read}, path::Path, time::Instant};

use anyhow::{anyhow, Result};
use orchard::{
    bundle::{Authorized, BatchValidator, ProofBatch},
    circuit::{OrchardCircuitVersion, VerifyingKey},
    Bundle,
};
use rayon::prelude::*;
use zcash_primitives::transaction::Transaction;
use zcash_protocol::{
    consensus::{BlockHeight, BranchId, MainNetwork},
    value::ZatBalance,
};

const DATA: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../proofsets/data");
/// zakura-consensus primitives::MAX_BATCH_SIZE, the halo2 batch weight in actions.
const ZAKURA_BATCH_ACTIONS: usize = 64;

type B = Bundle<Authorized, ZatBalance>;

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
            return Ok(());
        }
        each(h, id, b)?;
    }
}

/// Post-NU6.3 bundles of records with index % parts == part, in order, with each one's tx
/// sighash when the tx is fully shielded (None otherwise).
fn load(limit: usize, part: usize, parts: usize) -> Result<Vec<(B, Option<[u8; 32]>)>> {
    let mut out = vec![];
    let mut idx = 0usize;
    read_raw(BufReader::new(File::open(Path::new(DATA).join("raw.bin"))?), |h, _id, raw| {
        idx += 1;
        if (idx - 1) % parts != part || out.len() >= limit {
            return Ok(());
        }
        let branch = BranchId::for_height(&MainNetwork, BlockHeight::from_u32(h as u32));
        let tx = Transaction::read(&raw[..], branch)?;
        let shielded = tx.transparent_bundle().is_none_or(|t| t.vin.is_empty());
        let sighash = shielded.then(|| *tx.txid().as_ref());
        for b in [tx.orchard_bundle(), tx.ironwood_bundle()].into_iter().flatten() {
            if b.bundle_version().circuit_version() == OrchardCircuitVersion::PostNu6_3 && out.len() < limit {
                out.push((b.clone(), sighash));
            }
        }
        Ok(())
    })?;
    Ok(out)
}

fn zakura_vk() -> VerifyingKey {
    let vk = VerifyingKey::build(OrchardCircuitVersion::PostNu6_3);
    eprintln!("prepare_batch_validation (as Zakura): {}", vk.prepare_batch_validation());
    vk
}

/// Zakura's cut: add bundles until the batch holds >= 64 actions, then start the next.
fn cut_by_actions<T>(items: &[T], actions: impl Fn(&T) -> usize) -> Vec<&[T]> {
    let (mut out, mut start, mut w) = (vec![], 0, 0);
    for (i, it) in items.iter().enumerate() {
        w += actions(it).max(1);
        if w >= ZAKURA_BATCH_ACTIONS {
            out.push(&items[start..=i]);
            start = i + 1;
            w = 0;
        }
    }
    if start < items.len() {
        out.push(&items[start..]);
    }
    out
}

fn proofs_ok(vk: &VerifyingKey, c: &[&B]) -> bool {
    let mut v = ProofBatch::new(vk);
    for b in c {
        if v.add_bundle(*b).is_err() {
            return false;
        }
    }
    v.validate()
}

fn full_ok(vk: &VerifyingKey, c: &[(&B, [u8; 32])]) -> bool {
    let mut v = BatchValidator::new(vk);
    for (b, s) in c {
        if v.add_bundle(*b, *s).is_err() {
            return false;
        }
    }
    v.validate(rand::rng())
}

fn rust_batch(threads: usize, bundles: &[&B], vk: &VerifyingKey) -> bool {
    let pool = rayon::ThreadPoolBuilder::new().num_threads(threads).build().unwrap();
    pool.install(|| bundles.par_chunks(64).map(|c| proofs_ok(vk, c)).all(|x| x))
}

fn actions_batch(threads: usize, bundles: &[&B], vk: &VerifyingKey) -> bool {
    let pool = rayon::ThreadPoolBuilder::new().num_threads(threads).build().unwrap();
    pool.install(|| {
        let batches = cut_by_actions(bundles, |b| b.actions().len());
        batches.par_iter().map(|c| proofs_ok(vk, c)).all(|x| x)
    })
}

fn zakura_batch(threads: usize, items: &[(&B, [u8; 32])], vk: &VerifyingKey) -> bool {
    let pool = rayon::ThreadPoolBuilder::new().num_threads(threads).build().unwrap();
    pool.install(|| {
        let batches = cut_by_actions(items, |(b, _)| b.actions().len());
        batches.par_iter().map(|c| full_ok(vk, c)).all(|x| x)
    })
}

fn timed(name: &str, threads: usize, n: usize, f: impl FnOnce() -> bool) {
    let t = Instant::now();
    let ok = f();
    let s = t.elapsed().as_secs_f64();
    println!("{name} threads={threads}: {n} bundles, all ok {ok}, {s:.1}s = {:.0} bundles/s", n as f64 / s);
}

/// A copy of `b` with one byte of its proof flipped.
fn tampered(b: &B) -> Result<B> {
    let mut bytes = b.authorization().proof().as_ref().to_vec();
    bytes[100] ^= 1;
    let proof = orchard::Proof::new(bytes);
    b.clone().try_map_authorization(
        &mut (),
        |_, _, sig| Ok::<_, anyhow::Error>(sig),
        |_, auth| Ok(Authorized::from_parts(proof.clone(), auth.binding_signature().clone())),
    )
}

fn check(n: usize) -> Result<()> {
    let vk = zakura_vk();
    let all = load(n, 0, 1)?;
    let bundles: Vec<&B> = all.iter().map(|(b, _)| b).collect();
    let items: Vec<(&B, [u8; 32])> = all.iter().filter_map(|(b, s)| s.map(|s| (b, s))).collect();
    println!("check: {} bundles ({} fully shielded)", bundles.len(), items.len());
    println!("  valid: rust-batch {}  actions-batch {}  zakura-batch {}",
        rust_batch(4, &bundles, &vk), actions_batch(4, &bundles, &vk), zakura_batch(4, &items, &vk));
    let k = bundles.len() / 2;
    let bad = tampered(bundles[k])?;
    let mut tb = bundles.clone();
    tb[k] = &bad;
    let ki = items.len() / 2;
    let bad_i = tampered(items[ki].0)?;
    let mut ti = items.clone();
    ti[ki].0 = &bad_i;
    println!("  proof byte flipped in bundle {k}: rust-batch {}  actions-batch {}  zakura-batch {}",
        rust_batch(4, &tb, &vk), actions_batch(4, &tb, &vk), zakura_batch(4, &ti, &vk));
    let mut ts = items.clone();
    ts[ki].1[0] ^= 1;
    println!("  sighash changed for item {ki}: zakura-batch {}", zakura_batch(4, &ts, &vk));
    Ok(())
}

fn main() -> Result<()> {
    let a: Vec<String> = std::env::args().collect();
    let arg = |i: usize, d: usize| -> Result<usize> { Ok(a.get(i).map(|s| s.parse()).transpose()?.unwrap_or(d)) };
    match a.get(1).map(String::as_str) {
        Some(m @ ("rust-batch" | "actions-batch")) => {
            let threads = arg(2, 1)?;
            let all = load(arg(3, usize::MAX)?, arg(4, 0)?, arg(5, 1)?)?;
            let bundles: Vec<&B> = all.iter().map(|(b, _)| b).collect();
            let vk = zakura_vk();
            if m == "rust-batch" {
                timed("rust zakura-halo2 ProofBatch par_chunks(64)", threads, bundles.len(), || rust_batch(threads, &bundles, &vk));
            } else {
                timed("rust zakura-halo2 ProofBatch, Zakura's >=64-action batches", threads, bundles.len(), || actions_batch(threads, &bundles, &vk));
            }
            Ok(())
        }
        Some("zakura-batch") => {
            let threads = arg(2, 1)?;
            let all = load(arg(3, usize::MAX)?, 0, 1)?;
            let items: Vec<(&B, [u8; 32])> = all.iter().filter_map(|(b, s)| s.map(|s| (b, s))).collect();
            eprintln!("zakura-batch: {} of {} bundles are in fully shielded txs", items.len(), all.len());
            let vk = zakura_vk();
            timed("rust zakura BatchValidator (proofs + RedPallas), Zakura's >=64-action batches", threads, items.len(), || zakura_batch(threads, &items, &vk));
            Ok(())
        }
        Some("check") => check(arg(2, 256)?),
        _ => Err(anyhow!("usage: rust-batch THREADS [LIMIT] [PART] [PARTS] | actions-batch THREADS [LIMIT] [PART] [PARTS] | zakura-batch THREADS [LIMIT] | check N")),
    }
}
