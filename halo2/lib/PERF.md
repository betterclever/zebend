# Performance: fast MSM and batch verification for the Bend Halo 2 verifier

New files only; the H1 API (`fp`, `fq`, `vesta`, `pallas`, `msm`) is untouched.

| File | What |
|---|---|
| `msm_fast.bend` | Pippenger (bucket) MSM, parallel over (window × chunk) tasks |
| `fixed.bend` | fixed-base MSM for the params generators G: precomputed window table, one bucket pass |
| `batch.bend` | batch verification support: merge K r-weighted final MSMs into one |
| `msm_fast_main.bend`, `fixed_main.bend`, `batch_main.bend` | check + benchmark drivers |
| `pip_sweep.sh`, `fixed_sweep.sh`, `perf_bench.sh` | parameter sweeps and the median-of-5 table below |
| `perf/` | Rust: batch ground truth (`batchvec K`), `best_multiexp` baseline, real Orchard verify baseline |

## API

```
# msm_fast.bend (import as MF)
MF.chunks(+cdepth: Nat, +n: U32, +ps: +List<V.Pt>, +ss: +List<Wd.W>) -> MF.CT   # 2^cdepth chunks, build once
MF.pip(+c: U32, +cdepth: Nat, +ct: MF.CT) -> V.Pt        # CPU threads
MF.pip_gpu(+c: U32, +cdepth: Nat, +ct: MF.CT) -> V.Pt    # Metal
#   c = window bits (2^c buckets), W = ceil(256 / c) windows, W * 2^cdepth parallel tasks

# fixed.bend (import as FX)
FX.table(+c: U32, +cdepth: Nat, +n: U32, +ps: +List<V.Pt>) -> FX.FT     # T_ij = [2^(jc)] G_i, once per process
FX.fixed_msm(+c: U32, +tb: FX.FT, +n: U32, +ss: +List<Wd.W>) -> V.Pt   # CPU threads
FX.fixed_msm_gpu(...)                                                  # Metal (slower, see below)

# batch.bend (import as BT)
BT.Inst{r: Fp, g: +List<Fp>, f: +List<Fp>, vp: +List<V.Pt>, vs: +List<Fp>}
    # r: batch weight; g: scalars on the 2^k params G; f: scalars on bases shared by every
    # proof (VK fixed + permutation commitments, U, W); vp/vs: this proof's own terms
BT.itree(+fuel: Nat, one: Bool, +n: U32, +xs: +List<BT.Inst>) -> BT.IT  # one = (n < 2)
BT.merge(+fuel: Nat, t: BT.IT) -> BT.Part        # parallel: sum r_i g_i, sum r_i f_i, append r_i v_i
BT.eval(+c: U32, +tb: FX.FT, +ng: U32, +fb: +List<V.Pt>, p: BT.Part) -> V.Pt
    # fixed-base G-part || Pippenger over (F ++ per-proof terms), window picked by size
```

Additions use vesta.bend's complete formulas everywhere, so identity bases, P + P and
P + (−P) inside buckets are all handled.

## Correctness

Each result is compared with halo2's `best_multiexp`:

- **Pippenger:** MATCH at n = 16, 2048 and 4096 for every one of the 21 (c, cdepth) settings swept, on GPU and CPU.
- **Fixed-base:** MATCH at n = 16 and 2048 for all 9 settings swept, on GPU and CPU.
- **Batch merge:** MATCH at K = 1, 8, 64 and 256, against the naive expansion `sum_i r_i * MSM_i` computed in Rust.
  - Each instance has 2,048 G terms (the **real** params G from `halo2/vectors/params_g.bin`), 46 shared bases and 100 per-proof terms.
  - K = 256 is 561,664 expanded terms.

## Benchmarks (Apple M5 Max, 18 cores, Metal)

The Mac was shared with other agents during these runs (load average 15–23), so absolute
numbers are noisy. Bend figures are medians of 5 warm runs. Rust figures are medians over
the same period.

### Single MSM

| | n = 2048 | n = 4096 |
|---|---|---|
| Bend double-and-add (H1 `msm`), GPU | 32 ms | 41 ms |
| Bend double-and-add (H1 `msm`), CPU 18 threads | 146 ms | 244 ms |
| **Bend Pippenger, GPU** (c=4, cdepth=6) | **22 ms** | **27 ms** |
| **Bend Pippenger, CPU 18 threads** (c=8, cdepth=0) | 15–38 ms | **24–28 ms** |
| **Bend fixed-base (G), CPU 18 threads** (c=8, cdepth=4; table 47–90 ms once) | **12–23 ms** | — |
| Bend fixed-base (G), GPU | 66 ms | — |
| Rust `best_multiexp`, 1 thread | 31 ms (15 ms on a quiet machine) | 64 ms (26 ms quiet) |
| Rust `best_multiexp`, 18 threads | 2.9 ms (1.3 ms quiet) | 4.3 ms (2.3 ms quiet) |

How the new code compares:

- **Bend's own CPU path:** Pippenger is about 6–9× faster than double-and-add (146 → ~20 ms at n = 2048, 244 → ~26 ms at n = 4096).
- **Bend's GPU path:** about 1.5× faster (32 → 22 ms, 41 → 27 ms).
- **Rust, one thread:** Bend on 18 threads now roughly matches it.
- **Rust, 18 threads:** Rust is still about 8–10× faster. Rust's field multiplication is 6.3× faster per operation (15 ns vs 95 ns), and that accounts for most of the gap.

### Batched final MSM (K proofs merged)

| K | expanded terms | Bend CPU 18 threads (merge + fixed G + Pippenger) | Rust merged MSM, 1 thread | Rust merged MSM, 18 threads |
|---|---|---|---|---|
| 1 | 2,194 | 22–38 ms | 36 ms | 2.8 ms |
| 8 | 17,552 | 27–40 ms | 46 ms | 3.5 ms |
| 64 | 140,416 | 65–84 ms | 124 ms | 11.6 ms |
| 256 | 561,664 | 403 ms (first run 910 ms) | 265 ms | 22 ms |

The Bend times above exclude file parsing (K = 256: 7.7 s, a list-of-bytes parser) and the one-time G table.

- **Throughput:** at K = 64, Bend evaluates the final MSM of about **1,000 proofs/s**, compared with about 5,500/s for Rust on 18 threads.
- **Why batching pays:** going from K = 1 to K = 64 multiplies the work by 64 but the time only by about 3, because the 2,048-term G part is paid once.

### What full verification costs in Rust (real Orchard proofs, for context)

These use unpatched `orchard` 0.16 with real Ironwood bundles, each with 2 actions.

| | time | throughput |
|---|---|---|
| single `Proof::verify` | 7.6 ms | 131 proofs/s |
| `BatchValidator` (proofs + RedPallas sigs, 18 threads), K = 1 | 10.8 ms | 93 bundles/s |
| K = 8 | 21.0 ms | 381 bundles/s |
| K = 64 | 103.6 ms | 618 bundles/s |
| K = 256 | 406.5 ms | 630 bundles/s |

At K = 256, Rust's merged MSM is 22 ms of the 406 ms. **In a batch, the per-proof
work dominates, not the MSM.** That work is the transcript (BLAKE2b), the gate,
permutation and lookup evaluation, the O(n) s-polynomial, and the IPA folding.

## Recommendations for the verifier integration

1. **Single proof:** build `FX.table(8, 4n, 2048, G)` once per process, about 50–90 ms on
   CPU threads. Then evaluate the final MSM as `fixed_msm` for the G scalars plus
   `MF.pip(5, 0n, ...)` for the roughly 125 other terms. Run both on CPU threads; together
   they cost about 20–35 ms under load.
2. **Many proofs:** don't evaluate each proof's final MSM to the identity. Collect each
   proof's (G scalars, shared-base scalars, own terms) as a `BT.Inst` with a random
   `r_i` (squeezed from a transcript over all proofs, or from OS randomness), merge with
   `BT.merge`, and check that `BT.eval` returns the identity. The MSM part then grows
   slowly with K.
3. **Parallelise the per-proof stage.** Per-proof verification up to the final MSM
   (transcript, expressions, s-polynomial) has no shared state between proofs, so put
   proofs in a balanced parallel tree, on CPU threads or the GPU with `!`. Per the Rust
   numbers, that is where batch time goes.
4. **Keep MSMs on CPU threads.** The GPU helps only for wide, uniform Pippenger
   (c = 4, cdepth = 6). The fixed-base table is a shared `+` structure, and Bend pays an
   atomic for every shared read on the GPU, so `fixed_msm_gpu` is about 3× slower than
   the CPU path.
5. **The next real speedup is the field multiplication itself** (95 ns vs 15 ns). Every
   MSM and every gate evaluation pays for it.

## Limits

- The machine was shared and noisy, so the ranges above reflect that.
- The input parser in `batch_main` is slow (a list of bytes) and is excluded from all timings.
- Pippenger uses unsigned digits and full projective additions; signed digits and affine (mixed) additions would trim roughly 10–20% more.
- The G table is computed at startup, not loaded from a file.
