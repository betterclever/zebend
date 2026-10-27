//! Tampered set: each output record is one real record with exactly one mutation. All
//! byte mutations keep every length unchanged. The verdicts are recomputed by the oracle
//! (written by `annotate`); whatever it says is the truth.
use crate::oracle;
use crate::raw::{self, Record};
use anyhow::Result;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9e3779b97f4a7c15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
        z ^ (z >> 31)
    }
    fn below(&mut self, n: usize) -> usize {
        (self.next() % n as u64) as usize
    }
}

const KINDS: &[&str] = &[
    "sig_r_bitflip",
    "sig_s_bitflip",
    "hashtype_change",
    "out_amount_byte",
    "locktime_byte",
    "prev_amount",
    "spk_hash_bitflip",
    "multisig_pubkey_swap",
    "pubkey_bitflip",
    "sequence_byte",
    "prevout_index",
    "flags_no_p2sh",
];

/// DER signature pushes in a script: (offset of the DER blob, its length incl. hash type).
fn sigs(script: &[u8]) -> Vec<(usize, usize)> {
    let mut v = vec![];
    if let Ok(ops) = raw::parse_ops(script) {
        for o in ops {
            if let Some((off, len)) = o.data {
                if (9..=73).contains(&len) && script[off] == 0x30 && script[off + 1] as usize == len - 3 && script[off + 2] == 2 {
                    v.push((off, len));
                }
            }
        }
    }
    v
}

/// Apply mutation `kind` to input `i` of `r`; returns a description, or None if not applicable.
fn mutate(r: &mut Record, kind: &str, i: usize, rng: &mut Rng) -> Option<String> {
    let lay = raw::layout(&r.tx).ok()?;
    let txin = lay.vin.get(i)?.clone();
    let so = txin.script_off;
    let sig_script = r.tx[so..so + txin.script_len].to_vec();
    let flip = |b: &mut u8, bit: usize| *b ^= 1 << bit;
    match kind {
        "sig_r_bitflip" | "sig_s_bitflip" => {
            let ss = sigs(&sig_script);
            let (off, _len) = *ss.get(rng.below(ss.len().max(1)))?;
            let rlen = sig_script[off + 3] as usize;
            let (start, n) = if kind == "sig_r_bitflip" {
                (off + 4, rlen)
            } else {
                let p = off + 4 + rlen;
                (p + 2, sig_script[p + 1] as usize)
            };
            if n == 0 {
                return None;
            }
            let k = start + rng.below(n);
            let bit = rng.below(8);
            flip(&mut r.tx[so + k], bit);
            Some(format!("in {i} sigbyte {} bit {bit}", k - off))
        }
        "hashtype_change" => {
            let ss = sigs(&sig_script);
            let (off, len) = *ss.get(rng.below(ss.len().max(1)))?;
            let at = so + off + len - 1;
            let old = r.tx[at];
            let choices: Vec<u8> = [0x01u8, 0x02, 0x03, 0x81, 0x82, 0x83, 0x00, 0x04, 0x41, 0xc1].into_iter().filter(|&c| c != old).collect();
            let new = choices[rng.below(choices.len())];
            r.tx[at] = new;
            Some(format!("in {i} ht {old:02x}->{new:02x}"))
        }
        "out_amount_byte" => {
            if lay.vout.is_empty() {
                return None;
            }
            let o = rng.below(lay.vout.len());
            let bit = rng.below(8);
            flip(&mut r.tx[lay.vout[o].value_off], bit);
            Some(format!("out {o} value byte0 bit {bit}"))
        }
        "locktime_byte" => {
            flip(&mut r.tx[lay.lock_off], 0);
            Some(format!("locktime {} -> {}", lay.lock_time, lay.lock_time ^ 1))
        }
        "prev_amount" => {
            let a = r.prevs[i].amount;
            r.prevs[i].amount = if a > 0 { a - 1 } else { a + 1 };
            Some(format!("in {i} prev amount {a} -> {}", r.prevs[i].amount))
        }
        "spk_hash_bitflip" => {
            let spk = &mut r.prevs[i].spk;
            let range = if raw::is_p2pkh(spk) {
                3..23
            } else if raw::is_p2sh(spk) {
                2..22
            } else if raw::is_p2pk(spk) {
                2..spk.len() - 1
            } else {
                return None;
            };
            let k = range.start + rng.below(range.len());
            let bit = rng.below(8);
            flip(&mut spk[k], bit);
            Some(format!("in {i} spk byte {k} bit {bit}"))
        }
        "multisig_pubkey_swap" => {
            // P2SH multisig redeem script (last push of scriptSig) or a bare multisig scriptPubKey.
            let (target_tx, base, script): (bool, usize, Vec<u8>) = if raw::is_p2sh(&r.prevs[i].spk) {
                let ops = raw::parse_ops(&sig_script).ok()?;
                let (off, len) = ops.last()?.data?;
                (true, so + off, sig_script[off..off + len].to_vec())
            } else if raw::multisig(&r.prevs[i].spk).is_some() {
                (false, 0, r.prevs[i].spk.clone())
            } else {
                return None;
            };
            let (_m, n) = raw::multisig(&script)?;
            if n < 2 {
                return None;
            }
            let ops = raw::parse_ops(&script).ok()?;
            let keys: Vec<(usize, usize)> = ops[1..ops.len() - 2].iter().map(|o| o.data.unwrap()).collect();
            let a = rng.below(keys.len());
            let b = (a + 1 + rng.below(keys.len() - 1)) % keys.len();
            let (ka, kb) = (keys[a], keys[b]);
            if ka.1 != kb.1 || script[ka.0..ka.0 + ka.1] == script[kb.0..kb.0 + kb.1] {
                return None;
            }
            let mut s2 = script.clone();
            s2[ka.0..ka.0 + ka.1].copy_from_slice(&script[kb.0..kb.0 + kb.1]);
            s2[kb.0..kb.0 + kb.1].copy_from_slice(&script[ka.0..ka.0 + ka.1]);
            if target_tx {
                r.tx[base..base + s2.len()].copy_from_slice(&s2);
            } else {
                r.prevs[i].spk = s2;
            }
            Some(format!("in {i} swap keys {a} {b} in {}", if target_tx { "redeem script" } else { "bare multisig spk" }))
        }
        "pubkey_bitflip" => {
            if !raw::is_p2pkh(&r.prevs[i].spk) {
                return None;
            }
            let ops = raw::parse_ops(&sig_script).ok()?;
            let (off, len) = ops.last()?.data?;
            if len != 33 && len != 65 {
                return None;
            }
            let k = off + 1 + rng.below(len - 1);
            let bit = rng.below(8);
            flip(&mut r.tx[so + k], bit);
            Some(format!("in {i} pubkey byte {} bit {bit}", k - off))
        }
        "sequence_byte" => {
            flip(&mut r.tx[txin.seq_off], 0);
            Some(format!("in {i} sequence {:#x} -> {:#x}", txin.seq, txin.seq ^ 1))
        }
        "prevout_index" => {
            let new = txin.prev_n ^ 1;
            r.tx[txin.start + 32..txin.start + 36].copy_from_slice(&new.to_le_bytes());
            Some(format!("in {i} prevout n {} -> {new}", txin.prev_n))
        }
        "flags_no_p2sh" => {
            if !r.prevs.iter().any(|p| raw::is_p2sh(&p.spk)) {
                return None;
            }
            r.flags = 512;
            Some("flags 513 -> 512 (P2SH off)".into())
        }
        _ => None,
    }
}

pub fn run(seed: u64, n: usize, outdir: &Path, files: &[PathBuf]) -> Result<()> {
    let mut rng = Rng(seed);
    let mut all: Vec<(String, usize, Record)> = vec![];
    for f in files {
        let name = f.file_name().unwrap().to_string_lossy().to_string();
        for (k, r) in raw::read_file(f)?.into_iter().enumerate() {
            all.push((name.clone(), k, r));
        }
    }
    // Fisher-Yates shuffle, then take records round-robin over kinds.
    for j in (1..all.len()).rev() {
        let k = rng.below(j + 1);
        all.swap(j, k);
    }
    // TAMPER_KINDS=a,b restricts the mutation kinds (used for a targeted P2SH top-up pass).
    let kinds: Vec<&str> = match std::env::var("TAMPER_KINDS") {
        Ok(v) => KINDS.iter().copied().filter(|k| v.split(',').any(|x| x == *k)).collect(),
        Err(_) => KINDS.to_vec(),
    };
    let mut by_era: BTreeMap<&'static str, Vec<(Record, String)>> = BTreeMap::new();
    let mut made = 0;
    let mut turn = 0;
    for (name, k, r) in all {
        if made >= n {
            break;
        }
        // P2SH-specific kinds first get a chance if the record has a P2SH input.
        for t in 0..kinds.len() {
            let kind = kinds[(turn + t) % kinds.len()];
            let mut m = r.clone();
            let i = rng.below(m.prevs.len());
            if let Some(desc) = mutate(&mut m, kind, i, &mut rng) {
                if oracle::check(&m).tx_error.is_some() {
                    continue; // keep only mutations that leave the tx parsable
                }
                by_era.entry(raw::era_of(m.height)).or_default().push((m, format!("{kind} {desc} src {name} r {k}")));
                made += 1;
                turn += 1;
                break;
            }
        }
    }
    std::fs::create_dir_all(outdir)?;
    for (era, v) in by_era {
        let recs: Vec<Record> = v.iter().map(|x| x.0.clone()).collect();
        let files = crate::write_chunks(outdir, era, &recs)?;
        let mut idx = 0;
        for f in files {
            let cnt = raw::read_file(&f)?.len();
            let mut s = String::new();
            for (j, (_, d)) in v[idx..idx + cnt].iter().enumerate() {
                s += &format!("r {j} {d}\n");
            }
            std::fs::write(f.with_extension("kinds"), s)?;
            idx += cnt;
        }
    }
    println!("tampered records: {made}");
    Ok(())
}
