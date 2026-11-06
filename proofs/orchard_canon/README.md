# orchard_canon: decompositions, range checks and canonicity (37 laws)

Proven (`bend PROOF.bend --verdict`: ALL PROOFS CHECK, no `@unsafe`). `PROOF.bend` imports
`PROOF_RANGE.bend` and `PROOF_CANON.bend`, so the one command checks all 37 laws. Fp = Z/p,
p = 1 + pp. Conventions as in `../orchard_ecc/README.md`.

## The range check and canonicity (`RANGE.bend`, `CANON.bend`)

These reason about canonical field elements as integers, which is where range and canonicity
live. **The lookup argument is a hypothesis**: that a looked-up word is in the table is a
property of halo2's proof system, not of the gates, and is assumed as "the word is < r".

| Law | Statement in words |
|---|---|
| `running_sum_range` | The strict running-sum range check (halo2_gadgets' `LookupRangeCheck`, which every Orchard decomposition uses with r = 2^10) is sound: if z_0 is canonical, every word z_i - z_{i+1} r of an n-step running sum is in [0, r) (the lookups), z_n = 0, and r^n <= p, then z_0 < r^n as an integer. For any r, n. With n = 25 this is "a < 2^250"; with n = 13 and z_13 = 0, "< 2^130". |
| `running_sum_zero_satisfiable` | Non-vacuity: for every p, r >= 1 and n, the all-zero running sum satisfies every step and ends in 0. |
| `running_sum_range_satisfiable` | Non-vacuity of all hypotheses at once, with a non-zero value (p = 11, r = 3: 5 = 2 + 3 * 1). |
| `running_sum_nonstrict_counterexample` | Without z_n = 0 the bound fails (p = 11, r = 3, z = 10, 3: the one word is in the table, yet 10 >= 3). |
| `canon_gd` | NoteCommit's x(g_d) decomposition x = a + 2^250 b_0 + 2^254 b_1 is canonical: given the gate 38 facts (decomposition, a_prime_check, b_1 = 1 => b_0 = 0), b_1 a bit (gate 33), a < 2^250, b_0 < 2^4 and, when b_1 = 1, a' < 2^130 (range checks), and p = 2^254 + t_P with 1 <= t_P < 2^130 <= 2^250 and 2^254 = 16 * 2^250, x equals the **integer** a + 2^250 b_0 + 2^254 b_1. So the pieces describe x itself, never x + p. The constants are parameters; the law holds for every value satisfying those relations, and the real ones do (`gen.py` lists them). |
| `canon_gd_satisfiable` | Non-vacuity, with b_1 = 1, on a toy instance of the constants (p = 33). |
| `canon_gd_without_aprime_counterexample` | The a' range check is needed: without it, a = 1 >= t_P, b_1 = 1 satisfies every other hypothesis and x = 0, while the integer is 33 = p (on the toy constants). |

`canon_gd` combines laws: its hypotheses are what `gate_38`, `gate_33` and `running_sum_range`
conclude, plus the copy constraint of b_1 between regions. One observation: the proof does not
use "b_1 = 1 => z13_a = 0" (a < 2^130); a < 2^250 and the a' check already give a < t_P. The
gate enforces it anyway; this law does not say it is unnecessary for the circuit as a whole.

## Generated per-gate laws (`LAWS.bend`, by `gen.py` with `../orchard/lawgen.py`)

As in `../orchard_ecc`: `gate_<g>` turns "every polynomial vanishes, selector invertible,
cells canonical" into each polynomial's fact, and `gate_<g>_satisfiable` exhibits a row over
F_11 meeting every hypothesis. Large constants (2^120 ... 2^254, t_P) are parameters.

| Gate | Facts |
|---|---|
| 20 "Canonicity checks" (base-field scalar for fixed-base mul) | alpha_2 is a bit; alpha_1 <= 3; z_84 = alpha_1 + 4 alpha_2; alpha_0' = alpha_0 + 2^130 - t_P (shape `a20 - 2^252 a24 + 2^130 - t_P`); alpha_2 = 1 forces alpha_1 = 0, alpha_0_hi_120 = 0 (as a18 = 2^120 a24), a_43 a bit, z_13(alpha_0') = 0 |
| 27, 31 "Decomposition check" (Sinsemilla, two chips) | the message piece equals its sub-pieces: 2^10 / 2^240 / 2^5 splits |
| 32 "CommitIvk canonicity check" | b_1, d_1 are bits; b, d, ak, nk decompositions; b_1 = 1 forces b_0 = 0, z13_a = 0, z13_a' = 0; d_1 = 1 forces c_0 = 0, z13_c = 0, z14(b2_c') = 0; the a' and b2_c' relations |
| 33-37 "NoteCommit MessagePiece b, d, e, g, h" (and 44-48) | bit checks and the piece decompositions |
| 38-43 "NoteCommit input g_d, pk_d, value, rho, psi", "y coordinate checks" (and 49-54) | the field decompositions (a + 2^250 b_0 + 2^254 b_1 = x, ...), the primed relations (a + 2^130 = t_P + a'), and "top bit = 1 forces ..." |

Gates 44-54 are the second NoteCommit instance: `gen.py` checks their polynomials are
identical to 33-43's, so `gate_33` ... `gate_43` cover them.

## Not covered

- The integer canonicity argument for the other decompositions (pk_d, rho, psi, y in
  NoteCommit; ak, nk in CommitIvk; the base-field scalar of gate 20; the overflow check):
  only g_d's is proven. They follow the same pattern (`PROOF_CANON.bend`) with other splits.
- The lookup argument (assumed), the short range check's shift argument, copy constraints
  between regions (assumed where `canon_gd` needs them), and which rows enable which selector.
- That the running sum in the circuit is laid out as the `Steps` model says (the lookup input
  `z_cur - z_next * 2^10` is modelled, not read from the generated lookup expressions).

## Reproduce

```sh
python3 gen.py                                   # regenerate gates_model.bend, LAWS.bend, PROOF.bend
BEND_NO_TELEMETRY=1 bend PROOF.bend --verdict    # ALL PROOFS CHECK
```
