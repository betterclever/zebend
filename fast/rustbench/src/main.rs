// 1000 chained Vesta variable-base scalar multiplications (p <- [s_i] p, s_i from xorshift),
// one thread: the same workload as t/smul_bench*.bend.
use ff::PrimeField;
use group::{prime::PrimeCurveAffine, Curve, GroupEncoding};
use pasta_curves::{vesta, Fp};

fn xs(mut s: u32) -> u32 { s ^= s << 13; s ^= s >> 17; s ^= s << 5; s }

fn main() {
    let mut p = vesta::Affine::generator().to_curve();
    let mut seed = 2463534242u32;
    let t = std::time::Instant::now();
    for _ in 0..1000 {
        let mut w = [0u8; 32];
        for i in 0..8 {
            seed = xs(seed);
            w[4 * i..4 * i + 4].copy_from_slice(&seed.to_le_bytes());
        }
        w[31] &= 0x3f; // < 2^254 < p, so the word value is the scalar
        p = p * Fp::from_repr(w).unwrap();
    }
    let el = t.elapsed();
    println!("{}", p.to_affine().to_bytes().iter().map(|b| format!("{b:02x}")).collect::<String>());
    println!("1000 scalar mults: {:.1} ms", el.as_secs_f64() * 1e3);
}
