//! zcash/headers/oracle's Equihash timing and verdicts, on zakura-equihash.
//!
//!   check FILE       Equihash only, as the upstream oracle's `check`: the first 2,000 headers on
//!                    1 thread, then every header with rayon par_iter (RAYON_NUM_THREADS, default
//!                    all cores). Same output lines.
//!   lines FILE N     "index blockhash pow 0/1 target 0/1", as the upstream `lines`: diff against
//!                    zcash/headers/data/tampered.rust.txt
//!
//! Zakura calls equihash::is_valid_solution(200, 9, header[..108], nonce, solution) once per
//! header (zakura-chain work/equihash.rs, via zakura-consensus block/check.rs), the same call.

use std::time::Instant;

use anyhow::{anyhow, Result};
use rayon::prelude::*;
use sha2::{Digest, Sha256};

const HEADER_LEN: usize = 1487;

fn sha256d(b: &[u8]) -> [u8; 32] {
    Sha256::digest(Sha256::digest(b)).into()
}

fn eq(h: &[u8]) -> bool {
    equihash::is_valid_solution(200, 9, &h[..108], &h[108..140], &h[143..]).is_ok()
}

/// Compact nBits -> 256-bit big-endian target, copied from zcash/headers/oracle.
fn target_be(bits: u32) -> Option<[u8; 32]> {
    let exp = (bits >> 24) as usize;
    let mant = bits & 0x007f_ffff;
    if bits & 0x0080_0000 != 0 || exp > 32 {
        return None;
    }
    let mut t = [0u8; 32];
    let m = mant.to_be_bytes(); // [0, b2, b1, b0]
    for (j, byte) in m[1..].iter().enumerate() {
        let pos = 32 - exp + j as isize as usize;
        if exp >= 3 - j && pos < 32 {
            t[pos] = *byte;
        } else if *byte != 0 && exp < 3 - j {
            // bytes shifted out below the units place are dropped
        }
    }
    if exp < 3 {
        let v = mant >> (8 * (3 - exp));
        t = [0u8; 32];
        t[28..].copy_from_slice(&v.to_be_bytes());
    }
    Some(t)
}

fn check(file: &str) -> Result<()> {
    let b = std::fs::read(file)?;
    let n = b.len() / HEADER_LEN;
    let hs: Vec<&[u8]> = b.chunks_exact(HEADER_LEN).collect();
    let t = Instant::now();
    let m = n.min(2000);
    let single = hs.iter().take(m).filter(|h| eq(h)).count();
    let dt1 = t.elapsed();
    let t = Instant::now();
    let eq_ok = hs.par_iter().filter(|h| eq(h)).count();
    let dtn = t.elapsed();
    println!("headers {n}");
    println!("equihash valid (rust, {} threads) {eq_ok}/{n} in {dtn:?} = {:.0} headers/s", rayon::current_num_threads(), n as f64 / dtn.as_secs_f64());
    println!("equihash rust 1 thread: {m} headers ({single} valid) in {dt1:?} = {:.0} headers/s", m as f64 / dt1.as_secs_f64());
    Ok(())
}

fn lines(file: &str, n: usize) -> Result<()> {
    let b = std::fs::read(file)?;
    for (i, h) in b.chunks_exact(HEADER_LEN).take(n).enumerate() {
        let hash = sha256d(h);
        let bits = u32::from_le_bytes(h[104..108].try_into()?);
        let mut be = hash;
        be.reverse();
        let under = be <= target_be(bits).ok_or_else(|| anyhow!("bits"))?;
        println!("{i} {} pow {} target {}", hex::encode(hash), eq(h) as u8, under as u8);
    }
    Ok(())
}

fn main() -> Result<()> {
    let a: Vec<String> = std::env::args().collect();
    match a.get(1).map(String::as_str) {
        Some("check") => check(a.get(2).ok_or_else(|| anyhow!("FILE"))?),
        Some("lines") => lines(a.get(2).ok_or_else(|| anyhow!("FILE"))?, a.get(3).map(|s| s.parse()).transpose()?.unwrap_or(usize::MAX)),
        _ => Err(anyhow!("usage: check FILE | lines FILE N")),
    }
}
