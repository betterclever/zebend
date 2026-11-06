# curve: the RCB formulas compute the chord-and-tangent law (30 laws)

`BEND_NO_TELEMETRY=1 ../../tools/heavy.sh bend PROOF.bend --verdict`: ALL PROOFS CHECK
(37 s, 2.9 GB peak, no `@unsafe`).

## Scope

`model.bend` copies, over the Z/p model (p = 1 + bp, canonical Nats; `B.add` / `sub` / `mul` /
`sqr` are opt_gates' `T.fadd` / `T.fsub` / `T.fmul` / `T.fmul(x, x)`), statement by statement
and operand by operand:

* `crypto/field3/lib64/vesta.bend`: `add` (Renes–Costello–Batina Algorithm 7), `add_aff`
  (Algorithm 8), `double` (Algorithm 9), `mul15`;
* `research/perf4/lib/msm_ba.bend`: `add_aff` (the affine chord with the slope's inverse from
  the batch inversion).

The same laws cover, by textual identity (checked with `diff`, not proven):
`crypto/field3/lib64/pallas.bend` (identical to vesta.bend except the field types), and
`research/perf4/lib/vesta_lz.bend`'s `add` / `add_aff` / `double`, the ones the deployed
verifier calls (msm_ba, fixb, glv): identical to vesta.bend's after replacing `B.add_nr` (an
addition without the final conditional subtraction) by `B.add`, which is the same in Z/p.

Each formula is written twice: `add` with the code's `m15` (16a − a), and `addb` with 15
replaced by any b3. The laws are about `addb` with b3 = 3b, for **every** curve
y² = x³ + b; `add_is_b5`, `aff_is_b5`, `dbl_is_b5` prove that the code-faithful copies are the
b = 5 instance (Pallas and Vesta).

## Laws

P = (X1 : Y1 : Z1), Q = (X2 : Y2 : Z2). `Rep(X, Y, Z, zi, x, y)`: Z·zi = 1, x = X·zi, y = Y·zi (the
point has Z invertible and affine coordinates (x, y), as `to_aff` computes them). R is the
output (X3 : Y3 : Z3). Chord: λ = (y2 − y1)·di with (x2 − x1)·di = 1, x3 = λ² − x1 − x2,
y3 = λ(x1 − x3) − y1. Tangent: λ = 3x²·ti with (2y)·ti = 1.

| Law | Statement |
|---|---|
| `add_chord_x`, `add_chord_y` | P, Q on the curve with x1 ≠ x2 (di exists): X3 = x3·Z3 and Y3 = y3·Z3. |
| `add_chord_nz` | ... and Z3 ≠ 0, given `NoT2(b)` (x³ + b ≠ 0 for every x: no point of order 2). Z3 = y(P − Q)·(x2 − x1)³·Z1²Z2², and y(P − Q) = 0 would make P − Q a point of order 2. |
| `add_tan_x`, `add_tan_y`, `add_tan_nz` | P and Q the same affine point (any Z1, Z2), y ≠ 0 (ti exists): R is the tangent point, and Z3 ≠ 0 (Z3 = (2y)³Z1²Z2²). |
| `add_neg_x`, `add_neg_z` | Q = −P: X3 = 0 and Z3 = 0. |
| `add_neg_y_nz` | ... and Y3 ≠ 0, given `NoT2(b)`: R is the identity (0 : Y3 : 0). Y3 = y(2P)·(2y)³·Z1²Z2². |
| `add_id_l`, `add_id_r` | For every Y and every point: (0 : Y : 0) + Q = c·Q with c = Y²·Y2, and P + (0 : Y : 0) = c·P with c = Y1·Y². With the code's identity (0 : 1 : 0), c is Y2 (or Y1): nonzero for every valid point when there is no point of order 2. |
| `aff_is_add` | `add_aff(P, (x2, y2)) == add(P, (x2 : y2 : 1))` for all inputs: every law about add holds for add_aff with Z2 = 1. |
| `aff_chord_x`, `aff_chord_y` | The chord laws for add_aff directly. |
| `dbl_tan_x`, `dbl_tan_y`, `dbl_tan_nz` | double: the tangent point, Z3 = (2y)³Z⁴ ≠ 0. |
| `dbl_id` | double((0 : Y : 0)) == (0 : Y⁴ : 0). |
| `dbl_on_curve` | For every projective point on the curve (Y²Z = X³ + bZ³, identity included), double's output is on the curve. |
| `aadd_is_chord` | msm_ba.add_aff is the chord, by definition. |
| `chord_on_curve`, `tan_on_curve` | The chord and the tangent points are on the curve. |
| `add_is_b5`, `aff_is_b5`, `dbl_is_b5` | The copies with the code's mul15 equal the b3 = 3·5 instances. |
| `not2_7`, `chord_sat`, `tan_sat`, `neg_sat`, `on_curve_sat` | Non-vacuity, on y² = x³ + 5 over Z/7 (7 points, prime order like Pallas and Vesta): no point of order 2, and concrete points meeting each law's hypotheses. |

Together, for finite P and Q in a prime field without points of order 2: x1 ≠ x2 is the chord,
x1 = x2 forces y2 = ±y1 (the tangent, or the identity), and the identity on either side gives a
nonzero multiple of the other point. So add, add_aff and double compute the chord-and-tangent
law, which is the group law of the curve (that it is a group is standard, not proven here).

No law assumes p prime; `NoT2` is the only curve fact used, in the four "≠ 0" laws.

## How

`gen.py` mirrors `model.bend` as expressions (same operands, same order; a mismatch makes
the conversion fail, which the mutation check below exercises) and writes `certs/<name>.bend`:
the certificate and `lem_<name>`, the identity over Nat-level code, proven by
`ring/cert.bend`. `lemmas.bend` turns a projective point with Z·zi = 1 into (Z·x : Z·y : Z)
(`rep`) and supplies the "≠ 0" glue. `PROOF.bend` rewrites the inputs and applies the
generated lemma.

**Mutation check.** Swapping the operands of the subtraction that forms X3 in `model.bend`'s
`addh` makes `bend PROOF.bend` fail at `add_chord_x`.

## Not proven

* **add's projective on-curve identity** (the add analogue of `dbl_on_curve`). Its certificate
  has 3,150 monomials; the checker ran out of stack and the kernel out of fuel. The case laws
  above cover every input in a prime field without points of order 2, so this is not a gap in
  what is covered, only a missing single statement.
* That the field arithmetic implements Z/p (`fieldmul/`), and `add_nr`'s lazy reduction.
* The group law itself (associativity), GLV's endomorphism and decomposition (`glv_vesta_lz`),
  point decompression and encoding.

## Reproduce

```sh
python3 gen.py            # certs/*.bend (sympy), about 20 s
BEND_NO_TELEMETRY=1 ../../tools/heavy.sh bend PROOF.bend --verdict
```
