# Thread scaling: Bend (32-bit limbs + intrinsics) vs Rust

M5 Max (18 cores), medians, wall-clock unless noted; load average ~5 (Halo 2, MSM) and ~15–23 (tree).
Reproduce: `python3 research/bench/scaling.py` (Halo 2, MSM, Rust); tree with `research/fast/state32/tree_main`.

| Workload | 1 thread | 2 | 4 | 8 | 18 | 1→18 |
|---|---|---|---|---|---|---|
| Bend MSM n=2048 (Pippenger, c=8, in-program timer) | 54 ms | 28 | 14 | 8 | 5 ms | 10.8× |
| Rust `best_multiexp` n=2048 | 13.7 ms | 7.4 | 3.7 | 2.2 | 1.3 ms | 10.4× |
| Bend Halo 2 verify, 2-action mainnet bundle | 70.6 ms | 43.3 | 29.6 | 24.2 | 21.2 ms | 3.3× |
| Rust orchard verify, 2-action bundle (verify call only) | 20.9 ms | 11.1 | 6.0 | 3.9 | 3.1 ms | 6.7× |
| Bend Halo 2 verify, 16-action mainnet bundle | 121.5 ms | 90.8 | 74.9 | 69.6 | 66.1 ms | 1.8× |
| Bend Ironwood tree, 838,662 mainnet notes (6/6 roots MATCH) | — | — | 56 s | 33 s | 25 s | 2.2× (4→18) |

- The MSM scales like Rust's; Bend stays ~3.8× behind at every thread count (per-core cost).
- The Halo 2 verifier scales poorly because the generated code runs actions sequentially and the
  transcript, parsing and decompression are serial. Bend process times include process start and
  input parsing; Rust's verify number times only the verify call.
