//! Ground truth for the Bend Groth16 / BLS12-381 verifier (zcash/sapling/groth16).
//!
//!   vk                         ../data/vk_{spend,output}.bin   VKs read from the official params,
//!                                                              in Bend's word format (+ .txt dumps)
//!   extract MAXS MAXO [SEED]   ../data/real.bin, tamper.bin,   real mainnet Sapling proofs from
//!                              official_{real,tamper}.txt      research/proofsets/data/raw.bin (read only),
//!                                                              public inputs exactly as sapling-crypto,
//!                                                              verdict = groth16::verify_proof
//!   extract ... [RAW PREFIX] other raw.bin-format input, output sets named PREFIX*
//!   fetch H1,H2,.. BLOCKS PER_WINDOW CONC [OUT]   Sapling txs of other eras from lightwalletd
//!   dump FILE IDX              intermediates of one record (decoded points, acc, Miller loop
//!                              output, final exponentiation) for bisecting
//!   bench FILE THREADS [REPS]  Rust timing: single verify per record (rayon), and batch verify
//!   vectors N SEED             group-level vectors (points, scalar mults, pairings)
//!
//! Record format (little endian): u32 kind (0 spend, 1 output) | u32 tag (0 real, >0 tamper
//! kind) | 192-byte Groth16 proof (as on chain: A 48 | B 96 | C 48 compressed) | n x 32-byte
//! canonical Fr public inputs (n = 7 spend, 5 output).

use std::{
    fs::File,
    io::{BufReader, BufWriter, Read, Write},
    path::Path,
    time::Instant,
};

use anyhow::{anyhow, Result};
use bls12_381::{Bls12, G1Affine, G1Projective, G2Affine, G2Prepared, G2Projective, Scalar};
use ff::{Field, PrimeField};
use group::{Curve, GroupEncoding};
use groth16::{PreparedVerifyingKey, Proof, VerifyingKey};
use rayon::prelude::*;
use zcash_primitives::transaction::Transaction;
use zcash_protocol::consensus::{BlockHeight, BranchId, MainNetwork};

mod fetch;

const DATA: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../data");
const RAW: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../proofsets/data/raw.bin");

// ---------------------------------------------------------------- helpers

struct Xs(u64);
impl Xs {
    fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.0 = x;
        x
    }
    fn below(&mut self, n: u64) -> u64 {
        self.next() % n
    }
    fn scalar(&mut self) -> Scalar {
        let mut w = [0u8; 64];
        for c in w.chunks_mut(8) {
            c.copy_from_slice(&self.next().to_le_bytes());
        }
        Scalar::from_bytes_wide(&w)
    }
}

fn read_vk(name: &str) -> Result<VerifyingKey<Bls12>> {
    let file = if name == "sprout" { "sprout-groth16.params".to_string() } else { format!("sapling-{name}.params") };
    let f = File::open(Path::new(DATA).join(file))?;
    Ok(VerifyingKey::<Bls12>::read(BufReader::new(f))?)
}

/// 48-byte big-endian canonical field element -> 48 little-endian bytes (12 LE u32 words).
fn fp_words(be: &[u8]) -> Vec<u8> {
    let mut le: Vec<u8> = be.to_vec();
    le.reverse();
    le
}

fn g1_bend(p: &G1Affine) -> Vec<u8> {
    let u = p.to_uncompressed();
    let mut o = fp_words(&u[0..48]);
    o[47] &= 0x1f;
    o.extend(fp_words(&u[48..96]));
    o
}

fn g2_bend(p: &G2Affine) -> Vec<u8> {
    // uncompressed: x.c1 | x.c0 | y.c1 | y.c0 (big endian) -> x.c0 x.c1 y.c0 y.c1 (LE)
    let u = p.to_uncompressed();
    let mut xc1 = fp_words(&u[0..48]);
    xc1[47] &= 0x1f;
    let mut o = fp_words(&u[48..96]);
    o.extend(xc1);
    o.extend(fp_words(&u[144..192]));
    o.extend(fp_words(&u[96..144]));
    o
}

fn hex_g1(p: &G1Affine) -> String {
    let u = p.to_uncompressed();
    format!("{} {}", hex::encode(&u[0..48]), hex::encode(&u[48..96]))
}

fn hex_g2(p: &G2Affine) -> String {
    let u = p.to_uncompressed();
    // x.c0 x.c1 y.c0 y.c1
    format!("{} {} {} {}", hex::encode(&u[48..96]), hex::encode(&u[0..48]), hex::encode(&u[144..192]), hex::encode(&u[96..144]))
}

/// The 12 Fp coefficients of an Fp12 Debug string, in order c0.c0.c0, c0.c0.c1, c0.c1.c0, ...
fn fp12_hex(dbg: &str) -> String {
    let mut out = vec![];
    let b = dbg.as_bytes();
    let mut i = 0;
    while i + 2 < b.len() {
        if b[i] == b'0' && b[i + 1] == b'x' {
            out.push(dbg[i + 2..i + 2 + 96].to_string());
            i += 98;
        } else {
            i += 1;
        }
    }
    assert_eq!(out.len(), 12, "fp12 debug parse: {dbg}");
    out.join(" ")
}

// ---------------------------------------------------------------- vk

fn vk_cmd() -> Result<()> {
    for name in ["spend", "output", "sprout"] {
        let vk = read_vk(name)?;
        let mut b = vec![];
        b.extend(g1_bend(&vk.alpha_g1));
        b.extend(g2_bend(&vk.beta_g2));
        b.extend(g2_bend(&vk.gamma_g2));
        b.extend(g2_bend(&vk.delta_g2));
        b.extend((vk.ic.len() as u32).to_le_bytes());
        for p in &vk.ic {
            b.extend(g1_bend(p));
        }
        File::create(Path::new(DATA).join(format!("vk_{name}.bin")))?.write_all(&b)?;
        let mut t = BufWriter::new(File::create(Path::new(DATA).join(format!("vk_{name}.txt")))?);
        writeln!(t, "alpha_g1 {}", hex_g1(&vk.alpha_g1))?;
        writeln!(t, "beta_g2 {}", hex_g2(&vk.beta_g2))?;
        writeln!(t, "gamma_g2 {}", hex_g2(&vk.gamma_g2))?;
        writeln!(t, "delta_g2 {}", hex_g2(&vk.delta_g2))?;
        for (i, p) in vk.ic.iter().enumerate() {
            writeln!(t, "ic{i} {}", hex_g1(p))?;
        }
        let ab = bls12_381::pairing(&vk.alpha_g1, &vk.beta_g2);
        writeln!(t, "alpha_beta {}", fp12_hex(&format!("{:?}", ab)))?;
        eprintln!("{name}: ic {} points", vk.ic.len());
    }
    Ok(())
}

// ---------------------------------------------------------------- records

#[derive(Clone)]
struct Rec {
    kind: u32,
    tag: u32,
    proof: [u8; 192],
    inputs: Vec<Scalar>,
    height: u64,
    txid: [u8; 32],
    idx: usize,
    /// The description's raw public fields: spend cv | anchor | nf | rk, output cv | cmu | epk.
    raw: Vec<u8>,
}

impl Rec {
    fn raw_bytes(&self) -> Vec<u8> {
        let mut b = vec![];
        b.extend(self.kind.to_le_bytes());
        b.extend(self.tag.to_le_bytes());
        b.extend(self.proof);
        b.extend(&self.raw);
        b
    }

    fn bytes(&self) -> Vec<u8> {
        let mut b = vec![];
        b.extend(self.kind.to_le_bytes());
        b.extend(self.tag.to_le_bytes());
        b.extend(self.proof);
        for x in &self.inputs {
            b.extend(x.to_repr());
        }
        b
    }
}

/// The official verdict on one record: groth16::Proof::read (point decoding with subgroup
/// checks, identity rejected) then groth16::verify_proof, as sapling-crypto does.
fn verdict(pvk: &PreparedVerifyingKey<Bls12>, r: &Rec) -> bool {
    reason(pvk, r) == 1
}

/// 1 valid, 0 rejected by Proof::read (point decoding), 2 rejected by verify_proof.
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

fn read_raw(mut f: impl Read, mut each: impl FnMut(u64, [u8; 32], Vec<u8>) -> Result<bool>) -> Result<()> {
    let mut hdr = [0u8; 40];
    loop {
        match f.read_exact(&mut hdr) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(()),
            Err(e) => return Err(e.into()),
        }
        let h = u32::from_le_bytes(hdr[0..4].try_into().unwrap()) as u64;
        let id: [u8; 32] = hdr[4..36].try_into().unwrap();
        let n = u32::from_le_bytes(hdr[36..40].try_into().unwrap()) as usize;
        let mut b = vec![0u8; n];
        if f.read_exact(&mut b).is_err() {
            return Ok(());
        }
        if !each(h, id, b)? {
            return Ok(());
        }
    }
}

/// Public inputs of a spend, exactly as sapling-crypto's check_spend builds them.
/// None if rk is small order (check_spend rejects before the proof).
fn spend_inputs(s: &sapling::bundle::SpendDescription<sapling::bundle::Authorized>) -> Option<Vec<Scalar>> {
    let rk_affine = jubjub::AffinePoint::from_bytes((*s.rk()).into()).unwrap();
    if bool::from(rk_affine.is_small_order()) {
        return None;
    }
    let cv = s.cv().as_inner().to_affine();
    let nf = bellman::gadgets::multipack::bytes_to_bits_le(&s.nullifier().0);
    let nf = bellman::gadgets::multipack::compute_multipacking::<Scalar>(&nf);
    assert_eq!(nf.len(), 2);
    Some(vec![rk_affine.get_u(), rk_affine.get_v(), cv.get_u(), cv.get_v(), *s.anchor(), nf[0], nf[1]])
}

/// h_sig = BLAKE2b-256("ZcashComputehSig", randomSeed || nf1 || nf2 || joinSplitPubKey)
/// (protocol spec 4.3), as zcashd computes it before calling zcash_proofs::sprout::verify_proof.
fn h_sig(seed: &[u8; 32], nf: &[[u8; 32]; 2], pk: &[u8; 32]) -> [u8; 32] {
    let h = blake2b_simd::Params::new().hash_length(32).personal(b"ZcashComputehSig").to_state().update(seed).update(&nf[0]).update(&nf[1]).update(pk).finalize();
    h.as_bytes().try_into().unwrap()
}

/// A post-Sapling Sprout JoinSplit's Groth16 public inputs, as zcash_proofs::sprout::verify_proof
/// computes them (multipacking of the big-endian bits of rt | h_sig | nf1 | mac1 | nf2 | mac2 |
/// cm1 | cm2 | vpub_old | vpub_new), and that function's own verdict.
fn sprout_inputs(js: &zcash_primitives::transaction::components::sprout::JsDescription, pk: &[u8; 32], pvk: &PreparedVerifyingKey<Bls12>) -> Option<(Vec<Scalar>, bool)> {
    let proof = js.groth_proof_bytes()?;
    let hs = h_sig(js.random_seed(), js.nullifiers(), pk);
    let (nf, mac, cm) = (js.nullifiers(), js.macs(), js.commitments());
    let vo = u64::try_from(i64::from(js.vpub_old())).ok()?;
    let vn = u64::try_from(i64::from(js.vpub_new())).ok()?;
    let mut b = vec![];
    for x in [js.anchor(), &hs, &nf[0], &mac[0], &nf[1], &mac[1], &cm[0], &cm[1]] {
        b.extend(x);
    }
    b.extend(vo.to_le_bytes());
    b.extend(vn.to_le_bytes());
    let inputs = bellman::gadgets::multipack::compute_multipacking::<Scalar>(&bellman::gadgets::multipack::bytes_to_bits(&b));
    let ok = zcash_proofs::sprout::verify_proof(proof, js.anchor(), &hs, &mac[0], &mac[1], &nf[0], &nf[1], &cm[0], &cm[1], vo, vn, pvk);
    Some((inputs, ok))
}

/// Public inputs of an output, exactly as sapling-crypto's check_output builds them.
fn output_inputs(o: &sapling::bundle::OutputDescription<sapling::bundle::GrothProofBytes>) -> Option<Vec<Scalar>> {
    let epk: jubjub::ExtendedPoint = Option::from(jubjub::ExtendedPoint::from_bytes(&o.ephemeral_key().0))?;
    if bool::from(epk.is_small_order()) {
        return None;
    }
    let cv = o.cv().as_inner().to_affine();
    let e = epk.to_affine();
    Some(vec![cv.get_u(), cv.get_v(), e.get_u(), e.get_v(), Scalar::from_repr(o.cmu().to_bytes()).unwrap()])
}

fn write_set(name: &str, recs: &[Rec], verdicts: &[u8]) -> Result<()> {
    let mut f = BufWriter::new(File::create(Path::new(DATA).join(format!("{name}.bin")))?);
    for r in recs {
        f.write_all(&r.bytes())?;
    }
    let mut t = BufWriter::new(File::create(Path::new(DATA).join(format!("official_{name}.txt")))?);
    writeln!(t, "# index kind tag verdict height txid desc_index reason(1 ok, 0 Proof::read failed, 2 verify_proof failed)")?;
    for (i, (r, v)) in recs.iter().zip(verdicts).enumerate() {
        writeln!(t, "{i} {} {} {} {} {} {} {}", r.kind, r.tag, (*v == 1) as u8, r.height, hex::encode(r.txid), r.idx, v)?;
    }
    Ok(())
}

/// A compressed G1 encoding of an on-curve point that is NOT in the prime-order subgroup.
fn g1_non_subgroup(rng: &mut Xs) -> [u8; 48] {
    loop {
        let mut b = [0u8; 48];
        for c in b.chunks_mut(8) {
            c.copy_from_slice(&rng.next().to_le_bytes());
        }
        b[0] = (b[0] & 0x0f) | 0x80; // compressed, x < 2^380 < p
        if G1Affine::from_compressed_unchecked(&b).is_some().into() && G1Affine::from_compressed(&b).is_none().into() {
            return b;
        }
    }
}

fn g2_non_subgroup(rng: &mut Xs) -> [u8; 96] {
    loop {
        let mut b = [0u8; 96];
        for c in b.chunks_mut(8) {
            c.copy_from_slice(&rng.next().to_le_bytes());
        }
        b[0] = (b[0] & 0x0f) | 0x80;
        b[48] &= 0x0f;
        if G2Affine::from_compressed_unchecked(&b).is_some().into() && G2Affine::from_compressed(&b).is_none().into() {
            return b;
        }
    }
}

const TAGS: u32 = 10;

/// Tamper kinds (tag):
///  1 flip one random bit of the proof      2 flip A's sign bit (valid point -A)
///  3 add 1 to one public input            4 swap A and C
///  5 A := on-curve point outside G1's subgroup   6 B := on-curve point outside G2's subgroup
///  7 flip B's sign bit                     8 A's x >= p (non-canonical)
///  9 A := the point at infinity            10 proof of another record (same kind)
fn tamper(r: &Rec, tag: u32, rng: &mut Xs, other: &Rec) -> Rec {
    let mut t = r.clone();
    t.tag = tag;
    match tag {
        1 => {
            let bit = rng.below(192 * 8) as usize;
            t.proof[bit / 8] ^= 1 << (bit % 8);
        }
        2 => t.proof[0] ^= 0x20,
        3 => {
            let k = rng.below(t.inputs.len() as u64) as usize;
            t.inputs[k] += Scalar::ONE;
        }
        4 => {
            let a: [u8; 48] = t.proof[0..48].try_into().unwrap();
            let c: [u8; 48] = t.proof[144..192].try_into().unwrap();
            t.proof[0..48].copy_from_slice(&c);
            t.proof[144..192].copy_from_slice(&a);
        }
        5 => t.proof[0..48].copy_from_slice(&g1_non_subgroup(rng)),
        6 => t.proof[48..144].copy_from_slice(&g2_non_subgroup(rng)),
        7 => t.proof[48] ^= 0x20,
        8 => {
            t.proof[0] |= 0x1f;
            for b in &mut t.proof[1..48] {
                *b = 0xff;
            }
        }
        9 => {
            t.proof[0] = 0xc0;
            for b in &mut t.proof[1..48] {
                *b = 0;
            }
        }
        _ => t.proof = other.proof,
    }
    t
}

fn extract(max_s: usize, max_o: usize, seed: u64, raw_path: &str, prefix: &str) -> Result<()> {
    let (vks, vko, vkj) = (read_vk("spend")?, read_vk("output")?, read_vk("sprout")?);
    let (pvs, pvo, pvj) = (groth16::prepare_verifying_key(&vks), groth16::prepare_verifying_key(&vko), groth16::prepare_verifying_key(&vkj));
    // MAX_O_PER_TX: keep at most this many outputs per transaction (the 2022 spam era has
    // transactions with hundreds of outputs, which would otherwise swamp the sample)
    let max_o_per_tx: usize = std::env::var("MAX_O_PER_TX").ok().and_then(|x| x.parse().ok()).unwrap_or(usize::MAX);
    let mut recs: Vec<Rec> = vec![];
    let (mut ns, mut no, mut txs, mut sap_txs, mut skipped, mut nj, mut nj_bad) = (0usize, 0usize, 0u64, 0u64, 0u64, 0usize, 0usize);
    let t = Instant::now();
    read_raw(BufReader::with_capacity(1 << 22, File::open(raw_path)?), |h, id, raw| {
        txs += 1;
        let branch = BranchId::for_height(&MainNetwork, BlockHeight::from_u32(h as u32));
        let tx = match Transaction::read(&raw[..], branch) {
            Ok(tx) => tx,
            Err(_) => {
                skipped += 1;
                return Ok(true);
            }
        };
        if let Some(sb) = tx.sprout_bundle() {
            for (i, js) in sb.joinsplits.iter().enumerate() {
                if let Some((inp, ok)) = sprout_inputs(js, &sb.joinsplit_pubkey, &pvj) {
                    nj_bad += !ok as usize;
                    // raw: rt | randomSeed | nf1 | nf2 | mac1 | mac2 | cm1 | cm2 | joinSplitPubKey | vpub_old | vpub_new
                    let (nf, mac, cm) = (js.nullifiers(), js.macs(), js.commitments());
                    let mut raw = vec![];
                    for x in [js.anchor(), js.random_seed(), &nf[0], &nf[1], &mac[0], &mac[1], &cm[0], &cm[1], &sb.joinsplit_pubkey] {
                        raw.extend(x);
                    }
                    raw.extend(u64::try_from(i64::from(js.vpub_old())).unwrap().to_le_bytes());
                    raw.extend(u64::try_from(i64::from(js.vpub_new())).unwrap().to_le_bytes());
                    recs.push(Rec { kind: 2, tag: 0, proof: *js.groth_proof_bytes().unwrap(), inputs: inp, height: h, txid: id, idx: i, raw });
                    nj += 1;
                }
            }
        }
        if let Some(b) = tx.sapling_bundle() {
            sap_txs += 1;
            for (i, s) in b.shielded_spends().iter().enumerate() {
                if ns >= max_s {
                    break;
                }
                if let Some(inp) = spend_inputs(s) {
                    let mut raw = s.cv().to_bytes().to_vec();
                    raw.extend(s.anchor().to_repr());
                    raw.extend(s.nullifier().0);
                    raw.extend(<[u8; 32]>::from(*s.rk()));
                    recs.push(Rec { kind: 0, tag: 0, proof: *s.zkproof(), inputs: inp, height: h, txid: id, idx: i, raw });
                    ns += 1;
                }
            }
            for (i, o) in b.shielded_outputs().iter().enumerate() {
                if no >= max_o || i >= max_o_per_tx {
                    break;
                }
                if let Some(inp) = output_inputs(o) {
                    let mut raw = o.cv().to_bytes().to_vec();
                    raw.extend(o.cmu().to_bytes());
                    raw.extend(o.ephemeral_key().0);
                    recs.push(Rec { kind: 1, tag: 0, proof: *o.zkproof(), inputs: inp, height: h, txid: id, idx: i, raw });
                    no += 1;
                }
            }
        }
        Ok(ns < max_s || no < max_o)
    })?;
    eprintln!("scanned {txs} txs ({skipped} unparsed), {sap_txs} with Sapling; {ns} spends, {no} outputs; {nj} Groth16 JoinSplits ({nj_bad} rejected by zcash_proofs::sprout::verify_proof) ({:.0}s)", t.elapsed().as_secs_f64());
    let pvk = |k: u32| [&pvs, &pvo, &pvj][k as usize];
    let v: Vec<u8> = recs.par_iter().map(|r| reason(pvk(r.kind), r)).collect();
    eprintln!("official: {}/{} valid", v.iter().filter(|x| **x == 1).count(), v.len());
    write_set(&format!("{prefix}real"), &recs, &v)?;
    // tampered copies: every real record gets one tamper, cycling through the kinds
    let mut rng = Xs(seed | 1);
    let mut tam = vec![];
    for (i, r) in recs.iter().enumerate() {
        let tag = 1 + (i as u32 % TAGS);
        let other = recs[i + 1..].iter().chain(recs[..i].iter()).find(|o| o.kind == r.kind && o.proof != r.proof).unwrap_or(r);
        tam.push(tamper(r, tag, &mut rng, other));
    }
    let tv: Vec<u8> = tam.par_iter().map(|r| reason(pvk(r.kind), r)).collect();
    eprintln!("tampered: {}/{} valid", tv.iter().filter(|x| **x == 1).count(), tv.len());
    write_set(&format!("{prefix}tamper"), &tam, &tv)?;
    // raw-field sets: the same proofs with their description fields; Bend computes the inputs
    let rv: Vec<u8> = recs
        .par_iter()
        .map(|r| {
            let (code, inp) = raw_reason(pvk(r.kind), r.kind, &r.proof, &r.raw);
            assert_eq!(inp.as_ref(), Some(&r.inputs), "raw inputs differ from extracted inputs");
            code
        })
        .collect();
    eprintln!("real_raw: {}/{} valid", rv.iter().filter(|x| **x == 1).count(), rv.len());
    write_raw_set(&format!("{prefix}real_raw"), &recs, &rv)?;
    let mut rng = Xs((seed ^ 0x5eed) | 1);
    let mut tr = vec![];
    for (i, r) in recs.iter().enumerate() {
        let tag = 1 + (i as u32 % 15);
        let other = recs[i + 1..].iter().chain(recs[..i].iter()).find(|o| o.kind == r.kind && o.proof != r.proof).unwrap_or(r);
        tr.push(tamper_raw(r, tag, &mut rng, other));
    }
    let trv: Vec<u8> = tr.par_iter().map(|r| raw_reason(pvk(r.kind), r.kind, &r.proof, &r.raw).0).collect();
    eprintln!("tamper_raw: {}/{} valid", trv.iter().filter(|x| **x == 1).count(), trv.len());
    write_raw_set(&format!("{prefix}tamper_raw"), &tr, &trv)?;
    Ok(())
}

/// The official verdict from the raw description fields, as a node does it: parse the fields
/// as zcash_primitives does (cv: ValueCommitment::from_bytes_not_small_order, anchor:
/// read_base = Scalar::from_repr, rk: redjubjub VerificationKey::try_from, cmu:
/// ExtractedNoteCommitment::from_bytes), then sapling-crypto's check_spend / check_output
/// (rk / epk decoding and small-order rejection, public input construction), then the proof.
/// Returns (reason, inputs): 3 = rejected before the proof; else as `reason`.
fn raw_reason(pvk: &PreparedVerifyingKey<Bls12>, kind: u32, proof: &[u8; 192], raw: &[u8]) -> (u8, Option<Vec<Scalar>>) {
    let b32 = |i: usize| -> [u8; 32] { raw[32 * i..32 * i + 32].try_into().unwrap() };
    if kind == 2 {
        // Sprout: h_sig, then zcash_proofs::sprout::verify_proof's input packing
        let hs = h_sig(&b32(1), &[b32(2), b32(3)], &b32(8));
        let vo = u64::from_le_bytes(raw[288..296].try_into().unwrap());
        let vn = u64::from_le_bytes(raw[296..304].try_into().unwrap());
        let mut b = vec![];
        for x in [b32(0), hs, b32(2), b32(4), b32(3), b32(5), b32(6), b32(7)] {
            b.extend(x);
        }
        b.extend(vo.to_le_bytes());
        b.extend(vn.to_le_bytes());
        let inputs = bellman::gadgets::multipack::compute_multipacking::<Scalar>(&bellman::gadgets::multipack::bytes_to_bits(&b));
        let ok = zcash_proofs::sprout::verify_proof(proof, &b32(0), &hs, &b32(4), &b32(5), &b32(2), &b32(3), &b32(6), &b32(7), vo, vn, pvk);
        let r = Rec { kind, tag: 0, proof: *proof, inputs: inputs.clone(), height: 0, txid: [0; 32], idx: 0, raw: vec![] };
        let code = reason(pvk, &r);
        assert_eq!(ok, code == 1, "zcash_proofs::sprout::verify_proof disagrees with groth16 on the packed inputs");
        return (code, Some(inputs));
    }
    let cv = match Option::from(sapling::value::ValueCommitment::from_bytes_not_small_order(&b32(0))) {
        Some(cv) => cv,
        None => return (3, None),
    };
    let cv: sapling::value::ValueCommitment = cv;
    let cva = cv.as_inner().to_affine();
    let inputs = if kind == 0 {
        let anchor: Scalar = match Option::from(Scalar::from_repr(b32(1))) {
            Some(a) => a,
            None => return (3, None),
        };
        let rk = match redjubjub::VerificationKey::<redjubjub::SpendAuth>::try_from(b32(3)) {
            Ok(rk) => rk,
            Err(_) => return (3, None),
        };
        let rk_affine = jubjub::AffinePoint::from_bytes(rk.into()).unwrap();
        if bool::from(rk_affine.is_small_order()) {
            return (3, None);
        }
        let nf = bellman::gadgets::multipack::bytes_to_bits_le(&b32(2));
        let nf = bellman::gadgets::multipack::compute_multipacking::<Scalar>(&nf);
        vec![rk_affine.get_u(), rk_affine.get_v(), cva.get_u(), cva.get_v(), anchor, nf[0], nf[1]]
    } else {
        let cmu = match Option::<sapling::note::ExtractedNoteCommitment>::from(sapling::note::ExtractedNoteCommitment::from_bytes(&b32(1))) {
            Some(c) => c,
            None => return (3, None),
        };
        let epk: jubjub::ExtendedPoint = match Option::from(jubjub::ExtendedPoint::from_bytes(&b32(2))) {
            Some(e) => e,
            None => return (3, None),
        };
        if bool::from(epk.is_small_order()) {
            return (3, None);
        }
        let e = epk.to_affine();
        vec![cva.get_u(), cva.get_v(), e.get_u(), e.get_v(), Scalar::from_repr(cmu.to_bytes()).unwrap()]
    };
    let r = Rec { kind, tag: 0, proof: *proof, inputs: inputs.clone(), height: 0, txid: [0; 32], idx: 0, raw: vec![] };
    (reason(pvk, &r), Some(inputs))
}

/// Raw-field tampers (tags 11..15), on top of the proof tampers 1..10 (tag 3 becomes
/// anchor / cmu + 1 in the raw encoding):
///  11 flip a random bit of cv     12 flip a random bit of rk (spend) / epk (output)
///  13 rk / epk := the identity (small order)   14 anchor / cmu := a non-canonical value (>= r)
///  15 flip a random bit of nf (spend) / cmu (output)
fn tamper_raw(r: &Rec, tag: u32, rng: &mut Xs, other: &Rec) -> Rec {
    let mut t = if tag <= 10 && tag != 3 { tamper(r, tag, rng, other) } else { r.clone() };
    t.tag = tag;
    if r.kind == 2 {
        // Sprout: 3 flips a bit of cm1, 11 rt, 12 randomSeed (h_sig), 13 joinSplitPubKey
        // (h_sig), 14 mac1, 15 vpub_old + 1
        let slot = match tag {
            3 => Some(6),
            11 => Some(0),
            12 => Some(1),
            13 => Some(8),
            14 => Some(4),
            _ => None,
        };
        if let Some(sl) = slot {
            let bit = rng.below(256) as usize;
            t.raw[32 * sl + bit / 8] ^= 1 << (bit % 8);
        }
        if tag == 15 {
            let v = u64::from_le_bytes(t.raw[288..296].try_into().unwrap()).wrapping_add(1);
            t.raw[288..296].copy_from_slice(&v.to_le_bytes());
        }
        return t;
    }
    let pk = if r.kind == 0 { 3 } else { 2 }; // rk / epk slot
    let mut flip = |slot: usize, rng: &mut Xs| {
        let bit = rng.below(256) as usize;
        t.raw[32 * slot + bit / 8] ^= 1 << (bit % 8);
    };
    match tag {
        3 => {
            let v = Scalar::from_repr(r.raw[32..64].try_into().unwrap()).unwrap() + Scalar::ONE;
            t.raw[32..64].copy_from_slice(&v.to_repr());
        }
        11 => flip(0, rng),
        12 => flip(pk, rng),
        13 => {
            let mut id = [0u8; 32];
            id[0] = 1;
            t.raw[32 * pk..32 * pk + 32].copy_from_slice(&id);
        }
        14 => {
            for b in &mut t.raw[32..63] {
                *b = 0xff;
            }
            t.raw[63] = 0x7f;
        }
        15 => flip(if r.kind == 0 { 2 } else { 1 }, rng),
        _ => {}
    }
    t
}

fn write_raw_set(name: &str, recs: &[Rec], reasons: &[u8]) -> Result<()> {
    let mut f = BufWriter::new(File::create(Path::new(DATA).join(format!("{name}.bin")))?);
    for r in recs {
        f.write_all(&r.raw_bytes())?;
    }
    let mut t = BufWriter::new(File::create(Path::new(DATA).join(format!("official_{name}.txt")))?);
    writeln!(t, "# index kind tag verdict height txid desc_index reason(1 ok, 0 Proof::read failed, 2 verify_proof failed, 3 description fields rejected)")?;
    for (i, (r, v)) in recs.iter().zip(reasons).enumerate() {
        writeln!(t, "{i} {} {} {} {} {} {} {}", r.kind, r.tag, (*v == 1) as u8, r.height, hex::encode(r.txid), r.idx, v)?;
    }
    Ok(())
}

fn read_set(path: &str) -> Result<Vec<Rec>> {
    let mut b = vec![];
    File::open(path)?.read_to_end(&mut b)?;
    let mut out = vec![];
    let mut i = 0;
    while i < b.len() {
        let kind = u32::from_le_bytes(b[i..i + 4].try_into()?);
        let tag = u32::from_le_bytes(b[i + 4..i + 8].try_into()?);
        let proof: [u8; 192] = b[i + 8..i + 200].try_into()?;
        let n = [7, 5, 9][kind as usize];
        let mut inputs = vec![];
        for k in 0..n {
            let o = i + 200 + 32 * k;
            inputs.push(Option::from(Scalar::from_repr(b[o..o + 32].try_into()?)).ok_or_else(|| anyhow!("input"))?);
        }
        i += 200 + 32 * n;
        out.push(Rec { kind, tag, proof, inputs, height: 0, txid: [0; 32], idx: 0, raw: vec![] });
    }
    Ok(out)
}

// ---------------------------------------------------------------- dump

fn dump(path: &str, idx: usize) -> Result<()> {
    let recs = read_set(path)?;
    let r = &recs[idx];
    let vk = read_vk(["spend", "output", "sprout"][r.kind as usize])?;
    let pvk = groth16::prepare_verifying_key(&vk);
    println!("kind {} tag {}", r.kind, r.tag);
    for (i, x) in r.inputs.iter().enumerate() {
        let mut be = x.to_repr();
        be.reverse();
        println!("input{i} {}", hex::encode(be));
    }
    let a = G1Affine::from_compressed(&r.proof[0..48].try_into()?);
    let b = G2Affine::from_compressed(&r.proof[48..144].try_into()?);
    let c = G1Affine::from_compressed(&r.proof[144..192].try_into()?);
    println!("a_ok {} b_ok {} c_ok {}", a.is_some().unwrap_u8(), b.is_some().unwrap_u8(), c.is_some().unwrap_u8());
    let mut acc = G1Projective::from(vk.ic[0]);
    for (x, p) in r.inputs.iter().zip(vk.ic.iter().skip(1)) {
        acc += *p * x;
    }
    let acc = acc.to_affine();
    println!("acc {}", hex_g1(&acc));
    if let (Some(a), Some(b), Some(c)) = (Option::<G1Affine>::from(a), Option::<G2Affine>::from(b), Option::<G1Affine>::from(c)) {
        println!("A {}", hex_g1(&a));
        println!("B {}", hex_g2(&b));
        println!("C {}", hex_g1(&c));
        let ng = G2Prepared::from(-vk.gamma_g2);
        let nd = G2Prepared::from(-vk.delta_g2);
        let bp = G2Prepared::from(b);
        let ml1 = bls12_381::multi_miller_loop(&[(&a, &bp)]);
        println!("ml_ab {}", fp12_hex(&format!("{:?}", ml1)));
        let ml = bls12_381::multi_miller_loop(&[(&a, &bp), (&acc, &ng), (&c, &nd)]);
        println!("ml {}", fp12_hex(&format!("{:?}", ml)));
        let gt = ml.final_exponentiation();
        println!("fe {}", fp12_hex(&format!("{:?}", gt)));
    }
    println!("verdict {}", verdict(&pvk, r) as u8);
    Ok(())
}

// ---------------------------------------------------------------- bench

fn bench(path: &str, threads: usize, reps: usize) -> Result<()> {
    let recs = read_set(path)?;
    let (vks, vko, vkj) = (read_vk("spend")?, read_vk("output")?, read_vk("sprout")?);
    let (pvs, pvo, pvj) = (groth16::prepare_verifying_key(&vks), groth16::prepare_verifying_key(&vko), groth16::prepare_verifying_key(&vkj));
    let pool = rayon::ThreadPoolBuilder::new().num_threads(threads).build()?;
    for _ in 0..reps {
        let t = Instant::now();
        let ok: usize = pool.install(|| recs.par_iter().map(|r| verdict([&pvs, &pvo, &pvj][r.kind as usize], r) as usize).sum());
        let s = t.elapsed().as_secs_f64();
        println!(
            "rust single threads={threads} n={} valid={ok} {:.3}s = {:.0} proofs/s ({:.3} ms/proof)",
            recs.len(),
            s,
            recs.len() as f64 / s,
            1e3 * s / recs.len() as f64
        );
        // batch: one groth16::batch::Verifier per kind (as sapling's BatchValidator)
        let t = Instant::now();
        let ok = pool.install(|| {
            let mut bv: [groth16::batch::Verifier<Bls12>; 3] = Default::default();
            for r in &recs {
                bv[r.kind as usize].queue((Proof::<Bls12>::read(&r.proof[..]).unwrap(), r.inputs.clone()));
            }
            let vk = [&vks, &vko, &vkj];
            bv.into_iter().zip(vk).all(|(b, vk)| b.verify_multicore(vk).is_ok())
        });
        let s = t.elapsed().as_secs_f64();
        println!("rust batch(verify_multicore) threads={threads} n={} ok={ok} {:.3}s = {:.0} proofs/s", recs.len(), s, recs.len() as f64 / s);
        // batch per chunk (as Bend's batch_main): chunks of 128 in parallel, one
        // groth16::batch::Verifier per kind per chunk, single-threaded verify inside
        let t = Instant::now();
        let ok = pool.install(|| {
            recs.par_chunks(128).all(|ch| {
                let mut bv: [groth16::batch::Verifier<Bls12>; 3] = Default::default();
                for r in ch {
                    bv[r.kind as usize].queue((Proof::<Bls12>::read(&r.proof[..]).unwrap(), r.inputs.clone()));
                }
                let mut rng = rand_core::UnwrapErr(rand::rngs::SysRng);
                let vk = [&vks, &vko, &vkj];
                bv.into_iter().zip(vk).all(|(b, vk)| b.verify(&mut rng, vk).is_ok())
            })
        });
        let s = t.elapsed().as_secs_f64();
        println!("rust batch(chunks of 128, verify) threads={threads} n={} ok={ok} {:.3}s = {:.0} proofs/s", recs.len(), s, recs.len() as f64 / s);
    }
    Ok(())
}

// ---------------------------------------------------------------- vectors

/// Group-level vectors: random points (k * generator) with their compressed encodings,
/// scalar mults, pairings and Miller loops.
fn vectors(n: usize, seed: u64) -> Result<()> {
    let mut rng = Xs(seed | 1);
    let mut out = BufWriter::new(std::io::stdout());
    for _ in 0..n {
        let k1 = rng.scalar();
        let k2 = rng.scalar();
        let p = (G1Projective::generator() * k1).to_affine();
        let q = (G2Projective::generator() * k2).to_affine();
        let s = rng.scalar();
        writeln!(out, "g1 {} {}", hex_g1(&p), hex::encode(p.to_compressed()))?;
        writeln!(out, "g2 {} {}", hex_g2(&q), hex::encode(q.to_compressed()))?;
        let mut sb = s.to_repr();
        sb.reverse();
        writeln!(out, "smul {} {}", hex::encode(sb), hex_g1(&(p * s).to_affine()))?;
        writeln!(out, "pair {}", fp12_hex(&format!("{:?}", bls12_381::pairing(&p, &q))))?;
        let ml = bls12_381::multi_miller_loop(&[(&p, &G2Prepared::from(q))]);
        writeln!(out, "ml {}", fp12_hex(&format!("{:?}", ml)))?;
    }
    Ok(())
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let a = |i: usize, d: &str| args.get(i).cloned().unwrap_or_else(|| d.to_string());
    match args.get(1).map(String::as_str) {
        Some("vk") => vk_cmd(),
        Some("extract") => extract(a(2, "1000").parse()?, a(3, "1000").parse()?, a(4, "12345").parse()?, &a(5, RAW), &a(6, "")),
        Some("fetch") => {
            let starts: Vec<u64> = a(2, "").split(',').map(|x| x.parse()).collect::<Result<_, _>>()?;
            let rt = tokio::runtime::Runtime::new()?;
            rt.block_on(fetch::fetch(starts, a(3, "500").parse()?, a(4, "300").parse()?, a(5, "16").parse()?, Path::new(&a(6, &format!("{DATA}/raw_old.bin")))))
        }
        Some("dump") => dump(&a(2, ""), a(3, "0").parse()?),
        Some("bench") => bench(&a(2, ""), a(3, "1").parse()?, a(4, "3").parse()?),
        Some("vectors") => vectors(a(2, "8").parse()?, a(3, "7").parse()?),
        _ => Err(anyhow!("usage: vk | extract MAXS MAXO [SEED RAW PREFIX] | fetch H1,H2,.. BLOCKS PER_WINDOW CONC [OUT] | dump FILE IDX | bench FILE THREADS [REPS] | vectors N SEED")),
    }
}
