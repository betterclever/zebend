//! tv-fuzz OUT N SEED: N records of synthetic transactions (v4 at a Canopy height, v5 at an NU6
//! height), each with 1..3 transparent inputs whose scripts come from templates (P2PKH, P2PK,
//! bare multisig, P2SH multisig, P2SH single-key, CHECKLOCKTIMEVERIFY, hash locks, IF/ELSE,
//! numeric puzzles, zcash_script's own test vectors, random bytes) signed with real keys,
//! then mutated. Writes OUT.ztv (the Bend tv record format), OUT.expect ("r k verdicts", what
//! zcash_script 0.6 + zcash_primitives' sighash say, with Zebra's sighash callback rules) and
//! OUT.kinds (template/mutation per input).
//! `tv-fuzz vectors OUT`: zcash_script's test vectors as records (one input each, flags as given).
use rand::{rngs::StdRng, Rng, RngCore, SeedableRng};
use ripemd::Ripemd160;
use secp256k1::{Message, PublicKey, Secp256k1, SecretKey};
use sha2::{Digest, Sha256};
use std::io::Write;
use zcash_primitives::transaction::{
    sighash::{PrecomputedSighashData, SignableInput},
    Transaction, TransactionData,
};
use zcash_protocol::{consensus::BranchId, value::Zatoshis};
use zcash_script::{interpreter, script, signature};
use zcash_transparent::{address::Script, bundle as tb, sighash as ts};

// ------------------------------------------------------------------ Zebra-style sighash

#[derive(Clone, Debug)]
struct TAuth {
    prev: Vec<(i64, Vec<u8>)>,
}
impl tb::Authorization for TAuth {
    type ScriptSig = Script;
}
impl ts::TransparentAuthorizingContext for TAuth {
    fn input_amounts(&self) -> Vec<Zatoshis> {
        self.prev.iter().map(|(v, _)| Zatoshis::from_nonnegative_i64(*v).unwrap()).collect()
    }
    fn input_scriptpubkeys(&self) -> Vec<Script> {
        self.prev.iter().map(|(_, s)| Script(script::Code(s.clone()))).collect()
    }
}
struct MapT(TAuth);
impl tb::MapAuth<tb::Authorized, TAuth> for MapT {
    fn map_script_sig(&self, s: Script) -> Script {
        s
    }
    fn map_authorization(&self, _: tb::Authorized) -> TAuth {
        self.0.clone()
    }
}
#[derive(Debug)]
struct PAuth;
impl zcash_primitives::transaction::Authorization for PAuth {
    type TransparentAuth = TAuth;
    type SaplingAuth = sapling::bundle::Authorized;
    type OrchardAuth = orchard::bundle::Authorized;
}

struct Ctx {
    pre: PrecomputedSighashData<PAuth>,
    ver: u32,
    nout: usize,
    prev: Vec<(i64, Vec<u8>)>,
}

impl Ctx {
    fn new(bytes: &[u8], branch: BranchId, prev: Vec<(i64, Vec<u8>)>) -> Ctx {
        let tx = Transaction::read(bytes, branch).expect("synthetic tx parses");
        let ver = u32::from_le_bytes(bytes[..4].try_into().unwrap()) & 0x7fffffff;
        let data: TransactionData<_> = tx.into_data();
        let nout = data.transparent_bundle().map_or(0, |b| b.vout.len());
        let mapped = data.map_authorization(MapT(TAuth { prev: prev.clone() }), (), ());
        Ctx { pre: PrecomputedSighashData::new(mapped), ver, nout, prev }
    }

    /// zebra-script 14's calculate_sighash.
    fn sighash(&self, idx: usize, script_code: &[u8], raw: u8) -> Option<[u8; 32]> {
        if self.ver >= 5 {
            if ![0x01u8, 0x02, 0x03, 0x81, 0x82, 0x83].contains(&raw) {
                return None;
            }
            if raw & 0x1f == 3 && idx >= self.nout {
                return None;
            }
        }
        let ht = if self.ver < 5 { ts::SighashType::from_raw(raw) } else { ts::SighashType::parse(raw)? };
        let bundle = self.pre.tx().transparent_bundle()?;
        let sc = Script(script::Code(script_code.to_vec()));
        let spk = Script(script::Code(self.prev[idx].1.clone()));
        let si = ts::SignableInput::from_parts(bundle, ht, idx, &sc, &spk, Zatoshis::from_nonnegative_i64(self.prev[idx].0).ok()?).ok()?;
        Some(*self.pre.signature_hash(&SignableInput::Transparent(si)).as_ref())
    }
}

fn verdict(ctx: &Ctx, idx: usize, sig: &[u8], spk: &[u8], flags: u32, lock: u32, seq: u32) -> bool {
    let f = interpreter::Flags::from_bits_truncate(flags);
    let cb = |sc: &script::Code, ht: &signature::HashType| ctx.sighash(idx, &sc.0, ht.raw_bits() as u8);
    let checker = interpreter::CallbackTransactionSignatureChecker { sighash: &cb, lock_time: lock as i64, is_final: seq == u32::MAX };
    script::Raw::from_raw_parts(sig.to_vec(), spk.to_vec()).eval(f, &checker) == Ok(true)
}

// ------------------------------------------------------------------ encoding helpers

fn cs(n: usize) -> Vec<u8> {
    if n < 253 {
        vec![n as u8]
    } else if n <= 0xffff {
        vec![253, n as u8, (n >> 8) as u8]
    } else {
        let mut v = vec![254];
        v.extend((n as u32).to_le_bytes());
        v
    }
}

fn push(d: &[u8]) -> Vec<u8> {
    let mut v = match d.len() {
        0 => vec![0],
        1 if d[0] >= 1 && d[0] <= 16 => return vec![0x50 + d[0]],
        1 if d[0] == 0x81 => return vec![0x4f],
        n if n <= 75 => vec![n as u8],
        n if n <= 255 => vec![0x4c, n as u8],
        n => vec![0x4d, n as u8, (n >> 8) as u8],
    };
    v.extend_from_slice(d);
    v
}

fn num(n: i64) -> Vec<u8> {
    zcash_script::num::serialize(n)
}

fn h160(d: &[u8]) -> Vec<u8> {
    Ripemd160::digest(Sha256::digest(d)).to_vec()
}

const N: [u8; 32] = [
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE,
    0xBA, 0xAE, 0xDC, 0xE6, 0xAF, 0x48, 0xA0, 0x3B, 0xBF, 0xD2, 0x5E, 0x8C, 0xD0, 0x36, 0x41, 0x41,
];

fn der_int(x: &[u8]) -> Vec<u8> {
    let mut i = 0;
    while i < 31 && x[i] == 0 {
        i += 1;
    }
    let mut v = x[i..].to_vec();
    if v[0] & 0x80 != 0 {
        v.insert(0, 0);
    }
    v
}

fn der(r: &[u8], s: &[u8]) -> Vec<u8> {
    let (r, s) = (der_int(r), der_int(s));
    let mut v = vec![0x30, (4 + r.len() + s.len()) as u8, 0x02, r.len() as u8];
    v.extend(&r);
    v.push(0x02);
    v.push(s.len() as u8);
    v.extend(&s);
    v
}

fn neg_s(s: &[u8; 32]) -> [u8; 32] {
    let mut out = [0u8; 32];
    let mut borrow = 0i32;
    for i in (0..32).rev() {
        let d = N[i] as i32 - s[i] as i32 - borrow;
        borrow = (d < 0) as i32;
        out[i] = (d + 256 * borrow) as u8;
    }
    out
}

struct Key {
    sk: SecretKey,
    enc: Vec<u8>,
}

fn key(rng: &mut StdRng) -> Key {
    let sk = SecretKey::new(rng);
    let pk = PublicKey::from_secret_key(&sk);
    let enc = match rng.random_range(0..10) {
        0..=5 => pk.serialize().to_vec(),
        6..=8 => pk.serialize_uncompressed().to_vec(),
        _ => {
            let mut u = pk.serialize_uncompressed();
            u[0] = 6 | (u[64] & 1);
            u.to_vec()
        }
    };
    Key { sk, enc }
}

/// A DER signature + hash-type byte over `h` (high S sometimes).
fn sign(rng: &mut StdRng, k: &Key, h: Option<[u8; 32]>, ht: u8) -> Vec<u8> {
    let h = h.unwrap_or_else(|| rng.random());
    let c = Secp256k1::new().sign_ecdsa(Message::from_digest(h), &k.sk).serialize_compact();
    let (r, mut s) = ([0u8; 32], [0u8; 32]);
    let mut r = r;
    r.copy_from_slice(&c[..32]);
    s.copy_from_slice(&c[32..]);
    if rng.random_range(0..8) == 0 {
        s = neg_s(&s);
    }
    let mut d = der(&r, &s);
    d.push(ht);
    d
}

fn hash_type(rng: &mut StdRng) -> u8 {
    match rng.random_range(0..20) {
        0..=9 => 1,
        10 => 2,
        11 => 3,
        12 => 0x81,
        13 => 0x82,
        14 => 0x83,
        15 => 0,
        16 => 4,
        17 => 0x41,
        18 => 0xff,
        _ => rng.random(),
    }
}

// ------------------------------------------------------------------ templates

/// A spending condition: scriptSig built later (it needs the sighash), scriptPubKey now.
enum Tpl {
    /// keys, m: CHECKMULTISIG; wrap: P2SH
    Multi(Vec<Key>, usize, bool),
    P2pkh(Key),
    P2pk(Key, bool),
    Cltv(Key, i64),
    IfElse(Key, Key, bool),
    Raw(Vec<u8>, Vec<u8>, &'static str),
}

fn multisig_script(keys: &[Key], m: usize) -> Vec<u8> {
    let mut s = num_op(m as i64);
    for k in keys {
        s.extend(push(&k.enc));
    }
    s.extend(num_op(keys.len() as i64));
    s.push(0xae);
    s
}

fn num_op(n: i64) -> Vec<u8> {
    push(&num(n))
}

fn spk_of(t: &Tpl) -> (Vec<u8>, Vec<u8>, &'static str) {
    // (scriptPubKey, script code for signing, kind)
    match t {
        Tpl::Multi(keys, m, wrap) => {
            let ms = multisig_script(keys, *m);
            if *wrap {
                let mut spk = vec![0xa9, 0x14];
                spk.extend(h160(&ms));
                spk.push(0x87);
                (spk, ms, "p2sh-multisig")
            } else {
                (ms.clone(), ms, "multisig")
            }
        }
        Tpl::P2pkh(k) => {
            let mut s = vec![0x76, 0xa9, 0x14];
            s.extend(h160(&k.enc));
            s.extend([0x88, 0xac]);
            (s.clone(), s, "p2pkh")
        }
        Tpl::P2pk(k, wrap) => {
            let mut s = push(&k.enc);
            s.push(0xac);
            if *wrap {
                let mut spk = vec![0xa9, 0x14];
                spk.extend(h160(&s));
                spk.push(0x87);
                (spk, s, "p2sh-p2pk")
            } else {
                (s.clone(), s, "p2pk")
            }
        }
        Tpl::Cltv(k, lt) => {
            let mut s = push(&num(*lt));
            s.extend([0xb1, 0x75]);
            s.extend(push(&k.enc));
            s.push(0xac);
            (s.clone(), s, "cltv")
        }
        Tpl::IfElse(a, b, _) => {
            let mut s = vec![0x63];
            s.extend(push(&a.enc));
            s.push(0xac);
            s.push(0x67);
            s.extend(push(&b.enc));
            s.push(0xac);
            s.push(0x68);
            (s.clone(), s, "ifelse")
        }
        Tpl::Raw(_, spk, kind) => (spk.clone(), spk.clone(), kind),
    }
}

fn sig_of(rng: &mut StdRng, t: &Tpl, ctx: &Ctx, idx: usize, code: &[u8]) -> Vec<u8> {
    let mut sg = |rng: &mut StdRng, k: &Key| {
        let ht = hash_type(rng);
        sign(rng, k, ctx.sighash(idx, code, ht), ht)
    };
    match t {
        Tpl::Multi(keys, m, wrap) => {
            let mut s = vec![0x00];
            // m signatures by an ordered random subset of the keys
            let mut chosen: Vec<usize> = (0..keys.len()).collect();
            while chosen.len() > *m {
                let i = rng.random_range(0..chosen.len());
                chosen.remove(i);
            }
            if rng.random_range(0..10) == 0 {
                chosen.reverse(); // wrong order: fails unless m <= 1
            }
            for i in chosen {
                let sig = sg(rng, &keys[i]);
                s.extend(push(&sig));
            }
            if *wrap {
                s.extend(push(code));
            }
            s
        }
        Tpl::P2pkh(k) => {
            let sig = sg(rng, k);
            let mut s = push(&sig);
            s.extend(push(&k.enc));
            s
        }
        Tpl::P2pk(k, wrap) => {
            let sig = sg(rng, k);
            let mut s = push(&sig);
            if *wrap {
                s.extend(push(code));
            }
            s
        }
        Tpl::Cltv(k, _) => push(&sg(rng, k)),
        Tpl::IfElse(a, b, first) => {
            let sig = if *first { sg(rng, a) } else { sg(rng, b) };
            let mut s = push(&sig);
            s.extend(num_op(*first as i64));
            s
        }
        Tpl::Raw(sig, _, _) => sig.clone(),
    }
}

const OPS: &[u8] = &[
    0x00, 0x4f, 0x50, 0x51, 0x52, 0x53, 0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x6b,
    0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x7b, 0x7c, 0x7d,
    0x7e, 0x82, 0x87, 0x88, 0x89, 0x8b, 0x8c, 0x8f, 0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x9a, 0x9b, 0x9c, 0x9d,
    0x9e, 0x9f, 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf,
    0xb0, 0xb1, 0xb2, 0xb9, 0xba, 0xff,
];

fn rand_script(rng: &mut StdRng, n: usize) -> Vec<u8> {
    let mut s = vec![];
    for _ in 0..n {
        match rng.random_range(0..4) {
            0 => s.extend(num_op(rng.random_range(-300..300))),
            1 => {
                let len = [0usize, 1, 2, 4, 5, 20, 33][rng.random_range(0..7)];
                let mut d = vec![0u8; len];
                rng.fill_bytes(&mut d);
                s.extend(push(&d));
            }
            _ => s.push(OPS[rng.random_range(0..OPS.len())]),
        }
    }
    s
}

fn hashlock(rng: &mut StdRng) -> Tpl {
    let mut x = vec![0u8; rng.random_range(0..80)];
    rng.fill_bytes(&mut x);
    let (op, h): (u8, Vec<u8>) = match rng.random_range(0..5) {
        0 => (0xa6, Ripemd160::digest(&x).to_vec()),
        1 => (0xa7, sha1::Sha1::digest(&x).to_vec()),
        2 => (0xa8, Sha256::digest(&x).to_vec()),
        3 => (0xa9, h160(&x)),
        _ => (0xaa, Sha256::digest(Sha256::digest(&x)).to_vec()),
    };
    let mut spk = vec![op];
    spk.extend(push(&h));
    spk.push(0x87);
    Tpl::Raw(push(&x), spk, "hashlock")
}

fn arith(rng: &mut StdRng) -> Tpl {
    // <a> <b> OP <c> NUMEQUAL-ish puzzles, computed by the oracle anyway
    let mut sig = vec![];
    for _ in 0..rng.random_range(1..4) {
        let v: i64 = match rng.random_range(0..6) {
            0 => rng.random_range(-20..20),
            1 => 0x7fffffff,
            2 => -0x7fffffff,
            3 => 0x80,
            4 => rng.random_range(-70000..70000),
            _ => rng.random::<i32>() as i64,
        };
        sig.extend(num_op(v));
    }
    if rng.random_range(0..5) == 0 {
        // non-minimal number encodings
        sig.extend([0x02, 0x01, 0x00]);
    }
    let spk = { let n = rng.random_range(1..8); rand_script(rng, n) };
    Tpl::Raw(sig, spk, "arith")
}

fn mutate(rng: &mut StdRng, sig: &mut Vec<u8>, spk: &mut Vec<u8>) -> &'static str {
    let tgt_sig = rng.random_range(0..3) != 0;
    let v = if tgt_sig { &mut *sig } else { &mut *spk };
    match rng.random_range(0..10) {
        0 if !v.is_empty() => {
            let i = rng.random_range(0..v.len());
            v[i] ^= 1 << rng.random_range(0..8);
            if tgt_sig { "flip-sig" } else { "flip-spk" }
        }
        1 => {
            let i = rng.random_range(0..=v.len());
            v.insert(i, OPS[rng.random_range(0..OPS.len())]);
            "insert-op"
        }
        2 if !v.is_empty() => {
            let i = rng.random_range(0..v.len());
            v.remove(i);
            "delete-byte"
        }
        3 if !v.is_empty() => {
            let n = rng.random_range(0..v.len());
            v.truncate(n);
            "truncate"
        }
        4 => {
            v.extend({ let n = rng.random_range(1..4); rand_script(rng, n) });
            "append"
        }
        5 if v.len() > 2 => {
            // change the last byte of the first push (often the hash type)
            let l = v[0] as usize;
            if l >= 1 && l < v.len() && l <= 75 {
                v[l] = rng.random();
                "hashtype"
            } else {
                v[1] = rng.random();
                "byte1"
            }
        }
        6 => {
            let pre = { let n = rng.random_range(1..3); rand_script(rng, n) };
            v.splice(0..0, pre);
            "prepend"
        }
        _ => "none",
    }
}

// ------------------------------------------------------------------ transactions

struct In {
    sig: Vec<u8>,
    seq: u32,
    prevout: [u8; 36],
}

fn tx_bytes(v5: bool, branch: u32, ins: &[In], outs: &[(i64, Vec<u8>)], lock: u32, expiry: u32) -> Vec<u8> {
    let mut b = vec![];
    if v5 {
        b.extend(0x80000005u32.to_le_bytes());
        b.extend(0x26A7270Au32.to_le_bytes());
        b.extend(branch.to_le_bytes());
        b.extend(lock.to_le_bytes());
        b.extend(expiry.to_le_bytes());
    } else {
        b.extend(0x80000004u32.to_le_bytes());
        b.extend(0x892F2085u32.to_le_bytes());
    }
    b.extend(cs(ins.len()));
    for i in ins {
        b.extend(i.prevout);
        b.extend(cs(i.sig.len()));
        b.extend(&i.sig);
        b.extend(i.seq.to_le_bytes());
    }
    b.extend(cs(outs.len()));
    for (v, s) in outs {
        b.extend(v.to_le_bytes());
        b.extend(cs(s.len()));
        b.extend(s);
    }
    if v5 {
        b.extend([0, 0, 0]); // no Sapling spends/outputs, no Orchard actions
    } else {
        b.extend(lock.to_le_bytes());
        b.extend(expiry.to_le_bytes());
        b.extend(0i64.to_le_bytes()); // valueBalance
        b.extend([0, 0, 0]); // no spends, outputs, joinsplits
    }
    b
}

fn flags(rng: &mut StdRng) -> u32 {
    if rng.random_range(0..10) < 6 {
        return 1 | 512;
    }
    let mut f = 0u32;
    for bit in [1u32, 2, 8, 16, 32, 64, 128, 256, 512] {
        if rng.random_range(0..2) == 1 {
            f |= bit;
        }
    }
    if f & 256 != 0 {
        f |= 1; // CleanStack requires P2SH (zcash_script asserts it)
    }
    f
}

fn record(out: &mut Vec<u8>, height: u32, flags: u32, tx: &[u8], prev: &[(i64, Vec<u8>)]) {
    out.extend(height.to_le_bytes());
    out.extend(flags.to_le_bytes());
    out.extend((tx.len() as u32).to_le_bytes());
    out.extend(tx);
    out.extend((prev.len() as u32).to_le_bytes());
    for (a, s) in prev {
        out.extend(a.to_le_bytes());
        out.extend((s.len() as u32).to_le_bytes());
        out.extend(s);
    }
}

fn vectors() -> Vec<(Vec<u8>, Vec<u8>, u32)> {
    let cell = std::cell::RefCell::new(vec![]);
    for tv in zcash_script::test_vectors::test_vectors() {
        let _ = tv.run(
            &|raw, f| {
                cell.borrow_mut().push((raw.sig.0.clone(), raw.pub_key.0.clone(), f.bits()));
                Ok(true)
            },
            &|_| 0,
        );
    }
    cell.into_inner()
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let only_vectors = args[1] == "vectors";
    let out = if only_vectors { &args[2] } else { &args[1] };
    let n: usize = if only_vectors { 0 } else { args[2].parse().unwrap() };
    let seed: u64 = if only_vectors { 1 } else { args[3].parse().unwrap() };
    // optional 4th argument: "hard" = every input mutated 1..4 times
    let hard = args.get(4).map_or(false, |a| a == "hard");
    let mut rng = StdRng::seed_from_u64(seed);
    let vecs = vectors();
    let mut file = b"ZTV1".to_vec();
    file.extend(0u32.to_le_bytes());
    let mut expect = String::new();
    let mut kinds = String::new();
    let mut count = 0u32;
    let (mut nin, mut nvalid) = (0usize, 0usize);
    let total = if only_vectors { vecs.len() } else { n };
    for rec in 0..total {
        let v5 = !only_vectors && rng.random_range(0..2) == 1;
        let (height, branch) = if v5 { (2_800_000u32, BranchId::Nu6) } else { (1_100_000u32, BranchId::Canopy) };
        let lock: u32 = match rng.random_range(0..4) {
            0 => 0,
            1 => rng.random_range(0..2_000_000),
            2 => rng.random_range(500_000_000..2_000_000_000),
            _ => rng.random(),
        };
        let k = if only_vectors { 1 } else { rng.random_range(1..4) };
        let mut tpls = vec![];
        let mut fl = if only_vectors { vecs[rec].2 } else { flags(&mut rng) };
        if fl & 256 != 0 {
            fl |= 1;
        }
        for _ in 0..k {
            let t = if only_vectors {
                let (s, p, _) = &vecs[rec];
                Tpl::Raw(s.clone(), p.clone(), "vector")
            } else {
                match rng.random_range(0..20) {
                    0..=3 => Tpl::P2pkh(key(&mut rng)),
                    4 => Tpl::P2pk(key(&mut rng), false),
                    5 => Tpl::P2pk(key(&mut rng), true),
                    6..=7 => {
                        let nk = rng.random_range(1..5);
                        let m = rng.random_range(0..=nk);
                        Tpl::Multi((0..nk).map(|_| key(&mut rng)).collect(), m, false)
                    }
                    8..=9 => {
                        let nk = rng.random_range(1..4);
                        let m = rng.random_range(1..=nk);
                        Tpl::Multi((0..nk).map(|_| key(&mut rng)).collect(), m, true)
                    }
                    10 => {
                        let lt = match rng.random_range(0..5) {
                            0 => lock as i64,
                            1 => (lock as i64) - rng.random_range(0..100),
                            2 => (lock as i64) + rng.random_range(1..100),
                            3 => rng.random_range(-5..600_000_000),
                            _ => rng.random_range(0..(1i64 << 36)),
                        };
                        Tpl::Cltv(key(&mut rng), lt)
                    }
                    11 => Tpl::IfElse(key(&mut rng), key(&mut rng), rng.random()),
                    12 => hashlock(&mut rng),
                    13 => arith(&mut rng),
                    14..=16 => {
                        let (s, p, _) = &vecs[rng.random_range(0..vecs.len())];
                        Tpl::Raw(s.clone(), p.clone(), "vector")
                    }
                    _ => {
                        let s = { let n = rng.random_range(0..6); rand_script(&mut rng, n) };
                        let p = { let n = rng.random_range(0..10); rand_script(&mut rng, n) };
                        Tpl::Raw(s, p, "random")
                    }
                }
            };
            tpls.push(t);
        }
        let mut prev = vec![];
        let mut codes = vec![];
        let mut kind = vec![];
        for t in &tpls {
            let (spk, code, kd) = spk_of(t);
            prev.push((rng.random_range(0..2_100_000_000_000_000i64), spk));
            codes.push(code);
            kind.push(kd);
        }
        let nout = rng.random_range(0..4);
        let outs: Vec<(i64, Vec<u8>)> = (0..nout).map(|_| (rng.random_range(0..1_000_000_000i64), rand_script(&mut rng, 3))).collect();
        let mut ins: Vec<In> = (0..k)
            .map(|_| {
                let mut p = [0u8; 36];
                rng.fill_bytes(&mut p);
                In {
                    sig: vec![],
                    seq: if rng.random_range(0..3) == 0 { u32::MAX } else { rng.random() },
                    prevout: p,
                }
            })
            .collect();
        let br = u32::from(branch);
        let unsigned = tx_bytes(v5, br, &ins, &outs, lock, 0);
        let ctx = Ctx::new(&unsigned, branch, prev.clone());
        for i in 0..k {
            ins[i].sig = sig_of(&mut rng, &tpls[i], &ctx, i, &codes[i]);
        }
        // mutations (scriptSig changes do not change v4/v5 sighashes; scriptPubKey ones do)
        let mut muts = vec![];
        for i in 0..k {
            let m = if only_vectors || (!hard && rng.random_range(0..10) < 4) {
                "none"
            } else {
                let mut spk = prev[i].1.clone();
                let mut m = mutate(&mut rng, &mut ins[i].sig, &mut spk);
                if hard {
                    for _ in 0..rng.random_range(0..4) {
                        m = mutate(&mut rng, &mut ins[i].sig, &mut spk);
                    }
                }
                prev[i].1 = spk;
                m
            };
            muts.push(m);
        }
        let tx = tx_bytes(v5, br, &ins, &outs, lock, 0);
        let ctx = Ctx::new(&tx, branch, prev.clone());
        let mut vs = String::new();
        for i in 0..k {
            let ok = verdict(&ctx, i, &ins[i].sig, &prev[i].1, fl, lock, ins[i].seq);
            vs.push(if ok { '1' } else { '0' });
            nin += 1;
            nvalid += ok as usize;
        }
        record(&mut file, height, fl, &tx, &prev);
        expect.push_str(&format!("r {count} {vs}\n"));
        kinds.push_str(&format!(
            "r {count} v{} flags {fl} {}\n",
            if v5 { 5 } else { 4 },
            kind.iter().zip(&muts).map(|(a, b)| format!("{a}/{b}")).collect::<Vec<_>>().join(" ")
        ));
        count += 1;
    }
    file[4..8].copy_from_slice(&count.to_le_bytes());
    std::fs::write(format!("{out}.ztv"), &file).unwrap();
    std::fs::write(format!("{out}.expect"), expect).unwrap();
    std::fs::write(format!("{out}.kinds"), kinds).unwrap();
    std::io::stderr().write_all(format!("{count} records, {nin} inputs, {nvalid} valid\n").as_bytes()).unwrap();
}
