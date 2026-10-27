# `U32.mul_hi`: the high half of a 32×32-bit product

A proposal for Bend 2: one new Base primitive, lowered like `U32.mul` in every backend.

## Motivation

Bend's numbers are `Nat`, `U32` and `F32`. `U32.mul` returns the low 32 bits of a product
and drops the high 32, so multi-word arithmetic (big integers, elliptic-curve fields,
hashing with 64-bit words) has to rebuild the high half from four 16×16-bit products plus
carry juggling. On Zcash's Pasta field (255-bit Montgomery multiplication) that made Bend
6–10× slower than Rust per core.

The usual workaround is to post-process Bend's C output and splice in a 64-bit multiply.
It works, but it lives outside the language: the checker, the JS target and the hub never
see it. `U32.mul_hi` makes the same thing a first-class primitive.

## Design

Base (`bend2/base.bend`), next to `U32.mul`:

```python
def U32.mul_hi(a: U32, b: U32) -> U32:
  U32.from_nat(Nat.div(Nat.mul(U32.to_nat(a), U32.to_nat(b)), Nat.mul(65536n, 65536n)))
```

This definition is what the checker and proofs see: the product of the two values,
divided by 2³². Running it as written would overflow the 2⁴⁸ Nat immediate, so, like
`U32.mul`, it is never run as written; `comp.ts` lowers it by name (`u32_mul_hi`).

| Backend | Lowering |
|---|---|
| C host | `((u64)(u32)(((u64)(u32)(a) * (u64)(u32)(b)) >> 32))`, one widening multiply |
| Metal / CUDA device | the same C text (the device build compiles the same source; `u64` is `ulong`) |
| JS | `u32_mul_hi(a, b)`: 16-bit halves, so every partial product stays below 2⁵³ and the result is exact |

The diff is 18 lines: 5 in `base.bend`, 13 in `comp.ts` (the operation entry and the JS helper).

## Tests

- `tests/base/u32_mul_hi.bend`: edge cases (0, 1, 2³¹, 2³²−1, and pairs whose product
  overflows) and 2¹⁶ xorshift pairs compared with an independent reference built from
  16-bit halves and plain `U32` ops, on CPU threads and as a `!` batch on the GPU.
  Same output from `bend` (checker run), the native binary on CPU and on Metal, and the JS build.
- `tests/base/u32_mul_hi_law.bend`: `law mul_hi_zero_l: for b: U32, {U32.mul_hi(0, b) == 0 : U32}`,
  proven by `{==}` and accepted by `--verdict`.
- JS helper vs BigInt: 0 mismatches on 10⁷ random pairs plus all pairs of 9 edge values.
- The fork still prints the installed 2.0.38's results on the 116 field and 136 curve
  vectors of an existing 16-bit-limb Pasta library.

Concrete laws like `mul_hi(2³²−1, 2³²−1) == 2³²−2` are out of reach: the checker evaluates
`Nat` arithmetic structurally, and dividing a 64-bit product by 2³² there does not finish.

## Result on real cryptography

The Zebend project (an independent Zcash verifier in Bend) rebuilt its 8×32-bit-limb Pasta
fields on `U32.mul_hi` with no C post-processing. Carries use `Bool.to_u32(U32.is_lt(..))`,
which lowers to a native compare.

Correctness, pure Bend on the fork:

| Check | Result |
|---|---|
| Field vectors vs `pasta_curves` | 116/116 |
| Curve vectors | 136/136 |
| MSM vs halo2 `best_multiexp` (n = 16, 2048, 4096; 1 and 18 threads; Metal) | all MATCH |
| Halo 2 Orchard verifier on mainnet bundles, verdicts vs `halo2_proofs` | 42/42 post-NU6.3, 10/10 NU6.2, 8/8 pre-NU6.2 |

Speed, Apple M5 Max, medians of 5, **load average 27–37** (the machine was busy, so absolute
times are 2–3× those on an idle machine; all columns ran under the same conditions):

| Workload | Bend 16-bit limbs | Bend + C post-processing | **Bend + `U32.mul_hi`** | Rust 1 thread | Rust all threads |
|---|---|---|---|---|---|
| 10⁶ chained Fq multiplications, 1T (ms) | 355 | 117 | **107** | 35.4 | — |
| 1000 Vesta scalar mults, 1T (ms) | 1215 | 480 | **526** | — | — |
| MSM n=2048, 1T (ms) | 292 | 164 | **131** | 25.7 | — |
| MSM n=2048, 18T (ms) | 25 | 11 | **16** | — | 3.0 |
| Halo 2 verify, 2 actions, 1T (ms, wall) | 243 | 106 | **106** | 36.6 | — |
| Halo 2 verify, 2 actions, 18T (ms, wall) | 68 | 38 | **37** | — | 4.8 |
| Halo 2 verify, 16 actions, 1T (ms, wall) | 468 | 212 | **224** | — | — |
| Halo 2 verify, 16 actions, 18T (ms, wall) | 301 | 217 | **188** | — | — |

On an idle machine the same Bend + C post-processing build measured 35 ms for the field
loop and 186 ms for the scalar mults, against Rust's 14.6 ms and 82.9 ms.

`U32.mul_hi` alone gets pure Bend to parity with the post-processed build: about 2–3× faster
than 16-bit limbs. The rest of the gap to Rust is the runtime (boxed field values, calls),
not the multiply.

## Possible follow-ups

- `U32.add_carry` / `U32.sub_borrow`, or a `U64` type, would trim the carry compares.
- Proof-side lemmas relating `U32.mul_hi` and `U32.mul` (`to_nat(a)·to_nat(b) == hi·2³² + lo`)
  need `Nat` division lemmas Base does not have yet.

---

# U32.add_hi, U32.mac_hi, U32.mac64: carry and wide-multiply primitives

Branch `u32-prims` (on top of `u32-mulhi`). Same mechanism as `U32.mul_hi`: each op is
defined in `bend2/base.bend` through `Nat` (what the checker and proofs see) and
lowered by name in `bend2/comp.ts` (`OPERATIONS`).

| Op | Meaning | C / Metal / CUDA | JS |
|---|---|---|---|
| `U32.add_hi(a, b)` | carry out of `a + b` (0 or 1) | one widening add | exact compare |
| `U32.mac_hi(a, b, c, d)` | high 32 bits of `a*b + c + d` | one widening multiply-add | `u32_mul_hi` + exact carry |
| `U32.mac64(k, al, ah, bl, bh, cl, ch, dl, dh)` | word k (0..3) of the 128-bit `a*b + c + d`, 64-bit operands as (lo, hi) halves | inline `u32_mac64`: `unsigned __int128` on CPU, `mulhi(ulong)` on Metal, `__umul64hi` on CUDA; the four words of one product share one multiply after inlining | BigInt |

`mac64` is what gives Bend 64-bit limbs without a `U64` type: a Pasta field multiply
over 4 x 64-bit limbs costs ~32 widening multiplies (the pasta_curves shape) instead of
~96 with 32-bit limbs.

Tests (`tests/base/`): `u32_add_hi_mac_hi.bend` and `u32_mac64.bend` (edge cases plus
2^16 random tuples against independent references built from plain U32 ops, on CPU,
Metal via `!`, and the JS target: 0 mismatches), `u32_add_hi_mac_hi_law.bend` (laws read
through the Base definitions; `--verdict` accepts), `u32_add_hi_mac_hi_js.mjs` (JS
helpers vs BigInt on 10^7 tuples: 0 mismatches).

Effect on Zebend's Pasta / BLAKE2b (M5 Max, 1 thread, medians), from
`bend-zcash/field3/README.md`: Fq mul 41 -> 19 ms per 10^6 (Rust 14.4), sqr 41 -> 17 ms
(Rust 13.3), BLAKE2b compression 35 -> 23 ms per 10^5.

Known issue seen while testing (not caused by these ops): Metal (`!`) builds of the large
Equihash verifier made with this fork (2.0.39 via `bun bend2/main.ts`) fault with "memory
fault (machine stack overflow?)", with or without the new ops; the same program built by
the installed 2.0.38 binary runs on the GPU.

---

## Notes for the PR branch (`pr/u32-wide-mul`, on `pr/comp-simplify`)

- The two fork commits are folded into one, "Add U32.mul_hi, U32.add_hi, U32.mac_hi and
  U32.mac64".
- comp.ts was slimmed to fit the cap. The ops are listed once (`name:arity`) and lowered by
  name. In C they are three macros plus the `u32_mac64` inline, the same instructions as
  before. In JS they are BigInt one-liners (`u32_w64`, `u32_word`). They are exact, but slower
  than the old 16-bit-halves `u32_mul_hi`; only the JS target uses them.
- `tests/base/u32_add_hi_mac_hi_js.mjs` is dropped. A `.mjs` under tests/ fails
  `gates/repo.ts`'s allow list, and it tested a JS helper that no longer exists.
- Tests: every `tests/base/u32_*.bend` passes on C (CPU and Metal via `!`), JS and the
  interpreter.
- comp.ts: 66,306 tokens, 306 over the 66,000 cap. Still open; see the report.
