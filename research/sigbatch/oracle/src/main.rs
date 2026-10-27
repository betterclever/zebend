//! Inputs and Rust baseline for batched RedPallas verification (research/sigbatch/).
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
    fs::{self, File},
    io::{BufRead, BufReader, BufWriter, Write},
    path::Path,
    time::Instant,
};

use anyhow::{anyhow, Result};
use group::{Group, GroupEncoding};
use pasta_curves::pallas;
use rayon::prelude::*;
use reddsa::{batch, orchard as rp, Signature, VerificationKeyBytes};
use zcash_primitives::transaction::{
    Transaction,
};
use zcash_protocol::consensus::{BlockHeight, BranchId, MainNetwork};

const DATA: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../data");
const SIGS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../proofsets/data/sigs");

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

fn encode(items: &[Item]) -> Vec<u8> {
    let mut b = Vec::new();
    b.extend((items.len() as u32).to_le_bytes());
    for it in items {
        b.extend((it.binding as u32).to_le_bytes());
        b.extend((it.cvs.len() as u32).to_le_bytes());
        b.extend((it.vb as u64 as u32).to_le_bytes());
        b.extend(((it.vb as u64 >> 32) as u32).to_le_bytes());
        for f in [&it.r, &it.s, &it.msg, &it.vk] {
            b.extend(f);
        }
        for c in &it.cvs {
            b.extend(c);
        }
    }
    b
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

fn items_of(h: u64, raw: &[u8]) -> Result<Vec<Item>> {
    let branch = BranchId::for_height(&MainNetwork, BlockHeight::from_u32(h as u32));
    let tx = Transaction::read(raw, branch)?;
    // ZIP 244: with no transparent inputs (all txs here), the shielded sighash equals the txid.
    anyhow::ensure!(tx.transparent_bundle().is_none_or(|t| t.vin.is_empty()), "tx has transparent inputs");
    let msg: [u8; 32] = *tx.txid().as_ref();
    let mut out = Vec::new();
    for b in [tx.orchard_bundle(), tx.ironwood_bundle()].into_iter().flatten() {
        let mut cvs = Vec::new();
        for a in b.actions() {
            let sig: [u8; 64] = a.authorization().into();
            out.push(Item {
                binding: false,
                vb: 0,
                r: sig[..32].try_into()?,
                s: sig[32..].try_into()?,
                msg,
                vk: a.rk().into(),
                cvs: vec![],
            });
            cvs.push(a.cv_net().to_bytes());
        }
        let bsig: [u8; 64] = b.authorization().binding_signature().into();
        out.push(Item {
            binding: true,
            vb: i64::from(*b.value_balance()),
            r: bsig[..32].try_into()?,
            s: bsig[32..].try_into()?,
            msg,
            vk: [0; 32],
            cvs,
        });
    }
    Ok(out)
}

fn extract(per_chunk: usize) -> Result<()> {
    fs::create_dir_all(DATA)?;
    let mut man = BufWriter::new(File::create(Path::new(DATA).join("manifest.txt"))?);
    let (mut chunk, mut k, mut cur, mut ntx, mut nsa, mut nb) = (Vec::new(), 0usize, 0usize, 0usize, 0usize, 0usize);
    let flush = |chunk: &mut Vec<Item>, k: &mut usize| -> Result<()> {
        if !chunk.is_empty() {
            fs::write(Path::new(DATA).join(format!("chunk_{:04}.bin", k)), encode(chunk))?;
            chunk.clear();
            *k += 1;
        }
        Ok(())
    };
    for line in BufReader::new(File::open(Path::new(SIGS).join("expected.txt"))?).lines() {
        let line = line?;
        let f: Vec<&str> = line.split_whitespace().collect();
        let (key, h) = (f[0], f[1].parse::<u64>()?);
        let raw = fs::read(Path::new(SIGS).join(format!("{key}.bin")))?;
        let its = items_of(h, &raw)?;
        if cur + its.len() > per_chunk {
            flush(&mut chunk, &mut k)?;
            cur = 0;
        }
        for (j, it) in its.into_iter().enumerate() {
            writeln!(man, "{k} {} {key} {j} {}", cur, if it.binding { "binding" } else { "spend_auth" })?;
            if it.binding { nb += 1 } else { nsa += 1 }
            chunk.push(it);
            cur += 1;
        }
        ntx += 1;
    }
    flush(&mut chunk, &mut k)?;
    man.flush()?;
    eprintln!("extract: {ntx} txs, {nsa} spend-auth + {nb} binding signatures in {k} chunks of <= {per_chunk}");
    Ok(())
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

fn tamper(k: usize, field: &str, item: usize) -> Result<()> {
    let p = Path::new(DATA).join(format!("chunk_{k:04}.bin"));
    let mut b = fs::read(&p)?;
    // walk to the item: kind ncv vb_lo vb_hi (16) | R | s | msg | vk | cv*ncv
    let u = |b: &[u8], at: usize| u32::from_le_bytes(b[at..at + 4].try_into().unwrap()) as usize;
    let mut at = 4;
    for _ in 0..item {
        at += 144 + 32 * u(&b, at + 4);
    }
    let off = match field {
        "R" => 16 + 5,
        "s" => 16 + 32 + 5,
        "msg" => 16 + 64 + 5,
        "vk" => 16 + 96 + 5,
        "vb" => 8,
        "cv" => 144 + 5,
        _ => anyhow::bail!("field R|s|vk|msg|vb|cv"),
    };
    anyhow::ensure!(field != "cv" || u(&b, at + 4) > 0, "item has no cv");
    b[at + off] ^= 1;
    let out = Path::new(DATA).join(format!("tamper_{field}_{item}.bin"));
    fs::write(&out, &b)?;
    println!("tamper {field} item {item}: rust batch verifies {}", verify_chunk(&decode(&b)?)?);
    Ok(())
}

fn main() -> Result<()> {
    let a: Vec<String> = std::env::args().collect();
    let num = |i: usize| a.get(i).map(|s| s.parse::<usize>()).transpose();
    match a.get(1).map(String::as_str) {
        Some("extract") => extract(num(2)?.unwrap_or(8192)),
        Some("rust") => rust(num(2)?.unwrap_or(1)),
        Some("tamper") => tamper(num(2)?.unwrap_or(0), a.get(3).map(String::as_str).unwrap_or("s"), num(4)?.unwrap_or(0)),
        _ => Err(anyhow!("usage: extract N | rust THREADS | tamper K FIELD ITEM")),
    }
}
