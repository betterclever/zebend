# perf3: profiling and runtime/data-layout work

Goal: close the remaining gap to Rust on MSM and Halo 2 verification in pure Bend.
Everything here builds with the forked compiler (`bend-fork`, branch `u32-prims`, via
`build.sh`, which emits C with `bun bend2/main.ts` and compiles it with selectable clang flags
under a memory/time guard).

| Directory | Contents |
|---|---|
| `v/`, `lib/`, `t/` | research/algo/ (round 2) sources rebuilt on `research/fast/pure` fields (`fp32`, U32.mul_hi) |
| `v64/`, `lib_64/`, `t64/` | the same sources on `field3` fields (`fp64`, U32.mac64) |
| `lib/msm_arr.bend` | experiment: array-backed batch-affine MSM (correct, slower; see below) |
| `t/final_bench3.py` | the final comparison table |

## 1. Where the time goes (macOS `sample`, emitted-C symbols)

One 2-action mainnet bundle verified in a loop, 1 thread, fp32 fields, 8,384 non-idle samples:

| Category | Share |
|---|---|
| Field multiplication (Montgomery CIOS), almost all **Fq inside curve point additions** | **66.3%** |
| MSM bookkeeping (bucket fill, tree rounds, window sums) | 15.0% |
| Bend runtime: `term_drop`, `span_fade`, `rfc_wrap` (free / refcount) | 12.1% |
| Field add/sub and point-add glue | 5.8% |
| Transcript (BLAKE2b) and input parsing | **0.3%** |

The MSM alone (n = 2048, 1 thread): field multiplication 47%, bookkeeping 24%, runtime 23%.
Batch verification (168 bundles): field multiplication 56%, MSM bookkeeping ~17%, runtime ~13%;
batching merges every proof into one big MSM, so it has the same profile.

Conclusion: verification is an MSM benchmark. BLAKE2b and parsing are irrelevant here.

## 2. What was tried

| Experiment | Result |
|---|---|
| clang flags on the emitted C: `-O3` (Apple 21 / Homebrew 23), `-mcpu=native`, `-O2` | within ±5% of Bend's default (`-std=c11 -O3`); Apple clang marginally best |
| clang PGO (`-fprofile-instr-generate` → `llvm-profdata` → `-fprofile-instr-use`) | 1–4%, within noise |
| templates / forced inlining (step 3) | no change possible: Bend already emits field helpers as `static inline` spins and clang inlines them; the polling check in each spin (`err_spun`) constant-folds away |
| parallel input parsing (step 5) | not needed: parsing is 0.3% |
| `Array<U32>` vs shared list traversal (microbenchmark) | both cheap: 0.4 ns/word walking a refcounted list of 16-word records, 0.7 ns/word reading a flat array. The MSM's runtime cost is allocation churn, not traversal |
| **array-backed batch-affine MSM** (`lib/msm_arr.bend`: buckets in one flat `Array<U32>`, in-place updates, one queued addition per bucket per pass, deferred collisions, one inversion per flush) | **correct** (matches `best_multiexp` at n = 16 / 2048 / 4096) but **slower: 53 ms vs 40 ms** (n = 2048, 1T). Passes ≈ the fullest bucket's load (~15–18 per window) instead of the tree's ~5 rounds, so ~3× more inversions; 8 array ops per field element also cost. The list-based tree in `msm_ba` stays |
| switching to `field3` fp64/fq64 (4×64-bit limbs via `U32.mac64`) | the big win; see the table. 42/42 mainnet verdicts, MSM equal to `best_multiexp`, honest batch accepted and a tampered one rejected |

## 3. Final comparison

M5 Max, one session (`t/final_bench3.py`), medians; load average 3 at the start, 15 at the end
(the genesis header fetch was running). CPU only: Metal builds of programs this size crash with
the forked compiler (a known issue with 2.0.39 via bun, independent of our patches).

Columns: **algo** = round 2 (intrinsify fp32); **fp32** = the same code on `research/fast/pure` fields;
**fp64** = the same code on `field3` fp64/fq64; Rust = `pasta_curves`, halo2 `best_multiexp`,
`orchard` verify and `BatchValidator` (proofs + signatures), `RAYON_NUM_THREADS` 1 / 18.

| Workload | algo | fp32 | **fp64** | Rust 1T | Rust 18T | fp64 ÷ Rust |
|---|---|---|---|---|---|---|
| 1M field mul, 1T (ms) | 34.0 | 39.0 | **18.0** | 14.1 | — | 1.3× |
| 1000 scalar mults, 1T (ms) | 107.0 | 109.0 | **69.0** | 83.1 ¹ | — | **0.83×** |
| MSM n=2048, 1T (ms) | 34.0 | 33.0 | **22.0** | 13.3 | — | 1.65× |
| MSM n=2048, 18T (ms) | 6.0 | 5.0 | **4.0** | — | 1.3 | 3.1× |
| Halo 2 verify, 2-action, 1T (ms/proof) | 41.9 | 41.2 | **26.6** | 20.7 | — | 1.3× |
| Halo 2 verify, 2-action, 18T (ms/proof) | 13.2 | 12.8 | **8.5** | — | 2.9 | 2.9× |
| Halo 2 verify, 16-action, 1T (ms/proof) | 79.0 | 75.8 | **46.5** | — | — | — |
| Halo 2 verify, 16-action, 18T (ms/proof) | 34.3 | 32.0 | **19.3** | — | — | — |
| Batch verify, 1T (bundles/s) ² | 62.0 | 64.9 | **113.3** | 155 | — | 1.37× |
| Batch verify, 18T (bundles/s) ² | 425.7 | 420.0 | **623.8** | — | 1,559 | 2.5× |

¹ Rust's number is `pasta_curves`' plain `Point * Scalar` (no GLV); Bend uses GLV, so this row
compares implementations as shipped, not like-for-like algorithms.
² Bend: 63 real mainnet bundles (21 post-NU6.3 bundles × 3), proofs only. Rust: 64 locally built
2-action bundles, proofs + RedPallas signatures (so Rust does slightly more work per bundle).
Bend's Halo 2 numbers are whole-process wall time divided by the in-process loop count; Rust's
single-proof number times only the verify call.

Correctness of every fp64 binary used here: `run_bundles.py` 42/42 mainnet verdicts equal
`halo2_proofs`; MSM equal to `best_multiexp` at n = 16 / 2048 / 4096; batch of 21 honest
bundles accepted, batch with one tampered bundle rejected.

Single-threaded, Bend on fp64 is now within **1.3×** of Rust on field multiplication and Halo 2
verification and **1.4×** on batch throughput, and ahead on scalar multiplication. Multi-threaded,
the gap is 2.5–3×: the MSM and the verifier scale worse than Rust's (bucket-tree allocation and
runtime frees, see §1).

## 4. What is left

- The field multiply is now close to Rust's, so the remaining gap is in the curve/MSM code:
  bucket-tree list churn and runtime frees (~35–45% of the MSM before fp64), and the
  per-proof work in batches.
- Making the bucket tree allocate less without paying more inversions (for example tree rounds
  over flat arrays, keeping the tree's ~log2(load) inversions) is the next MSM step.
- Bend-level: unboxed small records and cheaper frees in the runtime would help every phase;
  that is compiler work (upstream).
