//! Ground truth and Rust baselines for field3.
//!   digest   — the same N random pairs as t/diff3.bend, XOR digest of mul/sqr/add/sub/lazy
//!   bench    — 1e6 chained mul / sqr, 1e4 sqrt / inversions, BLAKE2b throughput
use ff::{Field, PrimeField};
use pasta_curves::{Fp, Fq};
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
fn fold<F: PrimeField<Repr = [u8; 32]>>(d: &mut [u32; 8], x: F) {
    let r = x.to_repr();
    for i in 0..8 { d[i] ^= u32::from_le_bytes(r[4 * i..4 * i + 4].try_into().unwrap()); }
}
fn digest<F: PrimeField<Repr = [u8; 32]>>(root: u32, depth: u32, n: usize) -> [u32; 8] {
    let mut d = [0u32; 8];
    for leaf in 0..(1u32 << depth) {
        let seed = (root << depth) | leaf;
        let mut s = seed.wrapping_mul(2654435761).wrapping_add(12345);
        for _ in 0..n {
            let t = next8(s);
            let x = F::from_repr(rw(s)).unwrap();
            let y = F::from_repr(rw(t)).unwrap();
            s = next8(t);
            fold(&mut d, x * y);
            fold(&mut d, x.square());
            fold(&mut d, x + y);
            fold(&mut d, x - y);
            fold(&mut d, (x + y) * y);
        }
    }
    d
}
fn hex(d: [u32; 8]) -> String { d.iter().flat_map(|w| w.to_le_bytes()).map(|b| format!("{b:02x}")).collect() }

fn bench() {
    let y = Fq::from(3u64);
    let t = Instant::now();
    let mut x = Fq::from(7u64);
    for _ in 0..1_000_000 { x *= y; }
    println!("rust 1e6 Fq.mul: {:.1} ms ({:?})", t.elapsed().as_secs_f64() * 1e3, x.to_repr()[0]);
    let t = Instant::now();
    let mut x = Fq::from(7u64);
    for _ in 0..1_000_000 { x = x.square(); }
    println!("rust 1e6 Fq.sqr: {:.1} ms ({:?})", t.elapsed().as_secs_f64() * 1e3, x.to_repr()[0]);
    let t = Instant::now();
    let mut x = Fq::from(7u64);
    let mut hits = 0u32;
    for i in 0..10_000u64 { x += Fq::from(i); if bool::from(x.sqrt().is_some()) { hits += 1; } }
    println!("rust 1e4 Fq.sqrt: {:.1} ms ({hits} squares)", t.elapsed().as_secs_f64() * 1e3);
    let t = Instant::now();
    let mut x = Fq::from(7u64);
    for i in 1..10_001u64 { x = x.invert().unwrap() + Fq::from(i); }
    println!("rust 1e4 Fq.inv: {:.1} ms ({:?})", t.elapsed().as_secs_f64() * 1e3, x.to_repr()[0]);
    let data = vec![0x5au8; 1 << 20];
    let t = Instant::now();
    let mut h = blake2b_simd::Params::new().hash_length(64).hash(&data);
    for _ in 0..63 { h = blake2b_simd::Params::new().hash_length(64).hash(&data); }
    let el = t.elapsed().as_secs_f64();
    println!("rust BLAKE2b-512, 64 MiB in 1 MiB messages: {:.1} ms = {:.0} MB/s ({:02x})", el * 1e3, 64.0 / el * 1.048576, h.as_bytes()[0]);
    // Equihash hashes a 140-byte header prefix plus a 4-byte index: 144 bytes, 2 blocks.
    let mut input = [0x5au8; 144];
    let t = Instant::now();
    let mut acc = 0u8;
    for i in 0..1_000_000u32 {
        input[140..].copy_from_slice(&i.to_le_bytes());
        let h = blake2b_simd::Params::new().hash_length(50).personal(b"ZcashPoW\xc8\0\0\0\t\0\0\0").hash(&input);
        acc ^= h.as_bytes()[0];
    }
    println!("rust 1e6 Equihash-style BLAKE2b (144 bytes, 2 blocks): {:.1} ms ({acc:02x})", t.elapsed().as_secs_f64() * 1e3);
}

fn main() {
    match std::env::args().nth(1).as_deref() {
        Some("digest") => {
            println!("Fp digest {}", hex(digest::<Fp>(1, 6, 15625)));
            println!("Fq digest {}", hex(digest::<Fq>(2, 6, 15625)));
        }
        Some("bench") => bench(),
        _ => eprintln!("usage: digest | bench"),
    }
}
