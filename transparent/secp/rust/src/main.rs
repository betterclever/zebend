//! secp-vectors OUT N: writes OUT (mode-3 records for secp_t) and OUT.expect, the verdicts of
//! libsecp256k1 (via rust secp256k1 0.33) as zcash_script uses it:
//! `PublicKey::from_slice(pk)` then `ecdsa::verify(normalize_s(sig), Message::from_digest(msg), pk)`.
//! A record's r, s are 32-byte big-endian integers; r or s >= n reads as 0 (libsecp256k1's DER
//! parser does that), so the expected verdict is false for them.
//! `secp-vectors bench N` times N verifications.
use rand::{Rng, RngCore, SeedableRng};
use secp256k1::{ecdsa, Message, PublicKey, Secp256k1, SecretKey};
use std::io::Write;

const N: [u8; 32] = [
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE,
    0xBA, 0xAE, 0xDC, 0xE6, 0xAF, 0x48, 0xA0, 0x3B, 0xBF, 0xD2, 0x5E, 0x8C, 0xD0, 0x36, 0x41, 0x41,
];
const P: [u8; 32] = [
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFC, 0x2F,
];

fn verdict(pk: &[u8], r: &[u8; 32], s: &[u8; 32], msg: &[u8; 32]) -> (bool, String) {
    let dec = match PublicKey::from_slice(pk) {
        Ok(p) => {
            let u = p.serialize_uncompressed();
            let h: String = u[1..].iter().map(|b| format!("{:02x}", b)).collect();
            Some((p, h))
        }
        Err(_) => None,
    };
    let mut compact = [0u8; 64];
    let ok_rs = r.as_slice() < N.as_slice() && s.as_slice() < N.as_slice();
    compact[..32].copy_from_slice(r);
    compact[32..].copy_from_slice(s);
    let v = match (&dec, ok_rs) {
        (Some((p, _)), true) => match ecdsa::Signature::from_compact(&compact) {
            Ok(mut sig) => {
                sig.normalize_s();
                ecdsa::verify(&sig, Message::from_digest(*msg), p).is_ok()
            }
            Err(_) => false,
        },
        _ => false,
    };
    (v, dec.map(|d| d.1).unwrap_or_else(|| "none".into()))
}

fn neg_s(s: &[u8; 32]) -> [u8; 32] {
    // n - s (s < n, s != 0)
    let mut out = [0u8; 32];
    let mut borrow = 0i32;
    for i in (0..32).rev() {
        let d = N[i] as i32 - s[i] as i32 - borrow;
        borrow = if d < 0 { 1 } else { 0 };
        out[i] = (d + 256 * borrow) as u8;
    }
    out
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let secp = Secp256k1::new();
    let mut rng = rand::rngs::StdRng::seed_from_u64(0x5ec9);
    if args[1] == "bench" {
        let n: usize = args[2].parse().unwrap();
        let sk = SecretKey::new(&mut rng);
        let pk = PublicKey::from_secret_key(&sk);
        let msgs: Vec<[u8; 32]> = (0..n).map(|_| rng.random()).collect();
        let sigs: Vec<_> = msgs.iter().map(|m| secp.sign_ecdsa(Message::from_digest(*m), &sk)).collect();
        let t = std::time::Instant::now();
        let mut ok = 0;
        for (m, s) in msgs.iter().zip(&sigs) {
            ok += secp.verify_ecdsa(Message::from_digest(*m), s, &pk).is_ok() as usize;
        }
        let dt = t.elapsed();
        println!("{} verifications ({} ok) in {:?}: {:.1} us each", n, ok, dt, dt.as_secs_f64() * 1e6 / n as f64);
        let cpk = pk.serialize();
        let t = std::time::Instant::now();
        for _ in 0..n {
            std::hint::black_box(PublicKey::from_slice(std::hint::black_box(&cpk)).unwrap());
        }
        println!("{} compressed-key decodes in {:?}", n, t.elapsed());
        return;
    }
    let out = &args[1];
    let n: usize = args[2].parse().unwrap();
    let mut f = std::fs::File::create(out).unwrap();
    let mut e = std::fs::File::create(format!("{out}.expect")).unwrap();
    f.write_all(&[3]).unwrap();
    let mut cases = 0;
    let mut valid = 0;
    let mut emit = |pk: &[u8], r: &[u8; 32], s: &[u8; 32], m: &[u8; 32], f: &mut std::fs::File, e: &mut std::fs::File| {
        f.write_all(&[pk.len() as u8]).unwrap();
        f.write_all(pk).unwrap();
        f.write_all(r).unwrap();
        f.write_all(s).unwrap();
        f.write_all(m).unwrap();
        let (v, d) = verdict(pk, r, s, m);
        writeln!(e, "v {} d {}", v as u8, d).unwrap();
        cases += 1;
        valid += v as usize;
    };
    for i in 0..n {
        let sk = SecretKey::new(&mut rng);
        let pk = PublicKey::from_secret_key(&sk);
        let msg: [u8; 32] = rng.random();
        let sig = secp.sign_ecdsa(Message::from_digest(msg), &sk).serialize_compact();
        let mut r = [0u8; 32];
        let mut s = [0u8; 32];
        r.copy_from_slice(&sig[..32]);
        s.copy_from_slice(&sig[32..]);
        let c = pk.serialize();
        let u = pk.serialize_uncompressed();
        let mut hy = u;
        hy[0] = 6 | (u[64] & 1);
        let mut hy_bad = hy;
        hy_bad[0] ^= 1;
        match i % 16 {
            0 => emit(&c, &r, &s, &msg, &mut f, &mut e),
            1 => emit(&u, &r, &s, &msg, &mut f, &mut e),
            2 => emit(&hy, &r, &s, &msg, &mut f, &mut e),
            3 => emit(&hy_bad, &r, &s, &msg, &mut f, &mut e),
            4 => emit(&c, &r, &neg_s(&s), &msg, &mut f, &mut e), // high-S: valid after normalization
            5 => {
                let mut m2 = msg;
                m2[rng.random_range(0..32)] ^= 1 << rng.random_range(0..8);
                emit(&c, &r, &s, &m2, &mut f, &mut e)
            }
            6 => {
                let mut r2 = r;
                r2[rng.random_range(0..32)] ^= 1 << rng.random_range(0..8);
                emit(&c, &r2, &s, &msg, &mut f, &mut e)
            }
            7 => {
                let mut s2 = s;
                s2[rng.random_range(0..32)] ^= 1 << rng.random_range(0..8);
                emit(&u, &r, &s2, &msg, &mut f, &mut e)
            }
            8 => {
                // compressed key with the other parity: a different point
                let mut c2 = c;
                c2[0] ^= 1;
                emit(&c2, &r, &s, &msg, &mut f, &mut e)
            }
            9 => {
                // random x: on the curve about half the time
                let mut c2 = c;
                rng.fill_bytes(&mut c2[1..]);
                emit(&c2, &r, &s, &msg, &mut f, &mut e)
            }
            10 => {
                // uncompressed key off the curve
                let mut u2 = u;
                u2[64] ^= 1;
                emit(&u2, &r, &s, &msg, &mut f, &mut e)
            }
            11 => {
                // x >= p (p .. p + small) in a compressed key
                let mut c2 = [0u8; 33];
                c2[0] = 2 + (i as u8 & 1);
                c2[1..].copy_from_slice(&P);
                c2[32] = c2[32].wrapping_add(rng.random_range(0..3));
                emit(&c2, &r, &s, &msg, &mut f, &mut e)
            }
            12 => {
                // r or s = 0, or >= n
                let z = [0u8; 32];
                let big = N;
                let mut ff = [0xffu8; 32];
                ff[0] = 0xff;
                match (i / 16) % 4 {
                    0 => emit(&c, &z, &s, &msg, &mut f, &mut e),
                    1 => emit(&c, &r, &z, &msg, &mut f, &mut e),
                    2 => emit(&c, &big, &s, &msg, &mut f, &mut e),
                    _ => emit(&c, &r, &ff, &msg, &mut f, &mut e),
                }
            }
            13 => {
                // wrong lengths / prefixes
                let bad: Vec<u8> = match (i / 16) % 5 {
                    0 => c[..32].to_vec(),
                    1 => u[..64].to_vec(),
                    2 => { let mut x = c; x[0] = 4; x.to_vec() }
                    3 => { let mut x = u; x[0] = 5; x.to_vec() }
                    _ => vec![],
                };
                emit(&bad, &r, &s, &msg, &mut f, &mut e)
            }
            14 => {
                // msg >= n (reduced mod n by the verifier): sign the reduced value, verify with the raw one
                let mut m = [0xffu8; 32];
                rng.fill_bytes(&mut m[20..]);
                let sig2 = secp.sign_ecdsa(Message::from_digest(m), &sk).serialize_compact();
                let mut r2 = [0u8; 32];
                let mut s2 = [0u8; 32];
                r2.copy_from_slice(&sig2[..32]);
                s2.copy_from_slice(&sig2[32..]);
                emit(&c, &r2, &s2, &m, &mut f, &mut e)
            }
            _ => {
                // another key's signature
                let sk2 = SecretKey::new(&mut rng);
                let pk2 = PublicKey::from_secret_key(&sk2);
                emit(&pk2.serialize(), &r, &s, &msg, &mut f, &mut e)
            }
        }
    }
    eprintln!("{cases} cases, {valid} valid");
}
