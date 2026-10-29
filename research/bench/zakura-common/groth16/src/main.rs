//! zcash/sapling/groth16/oracle's `bench`, on the Zakura Common crates.
//!
//!   bench FILE THREADS [REPS]  same three Rust lines as the upstream oracle (names unchanged so
//!                              zcash/sapling/groth16/bench.py's regexes match), plus the two
//!                              batch shapes Zakura itself uses (see below)
//!   verdicts FILE              "index reason" per record (1 ok, 0 Proof::read failed,
//!                              2 verify_proof failed): diff against data/official_*.txt
//!
//! Record format: as zcash/sapling/groth16/oracle (u32 kind 0 spend / 1 output / 2 sprout,
//! u32 tag, 192-byte proof, n x 32-byte Fr inputs). VKs come from the same
//! zcash/sapling/groth16/data/*.params files; zakura-sapling-crypto's pinned keys are the same
//! keys (checked by `verdicts` agreeing with the official verdicts).
//!
//! Zakura's Sapling path (zakura-consensus primitives/sapling.rs -> sapling_crypto::BatchValidator):
//! tower batches of <= 64 descriptions (MAX_BATCH_SIZE, weight = spends + outputs), the
//! RedJubjub signatures first, then per kind `verify_multicore_prepared` with the key's cached
//! PreparedBatchG2, or `verify_joint_prepared` when the batch has exactly one spend and one
//! output. Sprout (primitives/groth16.rs) is verified one proof at a time.

use std::{fs::File, io::Read, path::Path, time::Instant};

use anyhow::{anyhow, Result};
use bellman::groth16::{self, batch, PreparedVerifyingKey, Proof, VerifyingKey};
use bls12_381::{Bls12, Scalar};
use ff::PrimeField;
use rayon::prelude::*;

const DATA: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../../zcash/sapling/groth16/data");

struct Rec {
    kind: u32,
    proof: [u8; 192],
    inputs: Vec<Scalar>,
}

fn read_vk(name: &str) -> Result<VerifyingKey<Bls12>> {
    let file = if name == "sprout" { "sprout-groth16.params".to_string() } else { format!("sapling-{name}.params") };
    Ok(VerifyingKey::<Bls12>::read(std::io::BufReader::new(File::open(Path::new(DATA).join(file))?))?)
}

fn read_set(path: &str) -> Result<Vec<Rec>> {
    let mut b = vec![];
    File::open(path)?.read_to_end(&mut b)?;
    let mut out = vec![];
    let mut i = 0;
    while i < b.len() {
        let kind = u32::from_le_bytes(b[i..i + 4].try_into()?);
        let proof: [u8; 192] = b[i + 8..i + 200].try_into()?;
        let n = [7, 5, 9][kind as usize];
        let mut inputs = vec![];
        for k in 0..n {
            let o = i + 200 + 32 * k;
            inputs.push(Option::from(Scalar::from_repr(b[o..o + 32].try_into()?)).ok_or_else(|| anyhow!("input"))?);
        }
        i += 200 + 32 * n;
        out.push(Rec { kind, proof, inputs });
    }
    Ok(out)
}

/// 1 valid, 0 rejected by Proof::read, 2 rejected by verify_proof (as the upstream oracle).
fn reason(pvk: &PreparedVerifyingKey<Bls12>, r: &Rec) -> u8 {
    match Proof::<Bls12>::read(&r.proof[..]) {
        Ok(p) => {
            if groth16::verify_proof(pvk, &p, &r.inputs).is_ok() {
                1
            } else {
                2
            }
        }
        Err(_) => 0,
    }
}

/// One Zakura-shaped batch: per kind, joint when exactly one spend and one output, else
/// verify_multicore_prepared (multicore) / verify_prepared; Sprout one at a time.
fn zakura_batch(ch: &[Rec], keys: &[batch::PreparedBatchVerifyingKey<'_, Bls12>; 2], pvj: &PreparedVerifyingKey<Bls12>, multicore: bool) -> bool {
    let mut bv: [batch::Verifier<Bls12>; 2] = Default::default();
    let mut count = [0usize; 2];
    for r in ch {
        if r.kind == 2 {
            if reason(pvj, r) != 1 {
                return false;
            }
            continue;
        }
        bv[r.kind as usize].queue((Proof::<Bls12>::read(&r.proof[..]).unwrap(), r.inputs.clone()));
        count[r.kind as usize] += 1;
    }
    let [spend, output] = bv;
    if count == [1, 1] {
        return spend.verify_joint_prepared(output, rand::rng(), &keys[0], &keys[1]).is_ok();
    }
    [spend, output].into_iter().zip(keys).zip(count).all(|((b, k), c)| {
        c == 0 || if multicore { b.verify_multicore_prepared(k).is_ok() } else { b.verify_prepared(rand::rng(), k).is_ok() }
    })
}

fn bench(path: &str, threads: usize, reps: usize) -> Result<()> {
    let recs = read_set(path)?;
    let (vks, vko, vkj) = (read_vk("spend")?, read_vk("output")?, read_vk("sprout")?);
    let (pvs, pvo, pvj) = (groth16::prepare_verifying_key(&vks), groth16::prepare_verifying_key(&vko), groth16::prepare_verifying_key(&vkj));
    // the keys' cached G2 terms, prepared once per process as SpendVerifyingKey's OnceLock does
    let (g2s, g2o) = (batch::PreparedBatchG2::from(&vks), batch::PreparedBatchG2::from(&vko));
    let keys = [batch::PreparedBatchVerifyingKey::from_cached(&vks, &g2s)?, batch::PreparedBatchVerifyingKey::from_cached(&vko, &g2o)?];
    let pool = rayon::ThreadPoolBuilder::new().num_threads(threads).build()?;
    for _ in 0..reps {
        let t = Instant::now();
        let ok: usize = pool.install(|| recs.par_iter().map(|r| (reason([&pvs, &pvo, &pvj][r.kind as usize], r) == 1) as usize).sum());
        let s = t.elapsed().as_secs_f64();
        println!(
            "rust single threads={threads} n={} valid={ok} {:.3}s = {:.0} proofs/s ({:.3} ms/proof)",
            recs.len(),
            s,
            recs.len() as f64 / s,
            1e3 * s / recs.len() as f64
        );
        let t = Instant::now();
        let ok = pool.install(|| {
            let mut bv: [batch::Verifier<Bls12>; 3] = Default::default();
            for r in &recs {
                bv[r.kind as usize].queue((Proof::<Bls12>::read(&r.proof[..]).unwrap(), r.inputs.clone()));
            }
            bv.into_iter().zip([&vks, &vko, &vkj]).all(|(b, vk)| b.verify_multicore(vk).is_ok())
        });
        let s = t.elapsed().as_secs_f64();
        println!("rust batch(verify_multicore) threads={threads} n={} ok={ok} {:.3}s = {:.0} proofs/s", recs.len(), s, recs.len() as f64 / s);
        let t = Instant::now();
        let ok = pool.install(|| {
            recs.par_chunks(128).all(|ch| {
                let mut bv: [batch::Verifier<Bls12>; 3] = Default::default();
                for r in ch {
                    bv[r.kind as usize].queue((Proof::<Bls12>::read(&r.proof[..]).unwrap(), r.inputs.clone()));
                }
                bv.into_iter().zip([&vks, &vko, &vkj]).all(|(b, vk)| b.verify(rand::rng(), vk).is_ok())
            })
        });
        let s = t.elapsed().as_secs_f64();
        println!("rust batch(chunks of 128, verify) threads={threads} n={} ok={ok} {:.3}s = {:.0} proofs/s", recs.len(), s, recs.len() as f64 / s);
        // Zakura's shape: batches of 64 one after another, each verify_multicore_prepared
        let t = Instant::now();
        let ok = pool.install(|| recs.chunks(64).all(|ch| zakura_batch(ch, &keys, &pvj, true)));
        let s = t.elapsed().as_secs_f64();
        println!("zakura batch(chunks of 64, verify_multicore_prepared) threads={threads} n={} ok={ok} {:.3}s = {:.0} proofs/s", recs.len(), s, recs.len() as f64 / s);
        // Bend batch_main's shape with Zakura's cached G2 terms: chunks of 128 in parallel
        let t = Instant::now();
        let ok = pool.install(|| recs.par_chunks(128).all(|ch| zakura_batch(ch, &keys, &pvj, false)));
        let s = t.elapsed().as_secs_f64();
        println!("zakura batch(chunks of 128, verify_prepared) threads={threads} n={} ok={ok} {:.3}s = {:.0} proofs/s", recs.len(), s, recs.len() as f64 / s);
    }
    Ok(())
}

fn verdicts(path: &str) -> Result<()> {
    let recs = read_set(path)?;
    let pvk = [read_vk("spend")?, read_vk("output")?, read_vk("sprout")?].map(|vk| groth16::prepare_verifying_key(&vk));
    let reasons: Vec<u8> = recs.par_iter().map(|r| reason(&pvk[r.kind as usize], r)).collect();
    for (i, v) in reasons.iter().enumerate() {
        println!("{i} {v}");
    }
    Ok(())
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let a = |i: usize, d: &str| args.get(i).cloned().unwrap_or_else(|| d.to_string());
    match args.get(1).map(String::as_str) {
        Some("bench") => bench(&a(2, ""), a(3, "1").parse()?, a(4, "3").parse()?),
        Some("verdicts") => verdicts(&a(2, "")),
        _ => Err(anyhow!("usage: bench FILE THREADS [REPS] | verdicts FILE")),
    }
}
