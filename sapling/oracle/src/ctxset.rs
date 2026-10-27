//! ctxset: v6 txs and v5 txs with transparent inputs from sig_raw.bin, with their spent-output
//! context (prev txs fetched via GetTransaction), official sighash and per-signature verdicts.

use std::{
    collections::{HashMap, HashSet},
    fs::{self, File},
    io::{BufReader, BufWriter, Write},
    time::Instant,
};

use anyhow::{anyhow, ensure, Result};
use rayon::prelude::*;
use redjubjub::{Binding, VerificationKey};
use zcash_primitives::transaction::Transaction;

use crate::sigs::{data, fetch, read_raw};
use crate::txs::compact_size;
use crate::txutil::{self, Ctx};

struct Sel {
    h: u64,
    id: [u8; 32],
    raw: Vec<u8>,
    v: u32,
}

pub async fn ctxset() -> Result<()> {
    let dir = data().join("ctxset");
    fs::create_dir_all(&dir)?;
    // 1. select
    let mut v6 = vec![];
    let mut v5t = vec![];
    let mut seen = HashSet::new();
    read_raw(BufReader::new(File::open(data().join("sig_raw.bin"))?), |h, id, raw| {
        if !seen.insert(id) {
            return Ok(());
        }
        let tx = txutil::parse(h, &raw)?;
        let v = txutil::version_num(&tx);
        if v >= 6 {
            v6.push(Sel { h, id, raw, v });
        } else if v == 5 && txutil::n_tin(&tx) > 0 {
            v5t.push(Sel { h, id, raw, v });
        }
        Ok(())
    })?;
    v6.sort_by_key(|s| s.h);
    v5t.sort_by_key(|s| s.h);
    eprintln!("selected {} v6, {} v5 with transparent inputs", v6.len(), v5t.len());
    for (name, set) in [("v6", &v6), ("v5t", &v5t)] {
        // 2. prev txids for this part -> fetch (resumable, concurrent, cached in ctxset/prev.bin)
        let mut want = HashSet::new();
        for s in set.iter() {
            let tx = txutil::parse(s.h, &s.raw)?;
            if let Some(b) = tx.transparent_bundle() {
                if !b.is_coinbase() {
                    for vin in &b.vin {
                        want.insert(*vin.prevout().hash());
                    }
                }
            }
        }
        let list = format!("ctxset/prev_{name}.txt");
        let mut f = BufWriter::new(File::create(data().join(&list))?);
        for id in &want {
            writeln!(f, "0 {} 0 0 0", hex::encode(id))?;
        }
        f.flush()?;
        drop(f);
        let t = Instant::now();
        fetch(&list, "ctxset/prev.bin", 32).await?;
        eprintln!("{name}: {} prev txs needed, fetch {:.0}s", want.len(), t.elapsed().as_secs_f64());
        // 3. load prevs (only the outputs we need)
        let mut prevs: HashMap<[u8; 32], Transaction> = HashMap::new();
        read_raw(BufReader::new(File::open(data().join("ctxset/prev.bin"))?), |h, id, raw| {
            if want.contains(&id) && !prevs.contains_key(&id) {
                let tx = txutil::parse(h, &raw)?;
                ensure!(*tx.txid().as_ref() == id, "prev txid mismatch");
                prevs.insert(id, tx);
            }
            Ok(())
        })?;
        ensure!(prevs.len() == want.len(), "{name}: have {} of {} prev txs", prevs.len(), want.len());
        // 4. ctx + sighash + verdicts
        let mut bin: Vec<u8> = (set.len() as u32).to_le_bytes().to_vec();
        let mut exp = BufWriter::new(File::create(dir.join(format!("expected_{name}.txt")))?);
        writeln!(exp, "# i height version txid sighash n_spends n_outputs verdicts(spend-auth in order, then binding; empty if no Sapling)")?;
        let mut ctxs: Vec<Ctx> = vec![];
        let (mut nsig, mut nbad) = (0usize, 0usize);
        for (i, s) in set.iter().enumerate() {
            let tx = txutil::parse(s.h, &s.raw)?;
            ensure!(*tx.txid().as_ref() == s.id, "txid");
            let mut ctx = Ctx::default();
            let (mut amounts, mut scripts) = (vec![], vec![]);
            if txutil::n_tin(&tx) > 0 {
                for vin in &tx.transparent_bundle().unwrap().vin {
                    let p = &prevs[vin.prevout().hash()];
                    let out = p.transparent_bundle().and_then(|b| b.vout.get(vin.prevout().n() as usize)).ok_or_else(|| anyhow!("prevout missing"))?.clone();
                    amounts.extend_from_slice(&i64::try_from(u64::from(out.value()))?.to_le_bytes());
                    let code = &out.script_pubkey().0 .0;
                    compact_size(code.len(), &mut scripts);
                    scripts.extend_from_slice(code);
                    ctx.amounts.push(out.value());
                    ctx.scripts.push(out.script_pubkey().clone());
                }
            }
            let sighash = txutil::shielded_sighash(&tx, ctx.clone())?;
            ctxs.push(ctx);
            let mut verd = String::new();
            let (mut ns, mut no) = (0, 0);
            if let Some(b) = tx.sapling_bundle() {
                ns = b.shielded_spends().len();
                no = b.shielded_outputs().len();
                for sp in b.shielded_spends() {
                    verd.push(if sp.rk().verify(&sighash, sp.spend_auth_sig()).is_ok() { '1' } else { '0' });
                }
                let sc: Vec<_> = b.shielded_spends().iter().map(|s| *s.cv().as_inner()).collect();
                let oc: Vec<_> = b.shielded_outputs().iter().map(|o| *o.cv().as_inner()).collect();
                let vb: i64 = (*b.value_balance()).into();
                let ok = VerificationKey::<Binding>::try_from(txutil::bvk(&sc, &oc, vb)).map(|k| k.verify(&sighash, &b.authorization().binding_sig).is_ok()).unwrap_or(false);
                verd.push(if ok { '1' } else { '0' });
            }
            nsig += verd.len();
            nbad += verd.chars().filter(|c| *c == '0').count();
            let mut ctxb = vec![];
            ctxb.extend((amounts.len() as u32).to_le_bytes());
            ctxb.extend(&amounts);
            ctxb.extend((scripts.len() as u32).to_le_bytes());
            ctxb.extend(&scripts);
            bin.extend((s.h as u32).to_le_bytes());
            bin.extend((s.raw.len() as u32).to_le_bytes());
            bin.extend(&s.raw);
            bin.extend((ctxb.len() as u32).to_le_bytes());
            bin.extend(&ctxb);
            writeln!(exp, "{i} {} {} {} {} {ns} {no} {verd}", s.h, s.v, hex::encode(s.id), hex::encode(sighash))?;
        }
        exp.flush()?;
        fs::write(dir.join(format!("txs_{name}.bin")), &bin)?;
        println!("{name}: {} txs, {nsig} Sapling signatures, {nbad} officially invalid", set.len());
        // 5. Rust timing: parse + txid + sighash (contexts prebuilt, untimed)
        for threads in [1usize, 18] {
            let pool = rayon::ThreadPoolBuilder::new().num_threads(threads).build()?;
            let t = Instant::now();
            let n: usize = pool.install(|| {
                set.par_iter()
                    .zip(ctxs.par_iter())
                    .map(|(s, c)| {
                        let tx = txutil::parse(s.h, &s.raw).unwrap();
                        assert!(*tx.txid().as_ref() == s.id);
                        std::hint::black_box(txutil::shielded_sighash(&tx, c.clone()).unwrap());
                        1usize
                    })
                    .sum()
            });
            let sec = t.elapsed().as_secs_f64();
            println!("{name}: rust parse+txid+sighash threads={threads}: {n} txs in {sec:.3}s = {:.0} tx/s", n as f64 / sec);
        }
    }
    Ok(())
}
