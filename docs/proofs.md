# Proofs

Every law below is checked by Bend's dependent type checker with `bend PROOF.bend --verdict`,
with no `@unsafe`. That checker is rechecked by a Lean-proven kernel. 176 laws in total.

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

`proofs/gadget` holds an early law that turned out to be vacuous: its hypotheses can never be met.
It is kept as a lesson and not counted. Every law with hypotheses now has a non-vacuity companion.

## What is assumed

- Field arithmetic computes a·b mod p. Tested on about 20,000 vectors per operation; Bend's checker
  evaluates naturals in unary, so this needs an algebraic proof that has not been written.
- The curve addition formulas are taken as the group operation.
- Montgomery batch inversion, and the sparse-to-dense step for fixed-base scalars, in the fast
  Halo 2 verifier.
- The proof systems themselves (halo2 with IPA, Groth16) and the hardness assumptions under them.
- The full Orchard Action relation is not proven: only the gates and the anchoring above.

## Check them

```sh
cd proofs/msm_bucket && BEND_NO_TELEMETRY=1 bend PROOF.bend --verdict    # ALL PROOFS CHECK
```

Each directory's README states its laws in words, gives what is and is not covered, and how to
reproduce.
