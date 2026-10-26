//! Parsing raw transactions and computing the shielded sighash with zcash_primitives' own API.

use anyhow::{ensure, Context, Result};
use group::GroupEncoding;
use transparent::{address::Script, bundle as tb, sighash::TransparentAuthorizingContext};
use zcash_primitives::transaction::{
    sighash::{PrecomputedSighashData, SignableInput},
    Authorization, Transaction, TxVersion,
};
use zcash_protocol::{
    consensus::{BlockHeight, BranchId, MainNetwork},
    value::Zatoshis,
};

/// Spent-output context for ZIP 244 (amounts and scriptPubKeys of the transparent inputs).
#[derive(Debug, Clone, Default)]
pub struct Ctx {
    pub amounts: Vec<Zatoshis>,
    pub scripts: Vec<Script>,
}
impl tb::Authorization for Ctx {
    type ScriptSig = Script;
}
impl TransparentAuthorizingContext for Ctx {
    fn input_amounts(&self) -> Vec<Zatoshis> {
        self.amounts.clone()
    }
    fn input_scriptpubkeys(&self) -> Vec<Script> {
        self.scripts.clone()
    }
}
struct CtxMap(Ctx);
impl tb::MapAuth<tb::Authorized, Ctx> for CtxMap {
    fn map_script_sig(&self, s: Script) -> Script {
        s
    }
    fn map_authorization(&self, _: tb::Authorized) -> Ctx {
        self.0.clone()
    }
}
#[derive(Debug)]
pub struct SigAuth;
impl Authorization for SigAuth {
    type TransparentAuth = Ctx;
    type SaplingAuth = sapling::bundle::Authorized;
    type OrchardAuth = orchard::bundle::Authorized;
}

pub fn branch(h: u64) -> BranchId {
    BranchId::for_height(&MainNetwork, BlockHeight::from_u32(h as u32))
}

pub fn parse(h: u64, raw: &[u8]) -> Result<Transaction> {
    Transaction::read(raw, branch(h)).with_context(|| format!("parse tx at {h}"))
}

pub fn version_num(tx: &Transaction) -> u32 {
    match tx.version() {
        TxVersion::Sprout(v) => v,
        TxVersion::V3 => 3,
        TxVersion::V4 => 4,
        TxVersion::V5 => 5,
        _ => 6,
    }
}

/// Non-coinbase transparent input count.
pub fn n_tin(tx: &Transaction) -> usize {
    tx.transparent_bundle().map_or(0, |b| if b.is_coinbase() { 0 } else { b.vin.len() })
}

/// The shielded sighash (SignableInput::Shielded): ZIP 243 for v4, ZIP 244 for v5.
/// `ctx` must hold the spent outputs when a v5 tx has transparent inputs.
pub fn shielded_sighash(tx: &Transaction, ctx: Ctx) -> Result<[u8; 32]> {
    if version_num(tx) >= 5 {
        ensure!(ctx.amounts.len() == n_tin(tx), "missing spent-output context");
    }
    let data = tx.clone().into_data();
    let data = data.map_bundles::<SigAuth>(|t| t.map(|b| b.map_authorization(CtxMap(ctx))), |s| s, |o| o);
    let pre = PrecomputedSighashData::new(data);
    Ok(*pre.signature_hash(&SignableInput::Shielded).as_ref())
}

pub fn i64_to_fr(v: i64) -> jubjub::Fr {
    if v >= 0 {
        jubjub::Fr::from(v as u64)
    } else {
        -jubjub::Fr::from(v.unsigned_abs())
    }
}

/// bvk = sum(cv_spend) - sum(cv_output) - [valueBalance] V   (protocol spec 4.13)
pub fn bvk(spend_cvs: &[jubjub::ExtendedPoint], out_cvs: &[jubjub::ExtendedPoint], vb: i64) -> [u8; 32] {
    let v = jubjub::ExtendedPoint::from(sapling::constants::VALUE_COMMITMENT_VALUE_GENERATOR);
    let mut acc = jubjub::ExtendedPoint::identity();
    for c in spend_cvs {
        acc += c;
    }
    for c in out_cvs {
        acc -= c;
    }
    acc -= v * i64_to_fr(vb);
    acc.to_bytes()
}

/// Rust timing: Transaction::read + txid + shielded sighash over every tx of sig_raw.bin
/// (raw bytes loaded untimed). v5 txs with transparent inputs get no sighash (no prevouts).
pub fn parsetime(threads: usize) -> anyhow::Result<()> {
    use rayon::prelude::*;
    let mut recs: Vec<(u64, [u8; 32], Vec<u8>)> = vec![];
    crate::sigs::read_raw(std::io::BufReader::new(std::fs::File::open(crate::sigs::data().join("sig_raw.bin"))?), |h, id, b| {
        recs.push((h, id, b));
        Ok(())
    })?;
    let bytes: usize = recs.iter().map(|r| r.2.len()).sum();
    let pool = rayon::ThreadPoolBuilder::new().num_threads(threads).build()?;
    let t = std::time::Instant::now();
    let (ok, nosh): (usize, usize) = pool.install(|| {
        recs.par_iter()
            .map(|(h, id, raw)| {
                let tx = parse(*h, raw).unwrap();
                assert!(tx.txid().as_ref() == id);
                if version_num(&tx) >= 5 && n_tin(&tx) > 0 {
                    (1, 1)
                } else {
                    let s = shielded_sighash(&tx, Ctx::default()).unwrap();
                    std::hint::black_box(s);
                    (1, 0)
                }
            })
            .reduce(|| (0, 0), |a, b| (a.0 + b.0, a.1 + b.1))
    });
    let s = t.elapsed().as_secs_f64();
    println!(
        "rust parse+txid+sighash threads={threads}: {ok} txs ({:.0} MB), {} without sighash (v5/v6 w/ transparent inputs), {s:.2}s = {:.0} tx/s",
        bytes as f64 / 1e6,
        nosh,
        ok as f64 / s
    );
    Ok(())
}
