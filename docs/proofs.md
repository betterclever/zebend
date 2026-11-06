# Proofs

Every law below is checked by Bend's dependent type checker with `bend PROOF.bend --verdict`,
with no `@unsafe`. That checker is rechecked by a Lean-proven kernel. 343 laws in total.

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
| `proofs/fieldarith` | 13 | Pasta field addition and subtraction (`zcash/halo2/lib/fp.bend`, 16-bit limbs) compute (a ± b) mod p with a result below p, for canonical inputs; masks and shifts are mod and div by 2^k; U32 add/sub that do not wrap are exact |
| `proofs/orchard` | 14 | soundness of real Orchard gates on the generated polynomials: value balance, anchor-or-zero, enable flags, booleanity, bit decomposition, conditional swap; a satisfiability companion for each |
| `proofs/orchard_ecc` | 46 | complete addition (all five cases give the group-law result), incomplete addition (the chord-rule sum when x_p != x_q), the LSB row, the short-mul sign is +-1, and per-row facts of every other ECC gate; each with a satisfiability companion |
| `proofs/orchard_canon` | 37 | the strict running-sum range check bounds z_0 < r^n (lookups assumed; counterexample without z_n = 0); x(g_d)'s NoteCommit decomposition is canonical (counterexample without the a' check); per-row facts of every decomposition and canonicity gate |
| `proofs/orchard_hash` | 16 | per-row equations of the Poseidon and Sinsemilla gates and the second conditional swap |
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

- Field multiplication computes a·b·R⁻¹ mod p (Montgomery), and the inversion and square root
  built on it. Tested on about 20,000 vectors per operation; not proven. Addition and subtraction
  of `zcash/halo2/lib/fp.bend` are proven (`proofs/fieldarith`).
- The 64-bit-limb field of the fast Halo 2 verifier (`crypto/field3/fp64.bend`, `fq64.bend`):
  tested, not proven, including addition. Its carry primitives (`U32.add_hi`, `U32.mac64`) cannot
  be unfolded by the checker on symbolic inputs (see `proofs/README.md`).
- That the modulus limbs in the field code spell Pallas' p is checked in Python (`gen_add.py`),
  not in Bend.
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
- The full Orchard Action relation is not proven: only the gates, the anchoring, the range check
  and one canonicity argument above. Not proven: that the gadgets compose (the mul loop computes
  [k] P, Poseidon and Sinsemilla compute their hashes), the integer canonicity of the other
  decompositions (pk_d, rho, psi, y, ak, nk, the gate 20 scalar, the overflow check), and the
  gradient_1 polynomials of the mul loop. `proofs/README.md` has the per-gate table.
- Lookup arguments (that a looked-up value is in the table), copy constraints (the permutation
  argument) and selector compression (that a gate's selector factor is non-zero exactly on the
  rows the layout enables) are properties of halo2 and the layout; the laws state them as
  hypotheses.
- Primality of the Pallas modulus, used as `NZD` (no zero divisors among canonical elements).

## Check them

```sh
cd proofs/msm_bucket && BEND_NO_TELEMETRY=1 bend PROOF.bend --verdict    # ALL PROOFS CHECK
cd proofs/curve && BEND_NO_TELEMETRY=1 ../../tools/heavy.sh bend PROOF.bend --verdict   # 37 s, 2.9 GB
```

Each directory's README states its laws in words, gives what is and is not covered, and how to
reproduce.
