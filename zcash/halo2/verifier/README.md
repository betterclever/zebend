# Halo 2 verifier in Bend (H2)

A Bend 2 implementation of halo2's `verify_proof` (halo2_proofs 0.4, as used by orchard 0.16),
generated per verifying key and checked value by value against the official Rust verifier.

## How it works

The verifier's control flow (what is read from the transcript and in what order, which
queries exist, how multiopen groups them, which MSM terms appear) depends only on the
verifying key. So `zebend_codegen.rs`, a module added to a vendored copy of halo2_proofs,
walks `verify_proof` symbolically for a given VK and emits straight-line Bend that performs
exactly the same field operations on the actual proof:

| halo2 source | what the generated Bend does |
|---|---|
| `transcript.rs` | BLAKE2b-512 transcript, personalization `Halo2-Transcript`: `0x01‖x‖y` per point (affine Fq), `0x02‖repr` per scalar, squeeze = absorb `0x00` + finalize a copy + `from_uniform_bytes` (vlib.bend, b2.bend) |
| `plonk/verifier.rs` | instance commitments `Σ instᵢ·G_lagrangeᵢ + 1·W` (halo2's `Blind::default()` is ONE), VK hash, reads for N proofs sharing one transcript |
| `vanishing/verifier.rs` | every gate polynomial, folded `h = h·y + e`, divided by `xⁿ − 1`; the h commitment as an MSM in powers of xⁿ |
| `permutation/verifier.rs` | l₀ / l_last / l_blind via barycentric Lagrange evaluation, product and chunk-boundary terms with DELTA powers |
| `lookup/verifier.rs` | θ-compressed inputs and tables, the five lookup terms |
| `multiopen/verifier.rs` | `construct_intermediate_sets` (by commitment identity, points by first appearance), reverse x₁ accumulation, Lagrange interpolation at x₃, x₂ / x₄ folding |
| `commitment/verifier.rs` | IPA: ξ, z, k rounds of (L, R, uⱼ), b, the s-vector, −v at G₀, W and U scalars |
| `SingleVerifier` | the final MSM over all terms + 2ᵏ generators, accepted iff it is the identity (H1's lib/msm.bend) |

All field elements and points in generated code are boxed (`L.BF`, `L.BP`: a recursive type is
one heap pointer) because the native backend flattens Data values into registers and caps a
call frame at 247 of them.

Note: halo2's `Blind::default()` is ONE, so an instance commitment is `Σ instᵢ·G_lagrangeᵢ + W`.
Every transcript challenge matching halo2 depends on absorbing exactly that point.

Points are decompressed with H1's `lib/vesta.bend` (canonical x, on-curve, as pasta's `from_bytes`),
scalars are checked canonical (< p).

## Results

| | toy circuit (k=5, 2 proofs) | Orchard post-NU6.3 (k=11, 2 actions) |
|---|---|---|
| generated Bend | ~900 lines, 3 defs | 14,375 lines, 40 defs (compile 3m39s, Homebrew clang 23) |
| honest proof | **accepted**: final MSM = identity | **accepted**: final MSM (2048 G + 125 other terms) = identity, **0.48 s** wall on the M5 Max CPU |
| tampered proof | **rejected** | **rejected** (byte 3632 flipped, as in H0's dump) |
| values equal to our instrumented halo2 | **81 / 81** | **2513 / 2513** (every challenge, 430 expressions, h, multiopen, v, IPA b/c/f, 2048 G-scalars, W/U scalars) |
| values equal to H0's independent dump | | **463 / 463** (challenges, 430 expressions, h numerator, expected h, msm_eval, v, 11 IPA uⱼ, b, c, f) |

`python3 compare.py toy_out.txt toy/out/toy_trace.txt` reproduces the comparison.

## Bend lessons (they shaped the generator)

- A def may only destructure its parameters, and only call defs written above it; no mutual recursion.
- The native backend flattens a def's parameters into registers (an Fp is 16 words, a Vesta
  point 48) and refuses more than 247 (`WIDE` in the compiler). The generator splits `verify`
  into a chain of short defs and boxes live Fp / point values into one list each per boundary.
- Apple clang 21 crashes on the result ("live register clobbered by inserted prologue
  instructions", a `preserve_none` codegen bug); Homebrew LLVM 23 compiles it:
  `PATH=/opt/homebrew/opt/llvm/bin:$PATH bend toy_main.bend -o toy_main`.

## Reproduce

```sh
cd toy && cargo run --release            # toy oracle: proof, trace, generated Bend
cd ../orchard_gen && cargo run --release # Orchard: VK from H0's vendored orchard, H0's proof
cd .. && PATH=/opt/homebrew/opt/llvm/bin:$PATH bend toy_main.bend -o toy_main && ./toy_main > toy_out.txt
python3 compare.py toy_out.txt toy/out/toy_trace.txt
```

## Mainnet: one binary, any bundle, inputs at runtime

`bend_verifier_dyn` generates a verifier for a VK in which the number of actions is a runtime
input: per-action work (gate/permutation/lookup terms, that action's multiopen accumulation) is
generated once and run in loops. Proof bytes, instance values and the 2^11 generators G are read
from files:

```sh
./bundle_main_fast data/params_g.bin data/bundles/tx_12.orchard.bin      # -> result 1
```

`orchard_gen` writes the bundle files from `zcash/tx/mainnet` (read-only), a tampered copy of each
(one proof bit flipped), and the official halo2 verdict for every file.

| circuit (VK) | binary | mainnet bundles | Bend accepts | tampered rejected | agrees with halo2 |
|---|---|---|---|---|---|
| post-NU6.3 (v6 Ironwood + withdraw-only Orchard) | `bundle_main_fast` | 20 (+ H0's) | 21/21 | 21/21 | 42/42 |
| NU6.2 fixed (v5) | `bundle_main_nu62` | 5 | 5/5 | 5/5 | 10/10 |
| pre-NU6.2 historical (v5) | `bundle_main_prenu62` | 4 | 4/4 | 4/4 | 8/8 |

That is every Orchard-protocol bundle in the 29 sampled mainnet transactions (blocks
3,363,401–3,528,212; 2 to 16 actions, 133 actions in all). H0's proof run through the runtime
binary still matches halo2 on 2513/2513 logged values.

Wall time per bundle (whole process: read files, decompress, verify), M5 Max, load ≈ 3:

| actions | final MSM: H1 Pippenger (`msm_fast`, c = 8) | H1 double-and-add (`msm`) |
|---|---|---|
| 2 | 38.5 ms | 117 ms |
| 3 | 45 ms | 137 ms |
| 4 | 52 ms | 134 ms |
| 16 | 135 ms | 230 ms |

The first run of a freshly built binary takes ~380 ms (cold caches).

```sh
python3 run_bundles.py ./bundle_main_fast                       # post-NU6.3
python3 run_bundles.py ./bundle_main_nu62 data/bundles_nu62
python3 run_bundles.py ./bundle_main_prenu62 data/bundles_prenu62
```
