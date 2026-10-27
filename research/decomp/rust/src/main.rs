//! Ground truth and Rust baselines for decomp (pasta_curves 0.5, default features incl. sqrt-table).
//!   check ../t/edges_fp.txt ../t/edges_fq.txt  — edge lines + 2^10 x 2^10 digests (as t/sqrt_vs_pasta)
//!   bench                                       — 1e4 sqrt (x += i), 1e4 decompress attempts
use ff::{Field, PrimeField};
use group::GroupEncoding;
use pasta_curves::{pallas, vesta, Fp, Fq};
use std::time::Instant;

fn xs(mut s: u32) -> u32 { s ^= s << 13; s ^= s >> 17; s ^= s << 5; s }
fn next8(mut s: u32) -> u32 { for _ in 0..8 { s = xs(s); } s }
fn rw(s: u32) -> [u8; 32] {
    let mut w = [0u32; 8];
    let mut t = s;
    for i in 0..8 { t = xs(t); w[i] = t; }
    w[7] &= 0x3fff_ffff;
    let mut b = [0u8; 32];
    for i in 0..8 { b[4 * i..4 * i + 4].copy_from_slice(&w[i].to_le_bytes()); }
    b
}
fn norm<F: PrimeField<Repr = [u8; 32]>>(r: F) -> F { if r.to_repr()[0] & 1 == 1 { -r } else { r } }
fn hash<F: PrimeField<Repr = [u8; 32]>>(mut h: u32, m: Option<F>) -> u32 {
    match m {
        Some(r) => {
            let b = norm(r).to_repr();
            for i in 0..8 { h = xs(h ^ u32::from_le_bytes(b[4 * i..4 * i + 4].try_into().unwrap())); }
            h
        }
        None => xs(h ^ 0xA5A5_A5A5),
    }
}
fn sq<F: PrimeField<Repr = [u8; 32]>>(x: F) -> Option<F> { Option::from(x.sqrt()) }
fn digest<F: PrimeField<Repr = [u8; 32]>>(root: u32, depth: u32, n: usize) -> (u32, u32) {
    let (mut sum, mut squares) = (0u32, 0u32);
    for leaf in 0..(1u32 << depth) {
        let mut s = ((root << depth) | leaf).wrapping_mul(2654435761).wrapping_add(777);
        for _ in 0..n {
            let x = F::from_repr(rw(s)).unwrap();
            for (seed, v) in [(s, x), (s ^ 1, x.square())] {
                let m = sq(v);
                squares += m.is_some() as u32;
                sum = sum.wrapping_add(hash(seed, m));
            }
            s = next8(s);
        }
    }
    (sum, squares)
}
fn hex(b: &[u8]) -> String { b.iter().map(|b| format!("{b:02x}")).collect() }
fn edges<F: PrimeField<Repr = [u8; 32]>>(tag: &str, path: &str) {
    for line in std::fs::read_to_string(path).unwrap().lines() {
        let mut b = [0u8; 32];
        for i in 0..32 { b[i] = u8::from_str_radix(&line[2 * i..2 * i + 2], 16).unwrap(); }
        let x = F::from_repr(b).unwrap();
        let r = sq(x).map(|r| hex(&norm(r).to_repr())).unwrap_or("none".into());
        println!("{tag} edge {line} {r}");
    }
}

fn enc(i: u32) -> [u8; 32] {
    let mut b = [0u8; 32];
    b[0..4].copy_from_slice(&(7 + i).to_le_bytes());
    if i & 1 == 1 { b[31] |= 0x80; }
    b
}

fn bench() {
    for _ in 0..3 {
        let t = Instant::now();
        let mut x = Fq::from(7u64);
        let mut hits = 0u32;
        for i in 0..10_000u64 { x += Fq::from(i); if bool::from(x.sqrt().is_some()) { hits += 1; } }
        println!("rust 1e4 Fq.sqrt: {:.1} ms ({hits} squares)", t.elapsed().as_secs_f64() * 1e3);
        let t = Instant::now();
        let mut x = Fp::from(7u64);
        let mut hits = 0u32;
        for i in 0..10_000u64 { x += Fp::from(i); if bool::from(x.sqrt().is_some()) { hits += 1; } }
        println!("rust 1e4 Fp.sqrt: {:.1} ms ({hits} squares)", t.elapsed().as_secs_f64() * 1e3);
        let t = Instant::now();
        let mut ok = 0u32;
        for i in 0..10_000u32 { ok += bool::from(vesta::Affine::from_bytes(&enc(i)).is_some()) as u32; }
        println!("rust 1e4 Vesta decompress attempts: {:.1} ms ({ok} valid)", t.elapsed().as_secs_f64() * 1e3);
        let t = Instant::now();
        let mut ok = 0u32;
        for i in 0..10_000u32 { ok += bool::from(pallas::Affine::from_bytes(&enc(i)).is_some()) as u32; }
        println!("rust 1e4 Pallas decompress attempts: {:.1} ms ({ok} valid)", t.elapsed().as_secs_f64() * 1e3);
    }
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    match a.get(1).map(|s| s.as_str()) {
        Some("check") => {
            edges::<Fp>("fp", &a[2]);
            edges::<Fq>("fq", &a[3]);
            let (d, q) = digest::<Fp>(1, 10, 1024);
            println!("fp digest {d} squares {q}");
            let (d, q) = digest::<Fq>(2, 10, 1024);
            println!("fq digest {d} squares {q}");
        }
        _ => bench(),
    }
}
