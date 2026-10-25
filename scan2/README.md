# scan2: faster Ironwood trial decryption in Bend

Round 2 of `gpu-scan`: the same wallet filter (per compact output: decompress `epk`,
`S = [ivk]·epk`, `K = BLAKE2b-256("Zcash_OrchardKDF", repr(S) ‖ epk)`, ChaCha20 block 1,
lead byte `== 0x03`), rebuilt on field3's 64-bit-limb fields with the key prepared once.
**Current build (constant-time key handling, merged from `harden/scan_ct`), always-inline
Metal: ~410k outputs/s on the M5 Max GPU, about 1.2× orchard's own batch trial decryption on
all 18 CPU cores (~346k/s); 173k/s on 18 threads and 12.3k/s on 1 thread (CPU numbers are
from the earlier build; inlining only changes the Metal kernel). On the CPU, orchard is still
~2× faster.**

> **Metal re-gate, 2026-10-26 (always-inline build).** Apple's Metal compiler can corrupt
> a 32-bit word of a caller's data across a helper call it keeps (nondeterministically), so
> every shipped Metal number must come from a build whose kernel has no calls. `scan_main` is
> now built with the Bend fork's `metal-spill` branch (`c8f04a61`: every device helper
> `always_inline`, GPU lane spill restored; `bend-fork/METAL_INLINE.md`). The emitted Metal
> compiles to AIR with **1 function and 0 non-intrinsic calls** (`gpuv/t/aircalls.sh`;
> `bench/metal_inline_build.log`). Gate (`bench/metal_inline_gate.sh scan`,
> `bench/metal_inline_gate.log`): 262,144 outputs at depth 14, **20 runs, hit list MATCH
> 20/20, 1 distinct output**.
>
> Speed: warm scan **639 ms median over 20 runs (≈410k outputs/s)**, load average 4.4–4.7.
> The previous non-inlined build (kept as `scan_main.noinline`), in the same session:
> 273.5 ms median over 6 runs (≈958k outputs/s), load 4.2–4.4. The ~892k/s claim was that
> build. **Full inlining costs ≈2.3× on Metal** at every depth from 10 to 16 (depth 14: 635 vs
> 273 ms). The inlined metallib is 45 MB against 1.9 MB: the old build kept the field
> multiplication and similar spins as calls (the FAR-only perl patch from `sigbatch/build.sh`
> still leaves 18,408 non-intrinsic calls in this program's AIR, e.g. 492 to the field-mul
> spin, so it is not an option). `BEND_CUBE_LOG=6` is slower (1,127 ms). Getting the speed
> back needs the kernel restructured around few call sites of the big spins (METAL_INLINE.md,
> "Kernel size"); not done.

> **Note.** The tables below were measured on the earlier variable-time, non-inlined build (~1.2M
> outputs/s on Metal), which leaks timing that depends on the secret ivk and is therefore not
> the shipped build. A reported Metal MISMATCH for that build was a test-harness artifact (a
> fresh-compile message on stderr shifted the parsed lines): re-run with stderr separated, it
> matches orchard's hit list 20/20 with a fresh Metal compile each run
> (`bench/metal_determinism.log`). The constant-time build matches on 1 thread, 18 threads
> and Metal (20/20).

## What changed (cumulative)

1. **64-bit fields.** `../field3/fp64.bend` (4 × 64-bit limbs through the forked Bend's
   `U32.mac64`) and `../field3/lib64/pallas.bend` replace gpu-scan's 16 × 16-bit limbs.
2. **ivk prepared once, GLV ladder.** The key is the same for every output, so `prep`
   computes its GLV split `k = k1 + k2·λ` (`glv.bend`, generated from `algo/lib/gen_glv.py`)
   and the 32 pairs of 4-bit digits once. Each output then runs a fixed Straus ladder,
   32 × (4 doublings + 2 table additions), instead of 256 doublings + 256 additions. The
   second table is the first mapped through the endomorphism `φ(X:Y:Z) = (ζX:Y:Z)` (15
   field multiplications instead of 15 point additions): φ commutes with scalar
   multiplication, so table₂[i] = (−1)^(n1⊕n2) φ(table₁[i]).
3. **Batched inversion.** Each leaf converts all its results to affine with one inversion
   (Montgomery's trick). A zero `Z` is replaced by 1 before batching so one identity point
   cannot corrupt its leaf; it still encodes as all zeros, as `repr_P` requires.
4. **Tail-recursive leaf walks, lane sweep.** See "The Metal fault" below. All list walks in
   a leaf are now tail-recursive, so any lane size works; 2¹⁴–2¹⁵ leaves (one per lane of
   Metal's 16,384-lane grid) is fastest.

Not done:
- **Skipping the square root (step 3 of the plan):** `x([k]P)` depends only on `x(P)`, but
  avoiding `y` means an x-only ladder (no GLV tables, roughly twice the multiplications of
  the GLV path) plus two KDF attempts for the unknown sign of `repr(S)`. The square root is
  about 12% of an output's time (~9 µs of ~75 µs on one thread), so the x-only path would be
  slower, not faster. Kept the variable-time square root (`epk` is public).
- **Batch-affine ladder** (all outputs of a leaf stepping in lockstep with shared
  inversions per step, as orchard's `batch_mul_same_scalar_vartime` does). That is the
  remaining CPU gap to orchard; it needs the leaf restructured around per-step lists.

## Correctness

- Every run of every variant reproduces the expected hit list exactly (MATCH): gpu-scan's
  vectors at N = 4,096 / 16,384 / 65,536 / 262,144 and the new `rust/out` vectors at
  N = 65,536 / 262,144, on 1 thread, 18 threads and Metal, at every tree depth 8–16.
- The new vectors come from `rust/` (gpu-scan's generator plus `full_N.bin`). Generation
  checks every output with orchard's `try_compact_note_decryption` and with the independent
  ECDH/KDF/ChaCha pipeline. The orchard batch benchmark finds exactly the generated notes
  (1,028 of 65,536; 4,110 of 262,144).

## Speed

Apple M5 Max, outputs/s, warm scans. Bend: 1 thread at depth 8, 18 threads at depth 8,
Metal at depth 14.

**Cumulative** (gpu-scan's vectors; 1 thread on N = 16,384 (old: 4,096), 18 threads on
65,536, Metal on 262,144; medians of 3; load average 4.6–6.7; `python3 bench.py`):

| Version | 1 thread | 18 threads | Metal GPU |
|---|---|---|---|
| gpu-scan (16-bit limbs) | 1,892 | 21,948 | 301,662 |
| 1. + 64-bit fields | 7,642 | 111,646 | 759,838 |
| 2. + prepared ivk, GLV ladder | 12,652 | 179,060 | 1,170,286 |
| 3. + batched inversion | **13,234** | **189,959** | **1,202,495** |
| 4. + tail-recursive leaves (best depth 14) | same | same | 1,208,037 |

**Against Rust, same data, same session** (`rust/out`; load average 4.9–8.3):

| | 1 thread | 18 threads | Metal GPU |
|---|---|---|---|
| **Bend scan2** | 13,310–13,479 | 178,208–183,574 | **1,159,929–1,170,286** |
| Rust, independent pipeline (pasta_curves + blake2b_simd + chacha20; gpu-scan's old baseline) | 11,139–11,161 | 142,709–159,038 | — |
| **orchard batch API** (`try_compact_note_decryption`, prepared ivk; also fully validates the 1.6% found notes) | **25,801–26,105** | **338,768–354,218** | — |

- **GPU:** Bend scans 262,144 outputs in ~225 ms, ~3.3× orchard's batch API on 18 cores,
  leaving the CPU free.
- **CPU:** Bend now beats the simple pipeline (1.2×) but orchard's batch API is ~1.9× faster
  on 1 thread and on 18. orchard batches the scalar multiplications (GLV, shared affine
  normalizations) on native 64-bit arithmetic.
- gpu-scan's README compared against the simple pipeline; against orchard's batch API, its
  1-thread and 18-thread paths were ~14× and ~16× slower.

## The Metal fault in the forked Bend: root cause

Metal builds from the forked compiler (Bend 2.0.39 source) faulted with
`memory fault (machine stack overflow?)` on large programs, while Bend 2.0.38 ran them. This
is not our primitives and not the bun build. A probe with no primitives (`t/deep.bend`: every
GPU lane builds a list of length L by **non-tail** recursion) shows it:

| L (frames per lane) | 2.0.38 | 2.0.39 (fork) |
|---|---|---|
| 256 | OK | OK |
| 1,024 | OK | memory fault |

2.0.38's emitted C has `lane_spill()`, which moves a full GPU lane stack to the heap.
Upstream commit `5ce1e07f` ("Remove the Metal lane spill (#1439): `bend -o` of a `!`
program built 17% slower", #1809, 2026-10-21) removed it, so since 2.0.39 a lane faults past
~1,023 frames of non-tail recursion. scan2 first hit it at ≤ 2¹² leaves (64+ outputs per lane
through non-tail list walks); making those walks tail-recursive fixed every depth.

## Caveats

- **Constant time in the key** (merged from harden/scan_ct). Every ivk-dependent table
  lookup reads all 16 entries through masked selects, and the GLV signs are applied by
  masked select, so the work per output does not depend on ivk. The earlier digit-indexed
  lookups were measurably key-dependent (~1.5%); the cost of the fix is in
  harden/README.md (−3% 1T, −6% 18T, −20% Metal at the time of measurement). The
  throughput tables above were measured before this change.
- The variable-time square root is used only on `epk`, which is public.
- Built with the forked Bend (`../../bend-fork`, branch `metal-spill` at `c8f04a61`, which is
  `u64-rot` (with `U32.mac64`) plus the lane spill and always-inline Metal), via `./build.sh`
  (it uses whatever branch the fork has checked out). Earlier builds predate `metal-spill` and
  are not inline-gated; none of the Metal numbers in the tables below are.

## Files and commands

- `gen.py` → `kdf.bend` (BLAKE2b / ChaCha20 from gpu-scan) and `glv.bend` (GLV for Pallas on
  field3's fields)
- `scan.bend` (the filter), `scan_main.bend` (driver, same batch format as gpu-scan)
- `scan_v1.bend` / `scan_v2.bend` + `scan_main_v1/_v2.bend`: step 1 and step 2 variants for
  the cumulative table
- `run.sh BIN N DEPTH [+RTS ...]` (one scan, checks the hit list; `VDIR` picks the vectors),
  `bench.py` (cumulative table)
- `rust/`: vectors (`gen N`, now also `full_N.bin`), `bench N` (simple pipeline),
  `bench-orchard N` (orchard batch API)
- `t/deep.bend`: the lane-stack probe

```sh
python3 gen.py
./guard.sh 5000 400 ./build.sh scan_main.bend scan_main
./run.sh ./scan_main 262144 14                          # Metal
./run.sh ./scan_main 262144 8 +RTS --gpu off -RTS       # 18 CPU threads
(cd rust && cargo run --release -- gen 65536 && cargo run --release -- bench-orchard 65536)
VDIR=rust/out ./run.sh ./scan_main 65536 8 +RTS --gpu off --threads 1 -RTS
```
