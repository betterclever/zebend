# algo: pure-Bend algorithmic speedups for Pasta / Halo 2

Builds on `research/fast/` (32-bit-limb fields with the `mulhi`/`mach`/`addc`/`subb` intrinsics). Everything here is
pure Bend: no new C intrinsics. Field modules are imported through one alias per file (`B`, `Fp`, `Fq`), so
`research/fast/pure/` fields can be swapped in. Machine: M5 Max (18 cores), medians, shared machine (load 4–8).

## Results, step by step

| Step | Workload | Before | After | Speedup | Correctness evidence |
|---|---|---|---|---|---|
| 1. GLV endomorphism | 1,000 chained Vesta scalar mults, 1 thread | 187 ms | **113 ms** | 1.65× | GLV vs validated double-and-add: 0/300 random + 0/34 edge mismatches, Vesta and Pallas; final point identical to Rust's |
| 2. MSM: signed digits + batch-affine buckets + carry-free recoding | n = 2048, 1 thread | 55 ms | **36 ms** | 1.53× | equals halo2 `best_multiexp` at n = 16 / 2048 / 4096 |
| | n = 2048, 18 threads | 6 ms | **5 ms** | 1.2× | |
| | n = 2048, Metal GPU | 32–89 ms (old `pip_gpu`) | 1,350 ms | **regression** | correct, but GPU-hostile (see notes); keep the old MSM on GPU |
| 3. Fixed-base tables for G | — | — | — | **not done** | see notes |
| 4. Verifier: new MSM + GLV + no-inversion transcript absorb + wide parallel instance commitments | 2-action mainnet bundle, 1 thread | 66 ms | **43 ms** | 1.53× | 42/42 mainnet verdicts (honest + tampered) equal `halo2_proofs` |
| | 2-action, 18 threads | 15 ms | **11 ms** | 1.36× | |
| | 16-action, 1 thread | 118 ms | **81 ms** | 1.46× | |
| | 16-action, 18 threads | 60 ms | **31 ms** | 1.94× | |
| 5. Batch verification (merged final MSM, random 128-bit weights) | 2-action bundles, 1 thread, K = 64 | 43 ms/bundle | **9.7 ms/bundle (103/s)** | 4.4× | honest K = 1/8/21/32/64 accepted; K = 21 with one tampered mainnet bundle rejected; with tampered H0 rejected |
| | 2-action bundles, 18 threads, K = 64 | 11 ms/bundle | **1.16 ms/bundle (865/s)** | 9.5× | |

Verifier thread scaling (in-process, ms per bundle):

| threads | 1 | 2 | 4 | 8 | 18 |
|---|---|---|---|---|---|
| 2 actions, before | 66 | 38 | 24 | 19 | 15 |
| 2 actions, after | 43 | 26 | 17 | 13 | 11 |
| 16 actions, before | 118 | 86 | 71 | 64 | 60 |
| 16 actions, after | 81 | 53 | 39 | 34 | 31 |

## Bend vs Rust (same machine)

| Workload | Bend now | Rust 1 thread | Rust 18 threads | Gap |
|---|---|---|---|---|
| 1,000 scalar mults (1 thread) | 113 ms | 83 ms (no GLV) | — | 1.36× |
| MSM n = 2048 | 36 ms (1T) / 5 ms (18T) | 13.7 ms | 1.3 ms | 2.6× / 3.8× |
| Halo 2 verify, one 2-action bundle | 43 ms (1T) / 11 ms (18T) | 20.7 ms | 2.9–3.1 ms | 2.1× / 3.6× |
| Batch, 2-action bundles, K = 64 | 103/s (1T) / 865/s (18T) | 153/s | 1,527/s | 1.5× / 1.8× |

Rust's `BatchValidator` numbers include RedPallas signature verification; Bend's batch is proofs only, so
the true gap is somewhat larger than shown.

## Notes

- **GPU.** The batch-affine MSM has ~29 window tasks, each running sequential list/array work (bucket
  lists, per-round batch inversion). That is the wrong shape for GPU lanes: 1.35 s on Metal versus 5 ms on
  18 CPU threads. The old `research/fast/lib32/msm_fast.bend` `pip_gpu` remains the GPU path.
- **Step 3 not done.** A fixed-base table for the 2,048 IPA generators needs ~2048 × 29 window multiples
  (~600k doublings) per process unless loaded from disk, and reading a 3 MB table through Bend byte lists is
  itself slow. For single verifications that costs more than it saves; in batch mode the G part is already
  paid once per batch. A disk-cached table would be the way to do it.
- **Bend scheduler.** An early narrow fork (2 instance-commitment tasks for a 2-action bundle) pinned the
  later wide MSM forks to few cores: the 18-thread time went 15 → 43 ms. Making that fork wide (one task per
  instance product: 20 tasks for 2 actions, 160 for 16) fixed it. Bend's static fork dealing rewards forks
  that are wide from the first split.
- **Bend compiler hazards.**
  - A chain of reused `+` lets (e.g. eight chained xorshift steps feeding a large call) blew the checker
    to >12 GB. The fix is to put each step in its own `def`.
  - Any program containing the generated Halo 2 verifier needs ~5–8 GB to compile.
  - `t/guard.sh` kills a compile past a time/RSS limit.
- **`research/fast/build.sh` bug.** It enables Metal only when `#define BANGS 1`; programs with two or more `!`
  sites (`BANGS 2`) were silently built CPU-only. `research/algo/build.sh` uses `BANGS [1-9]`.
- **Circuit versions.** `v/` is the post-NU6.3 (Ironwood/Orchard) verifier, the circuit for every
  transaction since NU6.3. The NU6.2 / pre-NU6.2 sets need their own verifying keys and are not built here.

## Files

- `lib/gen_glv.py` → `lib/glv_vesta.bend`, `lib/glv_pallas.bend`: GLV split (pasta_curves' Babai constants)
  + 4-bit Straus ladder.
- `lib/msm_ba.bend`: batch inversion, normalisation, signed digits, batch-affine buckets, `msm9` (carry-free,
  CPU) and `msm` (with carries).
- `v/`: verifier copy (`orchard_ba.bend`, `vlib.bend`), CLI `bundle_ba.bend`, in-process timer
  `loop_ba.bend`, batch verifier `orchard_bt.bend` + `bt.bend` + `batch_main.bend`.
- `t/`: GLV differential tests, `smul_glv.bend` (bench), `msm_ba_main.bend` (MSM check/bench),
  `msm_ba_loop.bend` (profiling), `guard.sh`.
- `prof/loop_main.bend`: the previous verifier timed the same way, for before/after numbers.

Reproduce (Mac, `PATH=/opt/homebrew/opt/llvm/bin:$PATH`, one compile at a time):

```sh
./build.sh t/glv_test_vesta.bend t/glv_test_vesta && t/glv_test_vesta
./build.sh v/bundle_ba.bend v/bundle_ba && (cd ../../zcash/halo2/verifier && python3 run_bundles.py ../../algo/v/bundle_ba data/bundles)
./build.sh v/batch_main.bend v/batch_main && (cd ../../zcash/halo2/verifier/data && ../../../algo/v/batch_main params_g.bin bundles/*.ironwood.bin)
```
