//! Test vectors from the official crates (fixed-seed ChaCha20). All field elements and points are
//! the crates' own 32-byte little-endian encodings, hex.

use std::{
    fs::{self, File},
    io::{BufWriter, Write},
    path::Path,
};

use anyhow::{ensure, Result};
use ff::{Field, PrimeField};
use group::{Curve, Group, GroupEncoding};
use incrementalmerkletree::{Hashable, Level};
use jubjub::{AffinePoint, ExtendedPoint, Fq, Fr, SubgroupPoint};
use rand_chacha::ChaCha20Rng;
use rand_core::{Rng, SeedableRng};
use sapling::{
    constants,
    pedersen_hash::{pedersen_hash, Personalization},
    Node,
};

use crate::DATA;

fn hx(b: impl AsRef<[u8]>) -> String {
    hex::encode(b.as_ref())
}
fn rnd32(rng: &mut ChaCha20Rng) -> [u8; 32] {
    let mut b = [0u8; 32];
    rng.fill_bytes(&mut b);
    b
}
fn rand_fq(rng: &mut ChaCha20Rng) -> Fq {
    let mut w = [0u8; 64];
    rng.fill_bytes(&mut w);
    Fq::from_bytes_wide(&w)
}
fn rand_fr(rng: &mut ChaCha20Rng) -> Fr {
    let mut w = [0u8; 64];
    rng.fill_bytes(&mut w);
    Fr::from_bytes_wide(&w)
}
fn opt<T>(o: subtle::CtOption<T>) -> Option<T> {
    Option::from(o)
}
/// Bytes of (modulus + k) for small signed k, as a 32-byte little-endian integer.
fn le_add(mut b: [u8; 32], k: i64) -> [u8; 32] {
    let mut carry = k as i128;
    for x in b.iter_mut() {
        let v = *x as i128 + carry;
        *x = v.rem_euclid(256) as u8;
        carry = v.div_euclid(256);
    }
    b
}
fn modulus_bytes<F: PrimeField>() -> [u8; 32] {
    // -1 as repr, plus one.
    let m1 = (-F::ONE).to_repr();
    le_add(m1.as_ref().try_into().unwrap(), 1)
}
fn uv(p: &AffinePoint) -> String {
    format!("{} {}", hx(p.get_u().to_bytes()), hx(p.get_v().to_bytes()))
}
fn aff_of_sub(p: &SubgroupPoint) -> AffinePoint {
    ExtendedPoint::from(*p).to_affine()
}
/// A random point of the full curve (any torsion component).
fn rand_point(rng: &mut ChaCha20Rng) -> ExtendedPoint {
    loop {
        if let Some(p) = opt(AffinePoint::from_bytes(rnd32(rng))) {
            return p.to_extended();
        }
    }
}

pub fn the_8_torsion() -> Vec<AffinePoint> {
    // [r_J] P for random P lands in the 8-torsion; collect until all 8 are found.
    let r = modulus_bytes::<Fr>();
    let mut rng = ChaCha20Rng::seed_from_u64(8);
    let mut v: Vec<[u8; 32]> = vec![];
    while v.len() < 8 {
        let p = rand_point(&mut rng).to_affine();
        let t = p.to_niels().multiply_bits(&r).to_affine();
        if !v.contains(&t.to_bytes()) {
            v.push(t.to_bytes());
        }
    }
    v.sort();
    v.iter().map(|b| AffinePoint::from_bytes(*b).unwrap()).collect()
}

pub fn edwards_d() -> Fq {
    -(Fq::from(10240u64) * Fq::from(10241u64).invert().unwrap())
}

pub fn run(seed: u64) -> Result<()> {
    let dir = Path::new(DATA).join("vectors");
    fs::create_dir_all(&dir)?;
    let mut rng = ChaCha20Rng::seed_from_u64(seed);
    let open = |n: &str| -> Result<BufWriter<File>> { Ok(BufWriter::new(File::create(dir.join(n))?)) };

    // ---------------------------------------------------------------- fr.txt (Fq = BLS12-381 scalar = Jubjub base)
    {
        let mut o = open("fr.txt")?;
        writeln!(o, "# a b a+b a-b a*b a^2 inv(a)|none sqrt(a)|none   (bls12_381::Scalar, 32-byte LE hex; sqrt = bls12_381's Scalar::sqrt root)")?;
        let p = modulus_bytes::<Fq>();
        let mut edges: Vec<Fq> = vec![Fq::ZERO, Fq::ONE, Fq::from(2), Fq::from(3), -Fq::ONE, -Fq::from(2), Fq::ROOT_OF_UNITY, Fq::MULTIPLICATIVE_GENERATOR, Fq::TWO_INV, -Fq::TWO_INV];
        edges.push(Fq::from_bytes(&le_add(p, -1)).unwrap());
        edges.push(Fq::from(u64::MAX));
        for k in [64u32, 128, 192, 253, 254] {
            edges.push(Fq::from(2).pow_vartime(&[k as u64, 0, 0, 0]));
        }
        let mut n = 0;
        for a in &edges {
            for b in &edges {
                if n < 200 {
                    fr_line(&mut o, *a, *b)?;
                    n += 1;
                }
            }
        }
        while n < 2000 {
            let (a, b) = (rand_fq(&mut rng), rand_fq(&mut rng));
            fr_line(&mut o, a, b)?;
            n += 1;
        }
        // canonical decoding checks
        writeln!(o, "# canon bytes 1|0  (Scalar::from_bytes)")?;
        for k in [-2i64, -1, 0, 1, 2] {
            let b = le_add(p, k);
            writeln!(o, "canon {} {}", hx(b), opt(Fq::from_bytes(&b)).is_some() as u8)?;
        }
        for _ in 0..200 {
            let mut b = rnd32(&mut rng);
            b[31] &= 0x7f;
            writeln!(o, "canon {} {}", hx(b), opt(Fq::from_bytes(&b)).is_some() as u8)?;
        }
        o.flush()?;
    }

    // ---------------------------------------------------------------- fs.txt (Fr = Jubjub scalar field)
    {
        let mut o = open("fs.txt")?;
        writeln!(o, "# wide wide64hex reducedhex   (jubjub::Fr::from_bytes_wide)")?;
        let mut edge_wide: Vec<[u8; 64]> = vec![[0u8; 64], [0xffu8; 64]];
        let mut one = [0u8; 64];
        one[0] = 1;
        edge_wide.push(one);
        let r = modulus_bytes::<Fr>();
        let mut rw = [0u8; 64];
        rw[..32].copy_from_slice(&r);
        edge_wide.push(rw);
        for w in edge_wide {
            writeln!(o, "wide {} {}", hx(w), hx(Fr::from_bytes_wide(&w).to_bytes()))?;
        }
        for _ in 0..1000 {
            let mut w = [0u8; 64];
            rng.fill_bytes(&mut w);
            writeln!(o, "wide {} {}", hx(w), hx(Fr::from_bytes_wide(&w).to_bytes()))?;
        }
        writeln!(o, "# canon bytes 1|0   (jubjub::Fr::from_bytes: 1 iff the LE integer < r_J)")?;
        for k in [-2i64, -1, 0, 1, 2] {
            let b = le_add(r, k);
            writeln!(o, "canon {} {}", hx(b), opt(Fr::from_bytes(&b)).is_some() as u8)?;
        }
        for i in 0..1000 {
            let mut b = rnd32(&mut rng);
            // mix top bytes so roughly half are canonical (r_J ~ 0x0e7d...)
            b[31] = match i % 4 {
                0 => b[31] & 0x0f,
                1 => 0x0e,
                2 => b[31] & 0x0d,
                _ => b[31],
            };
            writeln!(o, "canon {} {}", hx(b), opt(Fr::from_bytes(&b)).is_some() as u8)?;
        }
        writeln!(o, "# arith a b a+b a*b -a inv(a)|none   (jubjub::Fr)")?;
        for _ in 0..500 {
            let (a, b) = (rand_fr(&mut rng), rand_fr(&mut rng));
            let inv = opt(a.invert()).map(|x| hx(x.to_bytes())).unwrap_or("none".into());
            writeln!(o, "arith {} {} {} {} {} {inv}", hx(a.to_bytes()), hx(b.to_bytes()), hx((a + b).to_bytes()), hx((a * b).to_bytes()), hx((-a).to_bytes()))?;
        }
        o.flush()?;
    }

    // ---------------------------------------------------------------- points.txt
    {
        let mut o = open("points.txt")?;
        writeln!(o, "# decode bytes zip216_result|none pre_zip216_result|none   (AffinePoint::from_bytes / from_bytes_pre_zip216_compatibility; result = re-encoding)")?;
        let enc = |r: Option<AffinePoint>| r.map(|p| hx(p.to_bytes())).unwrap_or("none".into());
        let dec_line = |o: &mut BufWriter<File>, b: [u8; 32]| -> Result<()> {
            writeln!(o, "decode {} {} {}", hx(b), enc(opt(AffinePoint::from_bytes(b))), enc(opt(AffinePoint::from_bytes_pre_zip216_compatibility(b))))?;
            Ok(())
        };
        for _ in 0..1000 {
            dec_line(&mut o, rnd32(&mut rng))?;
        }
        // non-canonical / special cases
        let q = modulus_bytes::<Fq>();
        let ident = AffinePoint::identity().to_bytes();
        dec_line(&mut o, ident)?; // (0,1)
        let mut s = ident;
        s[31] |= 0x80; // u = 0 with sign bit set (ZIP 216: rejected; pre-ZIP-216: accepted)
        dec_line(&mut o, s)?;
        let m1 = (-Fq::ONE).to_bytes(); // v = -1 -> (0,-1), order 2
        dec_line(&mut o, m1)?;
        let mut m1s = m1;
        m1s[31] |= 0x80;
        dec_line(&mut o, m1s)?;
        for k in [0i64, 1, 2, 3, 100] {
            // v = q + k (non-canonical v), both sign bits
            let b = le_add(q, k);
            dec_line(&mut o, b)?;
            let mut bs = b;
            bs[31] |= 0x80;
            dec_line(&mut o, bs)?;
        }
        // v >= q encodings of valid points: v' = v + q for points with small v
        let mut added = 0;
        while added < 20 {
            let p = rand_point(&mut rng).to_affine();
            let vb = p.get_v().to_bytes();
            let vq = le_add(q, 0);
            // v + q < 2^255 ?
            let mut sum = [0u8; 32];
            let mut c = 0u16;
            for i in 0..32 {
                let t = vb[i] as u16 + vq[i] as u16 + c;
                sum[i] = t as u8;
                c = t >> 8;
            }
            if c == 0 && sum[31] & 0x80 == 0 {
                let mut b = sum;
                b[31] |= p.to_bytes()[31] & 0x80;
                dec_line(&mut o, b)?;
                added += 1;
            }
        }
        writeln!(o, "# add P Q P+Q 2P   (encodings; random points of the full curve)")?;
        for _ in 0..500 {
            let (p, q) = (rand_point(&mut rng), rand_point(&mut rng));
            writeln!(o, "add {} {} {} {}", hx(p.to_bytes()), hx(q.to_bytes()), hx((p + q).to_bytes()), hx(p.double().to_bytes()))?;
        }
        writeln!(o, "# mul P k [k]P   (k = jubjub::Fr scalar, 32-byte LE canonical; P on the full curve)")?;
        for i in 0..500 {
            let p = if i % 2 == 0 { rand_point(&mut rng) } else { ExtendedPoint::from(SubgroupPoint::random(&mut rng)) };
            let k = rand_fr(&mut rng);
            writeln!(o, "mul {} {} {}", hx(p.to_bytes()), hx(k.to_bytes()), hx((p * k).to_bytes()))?;
        }
        writeln!(o, "# order P [8]P is_small_order is_torsion_free")?;
        let tors = the_8_torsion();
        for i in 0..300 {
            let p = match i % 3 {
                0 => rand_point(&mut rng),
                1 => ExtendedPoint::from(SubgroupPoint::random(&mut rng)),
                _ => ExtendedPoint::from(SubgroupPoint::random(&mut rng)) + tors[i % 8].to_extended(),
            };
            writeln!(o, "order {} {} {} {}", hx(p.to_bytes()), hx(p.mul_by_cofactor().to_bytes()), p.is_small_order().unwrap_u8(), p.is_torsion_free().unwrap_u8())?;
        }
        for t in &tors {
            let p = t.to_extended();
            writeln!(o, "order {} {} {} {}", hx(p.to_bytes()), hx(p.mul_by_cofactor().to_bytes()), p.is_small_order().unwrap_u8(), p.is_torsion_free().unwrap_u8())?;
        }
        writeln!(o, "# torsion u v encoding   (the 8 points of order dividing 8)")?;
        for t in &tors {
            writeln!(o, "torsion {} {}", uv(t), hx(t.to_bytes()))?;
        }
        o.flush()?;
    }

    // ---------------------------------------------------------------- consts.txt
    {
        let mut o = open("consts.txt")?;
        writeln!(o, "# name u v encoding   (affine coordinates, 32-byte LE hex; sapling_crypto::constants)")?;
        let gens: Vec<(&str, SubgroupPoint)> = vec![
            ("SPENDING_KEY_GENERATOR", constants::SPENDING_KEY_GENERATOR),
            ("VALUE_COMMITMENT_VALUE_GENERATOR", constants::VALUE_COMMITMENT_VALUE_GENERATOR),
            ("VALUE_COMMITMENT_RANDOMNESS_GENERATOR", constants::VALUE_COMMITMENT_RANDOMNESS_GENERATOR),
            ("NOTE_COMMITMENT_RANDOMNESS_GENERATOR", constants::NOTE_COMMITMENT_RANDOMNESS_GENERATOR),
            ("NULLIFIER_POSITION_GENERATOR", constants::NULLIFIER_POSITION_GENERATOR),
            ("PROOF_GENERATION_KEY_GENERATOR", constants::PROOF_GENERATION_KEY_GENERATOR),
        ];
        for (n, g) in &gens {
            writeln!(o, "{n} {} {}", uv(&aff_of_sub(g)), hx(g.to_bytes()))?;
        }
        for (i, g) in constants::PEDERSEN_HASH_GENERATORS.iter().enumerate() {
            writeln!(o, "PEDERSEN_HASH_GENERATORS[{i}] {} {}", uv(&aff_of_sub(g)), hx(g.to_bytes()))?;
        }
        let d = edwards_d();
        // sanity: the spend-auth generator satisfies -u^2 + v^2 = 1 + d u^2 v^2
        let g = aff_of_sub(&constants::SPENDING_KEY_GENERATOR);
        let (u2, v2) = (g.get_u().square(), g.get_v().square());
        ensure!(v2 - u2 == Fq::ONE + d * u2 * v2, "curve equation");
        writeln!(o, "EDWARDS_D {}", hx(d.to_bytes()))?;
        writeln!(o, "FQ_MODULUS {}", hx(modulus_bytes::<Fq>()))?;
        writeln!(o, "FR_MODULUS {}", hx(modulus_bytes::<Fr>()))?;
        writeln!(o, "# EMPTY_ROOT level hex   (Node::empty_root; level 0 = Uncommitted^Sapling = 1)")?;
        for l in 0..=32u8 {
            writeln!(o, "EMPTY_ROOT {l} {}", hx(Node::empty_root(Level::from(l)).to_bytes()))?;
        }
        o.flush()?;
    }

    // ---------------------------------------------------------------- merkle.txt
    {
        let mut o = open("merkle.txt")?;
        writeln!(o, "# merkle level lhs rhs MerkleCRH(level,lhs,rhs)   (Node::combine == sapling_crypto::merkle_hash; inputs canonical Fq)")?;
        for i in 0..1000 {
            let level = (i % 32) as u8;
            let (l, r) = (rand_fq(&mut rng).to_bytes(), rand_fq(&mut rng).to_bytes());
            let (nl, nr) = (Node::from_bytes(l).unwrap(), Node::from_bytes(r).unwrap());
            let h = Node::combine(Level::from(level), &nl, &nr).to_bytes();
            ensure!(h == sapling::merkle_hash(level as usize, &l, &r));
            writeln!(o, "merkle {level} {} {} {}", hx(l), hx(r), hx(h))?;
        }
        writeln!(o, "# pedersen pers nbits bits01 u v   (pedersen_hash(pers, bits); pers 0..62 = MerkleTree(pers) i.e. 6 bits LSB-first, 63 = NoteCommitment (111111); bits01 = the message bits in order, AFTER the 6 personalization bits; output = affine (u,v) LE hex)")?;
        for i in 0..200 {
            let pers = if i % 5 == 0 { 63 } else { (rng.next_u32() % 63) as usize };
            let nbits = match i {
                0 => 0,
                1 => 1,
                2..=10 => 510,
                _ => 1 + (rng.next_u32() % 1128) as usize, // 6 generators x 63 chunks x 3 bits = 1134 incl. 6 personalization bits
            };
            let bits: Vec<bool> = (0..nbits).map(|_| rng.next_u32() & 1 == 1).collect();
            let p = if pers == 63 { Personalization::NoteCommitment } else { Personalization::MerkleTree(pers) };
            let h = aff_of_sub(&pedersen_hash(p, bits.iter().copied()));
            let s: String = bits.iter().map(|b| if *b { '1' } else { '0' }).collect();
            writeln!(o, "pedersen {pers} {nbits} {} {}", if s.is_empty() { "-".to_string() } else { s }, uv(&h))?;
        }
        o.flush()?;
    }

    // ---------------------------------------------------------------- sig.txt
    {
        use redjubjub::{Binding, Signature, SigningKey, SpendAuth, VerificationKey};
        let mut o = open("sig.txt")?;
        writeln!(o, "# kind vk R s msg valid   (kind spendauth|binding; msg 32 bytes; valid = redjubjub::VerificationKey::<T>::try_from(vk) then .verify(msg, sig) is Ok)")?;
        writeln!(o, "# tampered lines: kind vk R s msg valid tamper=<field>:<bit>")?;
        fn verdict<T: redjubjub::SigType>(vk: [u8; 32], r: [u8; 32], s: [u8; 32], msg: &[u8]) -> u8
        where
            VerificationKey<T>: TryFrom<[u8; 32]>,
        {
            let mut sig = [0u8; 64];
            sig[..32].copy_from_slice(&r);
            sig[32..].copy_from_slice(&s);
            match VerificationKey::<T>::try_from(vk) {
                Ok(k) => k.verify(msg, &Signature::<T>::from(sig)).is_ok() as u8,
                Err(_) => 0,
            }
        }
        let (mut good, mut bad) = (0u64, 0u64);
        for kind in ["spendauth", "binding"] {
            for _ in 0..500 {
                let msg = rnd32(&mut rng);
                let (vk, sig): ([u8; 32], [u8; 64]) = if kind == "spendauth" {
                    let sk = SigningKey::<SpendAuth>::new(&mut rng);
                    (VerificationKey::from(&sk).into(), sk.sign(&mut rng, &msg).into())
                } else {
                    let sk = SigningKey::<Binding>::new(&mut rng);
                    (VerificationKey::from(&sk).into(), sk.sign(&mut rng, &msg).into())
                };
                let r: [u8; 32] = sig[..32].try_into().unwrap();
                let s: [u8; 32] = sig[32..].try_into().unwrap();
                let v = if kind == "spendauth" { verdict::<SpendAuth>(vk, r, s, &msg) } else { verdict::<Binding>(vk, r, s, &msg) };
                ensure!(v == 1, "fresh signature failed");
                writeln!(o, "{kind} {} {} {} {} {v}", hx(vk), hx(r), hx(s), hx(msg))?;
                good += 1;
                // tampered variant
                let (mut vk2, mut r2, mut s2, mut m2) = (vk, r, s, msg);
                let field = rng.next_u32() % 4;
                let bit = (rng.next_u32() % 256) as usize;
                let tgt: &mut [u8; 32] = match field {
                    0 => &mut r2,
                    1 => &mut s2,
                    2 => &mut vk2,
                    _ => &mut m2,
                };
                tgt[bit / 8] ^= 1 << (bit % 8);
                let v2 = if kind == "spendauth" { verdict::<SpendAuth>(vk2, r2, s2, &m2) } else { verdict::<Binding>(vk2, r2, s2, &m2) };
                bad += (v2 == 0) as u64;
                writeln!(o, "{kind} {} {} {} {} {v2} tamper={}:{bit}", hx(vk2), hx(r2), hx(s2), hx(m2), ["R", "s", "vk", "msg"][field as usize])?;
            }
        }
        // Cofactor / canonicity edge cases on spend-auth signatures:
        //   R=[n]G+T: hand-made signature with a torsion component in R (accepted: cofactored);
        //   manual: same construction with T = 0 (cross-checks our H* challenge; accepted)
        //   s+r: s replaced by s + r_J (non-canonical scalar, rejected)
        //   vk+T: vk replaced by vk + T (challenge changes, rejected)
        let tors = the_8_torsion();
        let r_j = modulus_bytes::<Fr>();
        let mut edge = [0u64; 2];
        for i in 0..96usize {
            let msg = rnd32(&mut rng);
            let sk = SigningKey::<SpendAuth>::new(&mut rng);
            let vk: [u8; 32] = VerificationKey::from(&sk).into();
            let sig: [u8; 64] = sk.sign(&mut rng, &msg).into();
            let r: [u8; 32] = sig[..32].try_into().unwrap();
            let s: [u8; 32] = sig[32..].try_into().unwrap();
            let t = tors.iter().filter(|t| !bool::from(t.is_identity())).nth(i % 7).unwrap().to_extended();
            let (name, vk2, r2, s2) = match i % 3 {
                0 => {
                    // Hand-made signature whose nonce point has a torsion component:
                    // R = [n]G + T, c = H*(R || vk || msg), s = n + c*sk. Cofactored verification
                    // accepts (sB - cA - R = -T is small order); a cofactorless check would not.
                    let g = ExtendedPoint::from(constants::SPENDING_KEY_GENERATOR);
                    let skf = Fr::from_bytes(&sk.to_bytes()).unwrap();
                    let n = rand_fr(&mut rng);
                    let tt = if i % 6 == 0 { ExtendedPoint::identity() } else { t };
                    let rb = (g * n + tt).to_bytes();
                    let h = blake2b_simd::Params::new().hash_length(64).personal(b"Zcash_RedJubjubH").to_state().update(&rb).update(&vk).update(&msg).finalize();
                    let c = Fr::from_bytes_wide(h.as_bytes().try_into().unwrap());
                    let sv = n + c * skf;
                    (if i % 6 == 0 { "manual" } else { "R=[n]G+T" }, vk, rb, sv.to_bytes())
                }
                1 => {
                    let mut sum = [0u8; 32];
                    let mut c = 0u16;
                    for k in 0..32 {
                        let x = s[k] as u16 + r_j[k] as u16 + c;
                        sum[k] = x as u8;
                        c = x >> 8;
                    }
                    ("s+r", vk, r, sum)
                }
                _ => ("vk+T", (AffinePoint::from_bytes(vk).unwrap().to_extended() + t).to_bytes(), r, s),
            };
            let v = verdict::<SpendAuth>(vk2, r2, s2, &msg);
            edge[v as usize] += 1;
            writeln!(o, "spendauth {} {} {} {} {v} edge={name}", hx(vk2), hx(r2), hx(s2), hx(msg))?;
        }
        o.flush()?;
        println!("sig.txt: {good} valid signatures, {} tampered of which {bad} rejected; edge cases: {} accepted {} rejected", good, edge[1], edge[0]);
    }
    println!("vectors written to {}", dir.display());
    Ok(())
}

fn fr_line(o: &mut BufWriter<File>, a: Fq, b: Fq) -> Result<()> {
    let inv = opt(a.invert()).map(|x| hx(x.to_bytes())).unwrap_or("none".into());
    let sq = opt(a.sqrt()).map(|x| {
        assert_eq!(x.square(), a);
        hx(x.to_bytes())
    });
    writeln!(
        o,
        "{} {} {} {} {} {} {inv} {}",
        hx(a.to_bytes()),
        hx(b.to_bytes()),
        hx((a + b).to_bytes()),
        hx((a - b).to_bytes()),
        hx((a * b).to_bytes()),
        hx(a.square().to_bytes()),
        sq.unwrap_or("none".into())
    )?;
    Ok(())
}

