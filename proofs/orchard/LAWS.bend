import Base
import ../prims/natlib.bend as L
import ./fieldmodel.bend as F
import ./gates_model.bend as G

# Soundness of Orchard circuit gadgets, stated about the generated gate polynomials
# (gates_model.bend, emitted by gates.py from zcash/halo2/gen/orchard_cs.bend, whose decoded
# trees reproduce halo2's gate values on a real proof). Fp = Z/p with p = 1 + pp.
#
# Hypotheses, all explicit:
# - nzd: no zero divisors on canonical elements (true exactly when p is prime; Pallas' p is),
#   only where a law needs it,
# - l1: 1 <= p - 1 (p >= 2),
# - every queried evaluation is canonical (L.Le(v, pp), i.e. v < p),
# - the gate's selector value sel is invertible, fmul(si, sel) == 1 (the gate is active
#   on this row; in Fp that is exactly sel != 0),
# - the gate polynomial(s) evaluate to 0 (the constraint holds).
# Names in quotes are halo2's gate and constraint names (names/names.txt).

# Gate 0 "Orchard circuit checks", constraint "v_old - v_new = magnitude * sign":
# a0 = v_old, a1 = v_new, a2 = magnitude, a3 = sign.
law value_balance:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a0: Nat
  for +a1: Nat
  for +a2: Nat
  for +a3: Nat
  for +la0: L.Le(a0, pp)
  for +la1: L.Le(a1, pp)
  for h: {G.gate_0_0(pp, sel, a0, a1, a2, a3) == 0n : Nat}
  {a0 == F.fadd(1n+pp, a1, F.fmul(1n+pp, a2, a3)) : Nat}

# Gate 0, "Either v_old = 0, or root = anchor": a0 = v_old, a4 = root, a5 = anchor.
law anchor_or_zero:
  for +pp: Nat
  for nzd: F.NZD(pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a0: Nat
  for +a4: Nat
  for +a5: Nat
  for +la0: L.Le(a0, pp)
  for +la4: L.Le(a4, pp)
  for +la5: L.Le(a5, pp)
  for h: {G.gate_0_1(pp, sel, a0, a4, a5) == 0n : Nat}
  Either<&1, &1, {a0 == 0n : Nat}, {a4 == a5 : Nat}>

# Gate 0, "v_old = 0 or enable_spend = 1": a0 = v_old, a6 = enable_spend.
law spend_disabled_zero:
  for +pp: Nat
  for nzd: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a0: Nat
  for +a6: Nat
  for +la0: L.Le(a0, pp)
  for +la6: L.Le(a6, pp)
  for h: {G.gate_0_2(pp, sel, a0, a6) == 0n : Nat}
  Either<&1, &1, {a0 == 0n : Nat}, {a6 == 1n : Nat}>

# Gate 0, "v_new = 0 or enable_output = 1": a1 = v_new, a7 = enable_output.
law output_disabled_zero:
  for +pp: Nat
  for nzd: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a1: Nat
  for +a7: Nat
  for +la1: L.Le(a1, pp)
  for +la7: L.Le(a7, pp)
  for h: {G.gate_0_3(pp, sel, a1, a7) == 0n : Nat}
  Either<&1, &1, {a1 == 0n : Nat}, {a7 == 1n : Nat}>

# Gate 19 "Short fixed-base mul gate", "last_window_check": a5 is a bit.
law last_window_bit:
  for +pp: Nat
  for nzd: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a5: Nat
  for +la5: L.Le(a5, pp)
  for h: {G.gate_19_0(pp, sel, a5) == 0n : Nat}
  Either<&1, &1, {a5 == 0n : Nat}, {a5 == 1n : Nat}>

# Gate 13 "Decompose scalar for complete bits of variable-base mul", both constraints on
# one row ("bool_check", "y_switch"): the running sum steps by one bit,
# z_i = 2 * z_{i+1} + k with k in {0, 1} (a10 = z_i, a11 = z_{i+1}), and the y-coordinate
# switch follows the bit: k = 0 => a9 = -a21, k = 1 => a9 = a21.
law decompose_bit:
  for +pp: Nat
  for nzd: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a9: Nat
  for +a10: Nat
  for +a11: Nat
  for +a21: Nat
  for +la9: L.Le(a9, pp)
  for +la10: L.Le(a10, pp)
  for +la21: L.Le(a21, pp)
  for h0: {G.gate_13_0(pp, sel, a10, a11) == 0n : Nat}
  for h1: {G.gate_13_1(pp, sel, a9, a10, a11, a21) == 0n : Nat}
  Either<&1, &1, {a10 == F.fadd(1n+pp, F.fmul(1n+pp, 2n, a11), 0n) : Nat} & {F.fadd(1n+pp, a9, a21) == 0n : Nat}, {a10 == F.fadd(1n+pp, F.fmul(1n+pp, 2n, a11), 1n) : Nat} & {a9 == a21 : Nat}>

# Gate 26 "a' = b ⋅ swap + a ⋅ (1-swap)", all three constraints on one row ("a check",
# "b check", "swap is bool"): a0 = a, a1 = b, a2 = a', a3 = b', a4 = swap.
# The outputs are the inputs, either unchanged or exchanged, as the swap bit says.
law cond_swap:
  for +pp: Nat
  for nzd: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a0: Nat
  for +a1: Nat
  for +a2: Nat
  for +a3: Nat
  for +a4: Nat
  for +la0: L.Le(a0, pp)
  for +la1: L.Le(a1, pp)
  for +la2: L.Le(a2, pp)
  for +la3: L.Le(a3, pp)
  for +la4: L.Le(a4, pp)
  for h0: {G.gate_26_0(pp, sel, a0, a1, a2, a4) == 0n : Nat}
  for h1: {G.gate_26_1(pp, sel, a0, a1, a3, a4) == 0n : Nat}
  for h2: {G.gate_26_2(pp, sel, a4) == 0n : Nat}
  Either<&1, &1, {a4 == 0n : Nat} & {a2 == a0 : Nat} & {a3 == a1 : Nat}, {a4 == 1n : Nat} & {a2 == a1 : Nat} & {a3 == a0 : Nat}>
