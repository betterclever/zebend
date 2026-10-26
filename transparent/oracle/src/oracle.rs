//! The verdict for every transparent input of a record, as Zebra 14 computes it
//! (`zebra_script::CachedFfiTransaction::is_valid`), with the zcash_script 0.6 Rust
//! interpreter and the sighash callback of zebra-script 14 (`calculate_sighash`).
use crate::raw::{self, Layout, Record};
use anyhow::{anyhow, ensure, Result};
use std::cell::RefCell;
use zcash_primitives::transaction::{
    self as zp_tx, sighash::PrecomputedSighashData, Authorization, Transaction, TxVersion,
};
use zcash_protocol::consensus::{BranchId, MAIN_NETWORK};
use zcash_protocol::value::Zatoshis;
use zcash_script::{
    interpreter::{CallbackTransactionSignatureChecker, Flags},
    script,
    signature::{HashType, SignedOutputs},
};
use zcash_transparent::address::Script;

// ---- zcash_primitives authorization boilerplate (as in zebra-chain's zcash_primitives.rs)

#[derive(Clone, Debug)]
pub struct TransparentAuth {
    amounts: Vec<Zatoshis>,
    spks: Vec<Script>,
}
impl zcash_transparent::bundle::Authorization for TransparentAuth {
    type ScriptSig = Script;
}
impl zcash_transparent::sighash::TransparentAuthorizingContext for TransparentAuth {
    fn input_amounts(&self) -> Vec<Zatoshis> {
        self.amounts.clone()
    }
    fn input_scriptpubkeys(&self) -> Vec<Script> {
        self.spks.clone()
    }
}
struct MapTransparent(TransparentAuth);
impl zcash_transparent::bundle::MapAuth<zcash_transparent::bundle::Authorized, TransparentAuth> for MapTransparent {
    fn map_script_sig(&self, s: Script) -> Script {
        s
    }
    fn map_authorization(&self, _: zcash_transparent::bundle::Authorized) -> TransparentAuth {
        self.0.clone()
    }
}
#[derive(Debug)]
pub struct PrecomputedAuth;
impl Authorization for PrecomputedAuth {
    type TransparentAuth = TransparentAuth;
    type SaplingAuth = <zp_tx::Authorized as Authorization>::SaplingAuth;
    type OrchardAuth = <zp_tx::Authorized as Authorization>::OrchardAuth;
}

/// One signature check performed by the interpreter: (input, raw hash-type byte, sighash
/// returned by the callback or None = failure).
pub type SigCall = (usize, u8, Option<[u8; 32]>);

pub struct Outcome {
    pub ok: Vec<bool>,
    pub calls: Vec<SigCall>,
    /// Set when the whole tx cannot be checked (unparsable, wrong branch id, ...): all inputs 0.
    pub tx_error: Option<String>,
    pub version: u32,
    pub txid: String,
}

enum Hasher {
    Legacy,
    Zp(PrecomputedSighashData<PrecomputedAuth>),
}

/// Prepare: parse, txid, sighash precomputation.
fn prepare(rec: &Record, lay: &Layout) -> Result<(Hasher, String)> {
    ensure!(rec.prevs.len() == lay.vin.len(), "n_prev {} != #vin {}", rec.prevs.len(), lay.vin.len());
    if lay.version <= 2 {
        let mut id = raw::sha256d(&rec.tx);
        id.reverse();
        return Ok((Hasher::Legacy, hex::encode(id)));
    }
    let height_branch = BranchId::for_height(&MAIN_NETWORK, rec.height.into());
    let tx = Transaction::read(&rec.tx[..], height_branch).map_err(|e| anyhow!("tx parse: {e}"))?;
    let txid = format!("{}", tx.txid());
    let data = tx.into_data();
    // Zebra: for v5+ the embedded branch id must be the one of the block's network upgrade.
    if matches!(data.version(), TxVersion::V5 | TxVersion::V6) {
        ensure!(data.consensus_branch_id() == height_branch, "tx branch id is not the height's");
    }
    let amounts = rec
        .prevs
        .iter()
        .map(|p| Zatoshis::from_nonnegative_i64(p.amount).map_err(|_| anyhow!("prevout amount out of range")))
        .collect::<Result<Vec<_>>>()?;
    let spks = rec.prevs.iter().map(|p| Script(script::Code(p.spk.clone()))).collect();
    let data = data.map_authorization(MapTransparent(TransparentAuth { amounts, spks }), (), ());
    ensure!(data.transparent_bundle().map_or(0, |b| b.vin.len()) == lay.vin.len(), "bundle vin mismatch");
    Ok((Hasher::Zp(PrecomputedSighashData::new(data)), txid))
}

fn sighash(rec: &Record, lay: &Layout, h: &Hasher, i: usize, code: &script::Code, ht: &HashType) -> Option<[u8; 32]> {
    let raw_bits = ht.raw_bits();
    match h {
        Hasher::Legacy => raw::legacy_sighash(&rec.tx, lay, i, &code.0, raw_bits),
        Hasher::Zp(pre) => {
            if lay.version >= 5 {
                if ![0x01, 0x02, 0x03, 0x81, 0x82, 0x83].contains(&raw_bits) {
                    return None;
                }
                if ht.signed_outputs() == SignedOutputs::Single && i >= lay.vout.len() {
                    return None;
                }
            }
            // v3/v4: the raw byte goes in the preimage (zebra sighash_v4_raw). v5+: the byte is
            // one of the six canonical values, which is what zebra's HashType round-trip gives.
            let st = zcash_transparent::sighash::SighashType::from_raw(raw_bits as u8);
            let bundle = pre.tx().transparent_bundle()?;
            let script_code = Script(code.clone());
            let spk = Script(script::Code(rec.prevs[i].spk.clone()));
            let value = Zatoshis::from_nonnegative_i64(rec.prevs[i].amount).ok()?;
            let si = zcash_transparent::sighash::SignableInput::from_parts(bundle, st, i, &script_code, &spk, value).ok()?;
            Some(*pre.signature_hash(&zp_tx::sighash::SignableInput::Transparent(si)).as_ref())
        }
    }
}

/// Which interpreter evaluates the scripts.
#[derive(Clone, Copy, PartialEq)]
pub enum Interp {
    /// zcash_script 0.6 Rust interpreter (`script::Raw::eval`): the primary oracle.
    Rust,
    /// zcashd's C++ interpreter via libzcash_script 0.2 (`CxxInterpreter`, what Zebra 14 runs),
    /// with Zebra's shim: a failed sighash becomes a random 32-byte value.
    #[cfg(feature = "cxx")]
    Cxx,
}

pub fn check(rec: &Record) -> Outcome {
    check_with(rec, Interp::Rust)
}

pub fn check_with(rec: &Record, interp: Interp) -> Outcome {
    let lay = match raw::layout(&rec.tx) {
        Ok(l) => l,
        Err(e) => {
            return Outcome { ok: vec![false; rec.prevs.len()], calls: vec![], tx_error: Some(format!("layout: {e}")), version: 0, txid: String::new() }
        }
    };
    let n = lay.vin.len().max(rec.prevs.len());
    let (h, txid) = match prepare(rec, &lay) {
        Ok(x) => x,
        Err(e) => return Outcome { ok: vec![false; n], calls: vec![], tx_error: Some(e.to_string()), version: lay.version, txid: String::new() },
    };
    let flags = Flags::from_bits_truncate(rec.flags);
    let calls = RefCell::new(Vec::new());
    let mut ok = Vec::with_capacity(n);
    for i in 0..lay.vin.len() {
        let txin = &lay.vin[i];
        if txin.prev_hash == [0; 32] && txin.prev_n == u32::MAX {
            ok.push(false); // coinbase input: Zebra returns TxCoinbase
            continue;
        }
        let cb = |code: &script::Code, ht: &HashType| -> Option<[u8; 32]> {
            let r = sighash(rec, &lay, &h, i, code, ht);
            calls.borrow_mut().push((i, ht.raw_bits() as u8, r));
            r
        };
        let s = script::Raw::from_raw_parts(rec.tx[txin.script_off..txin.script_off + txin.script_len].to_vec(), rec.prevs[i].spk.clone());
        let is_final = txin.seq == u32::MAX;
        let v = match interp {
            Interp::Rust => {
                let checker = CallbackTransactionSignatureChecker { sighash: &cb, lock_time: lay.lock_time.into(), is_final };
                matches!(s.eval(flags, &checker), Ok(true))
            }
            #[cfg(feature = "cxx")]
            Interp::Cxx => {
                use libzcash_script::ZcashScript;
                let shim = |c: &script::Code, ht: &HashType| -> Option<[u8; 32]> {
                    Some(cb(c, ht).unwrap_or_else(|| {
                        let mut b = [0u8; 32];
                        getrandom_fill(&mut b);
                        b
                    }))
                };
                let it = libzcash_script::CxxInterpreter { sighash: &shim, lock_time: lay.lock_time, is_final };
                matches!(it.verify_callback(&s, flags), Ok(true))
            }
        };
        ok.push(v);
    }
    Outcome { ok, calls: calls.into_inner(), tx_error: None, version: lay.version, txid }
}

pub fn expect_line(k: usize, o: &Outcome) -> String {
    format!("r {k} {}", o.ok.iter().map(|&b| if b { '1' } else { '0' }).collect::<String>())
}

pub fn sighash_lines(k: usize, o: &Outcome, out: &mut String) {
    use std::fmt::Write;
    for (i, ht, r) in &o.calls {
        let _ = writeln!(out, "r {k} in {i} ht {ht:02x} {}", r.map_or("NONE".to_string(), hex::encode));
    }
}

/// Per-call random bytes for Zebra's failed-sighash shim (no crate needed: OS randomness).
#[cfg(feature = "cxx")]
fn getrandom_fill(b: &mut [u8; 32]) {
    use std::io::Read;
    std::fs::File::open("/dev/urandom").and_then(|mut f| f.read_exact(b)).expect("urandom");
}
