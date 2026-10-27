//! Ground truth for the Bend Ed25519 verifier (ZIP 215 rules, as Zebra checks joinSplitSig).
//!
//! The verdict of every record is `ed25519_zebra::VerificationKey::try_from(pk)` followed by
//! `.verify(&sig, msg)`, exactly what Zebra does. curve25519-dalek is used only to *construct*
//! test cases (custom nonces, torsion components, non-canonical encodings) and for the layer
//! dumps (decompression, SHA-512, k mod l).
//!
//!   oracle gen OUT SEED NVALID   writes OUT.bin (records) and OUT.meta (one "tag verdict cofactorless" line per record)
//!   oracle verify FILE           prints "verdicts <digits>" for a record file (and timing)
//!   oracle layer FILE            per record: decode(A) decode(R) sha512(R||A||M) k S<l
//!
//! Record file: u32 count, then per record pk 32 | sig 64 | msg_len u32 | msg (all little-endian).

use curve25519_dalek::{
    constants::EIGHT_TORSION,
    edwards::{CompressedEdwardsY, EdwardsPoint},
    scalar::Scalar,
    traits::IsIdentity,
};
use ed25519_zebra::{Signature, SigningKey, VerificationKey};
use rand::{rngs::StdRng, Rng, RngCore, SeedableRng};
use sha2::{Digest, Sha512};
use std::io::Write;

struct Rec {
    pk: [u8; 32],
    sig: [u8; 64],
    msg: Vec<u8>,
    tag: &'static str,
}

fn zebra_ok(pk: &[u8; 32], sig: &[u8; 64], msg: &[u8]) -> bool {
    let sig = Signature::from_bytes(sig);
    VerificationKey::try_from(*pk)
        .and_then(|vk| vk.verify(&sig, msg))
        .is_ok()
}

fn hram(r: &[u8], a: &[u8], m: &[u8]) -> Scalar {
    Scalar::from_hash(Sha512::new().chain_update(r).chain_update(a).chain_update(m))
}

/// The cofactorless (RFC 8032 "alternate") equation [s]B = R + [k]A, for information only.
/// None when A or R does not decode or s is not canonical.
fn cofactorless(pk: &[u8; 32], sig: &[u8; 64], msg: &[u8]) -> Option<bool> {
    let a = CompressedEdwardsY(*pk).decompress()?;
    let r = CompressedEdwardsY(sig[..32].try_into().unwrap()).decompress()?;
    let s: Option<Scalar> = Scalar::from_canonical_bytes(sig[32..].try_into().unwrap()).into();
    let s = s?;
    let k = hram(&sig[..32], pk, msg);
    let rp = EdwardsPoint::vartime_double_scalar_mul_basepoint(&k, &(-a), &s);
    Some((r - rp).is_identity())
}

fn rand_scalar(rng: &mut StdRng) -> Scalar {
    let mut w = [0u8; 64];
    rng.fill_bytes(&mut w);
    Scalar::from_bytes_mod_order_wide(&w)
}

fn rand_msg(rng: &mut StdRng, n: usize) -> Vec<u8> {
    let mut m = vec![0u8; n];
    rng.fill_bytes(&mut m);
    m
}

fn mk_sig(r: &[u8; 32], s: &Scalar) -> [u8; 64] {
    let mut sig = [0u8; 64];
    sig[..32].copy_from_slice(r);
    sig[32..].copy_from_slice(s.as_bytes());
    sig
}

/// l as little-endian bytes.
fn ell() -> [u8; 32] {
    let mut l = [0u8; 32];
    // l = 2^252 + 27742317777372353535851937790883648493
    let lo: u128 = 27742317777372353535851937790883648493;
    l[..16].copy_from_slice(&lo.to_le_bytes());
    l[31] = 0x10;
    l
}

/// x + n*l over 256 bits; None on overflow.
fn add_nl(x: &[u8], n: u32) -> Option<[u8; 32]> {
    let l = ell();
    let mut out = [0u8; 32];
    let mut c: u64 = 0;
    for i in 0..32 {
        let v = x[i] as u64 + (l[i] as u64) * (n as u64) + c;
        out[i] = v as u8;
        c = v >> 8;
    }
    if c != 0 {
        None
    } else {
        Some(out)
    }
}

// --- ed25519-zebra tests/util/mod.rs, verbatim logic ---
fn non_canonical_field_encodings() -> Vec<[u8; 32]> {
    let mut bytes = [255u8; 32];
    bytes[31] = 127;
    let mut encodings = Vec::new();
    for i in 0..19u8 {
        bytes[0] = 237 + i;
        encodings.push(bytes);
    }
    encodings
}

fn non_canonical_point_encodings() -> Vec<[u8; 32]> {
    let mut encodings = Vec::new();
    let mut y1 = [0u8; 32];
    y1[0] = 1;
    y1[31] = 128;
    encodings.push(y1);
    let mut ym1 = [255u8; 32];
    ym1[0] = 236;
    encodings.push(ym1);
    for mut x in non_canonical_field_encodings().into_iter() {
        if CompressedEdwardsY(x).decompress().is_some() {
            encodings.push(x);
        }
        x[31] |= 128;
        if CompressedEdwardsY(x).decompress().is_some() {
            encodings.push(x);
        }
    }
    for &e in &encodings {
        assert_ne!(e, CompressedEdwardsY(e).decompress().unwrap().compress().to_bytes());
    }
    encodings
}

/// tests/small_order.rs SMALL_ORDER_SIGS: 14 x 14 = 196 cases, all valid under ZIP 215.
fn small_order_sigs() -> Vec<Rec> {
    let s = Scalar::ZERO;
    let encodings = EIGHT_TORSION
        .iter()
        .map(|p| p.compress().to_bytes())
        .chain(non_canonical_point_encodings().into_iter().take(6))
        .collect::<Vec<_>>();
    let mut out = Vec::new();
    for a in &encodings {
        for r in &encodings {
            out.push(Rec { pk: *a, sig: mk_sig(r, &s), msg: b"Zcash".to_vec(), tag: "zip215" });
        }
    }
    out
}

/// A signing key we know the scalar of: (a, A_bytes).
fn keypair(rng: &mut StdRng) -> (Scalar, [u8; 32]) {
    let a = rand_scalar(rng);
    (a, EdwardsPoint::mul_base(&a).compress().to_bytes())
}

fn flip(rng: &mut StdRng, bytes: &mut [u8]) {
    let i = rng.gen_range(0..bytes.len() * 8);
    bytes[i / 8] ^= 1 << (i % 8);
}

fn nondecodable(rng: &mut StdRng) -> [u8; 32] {
    loop {
        let mut b = [0u8; 32];
        rng.fill_bytes(&mut b);
        if CompressedEdwardsY(b).decompress().is_none() {
            return b;
        }
    }
}

fn gen(seed: u64, nvalid: usize) -> Vec<Rec> {
    let mut rng = StdRng::seed_from_u64(seed);
    let mut out = small_order_sigs();

    // Honest signatures from ed25519-zebra's own signer, 32-byte messages (as joinSplitSig).
    let mut valid = Vec::new();
    for _ in 0..nvalid {
        let sk = SigningKey::new(&mut rng);
        let vk = VerificationKey::from(&sk);
        let msg = rand_msg(&mut rng, 32);
        let sig = sk.sign(&msg);
        valid.push(Rec { pk: vk.into(), sig: sig.to_bytes(), msg, tag: "valid" });
    }
    // Message lengths 0..=300 and a few long ones (SHA-512 padding / multi-block paths).
    let mut lens: Vec<usize> = (0..=300).collect();
    lens.extend([511, 512, 1000, 4096]);
    for n in lens {
        let sk = SigningKey::new(&mut rng);
        let vk = VerificationKey::from(&sk);
        let msg = rand_msg(&mut rng, n);
        let sig = sk.sign(&msg);
        out.push(Rec { pk: vk.into(), sig: sig.to_bytes(), msg, tag: "valid_len" });
    }
    // Tampered copies of every honest signature.
    let mut tampered = Vec::new();
    for v in &valid {
        let mut t = Rec { pk: v.pk, sig: v.sig, msg: v.msg.clone(), tag: "flip_R" };
        flip(&mut rng, &mut t.sig[..32]);
        tampered.push(t);
        let mut t = Rec { pk: v.pk, sig: v.sig, msg: v.msg.clone(), tag: "flip_A" };
        flip(&mut rng, &mut t.pk);
        tampered.push(t);
        let mut t = Rec { pk: v.pk, sig: v.sig, msg: v.msg.clone(), tag: "flip_S" };
        flip(&mut rng, &mut t.sig[32..]);
        tampered.push(t);
        let mut t = Rec { pk: v.pk, sig: v.sig, msg: v.msg.clone(), tag: "flip_M" };
        flip(&mut rng, &mut t.msg);
        tampered.push(t);
        // S + l: the same scalar mod l, non-canonical, must be rejected.
        let mut t = Rec { pk: v.pk, sig: v.sig, msg: v.msg.clone(), tag: "S_plus_l" };
        t.sig[32..].copy_from_slice(&add_nl(&v.sig[32..], 1).unwrap());
        tampered.push(t);
        // S + n*l for a random n in 2..=15 while it fits 256 bits.
        let n = rng.gen_range(2..=15);
        if let Some(s2) = add_nl(&v.sig[32..], n) {
            let mut t = Rec { pk: v.pk, sig: v.sig, msg: v.msg.clone(), tag: "S_plus_nl" };
            t.sig[32..].copy_from_slice(&s2);
            tampered.push(t);
        }
        // Signature checked against another message / key.
        let mut t = Rec { pk: v.pk, sig: v.sig, msg: rand_msg(&mut rng, 32), tag: "other_msg" };
        t.tag = "other_msg";
        tampered.push(t);
    }
    out.extend(valid);
    out.extend(tampered);

    let ncs = non_canonical_point_encodings(); // 25; the first 6 are small order
    // Non-canonical A (each of the 25 encodings), R = [r]B, s = r: valid iff A has small order.
    for e in &ncs {
        for _ in 0..4 {
            let r = rand_scalar(&mut rng);
            let rb = EdwardsPoint::mul_base(&r).compress().to_bytes();
            out.push(Rec { pk: *e, sig: mk_sig(&rb, &r), msg: rand_msg(&mut rng, 32), tag: "nc_A" });
        }
    }
    // Non-canonical R, real key, s = k*a: valid iff R has small order.
    for e in &ncs {
        for _ in 0..4 {
            let (a, ab) = keypair(&mut rng);
            let msg = rand_msg(&mut rng, 32);
            let s = hram(e, &ab, &msg) * a;
            out.push(Rec { pk: ab, sig: mk_sig(e, &s), msg, tag: "nc_R" });
        }
    }
    // Both non-canonical, s = 0.
    for ea in &ncs {
        for er in ncs.iter().step_by(3) {
            out.push(Rec { pk: *ea, sig: mk_sig(er, &Scalar::ZERO), msg: b"Zcash".to_vec(), tag: "nc_AR" });
        }
    }
    // Non-canonical A / R with an honest-looking s (random): rejected by the equation.
    for e in &ncs {
        let (_, ab) = keypair(&mut rng);
        let s = rand_scalar(&mut rng);
        out.push(Rec { pk: ab, sig: mk_sig(e, &s), msg: rand_msg(&mut rng, 32), tag: "nc_bad" });
        let r = rand_scalar(&mut rng);
        let rb = EdwardsPoint::mul_base(&r).compress().to_bytes();
        out.push(Rec { pk: *e, sig: mk_sig(&rb, &s), msg: rand_msg(&mut rng, 32), tag: "nc_bad" });
    }
    // Canonical small-order A (the 8 torsion points), R = [r]B, s = r; and small-order R, s = k*a.
    for t in EIGHT_TORSION.iter() {
        let tb = t.compress().to_bytes();
        for _ in 0..5 {
            let r = rand_scalar(&mut rng);
            let rb = EdwardsPoint::mul_base(&r).compress().to_bytes();
            out.push(Rec { pk: tb, sig: mk_sig(&rb, &r), msg: rand_msg(&mut rng, 32), tag: "small_A" });
            let (a, ab) = keypair(&mut rng);
            let msg = rand_msg(&mut rng, 32);
            let s = hram(&tb, &ab, &msg) * a;
            out.push(Rec { pk: ab, sig: mk_sig(&tb, &s), msg, tag: "small_R" });
            // small-order A with a random s: rejected unless [8][s]B = 0, i.e. never.
            let s = rand_scalar(&mut rng);
            out.push(Rec { pk: tb, sig: mk_sig(&rb, &s), msg: rand_msg(&mut rng, 32), tag: "small_A_bad" });
        }
    }
    // Mixed order: R = [r]B + T or A = [a]B + T (T a nonzero 8-torsion point), s = r + k*a.
    // The cofactored equation holds; the cofactorless one fails whenever [k]T or T != 0.
    for i in 0..400 {
        let t = EIGHT_TORSION[1 + i % 7];
        let (a, ab) = keypair(&mut rng);
        let r = rand_scalar(&mut rng);
        let msg = rand_msg(&mut rng, 32);
        let rb = (EdwardsPoint::mul_base(&r) + t).compress().to_bytes();
        let s = r + hram(&rb, &ab, &msg) * a;
        out.push(Rec { pk: ab, sig: mk_sig(&rb, &s), msg: msg.clone(), tag: "mixed_R" });
        let ab2 = (EdwardsPoint::mul_base(&a) + t).compress().to_bytes();
        let rb2 = EdwardsPoint::mul_base(&r).compress().to_bytes();
        let s2 = r + hram(&rb2, &ab2, &msg) * a;
        out.push(Rec { pk: ab2, sig: mk_sig(&rb2, &s2), msg: msg.clone(), tag: "mixed_A" });
        let t2 = EIGHT_TORSION[1 + (i * 3) % 7];
        let rb3 = (EdwardsPoint::mul_base(&r) + t2).compress().to_bytes();
        let s3 = r + hram(&rb3, &ab2, &msg) * a;
        out.push(Rec { pk: ab2, sig: mk_sig(&rb3, &s3), msg, tag: "mixed_AR" });
    }
    // Non-decodable A or R in an otherwise valid signature.
    for i in 0..400 {
        let v = &out[196 + 305 + (i % nvalid.max(1))];
        let (pk, sig, msg) = (v.pk, v.sig, v.msg.clone());
        let mut t = Rec { pk, sig, msg: msg.clone(), tag: "nondec_R" };
        t.sig[..32].copy_from_slice(&nondecodable(&mut rng));
        out.push(t);
        let t = Rec { pk: nondecodable(&mut rng), sig, msg, tag: "nondec_A" };
        out.push(t);
    }
    // Uniformly random records.
    for _ in 0..300 {
        let mut pk = [0u8; 32];
        let mut sig = [0u8; 64];
        rng.fill_bytes(&mut pk);
        rng.fill_bytes(&mut sig);
        if rng.gen_bool(0.5) {
            sig[63] &= 0x0f; // S < 2^252 < l
        }
        out.push(Rec { pk, sig, msg: rand_msg(&mut rng, 32), tag: "random" });
    }
    out
}

fn write_set(path: &str, recs: &[Rec]) {
    let mut b = Vec::new();
    b.extend((recs.len() as u32).to_le_bytes());
    for r in recs {
        b.extend(r.pk);
        b.extend(r.sig);
        b.extend((r.msg.len() as u32).to_le_bytes());
        b.extend(&r.msg);
    }
    std::fs::write(path, b).unwrap();
}

fn read_set(path: &str) -> Vec<Rec> {
    let b = std::fs::read(path).unwrap();
    let n = u32::from_le_bytes(b[0..4].try_into().unwrap()) as usize;
    let mut p = 4;
    let mut out = Vec::with_capacity(n);
    for _ in 0..n {
        let pk: [u8; 32] = b[p..p + 32].try_into().unwrap();
        let sig: [u8; 64] = b[p + 32..p + 96].try_into().unwrap();
        let ml = u32::from_le_bytes(b[p + 96..p + 100].try_into().unwrap()) as usize;
        let msg = b[p + 100..p + 100 + ml].to_vec();
        p += 100 + ml;
        out.push(Rec { pk, sig, msg, tag: "" });
    }
    out
}

fn dec_hex(e: &[u8; 32]) -> String {
    match CompressedEdwardsY(*e).decompress() {
        Some(p) => hex::encode(p.compress().to_bytes()),
        None => "-".into(),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(|s| s.as_str()) {
        Some("gen") => {
            let out = &args[2];
            let seed: u64 = args[3].parse().unwrap();
            let nvalid: usize = args[4].parse().unwrap();
            let recs = gen(seed, nvalid);
            write_set(&format!("{out}.bin"), &recs);
            let mut meta = String::new();
            for r in &recs {
                let v = zebra_ok(&r.pk, &r.sig, &r.msg);
                let c = match cofactorless(&r.pk, &r.sig, &r.msg) {
                    Some(true) => "1",
                    Some(false) => "0",
                    None => "-",
                };
                meta.push_str(&format!("{} {} {}\n", r.tag, v as u8, c));
            }
            std::fs::write(format!("{out}.meta"), meta).unwrap();
            eprintln!("wrote {} records to {out}.bin / {out}.meta", recs.len());
        }
        Some("verify") => {
            let recs = read_set(&args[2]);
            let t0 = std::time::Instant::now();
            let vs: String = recs.iter().map(|r| if zebra_ok(&r.pk, &r.sig, &r.msg) { '1' } else { '0' }).collect();
            let dt = t0.elapsed();
            println!("verdicts {vs}");
            println!("n {} us_per_verify {:.2}", recs.len(), dt.as_secs_f64() * 1e6 / recs.len() as f64);
        }
        Some("layer") => {
            let recs = read_set(&args[2]);
            let mut o = std::io::BufWriter::new(std::io::stdout());
            for r in &recs {
                let rb: [u8; 32] = r.sig[..32].try_into().unwrap();
                let h = Sha512::new().chain_update(rb).chain_update(r.pk).chain_update(&r.msg).finalize();
                let k = hram(&rb, &r.pk, &r.msg);
                let sc: bool = Option::<Scalar>::from(Scalar::from_canonical_bytes(r.sig[32..].try_into().unwrap())).is_some();
                writeln!(o, "{} {} {} {} {}", dec_hex(&r.pk), dec_hex(&rb), hex::encode(h), hex::encode(k.to_bytes()), sc as u8).unwrap();
            }
        }
        Some("decset") => {
            // Decoding-targeted encodings as pk and R of records (S random, msg random length):
            // y in [0, 64) and [p - 64, 2^255) (non-canonical y >= p), both sign bits, the 26
            // ZIP 215 non-canonical encodings, the 8 torsion points, and random bytes.
            let out = &args[2];
            let seed: u64 = args[3].parse().unwrap();
            let mut rng = StdRng::seed_from_u64(seed);
            let mut encs: Vec<[u8; 32]> = Vec::new();
            for y in 0u8..64 {
                let mut e = [0u8; 32];
                e[0] = y;
                encs.push(e);
                e[31] |= 0x80;
                encs.push(e);
                let mut f = [0xffu8; 32];
                f[31] = 0x7f;
                f[0] = 0xff - y; // 2^255 - 1 - y, covers p - 45 .. 2^255 - 1
                encs.push(f);
                f[31] |= 0x80;
                encs.push(f);
            }
            encs.extend(non_canonical_point_encodings());
            encs.extend(EIGHT_TORSION.iter().map(|p| p.compress().to_bytes()));
            for _ in 0..4000 {
                let mut e = [0u8; 32];
                rng.fill_bytes(&mut e);
                encs.push(e);
            }
            let mut recs = Vec::new();
            for (i, e) in encs.iter().enumerate() {
                let r = encs[(i * 7 + 3) % encs.len()];
                let mut sig = [0u8; 64];
                sig[..32].copy_from_slice(&r);
                rng.fill_bytes(&mut sig[32..]);
                if i % 3 == 0 {
                    sig[63] &= 0x1f;
                }
                let n = rng.gen_range(0..300);
                recs.push(Rec { pk: *e, sig, msg: rand_msg(&mut rng, n), tag: "dec" });
            }
            write_set(&format!("{out}.bin"), &recs);
            eprintln!("wrote {} records to {out}.bin", recs.len());
        }
        _ => eprintln!("usage: oracle gen OUT SEED NVALID | decset OUT SEED | verify FILE | layer FILE"),
    }
}
