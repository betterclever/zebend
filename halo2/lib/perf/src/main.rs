//! Ground truth and Rust baselines for the Bend Halo 2 performance work.
//!
//!   cargo run --release -- batchvec K     # out/batch_K.bin: K halo2-shaped final-MSM instances
//!   cargo run --release -- bench-msm N    # halo2 best_multiexp, 1 and all threads
//!   cargo run --release -- bench-verify K # real Orchard proofs: single verify and BatchValidator
//!
//! A halo2 IPA final MSM has three kinds of bases: the 2^k params generators G (fixed),
//! bases shared by every proof of the circuit (VK fixed/permutation commitments, U, W),
//! and per-proof commitments (advice, lookups, h pieces, the IPA's L_j / R_j). A batch
//! of K proofs scales instance i by a random r_i and adds everything into one MSM, so
//! scalars on G and on the shared bases merge. `batchvec` writes exactly that shape,
//! using the real params G exported by halo2/oracle.

use std::{fs, time::Instant};

use ff::{Field, PrimeField};
use group::{Curve, Group, GroupEncoding};
use halo2_proofs::arithmetic::best_multiexp;
use pasta_curves::{vesta, Fp};
use rand::SeedableRng;
use rand_chacha::ChaCha20Rng;

const N_F: usize = 46; // 29 fixed + 15 permutation commitments + U + W
const N_V: usize = 100; // per-proof commitments + IPA rounds, rounded

fn params_g() -> Vec<vesta::Affine> {
    let raw = fs::read("../../vectors/params_g.bin").expect("halo2/vectors/params_g.bin (run halo2/oracle)");
    raw.chunks(32)
        .map(|c| vesta::Affine::from_bytes(c.try_into().unwrap()).unwrap())
        .collect()
}

fn random_points(n: usize, rng: &mut ChaCha20Rng) -> Vec<vesta::Affine> {
    let pts: Vec<vesta::Point> = (0..n).map(|_| vesta::Point::random(&mut *rng)).collect();
    let mut aff = vec![vesta::Affine::default(); n];
    vesta::Point::batch_normalize(&pts, &mut aff);
    aff
}

fn batchvec(k: usize) {
    let mut rng = ChaCha20Rng::seed_from_u64(k as u64 + 7);
    let g = params_g();
    let f = random_points(N_F, &mut rng);
    let mut out = Vec::new();
    for x in [k, g.len(), N_F, N_V] {
        out.extend_from_slice(&(x as u32).to_le_bytes());
    }
    for b in g.iter().chain(&f) {
        out.extend_from_slice(&b.to_bytes());
    }
    // Expected: the naive expansion sum_i r_i * (sum g_ij G_j + sum f_ik F_k + sum v_il V_il).
    let mut bases: Vec<vesta::Affine> = Vec::new();
    let mut coeffs: Vec<Fp> = Vec::new();
    for _ in 0..k {
        let r = Fp::random(&mut rng);
        out.extend_from_slice(&r.to_repr());
        for gb in &g {
            let s = Fp::random(&mut rng);
            out.extend_from_slice(&s.to_repr());
            bases.push(*gb);
            coeffs.push(r * s);
        }
        for fb in &f {
            let s = Fp::random(&mut rng);
            out.extend_from_slice(&s.to_repr());
            bases.push(*fb);
            coeffs.push(r * s);
        }
        for vb in random_points(N_V, &mut rng) {
            let s = Fp::random(&mut rng);
            out.extend_from_slice(&vb.to_bytes());
            out.extend_from_slice(&s.to_repr());
            bases.push(vb);
            coeffs.push(r * s);
        }
    }
    let want = best_multiexp(&coeffs, &bases);
    out.extend_from_slice(&want.to_bytes());
    fs::create_dir_all("out").unwrap();
    fs::write(format!("out/batch_{k}.bin"), &out).unwrap();
    println!("wrote out/batch_{k}.bin ({} bytes, {} expanded terms); expected {}", out.len(), coeffs.len(), hex(&want.to_bytes()));

    // Rust timing of the same merged computation (merge scalars, then one MSM).
    for threads in [1, rayon::current_num_threads()] {
        let pool = rayon::ThreadPoolBuilder::new().num_threads(threads).build().unwrap();
        let mut times = vec![];
        for _ in 0..5 {
            let t = Instant::now();
            let r = pool.install(|| merged_msm(k, &g, &f, &bases, &coeffs));
            assert_eq!(r, want);
            times.push(t.elapsed().as_secs_f64() * 1e3);
        }
        times.sort_by(|a, b| a.partial_cmp(b).unwrap());
        println!("rust merged batch MSM K={k} threads={threads}: median {:.3} ms", times[2]);
    }
}

/// The merged form a batch verifier evaluates: G and shared-base scalars summed across
/// instances, per-proof terms appended. (The scalars here are already r-scaled.)
fn merged_msm(k: usize, g: &[vesta::Affine], f: &[vesta::Affine], bases: &[vesta::Affine], coeffs: &[Fp]) -> vesta::Point {
    let per = g.len() + f.len() + N_V;
    let mut gs = vec![Fp::ZERO; g.len()];
    let mut fs_ = vec![Fp::ZERO; f.len()];
    let mut vb = Vec::with_capacity(k * N_V);
    let mut vs = Vec::with_capacity(k * N_V);
    for i in 0..k {
        let o = i * per;
        for j in 0..g.len() {
            gs[j] += coeffs[o + j];
        }
        for j in 0..f.len() {
            fs_[j] += coeffs[o + g.len() + j];
        }
        for j in 0..N_V {
            vb.push(bases[o + g.len() + f.len() + j]);
            vs.push(coeffs[o + g.len() + f.len() + j]);
        }
    }
    let mut all_b: Vec<vesta::Affine> = g.to_vec();
    all_b.extend_from_slice(f);
    all_b.extend(vb);
    let mut all_s = gs;
    all_s.extend(fs_);
    all_s.extend(vs);
    best_multiexp(&all_s, &all_b)
}

fn bench_msm(n: usize) {
    let mut rng = ChaCha20Rng::seed_from_u64(n as u64);
    let bases = random_points(n, &mut rng);
    let coeffs: Vec<Fp> = (0..n).map(|_| Fp::random(&mut rng)).collect();
    for threads in [1, rayon::current_num_threads()] {
        let pool = rayon::ThreadPoolBuilder::new().num_threads(threads).build().unwrap();
        let mut times = vec![];
        for _ in 0..9 {
            let t = Instant::now();
            std::hint::black_box(pool.install(|| best_multiexp(&coeffs, &bases)));
            times.push(t.elapsed().as_secs_f64() * 1e3);
        }
        times.sort_by(|a, b| a.partial_cmp(b).unwrap());
        println!("rust best_multiexp n={n} threads={threads}: median {:.3} ms", times[4]);
    }
}

fn bench_verify(k: usize) {
    use orchard::{
        builder::{Builder, BundleType},
        bundle::{Authorized, BatchValidator, BundleVersion},
        circuit::{Instance, OrchardCircuitVersion, ProvingKey},
        keys::{FullViewingKey, Scope, SpendingKey},
        tree::Anchor,
        value::NoteValue,
        Bundle,
    };
    let mut rng = rand::rngs::StdRng::seed_from_u64(20261024);
    let t = Instant::now();
    let pk = ProvingKey::build(OrchardCircuitVersion::PostNu6_3);
    let vk = pk.verifying_key();
    println!("keygen {:.0} ms", t.elapsed().as_secs_f64() * 1e3);
    let sk = SpendingKey::from_bytes([7u8; 32]).unwrap();
    let recipient = FullViewingKey::from(&sk).address_at(0u32, Scope::External);
    let version = BundleVersion::ironwood_v3();
    let sighash = [0x42u8; 32];
    let t = Instant::now();
    let bundles: Vec<Bundle<Authorized, i64>> = (0..k)
        .map(|i| {
            let mut b = Builder::new(BundleType::DEFAULT, version, version.default_flags(), Anchor::empty_tree()).unwrap();
            b.add_output(None, recipient, NoteValue::from_raw(1_000 + i as u64), [0u8; 512]).unwrap();
            b.add_output(None, recipient, NoteValue::from_raw(2_000 + i as u64), [0u8; 512]).unwrap();
            let (u, _) = b.build::<i64>(&mut rng).unwrap().unwrap();
            u.create_proof(&pk, &mut rng).unwrap().apply_signatures(&mut rng, sighash, &[]).unwrap()
        })
        .collect();
    println!("built and proved {k} bundles (2 actions each) in {:.0} ms", t.elapsed().as_secs_f64() * 1e3);

    // Single-proof verification, one at a time.
    let mut times = vec![];
    for b in bundles.iter().take(9.min(k)) {
        let instances: Vec<Instance> = b.actions().iter().map(|a| a.to_instance(*b.flags(), *b.anchor())).collect();
        let t = Instant::now();
        b.authorization().proof().verify(&vk, &instances).unwrap();
        times.push(t.elapsed().as_secs_f64() * 1e3);
    }
    times.sort_by(|a, b| a.partial_cmp(b).unwrap());
    println!("rust orchard single proof verify (2 actions): median {:.3} ms", times[times.len() / 2]);

    // Batch validation (proofs + RedPallas signatures), across all threads.
    for kk in [1usize, 8, 64, 256].into_iter().filter(|&x| x <= k) {
        let mut times = vec![];
        for _ in 0..3 {
            let mut v = BatchValidator::new(&vk);
            for b in bundles.iter().take(kk) {
                v.add_bundle(b, sighash);
            }
            let t = Instant::now();
            assert!(v.validate(&mut rng));
            times.push(t.elapsed().as_secs_f64() * 1e3);
        }
        times.sort_by(|a, b| a.partial_cmp(b).unwrap());
        println!(
            "rust orchard BatchValidator K={kk} bundles (proofs + signatures, all threads): median {:.1} ms = {:.0} bundles/s",
            times[1],
            kk as f64 / (times[1] / 1e3)
        );
    }
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let arg = |i: usize| args.get(i).and_then(|s| s.parse().ok()).unwrap_or(1);
    match args.get(1).map(String::as_str) {
        Some("batchvec") => batchvec(arg(2)),
        Some("bench-msm") => bench_msm(arg(2)),
        Some("bench-verify") => bench_verify(arg(2)),
        _ => eprintln!("usage: batchvec K | bench-msm N | bench-verify K"),
    }
}
