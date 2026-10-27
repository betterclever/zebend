#[inline(always)] fn xs(mut x: u32) -> u32 { x ^= x << 13; x ^= x >> 17; x ^= x << 5; x }
fn run(n: u64, mut x: u32) -> u32 { let mut acc = 0u32; for _ in 0..n { acc = acc.wrapping_add(x); x = xs(x); } acc }
fn main() {
    let threads: usize = std::env::args().nth(1).map(|s| s.parse().unwrap()).unwrap_or(1);
    let (chunks, n) = (64u32, 4_194_304u64);
    // thread t handles chunks t, t+T, t+2T, ... (static interleaved split, no waves)
    let total = std::thread::scope(|s| {
        let hs: Vec<_> = (0..threads).map(|t| s.spawn(move || {
            (t as u32..chunks).step_by(threads).fold(0u32, |a, i| a.wrapping_add(run(n, i + 1)))
        })).collect();
        hs.into_iter().fold(0u32, |a, h| a.wrapping_add(h.join().unwrap()))
    });
    println!("{}", total);
}
