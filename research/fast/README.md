# fast: 64-bit multiply intrinsics for Bend crypto

Bend 2 has only `U32` integers, so our Pasta field arithmetic used 16 limbs of 16 bits
(every partial product had to fit in a U32): 256 limb products per field multiplication
plus branch-free carry chains. This directory adds four **intrinsics**, pure Bend
definitions that a post-processor lowers to single 64-bit expressions in Bend's emitted C,
and rebuilds the fields on 8 limbs of 32 bits.

| intrinsic (intrinsics.bend) | meaning (pure Bend definition) | lowered to |
|---|---|---|
| `mulhi(a, b)` | high 32 bits of a·b, via four 16×16 products | `((u64)a * b) >> 32` |
| `mach(a, b, c, d)` | high 32 bits of a·b + c + d | `((u64)a * b + c + d) >> 32` |
| `addc(x, y, z)` | carry out of x + y + z | `((u64)x + y + z) >> 32` |
| `subb(x, y, z)` | borrows out of x − y − z | `0 - (u32)(((u64)x - y - z) >> 32)` |

The low halves need no intrinsic: they are ordinary wrapping `U32` arithmetic.

## How it works

1. Bend compiles a U32-only def into an `INLINE spin_N(Env, Term* o, u32 r0, ...)` C function
   whose locals keep the Bend names (`_al_0`, `_qs2_0`, `_wc2_0`, ...).
2. `intrinsify.py` finds each intrinsic's spin function by those names, reads its parameter
   names from the frame, and replaces only the body. Anything unexpected (a changed frame,
   a missing intrinsic) is a hard failure, not a silent skip.
3. `build.sh` = `bend -o x.c` → `intrinsify.py` → clang with the same flags `bend -o` uses
   (`-std=c11 -O3 … -lpthread -lm`, plus `-DBEND_METAL=1 -x objective-c -fobjc-arc -fmodules`
   for programs with `!`). The binary embeds its own C file (`#embed __FILE__`) and compiles it
   as the Metal program, so the GPU runs the same patched intrinsics as the CPU.
4. `gen_field32.py` emits `fp32.bend` / `fq32.bend` (same API and Montgomery form R = 2²⁵⁶ as
   `zcash/halo2/lib/fp.bend`), CIOS Montgomery multiplication on 32-bit limbs.
5. `port32.py` copies the curve, MSM and Halo 2 verifier modules onto the new fields:
   import paths change, and the 122 embedded 16-limb field literals become 8-limb ones
   (exact: same R, so w_i = l_{2i} | l_{2i+1} << 16). `state32/` is the Sinsemilla tree, ported
   the same way.

## Correctness

| check | result |
|---|---|
| intrinsics vs pure definitions (`t/intrinsics_diff.bend`): 1,000 edge triples + 2²⁴ random inputs, × 4 intrinsics | **0 mismatches**; a deliberately broken patch gives 1,786 + 33,554,432 |
| `fp32` / `fq32` vs `pasta_curves` vectors (`t/field_tests32`) | **116/116**, patched and unpatched (pure Bend) builds |
| Vesta/Pallas on the new fields vs `pasta_curves` (`t/curve_tests32`) | **136/136** |
| Pippenger MSM n = 2048 vs halo2 `best_multiexp` | **MATCH** for every (c, cdepth) tried, CPU and Metal GPU |
| Halo 2 verifier on the new fields, 42 mainnet bundles (honest + tampered) | **42/42 verdicts equal `halo2_proofs`** |
| 1000 chained scalar mults: Bend 16-bit, Bend 32-bit, Rust `pasta_curves` | identical final point |
| Mainnet Ironwood tree, 838,662 notes, on the new fields | **6/6 chain roots MATCH** (CPU threads and GPU) |

## Speed: Bend vs Rust (M5 Max, medians)

The machine was shared with other agents; load average is noted per run (4–12 for most,
spiking to 62 during the tree run, which is therefore the noisiest row).

| workload | Bend 16-bit (before) | **Bend 32-bit + intrinsics** | Rust 1 thread | Rust all threads | Bend new ÷ Rust (1T) |
|---|---|---|---|---|---|
| 1M chained Fq multiplications, 1 thread | 91 ms | **36 ms** | 14.6 ms | — | 2.5× |
| 1000 chained Vesta scalar mults, 1 thread | 458 ms | **186 ms** | 82.9 ms | — | 2.2× |
| MSM n = 2048 (Pippenger c = 8), 1 thread | 130 ms | **54 ms** | 13.4 ms | — | 4.0× |
| MSM n = 2048, 18 threads | 12 ms | **5 ms** | — | 1.3 ms | 3.8× (vs 18T) |
| MSM n = 2048, Metal GPU (warm) | 70 ms | **32 ms** | — | — | — |
| Halo 2 verify, 2-action mainnet bundle, 1 thread ¹ | 167 ms | **71 ms** (≈67 verify) | 20.8 ms | — | ≈3.2× |
| Halo 2 verify, 2-action bundle, all threads ¹ | 42.6 ms | **21.4 ms** (≈17.5 verify) | — | 4.2 ms | ≈4.2× (vs NT) |
| Halo 2 verify, 16-action bundle, 1 thread / all ¹ | 284 / 142 ms | **122 / 66.5 ms** | — | — | — |
| Rust `BatchValidator`, 64 bundles (proofs + sigs) | — | — | 152 bundles/s | 1,125 bundles/s | (no Bend batch path yet) |
| Mainnet Ironwood tree, 838,662 notes, CPU threads (wall) ² | 75 s | **40 s** | 45 s (orchard frontier, earlier run) | — | — |
| same, Metal GPU (wall) ² | 21 s | **19 s** | — | — | — |
| Equihash headers (not ported) | 5,700/s GPU | — | 7,005/s | 37,975/s | ≈1.2× (GPU vs 1T) |

¹ Bend numbers are whole-process wall time: start-up, reading params and bundle, decompressing
the 2,048 generators (a separate setup-only process takes ≈4 ms), then verifying. Rust times only
`proof.verify(&vk, &instances)` in-process. The "≈ verify" figure subtracts the measured setup.
² Wall time for the whole run (reading 838,662 leaves and checking 6 checkpoint roots).

**Summary:** the intrinsics make Bend's field arithmetic **2.5×** faster and Halo 2 verification
**2.0–2.4×** faster. Against Rust, the gap is now about 2–4× single-threaded (it was 6–10×).

## What's left

- The remaining field-mul gap (36 vs 14.6 ns) is mostly Bend's boxed `Fp` constructor and call
  overhead around each multiplication, not arithmetic.
- Equihash / BLAKE2b (`zcash/headers`) still emulate 64-bit words with 16-bit pieces; `addc`
  would speed up its 64-bit additions, but the generator needs changes.
- Upstream: a `U32.mul_hi` / `U64` primitive in Bend would make the C patch unnecessary.
- The binary recompiles its Metal program on each launch (the `.gpu` cache is not written for
  these hand-built binaries); warm in-process timings exclude that.

## Files

`intrinsics.bend`, `intrinsify.py`, `build.sh`, `gen_field32.py` → `fp32.bend`, `fq32.bend`,
`port32.py` → `lib32/`, `v32/`, `state32/` (copied by hand with the same import rewrites),
`t/` (differential tests, vector tests, benchmarks), `rustbench/` (Rust scalar-mult baseline),
`bench_fieldmul.sh`, `bench_verify.py`, `v32/bundle_time.bend`, `v32/decomp_only.bend`.
