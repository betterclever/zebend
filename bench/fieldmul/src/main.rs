// Same workload as halo2/lib/t/mulbench.bend: 1e6 chained Fq multiplications, one thread.
use ff::{Field, PrimeField};
use pasta_curves::Fq;
fn main() {
    let y = Fq::from(3u64);
    let t = std::time::Instant::now();
    let mut x = Fq::from(7u64);
    for _ in 0..1_000_000 { x *= y; }
    let el = t.elapsed();
    let r = x.to_repr();
    println!("{}", r.as_ref().iter().rev().map(|b| format!("{b:02x}")).collect::<String>());
    println!("1e6 Fq.mul: {:.1} ms", el.as_secs_f64() * 1e3);
    let _ = Fq::ONE;
}
