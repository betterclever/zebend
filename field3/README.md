# field3: Pasta field arithmetic and hashing, round 3

Pure Bend (no C post-processing) on three new primitives added to the local Bend fork
(`../../bend-fork`, branch `u32-prims`, commit `ba061c18`; see its PRIMS.md):
`U32.add_hi` (add carry), `U32.mac_hi` (high half of a 32-bit multiply-accumulate) and
`U32.mac64` (a 64x64-bit multiply-accumulate over U32 halves). Build with `./build.sh
prog.bend out` (the fork's `bend2/main.ts` via bun); `guard.sh MB SECONDS cmd` kills
compiles that blow up.

The field modules keep the exact API of `fast/pure/fp32.bend` (Montgomery form,
R = 2^256, `Fp{l0..l7}` 32-bit words), so they drop into the curve, MSM and verifier code:

| File | Generator | Multiplication |
|---|---|---|
| `fp3.bend`, `fq3.bend` | `gen_field3.py` | 8 x 32-bit limbs, CIOS, carries via `U32.add_hi` / `U32.mac_hi` |
| **`fp64.bend`, `fq64.bend`** | `gen_field64.py` | **4 x 64-bit limbs via `U32.mac64`** (pasta_curves' shape) |

Both also carry: a dedicated squaring (`sqr_d`, routed from `sqr`), a lazy add
(`add_nr`), sliding-window (w = 5) exponent chains for inversion and the square-root
power, a variable-time square root (`sqrt`; the constant-time one stays as `sqrt_ct`),
and `batch_inv` (Montgomery's trick).

## Correctness

Every variant passes all of these (re-run after each change):

| Check | Result |
|---|---|
| 116 pasta_curves field vectors (`t/field_tests3*`) | 116/116 identical |
| 10^6 random pairs per field through mul, sqr, add, sub and `mul(add_nr(x,y), y)` (`t/diff3*`) | 0 mismatches vs the round-2 fields and vs `sqr = mul(x,x)`; XOR digest of all 5x10^6 results per field **identical to pasta_curves** (`rust/ digest`) |
| 20 edge values per field, all 400 pairs, same 5 ops (`t/edges3*`): 0, 1, 2, 3, m−1, m−2, (m±1)/2, 2^254−1, 2^254, R mod m, R² mod m, m, m+1, 2^255−1, 2^256−1, 2^32−1, 2^32, 2^128, m−2^32 | digest identical to exact Python integers |
| 2^15 random values per field through sqrt, inv (`t/sqrt3*`) | 0 mismatches vs round 2 (same square/non-square verdict, same root up to sign, sqr(r) = x; inverses identical and x·x⁻¹ = 1) |
| `batch_inv` on 64 lists of 64 random values per field | 0 mismatches vs one-by-one `inv` |
| 136 curve vectors (Vesta + Pallas, `t/curve_tests3`, `t/curve_tests64`) | 136/136 identical |
| MSM n = 2048 vs halo2 `best_multiexp` (`lib3/`, `lib64/`) | MATCH at 1 and 18 threads |
| BLAKE2b (`eh/new`): Equihash on 16,384 mainnet headers | 16,384/16,384 valid; target, links, difficulty 100% (same as before) |

## Speed

M5 Max, one thread unless noted, medians of 5–7 interleaved runs. The genesis header
fetch was running on the Mac; load average 3–6 throughout (recorded per run).

| Workload | Round 2 (`fast/pure`) | Round 3, 32-bit limbs | **Round 3, 64-bit limbs** | Rust (pasta_curves / halo2) |
|---|---|---|---|---|
| 1e6 chained Fq mul | 41 ms | 40 ms | **19 ms** | 14.4 ms |
| 1e6 chained Fq sqr | 41 ms | 33 ms (dedicated squaring) | **17 ms** | 13.3 ms |
| 1e4 Fq sqrt (x += i; 5,030 squares) | 330 ms | 149 ms | **88 ms** | 41–49 ms |
| 1e4 chained Fq inversions | 132 ms | 102 ms | **59 ms** | 43–46 ms |
| 1000 Vesta scalar mults (round-2 curve code) | 183 ms | 182 ms | **115 ms** | 81 ms |
| MSM n = 2048, Pippenger c = 8, 1 thread | 53 ms | 55 ms | **34 ms** | 13.9 ms |
| MSM n = 2048, 18 threads | 5 ms | 5 ms | **3 ms** | 1.5 ms |
| 1e5 chained BLAKE2b compressions | 35 ms | **23 ms** (`add_hi`) | 27 ms (`mac64` adds) | 8 ms (~80 ns each, blake2b_simd) |
| Equihash verify, 4,096 mainnet headers, 1 thread | 3,193 ms | **2,833 ms** | — | ~585 ms (equihash crate, 7,005/s) |
| Equihash verify, 16,384 headers, 18 threads | 1,393 ms | **1,282 ms** | — | — |
| `mul(add(x,c), d)` vs `mul(add_nr(x,c), d)`, 1e6 | 46 ms | 42 ms (lazy) | — | — |

Step by step:

1. **Dedicated squaring**: 28 cross products doubled + 8 diagonal squares, then a sparse
   SOS reduction: sqr 41 → 33 ms (32-bit limbs).
2. **Lazy reduction** (`add_nr`): ~8% on the add→mul pattern. Pasta has under two
   spare bits (4m > 2^256), so it is only safe as ONE operand of `mul` whose other
   operand is reduced: then a·b < 2m², the Montgomery output is < 2m, and `mul`'s single
   conditional subtraction lands in [0, m). Two lazy operands, or lazy values reaching
   `to_words` / `eq` / a transcript, are not safe. Not wired into the curve code.
3. **Special-form reduction (p = 2^254 + c)**: not implemented. The Montgomery REDC here
   already exploits the sparse modulus (limb 0 is 1, limbs 4–6 are 0): 32 of the 96
   multiply-accumulates per field multiply. Folding 2^256 ≡ −4c needs 8x4 + 4x4 = 48 for
   the reduction (112 in total) plus signed corrections, so it would be slower.
4. **Square root and inversion**: window-5 chains cut the multiplies in the fixed
   exponentiations roughly in half (inv 132 → 102 ms); the variable-time Tonelli–Shanks
   (with an early exit for non-squares, half of all inputs) does about half the squarings
   of the constant-time loop (sqrt 330 → 149 ms). Variable time is fine for public data
   (proof points, transaction fields); `sqrt_ct` remains for secrets.
5. **Primitives**: `U32.add_hi` makes the BLAKE2b 64-bit add one op instead of a 5-op
   carry formula (−35% per compression, −8 to −11% on Equihash, where the rest of the
   verifier dominates). `U32.mac_hi` / `add_hi` barely change the 32-bit field multiply
   (41 → 40 ms): compare-based carries were already single compares. **`U32.mac64`** is
   the big one: 4 x 64-bit limbs halve the field multiply (41 → 19 ms); clang folds the
   four words of each product into one `mul` + `umulh`.

## Where Bend now stands against Rust

- Field mul/sqr: **1.3x** behind pasta_curves (was 2.8x); inversion 1.3x; sqrt 1.9x.
- Scalar multiplication 1.4x, MSM 2.4x (1 thread) / 2x (18 threads): the gap left is the
  curve and MSM code (boxed point records, per-call overhead), not the field.
- No operation beats Rust. Compiler flags don't close the rest: `-mcpu=native` and LTO
  change nothing; Apple clang is a little faster than Homebrew LLVM 23 on this code.

## Notes

- `sqrt` is variable-time; `add_nr` has the usage rule above; both are documented in the
  generated modules.
- The fork's Metal builds of the large Equihash verifier fault (`memory fault (machine
  stack overflow?)`) with or without these changes, so the GPU column is missing above;
  the installed Bend 2.0.38 builds of the same program run on the GPU. CPU numbers only.
- Combining these fields with `algo/` (GLV, batch-affine MSM) is the obvious next step;
  GLV alone took scalar mults 187 → 113 ms on the round-2 fields.
