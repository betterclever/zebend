# Proofs

Every law below is checked by Bend's dependent type checker with `bend PROOF.bend --verdict`,
with no `@unsafe`. That checker is rechecked by a Lean-proven kernel. 224 laws in total.

## What is proven

| Directory | Laws | Statement |
|---|---|---|
| `proofs/turnstile` | 9 | ZIP 209 turnstile, supply conservation, NU6.3/NU7 pool rules |
| `proofs/migration` | 6 | the ZIP 318 migration planner |
| `zcash/consensus/issuance` | 5 | subsidy, funding streams and lockbox stay within the issuance schedule |
| `zcash/consensus/anchors` | 3 | anchor validity rules |
| `zcash/consensus/nu7` | 15 | the supply cap holds across the switch to 25 s blocks, subsidy per unit of time is preserved, the fee split and NSM conserve value, reissuance never makes the NSM negative |
| `proofs/difficulty`, `zcash/headers` | 14 | difficulty and timespan bounds in every era, including one law about the running verifier code |
| `proofs/parse` | 11 | parser round-trips, and rejection of non-canonical and over-length input |
| `proofs/merkle`, `proofs/state`, `zcash/state` | 9 | the incremental frontier equals the full tree, Merkle path soundness, nullifier-set insertion, on the running code |
| `proofs/prims`, `proofs/field`, `proofs/fieldmul` | 12 | the 64-bit word primitives compute exact products and sums |
| `proofs/orchard` | 7 | soundness of real Orchard gates on the generated polynomials: value balance, anchor-or-zero, enable flags, booleanity, bit decomposition, conditional swap |
| `proofs/orchard_mul` | 3 | the NU6.2 fix for the May 2026 Orchard bug: the base of the variable-base scalar multiplication is anchored to `g_d`, plus non-vacuity and a counterexample on the pre-NU6.2 circuit |
| `proofs/opt_gates` | 56 | every optimised function of the fast Halo 2 verifier computes the same values as the original, in Z/p for every p ≥ 2 |
| `proofs/msm_chunk` | 8 | chunked and parallel MSM equals the plain MSM; merging proofs on shared bases is exact |
| `proofs/msm_bucket` | 18 | the signed-digit bucket method computes Σ sᵢ·Pᵢ |
| `proofs/batchinv` | 9 | Montgomery batch inversion (fp64/fq64, msm_ba, vlib.binvs) returns the pointwise inverses whenever its one inversion succeeds; in a prime field it equals x^(p−2) pointwise, 0 ↦ 0 for binvs; a zero input makes every output 0 |
| `proofs/curve` | 30 | the RCB complete addition, mixed addition and doubling of Pallas/Vesta compute the chord-and-tangent law of y² = x³ + b: the chord for P ≠ ±Q, the tangent for P = Q, the identity (0 : Y : 0) for P = −Q, the identity handled on either side, Z3 ≠ 0 when there is no point of order 2, doubling stays on the curve; the code's mul15 is b = 5 |
| `proofs/fixedbase` | 9 | the sparse-to-dense step for fixed-base scalars (`bt.fx_dense`) keeps the MSM; the fixb comb tables and walk compute acc + Σ ±mⱼ·2^(c·j)·P |

`proofs/gadget` holds an early law that turned out to be vacuous: its hypotheses can never be met.
It is kept as a lesson and not counted. Every law with hypotheses now has a non-vacuity companion.

## What is assumed

- Field arithmetic computes a·b mod p. Tested on about 20,000 vectors per operation; Bend's checker
  evaluates naturals in unary, so this needs an algebraic proof that has not been written.
- That the chord-and-tangent law is a group (associativity). The formulas are proven to compute
  it (`proofs/curve`), but add's projective on-curve identity as a single statement is not:
  its 3,150-monomial certificate exceeds the checker's limits (in a prime field the case laws
  cover every input).
- Pallas' and Vesta's p are prime, as Fermat's little theorem (used by `batchinv`'s field laws),
  and the curves have no point of order 2 (used by `curve`'s "Z3 ≠ 0" laws).
- In `fixb`: that U32 shifts and masks extract the index bits `tget` reads, that the parallel
  table build `wpar` equals the per-window map, and that `msm_ba.recode` recodes the scalar.
  GLV's endomorphism and decomposition, and point decompression.
- The proof systems themselves (halo2 with IPA, Groth16) and the hardness assumptions under them.
- The full Orchard Action relation is not proven: only the gates and the anchoring above.

## Check them

```sh
cd proofs/msm_bucket && BEND_NO_TELEMETRY=1 bend PROOF.bend --verdict    # ALL PROOFS CHECK
cd proofs/curve && BEND_NO_TELEMETRY=1 ../../tools/heavy.sh bend PROOF.bend --verdict   # 37 s, 2.9 GB
```

Each directory's README states its laws in words, gives what is and is not covered, and how to
reproduce.
