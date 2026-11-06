# orchard_ecc: Orchard's ECC-chip gates (46 laws)

Proven (`bend PROOF.bend --verdict`: ALL PROOFS CHECK, no `@unsafe`). `PROOF.bend` imports
`PROOF_ECC.bend`, so the one command checks both the generated and the hand-written laws.
Fp = Z/p with p = 1 + pp; field elements are canonical Nats below p. "x != 0" is stated as
"x has an inverse" (`xi * x == 1`), which is the same thing in Fp and, unlike a negation, is
data a proof may use more than once.

The target is the gate code Zebend's verifier runs, `zcash/halo2/gen/orchard_cs.bend`, whose
polynomials equal the deployed verifying keys' (`zcash/halo2/constraints`). `gen.py` emits
`gates_model.bend` from it through `../orchard/gates.py` (whose decoded trees reproduce halo2's
gate values on a real proof, 386/386). The compressed selector factor of each gate becomes the
variable `sel`, assumed invertible (the gate is active on the row). Gate and constraint names:
`../orchard/names/names.txt`. Cells `a<k>` / `f<k>` are the k-th queried advice / fixed
evaluation; `LAWS.bend` lists each one's column and rotation.

## Hand-written laws (`ECC.bend`, proofs in `PROOF_ECC.bend`)

| Law | Gate | Statement in words |
|---|---|---|
| `cadd_p_identity` | 6 "complete addition", constraints 4a, 4b | If x_p = 0 (P is the identity (0, 0)), the output is R = Q: x_r = x_q, y_r = y_q. |
| `cadd_q_identity` | 6, constraints 5a, 5b | If x_q = 0, R = P. |
| `cadd_inverse` | 6, constraints 6a, 6b | If x_q = x_p and y_q + y_p = 0 (Q = -P), R = (0, 0), whatever the witnesses alpha, delta are. |
| `cadd_distinct` | 6, constraints 1, 3a, 3b | If x_p, x_q and x_q - x_p are non-zero, lambda is the chord slope ((x_q - x_p) lambda = y_q - y_p) and R is the chord-rule sum: x_r = lambda^2 - x_p - x_q, y_r = lambda (x_p - x_r) - y_p. |
| `cadd_double` | 6, constraints 2, 3c, 3d | If x_p, x_q, y_q + y_p are non-zero and x_q = x_p, lambda is the tangent slope (2 y_p lambda = 3 x_p^2) and R is given by the same formulas. |
| `incomplete_add` | 5 "incomplete addition" | If x_p != x_q, then with lambda = (y_p - y_q) / (x_p - x_q): x_r + x_q + x_p = lambda^2 and y_r + y_q = lambda (x_q - x_r): R is the chord-rule sum. |
| `lsb_check` | 15 "LSB check", all three constraints | The scalar's last bit k = z_0 - 2 z_1 is 0 or 1; if 0, the last row's point is the base with y negated (x_p = x_base, y_p + y_base = 0); if 1, it is (0, 0). |
| `short_sign` | 19 "Short fixed-base mul gate", sign_check | sign^2 = 1 forces sign = 1 or sign = -1. |

The five complete-addition laws cover every (P, Q): P = O; Q = O; Q = -P; distinct x; doubling.
That these cases are exhaustive is the field fact "every element is 0 or invertible"
(primality), which is not restated as a law. Each law has a `_satisfiable` companion: all of
its hypotheses at once on a concrete row at p = 11.

## Generated laws (`LAWS.bend`, by `gen.py` with `../orchard/lawgen.py`)

One law `gate_<g>` per gate: with the selector invertible, the listed cells canonical and every
listed polynomial vanishing on the row, each polynomial's fact holds. `lawgen.py` reads each
polynomial as one of a few shapes and emits the matching fact and proof: `X - Y` gives
`X == Y` (or `A == B + Y` when `X = A - B`); `x (1 - x)` gives `x == 0 or x == 1`;
`x (1 - x)(2 - x)...(k - x)` gives `x <= k` as an integer; `b * body` with `b` a bit gives
`b == 1 => fact(body)`; a listed product gives `fact(X) or fact(Y)`. Each `gate_<g>` has a
`gate_<g>_satisfiable` companion: every hypothesis, the copies of `F.NZD` included (proved for
p = 11 in `../orchard/nzd11.bend`), at a row over F_11 the script finds by search.

| Gate | Polynomials | Facts |
|---|---|---|
| 1 "Field element addition" | all | c = a + b |
| 2 "Short lookup bitshift" | all | shifted = word * 2^10 * inv_two_pow_s |
| 3 "witness point" | all | (x = 0 or y^2 - x^3 = 5) and (y = 0 or y^2 - x^3 = 5) |
| 4 "witness non-identity point" | all | y^2 - x^3 = 5 |
| 7, 10 "q_mul_1 == 1 checks" | all | init y_a: y_a = (lambda_1 + lambda_2)(x_a - x_r) / 2 |
| 8, 11 "q_mul_2 == 1 checks" | bool_check, secant_line, gradient_2 | the loop's bit is 0 or 1; the secant and gradient equations |
| 9, 12 "q_mul_3 == 1 checks" | bool_check, secant_line, gradient_2 | as for 8, 11 on the last loop row |
| 14 "overflow checks" | all | s = alpha + k_254 * 2^130; recovery; k_254 = 1 forces lo_zero and s_minus_lo_130 = 0; canonicity as a disjunction |
| 16 "range check" | all | each fixed-base window (a4 - 8 a14) is at most 7 |
| 17 "Running sum coordinates check" | all | x is the Lagrange interpolation of the window; u^2 = y + z; on-curve |
| 18 "Full-width fixed-base scalar mul" | all | as 17, plus window <= 7 |
| 19 "Short fixed-base mul gate" | all | last window bit is 0 or 1; sign^2 = 1; y' = +/- y; y' = sign * y |

Gates 5, 6, 15 are emitted into `gates_model.bend` only; their meaning is the hand-written laws.

## Not covered

- gradient_1 of the variable-base mul loop (polynomials 8_3, 9_1, 11_3, 12_1: shape
  `X - Y + Z`, not read by `lawgen.py`).
- That the loop as a whole computes [k] P, including that its incomplete additions never hit
  their exceptional cases (x_p = x_q); `../orchard_mul` proves only that the loop's base is g_d.
- That the fixed-base tables (fixed columns of gates 17, 18) hold the multiples of the base:
  that is circuit data, not a gate fact.
- The overflow check's cross-row argument (gate 14 with the running sums it reads) and the
  short range check's integer argument (gate 2 with its two lookups).
- That the selector factor is non-zero exactly on the rows the layout enables (selector
  compression), and copy constraints between regions (halo2's permutation argument).

## Reproduce

```sh
python3 gen.py                                   # regenerate gates_model.bend, LAWS.bend, PROOF.bend
BEND_NO_TELEMETRY=1 bend PROOF.bend --verdict    # ALL PROOFS CHECK
```
