//! tv-zakura: the transparent-input baseline on Zakura's own code path.
//!
//! Per record of a `.ztv` file (zcash/transparent/oracle's format), this does what
//! zakura-consensus does for a block transaction (`transaction.rs`, `script.rs`): parse with
//! zakura-chain, build one `CachedFfiTransaction` (zakura-chain `SigHasher`, precomputed once
//! per tx) for the network upgrade at the record's height, then `is_valid(i)` per input
//! (zcash_script 0.6 interpreter, libsecp256k1 via secp256k1 0.33, flags P2SH | CLTV).
//! Inputs fan out on rayon as Zakura's `spawn_fifo` does.
//!
//!   tv-zakura check FILE.ztv      expect lines (r <k> <verdicts>), '?' for v1/v2 inputs
//!   tv-zakura compare DIR...      verdicts against each file's .expect (tv-oracle's)
//!
//! v1/v2 (pre-Overwinter) transactions: Zakura rejects v1..v3 in its transaction verifier and
//! relies on checkpoints for those heights, and zakura-chain has no legacy sighash. They are
//! reported as '?' and counted separately; time them out with `compare`'s per-version counts.
#[allow(dead_code)]
mod raw;

use anyhow::{anyhow, Result};
use rayon::prelude::*;
use raw::Record;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use zakura_chain::{
    amount::Amount,
    block::Height,
    parameters::{Network, NetworkUpgrade},
    serialization::ZcashDeserializeInto,
    transaction::Transaction,
    transparent,
};
use zakura_script::CachedFfiTransaction;

/// Per-input verdict: Some(valid) or None (v1/v2, not checked by Zakura).
fn check(rec: &Record) -> Vec<Option<bool>> {
    let n = rec.prevs.len();
    let version = raw::layout(&rec.tx).map(|l| l.version).unwrap_or(0);
    if (1..=2).contains(&version) {
        return vec![None; n];
    }
    let cached = match prepare(rec) {
        Ok(c) => Arc::new(c),
        Err(_) => return vec![Some(false); n],
    };
    (0..n).into_par_iter().map(|i| Some(cached.is_valid(i).is_ok())).collect()
}

fn prepare(rec: &Record) -> Result<CachedFfiTransaction> {
    let tx: Transaction = rec.tx.as_slice().zcash_deserialize_into().map_err(|e| anyhow!("tx parse: {e}"))?;
    let nu = NetworkUpgrade::current(&Network::Mainnet, Height(rec.height));
    let outs = rec
        .prevs
        .iter()
        .map(|p| {
            Ok(transparent::Output {
                value: Amount::try_from(p.amount).map_err(|e| anyhow!("prevout amount: {e}"))?,
                lock_script: transparent::Script::new(&p.spk),
            })
        })
        .collect::<Result<Vec<_>>>()?;
    CachedFfiTransaction::new(Arc::new(tx), Arc::new(outs), nu).map_err(|e| anyhow!("{e}"))
}

fn line(k: usize, v: &[Option<bool>]) -> String {
    let s: String = v.iter().map(|x| match x {
        Some(true) => '1',
        Some(false) => '0',
        None => '?',
    }).collect();
    format!("r {k} {s}")
}

fn ztv_files(args: &[String]) -> Result<Vec<PathBuf>> {
    let mut v = vec![];
    for a in args {
        let p = PathBuf::from(a);
        if p.is_dir() {
            for e in std::fs::read_dir(&p)? {
                let e = e?.path();
                if e.extension().map_or(false, |x| x == "ztv") {
                    v.push(e);
                }
            }
        } else {
            v.push(p);
        }
    }
    v.sort();
    Ok(v)
}

fn compare(files: &[PathBuf]) -> Result<()> {
    let (mut inputs, mut same, mut diff, mut skipped) = (0usize, 0usize, 0usize, 0usize);
    for f in files {
        let recs = raw::read_file(f)?;
        let want = std::fs::read_to_string(f.with_extension("expect"))?;
        let want: Vec<&str> = want.lines().map(|l| l.split_whitespace().nth(2).unwrap_or("")).collect();
        let got: Vec<_> = recs.par_iter().map(check).collect();
        for (k, g) in got.iter().enumerate() {
            for (i, v) in g.iter().enumerate() {
                inputs += 1;
                let w = want[k].as_bytes()[i] == b'1';
                match v {
                    None => skipped += 1,
                    Some(b) if *b == w => same += 1,
                    Some(_) => {
                        diff += 1;
                        if diff <= 20 {
                            println!("MISMATCH {} r {k} in {i}: zakura {} oracle {}", f.display(), *v == Some(true), w);
                        }
                    }
                }
            }
        }
    }
    println!("{} files, {inputs} inputs: {same} agree, {diff} differ, {skipped} v1/v2 not checked by Zakura", files.len());
    Ok(())
}

fn main() -> Result<()> {
    let a: Vec<String> = std::env::args().collect();
    match a.get(1).map(String::as_str) {
        Some("check") => {
            let recs = raw::read_file(Path::new(&a[2]))?;
            let outs: Vec<_> = recs.par_iter().map(check).collect();
            for (k, o) in outs.iter().enumerate() {
                println!("{}", line(k, o));
            }
        }
        Some("compare") => compare(&ztv_files(&a[2..])?)?,
        _ => anyhow::bail!("usage: check FILE.ztv | compare DIR..."),
    }
    Ok(())
}
