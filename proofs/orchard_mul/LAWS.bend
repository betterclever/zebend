import Base
import ../prims/natlib.bend as L
import ../orchard/fieldmodel.bend as F
import ./rows.bend as R

# The base of variable-base scalar multiplication is anchored (NU6.2 fix), stated about the
# generated base-constancy constraints of the real Orchard circuit (gates_model.bend, emitted
# by gen.py from zcash/halo2/gen/orchard_cs.bend). Fp = Z/p, p = 1 + pp. See README.md for the
# statement in words and its relation to the protocol's Action statement.

# THEOREM (fixed circuit). If the first loop row's base coordinate x1 is copy-constrained
# to the external base coordinate g (the NU6.2 `copy_advice` at row 0 of the loop:
# anchor : x1 == g), and every base-constancy constraint holds on every loop row with a
# non-zero selector, then the base coordinate on EVERY loop row equals g.
# For each of the four constraints (x and y coordinate; hi and lo half of the scalar),
# for any number of rows. No primality hypothesis is needed.
law base_anchored:
  for rows: List<&2, R.Row>
  for +c: R.Check
  for +pp: Nat
  for +g: Nat
  for +lg: L.Le(g, pp)
  for +x1: Nat
  for anchor: {x1 == g : Nat}
  for h: R.Steps(rows, c, pp, x1)
  R.AllEq(rows, g)

# NON-VACUITY. For every number of rows n, every p >= 2 and every canonical g, the
# hypotheses of base_anchored are satisfiable: n rows whose base is g, with selector 1,
# satisfy every constraint, and the anchor holds.
law base_anchored_satisfiable:
  for n: Nat
  for +c: R.Check
  for +pp: Nat
  for +l1: L.Le(1n, pp)
  for +g: Nat
  for +lg: L.Le(g, pp)
  R.Steps(R.rep(n, g), c, pp, g)

# COUNTEREXAMPLE (pre-NU6.2 circuit: the same constraints WITHOUT the anchor). For every
# p >= 2, every canonical external base coordinate g and every number of loop rows
# n >= 1, there is a first-row coordinate x1 != g and n rows on which every base-constancy
# constraint holds with every selector active, yet no row's base equals g. So the
# constancy constraints alone do not tie the loop's base to the external base: the
# conclusion of base_anchored fails without its anchor hypothesis.
law unanchored_counterexample:
  for n: Nat
  for +c: R.Check
  for +pp: Nat
  for +l1: L.Le(1n, pp)
  for +g: Nat
  for +lg: L.Le(g, pp)
  exs x1: Nat
  {x1 != g : Nat} & R.Steps(R.rep(1n+n, x1), c, pp, x1) & (R.AllEq(R.rep(1n+n, x1), g) -> Empty)
