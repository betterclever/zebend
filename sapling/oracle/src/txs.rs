//! A detailed sample of real v4/v5 Sapling transactions for the Bend parser.

use std::{
    collections::{BTreeMap, HashMap, HashSet},
    fs::{self, File},
    io::{BufReader, BufWriter, Write},
};

use anyhow::{anyhow, ensure, Result};
use blake2b_simd::Params;
use zcash_primitives::transaction::{txid::TxIdDigester, Transaction};

use crate::lwd::Lwd;
use crate::sigs::{data, read_raw};
use crate::txutil::{self, Ctx};

fn h32(personal: &[u8], parts: &[&[u8]]) -> [u8; 32] {
    let mut s = Params::new().hash_length(32).personal(personal).to_state();
    for p in parts {
        s.update(p);
    }
    s.finalize().as_bytes().try_into().unwrap()
}

struct Rd<'a>(&'a [u8]);
impl<'a> Rd<'a> {
    fn take(&mut self, n: usize) -> Result<&'a [u8]> {
        ensure!(self.0.len() >= n, "short tx");
        let (a, b) = self.0.split_at(n);
        self.0 = b;
        Ok(a)
    }
    fn cs(&mut self) -> Result<usize> {
        let b = self.take(1)?[0];
        Ok(match b {
            0xfd => u16::from_le_bytes(self.take(2)?.try_into()?) as usize,
            0xfe => u32::from_le_bytes(self.take(4)?.try_into()?) as usize,
            0xff => u64::from_le_bytes(self.take(8)?.try_into()?) as usize,
            x => x as usize,
        })
    }
}

/// ZIP 243 digests and the shielded sighash, computed from the raw v4 bytes by our own parser:
/// (hashPrevouts, hashSequence, hashOutputs, hashJoinSplits, hashShieldedSpends, hashShieldedOutputs, sighash)
fn zip243(raw: &[u8], branch_id: u32) -> Result<[[u8; 32]; 7]> {
    let mut r = Rd(raw);
    let header = r.take(4)?;
    let vgid = r.take(4)?;
    ensure!(u32::from_le_bytes(header.try_into()?) == 0x8000_0004, "not v4");
    let nin = r.cs()?;
    let (mut prev, mut seq) = (vec![], vec![]);
    for _ in 0..nin {
        prev.extend_from_slice(r.take(36)?);
        let sl = r.cs()?;
        r.take(sl)?;
        seq.extend_from_slice(r.take(4)?);
    }
    let nout = r.cs()?;
    let mut outs = vec![];
    for _ in 0..nout {
        outs.extend_from_slice(r.take(8)?);
        let sl = r.cs()?;
        let s = r.take(sl)?;
        // re-serialize the compactsize canonically as written (same bytes)
        let mut cs = vec![];
        crate::txs::compact_size(sl, &mut cs);
        outs.extend_from_slice(&cs);
        outs.extend_from_slice(s);
    }
    let lock = r.take(4)?;
    let expiry = r.take(4)?;
    let vb = r.take(8)?;
    let nsp = r.cs()?;
    let mut sp = vec![];
    for _ in 0..nsp {
        let d = r.take(384)?;
        sp.extend_from_slice(&d[..320]); // cv anchor nf rk zkproof (no spendAuthSig)
    }
    let nso = r.cs()?;
    let mut so = vec![];
    for _ in 0..nso {
        so.extend_from_slice(r.take(948)?);
    }
    let njs = r.cs()?;
    let mut js = vec![];
    for _ in 0..njs {
        js.extend_from_slice(r.take(1698)?);
    }
    if njs > 0 {
        js.extend_from_slice(r.take(32)?); // joinSplitPubKey
        r.take(64)?; // joinSplitSig
    }
    if nsp + nso > 0 {
        r.take(64)?; // bindingSig
    }
    ensure!(r.0.is_empty(), "trailing bytes");
    let z = [0u8; 32];
    let hp = h32(b"ZcashPrevoutHash", &[&prev]);
    let hs = h32(b"ZcashSequencHash", &[&seq]);
    let ho = h32(b"ZcashOutputsHash", &[&outs]);
    let hj = if njs > 0 { h32(b"ZcashJSplitsHash", &[&js]) } else { z };
    let hsp = if nsp > 0 { h32(b"ZcashSSpendsHash", &[&sp]) } else { z };
    let hso = if nso > 0 { h32(b"ZcashSOutputHash", &[&so]) } else { z };
    let mut personal = *b"ZcashSigHash\0\0\0\0";
    personal[12..].copy_from_slice(&branch_id.to_le_bytes());
    let sh = h32(&personal, &[header, vgid, &hp, &hs, &ho, &hj, &hsp, &hso, lock, expiry, vb, &1u32.to_le_bytes()]);
    Ok([hp, hs, ho, hj, hsp, hso, sh])
}

pub fn compact_size(n: usize, out: &mut Vec<u8>) {
    if n < 253 {
        out.push(n as u8);
    } else if n <= 0xffff {
        out.push(253);
        out.extend((n as u16).to_le_bytes());
    } else if n <= 0xffff_ffff {
        out.push(254);
        out.extend((n as u32).to_le_bytes());
    } else {
        out.push(255);
        out.extend((n as u64).to_le_bytes());
    }
}

struct Info {
    h: u64,
    id: [u8; 32],
    raw: Vec<u8>,
    v: u32,
    tin: usize,
    tout: usize,
    js: usize,
    sp: usize,
    so: usize,
    orchard: bool,
}

fn mix(id: &[u8; 32], seed: u64) -> u64 {
    let mut z = seed ^ u64::from_le_bytes(id[0..8].try_into().unwrap());
    z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
    z ^ (z >> 31)
}

pub async fn txs(per_version: usize) -> Result<()> {
    let dir = data().join("txs");
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir)?;
    // Candidates from the signature corpus (sig_raw.bin).
    let mut all: Vec<Info> = vec![];
    let mut seen = HashSet::new();
    read_raw(BufReader::new(File::open(data().join("sig_raw.bin"))?), |h, id, raw| {
        if !seen.insert(id) {
            return Ok(());
        }
        let tx = txutil::parse(h, &raw)?;
        let v = txutil::version_num(&tx);
        if v != 4 && v != 5 {
            return Ok(());
        }
        let Some(b) = tx.sapling_bundle() else { return Ok(()) };
        let info = Info {
            h,
            id,
            v,
            tin: txutil::n_tin(&tx),
            tout: tx.transparent_bundle().map_or(0, |b| b.vout.len()),
            js: tx.sprout_bundle().map_or(0, |b| b.joinsplits.len()),
            sp: b.shielded_spends().len(),
            so: b.shielded_outputs().len(),
            orchard: tx.orchard_bundle().is_some(),
            raw: vec![],
        };
        // keep raw bytes only for small-ish txs (the spam-era 200+-output txs are capped below)
        all.push(Info { raw: if raw.len() < 400_000 { raw } else { vec![] }, ..info });
        Ok(())
    })?;
    all.retain(|i| !i.raw.is_empty());
    eprintln!("{} v4/v5 sapling candidates", all.len());
    // Deterministic shuffled order; then fill category quotas per version.
    all.sort_by_key(|i| mix(&i.id, 2026));
    type Pred = fn(&Info) -> bool;
    let cats: Vec<(&str, Pred, usize)> = vec![
        ("joinsplit", |i| i.js > 0, 30),
        ("transparent_in", |i| i.tin > 0, 40),
        ("transparent_out", |i| i.tout > 0 && i.tin == 0, 30),
        ("spends_only", |i| i.so == 0, 20),
        ("outputs_only", |i| i.sp == 0, 30),
        ("many_spends", |i| i.sp >= 5, 30),
        ("many_outputs", |i| i.so >= 20, 10),
        ("with_orchard", |i| i.orchard, 20),
        ("fully_shielded", |i| i.tin == 0 && i.tout == 0 && i.js == 0 && i.sp > 0 && i.so > 0, 40),
    ];
    let mut chosen: Vec<usize> = vec![];
    let mut taken = HashSet::new();
    let mut tally: BTreeMap<String, usize> = BTreeMap::new();
    for v in [4u32, 5] {
        let mut nv = 0;
        for (name, pred, quota) in &cats {
            let mut k = 0;
            for (idx, i) in all.iter().enumerate() {
                if nv >= per_version || k >= *quota {
                    break;
                }
                if i.v == v && pred(i) && !taken.contains(&idx) {
                    taken.insert(idx);
                    chosen.push(idx);
                    k += 1;
                    nv += 1;
                }
            }
            *tally.entry(format!("v{v} {name}")).or_default() += k;
        }
        // fill with random others spread over heights
        for (idx, i) in all.iter().enumerate() {
            if nv >= per_version {
                break;
            }
            if i.v == v && !taken.contains(&idx) {
                taken.insert(idx);
                chosen.push(idx);
                nv += 1;
                *tally.entry(format!("v{v} other")).or_default() += 1;
            }
        }
    }
    chosen.sort_by_key(|&i| (all[i].v, all[i].h));
    let mut exp = BufWriter::new(File::create(dir.join("expected.txt"))?);
    writeln!(exp, "# N height version branch_id txid sighash n_spends n_outputs value_balance n_tin n_tout n_joinsplit has_orchard | v4: hashPrevouts hashSequence hashOutputs hashJoinSplits hashShieldedSpends hashShieldedOutputs | v5: sapling_digest")?;
    writeln!(exp, "# txid/sighash/digests: hex of the raw 32 hash bytes (internal order; block explorers show the txid byte-reversed). branch_id: hex of the u32 consensus branch id. value_balance: signed decimal zatoshis.")?;
    let mut lwd: Option<Lwd> = None;
    let mut prev_cache: HashMap<[u8; 32], Transaction> = HashMap::new();
    let mut nsig = (0usize, 0usize);
    for (n, &idx) in chosen.iter().enumerate() {
        let i = &all[idx];
        let tx = txutil::parse(i.h, &i.raw)?;
        ensure!(*tx.txid().as_ref() == i.id, "txid");
        let branch_id = u32::from(tx.consensus_branch_id());
        let mut ctx = Ctx::default();
        let (mut amounts, mut scripts) = (vec![], vec![]);
        if i.v == 5 && i.tin > 0 {
            let tb = tx.transparent_bundle().unwrap();
            for vin in &tb.vin {
                let ph: [u8; 32] = *vin.prevout().hash();
                if !prev_cache.contains_key(&ph) {
                    if lwd.is_none() {
                        lwd = Some(Lwd::any().await?);
                    }
                    let pr = lwd.as_mut().unwrap().raw_tx(&ph).await?;
                    prev_cache.insert(ph, txutil::parse(pr.height, &pr.data)?);
                }
                let out = prev_cache[&ph].transparent_bundle().and_then(|b| b.vout.get(vin.prevout().n() as usize)).ok_or_else(|| anyhow!("prevout"))?.clone();
                amounts.extend_from_slice(&i64::try_from(u64::from(out.value()))?.to_le_bytes());
                let code = &out.script_pubkey().0 .0;
                compact_size(code.len(), &mut scripts);
                scripts.extend_from_slice(code);
                ctx.amounts.push(out.value());
                ctx.scripts.push(out.script_pubkey().clone());
            }
        }
        let sighash = txutil::shielded_sighash(&tx, ctx)?;
        // Every Sapling signature must verify under this sighash.
        let b = tx.sapling_bundle().unwrap();
        for s in b.shielded_spends() {
            ensure!(s.rk().verify(&sighash, s.spend_auth_sig()).is_ok(), "spend-auth sig fails in tx {n}");
            nsig.0 += 1;
        }
        let spend_cvs: Vec<_> = b.shielded_spends().iter().map(|s| *s.cv().as_inner()).collect();
        let out_cvs: Vec<_> = b.shielded_outputs().iter().map(|o| *o.cv().as_inner()).collect();
        let vb: i64 = (*b.value_balance()).into();
        let bvk = redjubjub::VerificationKey::<redjubjub::Binding>::try_from(txutil::bvk(&spend_cvs, &out_cvs, vb)).map_err(|_| anyhow!("bvk"))?;
        ensure!(bvk.verify(&sighash, &b.authorization().binding_sig).is_ok(), "binding sig fails in tx {n}");
        nsig.1 += 1;
        let extra = if i.v == 4 {
            let d = zip243(&i.raw, branch_id)?;
            ensure!(d[6] == sighash, "independent ZIP 243 sighash disagrees in tx {n}");
            d[..6].iter().map(hex::encode).collect::<Vec<_>>().join(" ")
        } else {
            let dg = tx.deref_digest();
            hex::encode(dg)
        };
        let mut ctxb = vec![];
        ctxb.extend((amounts.len() as u32).to_le_bytes());
        ctxb.extend(&amounts);
        ctxb.extend((scripts.len() as u32).to_le_bytes());
        ctxb.extend(&scripts);
        fs::write(dir.join(format!("tx_{n}.bin")), &i.raw)?;
        fs::write(dir.join(format!("tx_{n}.ctx")), &ctxb)?;
        writeln!(
            exp,
            "{n} {} {} {branch_id:08x} {} {} {} {} {vb} {} {} {} {} {extra}",
            i.h,
            i.v,
            hex::encode(i.id),
            hex::encode(sighash),
            i.sp,
            i.so,
            i.tin,
            i.tout,
            i.js,
            i.orchard as u8
        )?;
    }
    exp.flush()?;
    println!("wrote {} txs; all {} spend-auth + {} binding signatures verify under the computed sighash", chosen.len(), nsig.0, nsig.1);
    for (k, v) in tally {
        println!("  {k}: {v}");
    }
    Ok(())
}

trait SaplingDigest {
    fn deref_digest(&self) -> [u8; 32];
}
impl SaplingDigest for Transaction {
    /// ZIP 244 sapling_digest (T.3), from zcash_primitives' TxIdDigester (empty bundle digest if none).
    fn deref_digest(&self) -> [u8; 32] {
        let d = (**self).digest(TxIdDigester);
        d.sapling_digest().map(|h| h.as_bytes().try_into().unwrap()).unwrap_or_else(|| h32(b"ZTxIdSaplingHash", &[]))
    }
}
