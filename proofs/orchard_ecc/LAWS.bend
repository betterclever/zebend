import Base
import ../prims/natlib.bend as L
import ../orchard/fieldmodel.bend as F
import ./gates_model.bend as G

# Per-row soundness of Orchard's ECC-chip gates, stated about the generated gate polynomials
# (gates_model.bend, emitted by gen.py from zcash/halo2/gen/orchard_cs.bend). Fp = Z/p,
# p = 1 + pp. Hypotheses, all explicit: nzd<k> (no zero divisors among canonical elements,
# true for prime p; one copy per product the proof splits), l1 / lc<c> (the small constants
# used are below p), the selector is invertible, the cells named l<cell> are canonical, and
# every listed polynomial of the gate vanishes on the row. Large constants are parameters
# (values in gates_model.bend). Names in quotes are halo2's gate names
# (../orchard/names/names.txt); cells are the gate's queried evaluations.

# Gate 1 "Field element addition: c = a + b".
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a8: advice column 8, rotation +0
law gate_1:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a6: Nat
  for +a7: Nat
  for +a8: Nat
  for +la6: L.Le(a6, pp)
  for h0: {G.gate_1_0(pp, sel, a6, a7, a8) == 0n : Nat}
  {F.fadd(1n+pp, a7, a8) == a6 : Nat}

# NON-VACUITY: every hypothesis of gate_1 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a6 = 1, a7 = 2, a8 = 10.
law gate_1_satisfiable:
  {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(1n, 10n) & {G.gate_1_0(10n, 1n, 1n, 2n, 10n) == 0n : Nat}

# Gate 2 "Short lookup bitshift".
# a11 = word, a10 = inv_two_pow_s (constrained to 2^-s elsewhere), a9 = shifted word.
#   a9: advice column 9, rotation +0
#   a10: advice column 9, rotation +1
#   a11: advice column 9, rotation -1
law gate_2:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a9: Nat
  for +a10: Nat
  for +a11: Nat
  for +la9: L.Le(a9, pp)
  for h0: {G.gate_2_0(pp, sel, a9, a10, a11) == 0n : Nat}
  {F.fmul(1n+pp, F.fmul(1n+pp, a11, 1024n), a10) == a9 : Nat}

# NON-VACUITY: every hypothesis of gate_2 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a9 = 0, a10 = 7, a11 = 0.
law gate_2_satisfiable:
  {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(0n, 10n) & {G.gate_2_0(10n, 1n, 0n, 7n, 0n) == 0n : Nat}

# Gate 3 "witness point".
# halo2 writes q_point * x * on_curve and q_point * y * on_curve: the cell is part of the
# product, so each constraint gives x == 0 (resp. y == 0) or the curve equation y^2 - x^3 == 5.
#   a0: advice column 0, rotation +0
#   a1: advice column 1, rotation +0
law gate_3:
  for +pp: Nat
  for nzd0: F.NZD(pp)
  for nzd1: F.NZD(pp)
  for +lc5: L.Le(5n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a0: Nat
  for +a1: Nat
  for +la0: L.Le(a0, pp)
  for +la1: L.Le(a1, pp)
  for h0: {G.gate_3_0(pp, sel, a0, a1) == 0n : Nat}
  for h1: {G.gate_3_1(pp, sel, a0, a1) == 0n : Nat}
  Either<&1, &1, {a0 == 0n : Nat}, {F.fmul(1n+pp, a1, a1) == F.fadd(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, a0, a0), a0), 5n) : Nat}> & Either<&1, &1, {a1 == 0n : Nat}, {F.fmul(1n+pp, a1, a1) == F.fadd(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, a0, a0), a0), 5n) : Nat}>

# NON-VACUITY: every hypothesis of gate_3 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a0 = 0, a1 = 0.
law gate_3_satisfiable:
  F.NZD(10n) & F.NZD(10n) & L.Le(5n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(0n, 10n) & L.Le(0n, 10n) & {G.gate_3_0(10n, 1n, 0n, 0n) == 0n : Nat} & {G.gate_3_1(10n, 1n, 0n, 0n) == 0n : Nat}

# Gate 4 "witness non-identity point".
# a1 = y, a0 = x: y^2 - x^3 == 5.
#   a0: advice column 0, rotation +0
#   a1: advice column 1, rotation +0
law gate_4:
  for +pp: Nat
  for +lc5: L.Le(5n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a0: Nat
  for +a1: Nat
  for h0: {G.gate_4_0(pp, sel, a0, a1) == 0n : Nat}
  {F.fmul(1n+pp, a1, a1) == F.fadd(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, a0, a0), a0), 5n) : Nat}

# NON-VACUITY: every hypothesis of gate_4 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a0 = 0, a1 = 4.
law gate_4_satisfiable:
  L.Le(5n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & {G.gate_4_0(10n, 1n, 0n, 4n) == 0n : Nat}

# Gate 7 "q_mul_1 == 1 checks".
# init y_a, hi half (inv2 = 1/2 mod p).
#   a4: advice column 4, rotation +0
#   a13: advice column 3, rotation +1
#   a14: advice column 4, rotation +1
#   a15: advice column 5, rotation +1
#   a16: advice column 0, rotation +1
law gate_7:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +inv2: Nat
  for +a4: Nat
  for +a13: Nat
  for +a14: Nat
  for +a15: Nat
  for +a16: Nat
  for +la4: L.Le(a4, pp)
  for h0: {G.gate_7_0(pp, sel, inv2, a4, a13, a14, a15, a16) == 0n : Nat}
  {a4 == F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a14, a15), F.fadd(1n+pp, a13, F.fsub(1n+pp, 0n, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a14, a14), F.fsub(1n+pp, 0n, a13)), F.fsub(1n+pp, 0n, a16))))), inv2) : Nat}

# NON-VACUITY: every hypothesis of gate_7 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a4 = 8, a13 = 1, a14 = 3, a15 = 7, a16 = 0.
law gate_7_satisfiable:
  {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(8n, 10n) & {G.gate_7_0(10n, 1n, 9n, 8n, 1n, 3n, 7n, 0n) == 0n : Nat}

# Gate 10 "q_mul_1 == 1 checks".
# init y_a, lo half.
#   a8: advice column 8, rotation +0
#   a12: advice column 2, rotation +1
#   a16: advice column 0, rotation +1
#   a18: advice column 7, rotation +1
#   a19: advice column 8, rotation +1
law gate_10:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +inv2: Nat
  for +a8: Nat
  for +a12: Nat
  for +a16: Nat
  for +a18: Nat
  for +a19: Nat
  for +la8: L.Le(a8, pp)
  for h0: {G.gate_10_0(pp, sel, inv2, a8, a12, a16, a18, a19) == 0n : Nat}
  {a8 == F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a19, a12), F.fadd(1n+pp, a18, F.fsub(1n+pp, 0n, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a19, a19), F.fsub(1n+pp, 0n, a18)), F.fsub(1n+pp, 0n, a16))))), inv2) : Nat}

# NON-VACUITY: every hypothesis of gate_10 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a8 = 6, a12 = 0, a16 = 0, a18 = 4, a19 = 6.
law gate_10_satisfiable:
  {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(6n, 10n) & {G.gate_10_0(10n, 1n, 9n, 6n, 0n, 0n, 4n, 6n) == 0n : Nat}

# Gate 8 "q_mul_2 == 1 checks".
# Incomplete-addition loop, hi half: bool_check, secant_line, gradient_2. x_p_check /
# y_p_check are ../orchard_mul's base_anchored.
# Not covered by this law: polynomials 8_0, 8_1, 8_3.
#   a0: advice column 0, rotation +0
#   a3: advice column 3, rotation +0
#   a4: advice column 4, rotation +0
#   a5: advice column 5, rotation +0
#   a9: advice column 9, rotation +0
#   a11: advice column 9, rotation -1
#   a13: advice column 3, rotation +1
#   a14: advice column 4, rotation +1
#   a15: advice column 5, rotation +1
#   a16: advice column 0, rotation +1
law gate_8:
  for +pp: Nat
  for nzd0: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +inv2: Nat
  for +a0: Nat
  for +a3: Nat
  for +a4: Nat
  for +a5: Nat
  for +a9: Nat
  for +a11: Nat
  for +a13: Nat
  for +a14: Nat
  for +a15: Nat
  for +a16: Nat
  for +la3: L.Le(a3, pp)
  for h0: {G.gate_8_2(pp, sel, a9, a11) == 0n : Nat}
  for h1: {G.gate_8_4(pp, sel, a0, a3, a4, a5, a13) == 0n : Nat}
  for h2: {G.gate_8_5(pp, sel, inv2, a0, a3, a4, a5, a13, a14, a15, a16) == 0n : Nat}
  Either<&1, &1, {F.fadd(1n+pp, a9, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a11, 2n))) == 0n : Nat}, {F.fadd(1n+pp, a9, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a11, 2n))) == 1n : Nat}> & {F.fadd(1n+pp, F.fmul(1n+pp, a5, a5), F.fsub(1n+pp, 0n, a13)) == F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a4, a4), F.fsub(1n+pp, 0n, a3)), F.fsub(1n+pp, 0n, a0)), a3) : Nat} & {F.fmul(1n+pp, a5, F.fadd(1n+pp, a3, F.fsub(1n+pp, 0n, a13))) == F.fadd(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a4, a5), F.fadd(1n+pp, a3, F.fsub(1n+pp, 0n, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a4, a4), F.fsub(1n+pp, 0n, a3)), F.fsub(1n+pp, 0n, a0))))), inv2), F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a14, a15), F.fadd(1n+pp, a13, F.fsub(1n+pp, 0n, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a14, a14), F.fsub(1n+pp, 0n, a13)), F.fsub(1n+pp, 0n, a16))))), inv2)) : Nat}

# NON-VACUITY: every hypothesis of gate_8 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a0 = 0, a3 = 9, a4 = 1, a5 = 1, a9 = 6, a11 = 8, a13 = 0, a14 = 0, a15 = 2, a16 = 0.
law gate_8_satisfiable:
  F.NZD(10n) & L.Le(1n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(9n, 10n) & {G.gate_8_2(10n, 1n, 6n, 8n) == 0n : Nat} & {G.gate_8_4(10n, 1n, 0n, 9n, 1n, 1n, 0n) == 0n : Nat} & {G.gate_8_5(10n, 1n, 9n, 0n, 9n, 1n, 1n, 0n, 0n, 2n, 0n) == 0n : Nat}

# Gate 9 "q_mul_3 == 1 checks".
# Last loop row, hi half: bool_check, secant_line, gradient_2.
# Not covered by this law: polynomial 9_1.
#   a0: advice column 0, rotation +0
#   a3: advice column 3, rotation +0
#   a4: advice column 4, rotation +0
#   a5: advice column 5, rotation +0
#   a9: advice column 9, rotation +0
#   a11: advice column 9, rotation -1
#   a13: advice column 3, rotation +1
#   a14: advice column 4, rotation +1
law gate_9:
  for +pp: Nat
  for nzd0: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +inv2: Nat
  for +a0: Nat
  for +a3: Nat
  for +a4: Nat
  for +a5: Nat
  for +a9: Nat
  for +a11: Nat
  for +a13: Nat
  for +a14: Nat
  for +la3: L.Le(a3, pp)
  for +la14: L.Le(a14, pp)
  for h0: {G.gate_9_0(pp, sel, a9, a11) == 0n : Nat}
  for h1: {G.gate_9_2(pp, sel, a0, a3, a4, a5, a13) == 0n : Nat}
  for h2: {G.gate_9_3(pp, sel, inv2, a0, a3, a4, a5, a13, a14) == 0n : Nat}
  Either<&1, &1, {F.fadd(1n+pp, a9, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a11, 2n))) == 0n : Nat}, {F.fadd(1n+pp, a9, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a11, 2n))) == 1n : Nat}> & {F.fadd(1n+pp, F.fmul(1n+pp, a5, a5), F.fsub(1n+pp, 0n, a13)) == F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a4, a4), F.fsub(1n+pp, 0n, a3)), F.fsub(1n+pp, 0n, a0)), a3) : Nat} & {F.fmul(1n+pp, a5, F.fadd(1n+pp, a3, F.fsub(1n+pp, 0n, a13))) == F.fadd(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a4, a5), F.fadd(1n+pp, a3, F.fsub(1n+pp, 0n, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a4, a4), F.fsub(1n+pp, 0n, a3)), F.fsub(1n+pp, 0n, a0))))), inv2), a14) : Nat}

# NON-VACUITY: every hypothesis of gate_9 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a0 = 2, a3 = 3, a4 = 2, a5 = 1, a9 = 2, a11 = 1, a13 = 10, a14 = 6.
law gate_9_satisfiable:
  F.NZD(10n) & L.Le(1n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(3n, 10n) & L.Le(6n, 10n) & {G.gate_9_0(10n, 1n, 2n, 1n) == 0n : Nat} & {G.gate_9_2(10n, 1n, 2n, 3n, 2n, 1n, 10n) == 0n : Nat} & {G.gate_9_3(10n, 1n, 9n, 2n, 3n, 2n, 1n, 10n, 6n) == 0n : Nat}

# Gate 11 "q_mul_2 == 1 checks".
# Incomplete-addition loop, lo half.
# Not covered by this law: polynomials 11_0, 11_1, 11_3.
#   a0: advice column 0, rotation +0
#   a2: advice column 2, rotation +0
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a8: advice column 8, rotation +0
#   a12: advice column 2, rotation +1
#   a16: advice column 0, rotation +1
#   a18: advice column 7, rotation +1
#   a19: advice column 8, rotation +1
#   a20: advice column 6, rotation -1
law gate_11:
  for +pp: Nat
  for nzd0: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +inv2: Nat
  for +a0: Nat
  for +a2: Nat
  for +a6: Nat
  for +a7: Nat
  for +a8: Nat
  for +a12: Nat
  for +a16: Nat
  for +a18: Nat
  for +a19: Nat
  for +a20: Nat
  for +la7: L.Le(a7, pp)
  for h0: {G.gate_11_2(pp, sel, a6, a20) == 0n : Nat}
  for h1: {G.gate_11_4(pp, sel, a0, a2, a7, a8, a18) == 0n : Nat}
  for h2: {G.gate_11_5(pp, sel, inv2, a0, a2, a7, a8, a12, a16, a18, a19) == 0n : Nat}
  Either<&1, &1, {F.fadd(1n+pp, a6, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a20, 2n))) == 0n : Nat}, {F.fadd(1n+pp, a6, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a20, 2n))) == 1n : Nat}> & {F.fadd(1n+pp, F.fmul(1n+pp, a2, a2), F.fsub(1n+pp, 0n, a18)) == F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a8, a8), F.fsub(1n+pp, 0n, a7)), F.fsub(1n+pp, 0n, a0)), a7) : Nat} & {F.fmul(1n+pp, a2, F.fadd(1n+pp, a7, F.fsub(1n+pp, 0n, a18))) == F.fadd(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a8, a2), F.fadd(1n+pp, a7, F.fsub(1n+pp, 0n, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a8, a8), F.fsub(1n+pp, 0n, a7)), F.fsub(1n+pp, 0n, a0))))), inv2), F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a19, a12), F.fadd(1n+pp, a18, F.fsub(1n+pp, 0n, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a19, a19), F.fsub(1n+pp, 0n, a18)), F.fsub(1n+pp, 0n, a16))))), inv2)) : Nat}

# NON-VACUITY: every hypothesis of gate_11 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a0 = 5, a2 = 10, a6 = 5, a7 = 8, a8 = 9, a12 = 4, a16 = 4, a18 = 2, a19 = 10, a20 = 2.
law gate_11_satisfiable:
  F.NZD(10n) & L.Le(1n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(8n, 10n) & {G.gate_11_2(10n, 1n, 5n, 2n) == 0n : Nat} & {G.gate_11_4(10n, 1n, 5n, 10n, 8n, 9n, 2n) == 0n : Nat} & {G.gate_11_5(10n, 1n, 9n, 5n, 10n, 8n, 9n, 4n, 4n, 2n, 10n) == 0n : Nat}

# Gate 12 "q_mul_3 == 1 checks".
# Last loop row, lo half.
# Not covered by this law: polynomial 12_1.
#   a0: advice column 0, rotation +0
#   a2: advice column 2, rotation +0
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a8: advice column 8, rotation +0
#   a18: advice column 7, rotation +1
#   a19: advice column 8, rotation +1
#   a20: advice column 6, rotation -1
law gate_12:
  for +pp: Nat
  for nzd0: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +inv2: Nat
  for +a0: Nat
  for +a2: Nat
  for +a6: Nat
  for +a7: Nat
  for +a8: Nat
  for +a18: Nat
  for +a19: Nat
  for +a20: Nat
  for +la7: L.Le(a7, pp)
  for +la19: L.Le(a19, pp)
  for h0: {G.gate_12_0(pp, sel, a6, a20) == 0n : Nat}
  for h1: {G.gate_12_2(pp, sel, a0, a2, a7, a8, a18) == 0n : Nat}
  for h2: {G.gate_12_3(pp, sel, inv2, a0, a2, a7, a8, a18, a19) == 0n : Nat}
  Either<&1, &1, {F.fadd(1n+pp, a6, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a20, 2n))) == 0n : Nat}, {F.fadd(1n+pp, a6, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a20, 2n))) == 1n : Nat}> & {F.fadd(1n+pp, F.fmul(1n+pp, a2, a2), F.fsub(1n+pp, 0n, a18)) == F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a8, a8), F.fsub(1n+pp, 0n, a7)), F.fsub(1n+pp, 0n, a0)), a7) : Nat} & {F.fmul(1n+pp, a2, F.fadd(1n+pp, a7, F.fsub(1n+pp, 0n, a18))) == F.fadd(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a8, a2), F.fadd(1n+pp, a7, F.fsub(1n+pp, 0n, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a8, a8), F.fsub(1n+pp, 0n, a7)), F.fsub(1n+pp, 0n, a0))))), inv2), a19) : Nat}

# NON-VACUITY: every hypothesis of gate_12 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a0 = 4, a2 = 5, a6 = 7, a7 = 5, a8 = 4, a18 = 2, a19 = 1, a20 = 3.
law gate_12_satisfiable:
  F.NZD(10n) & L.Le(1n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(5n, 10n) & L.Le(1n, 10n) & {G.gate_12_0(10n, 1n, 7n, 3n) == 0n : Nat} & {G.gate_12_2(10n, 1n, 4n, 5n, 5n, 4n, 2n) == 0n : Nat} & {G.gate_12_3(10n, 1n, 9n, 4n, 5n, 5n, 4n, 2n, 1n) == 0n : Nat}

# Gate 14 "overflow checks".
# Constraints in order: s_check, recovery, lo_zero, s_minus_lo_130_check, canonicity. a23 = k_254, the
# bit whose value 1 forces the lo_zero and s_minus_lo_130 conditions; a22 is an inverse witness.
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a8: advice column 8, rotation +0
#   a18: advice column 7, rotation +1
#   a20: advice column 6, rotation -1
#   a22: advice column 6, rotation +1
#   a23: advice column 7, rotation -1
law gate_14:
  for +pp: Nat
  for nzd0: F.NZD(pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +t124: Nat
  for +lt124: L.Le(t124, pp)
  for +tQ: Nat
  for +ltQ: L.Le(tQ, pp)
  for +a6: Nat
  for +a7: Nat
  for +a8: Nat
  for +a18: Nat
  for +a20: Nat
  for +a22: Nat
  for +a23: Nat
  for +la6: L.Le(a6, pp)
  for +la7: L.Le(a7, pp)
  for +la8: L.Le(a8, pp)
  for +la18: L.Le(a18, pp)
  for +la20: L.Le(a20, pp)
  for h0: {G.gate_14_0(pp, sel, t124, a7, a8, a23) == 0n : Nat}
  for h1: {G.gate_14_1(pp, sel, tQ, a7, a20) == 0n : Nat}
  for h2: {G.gate_14_2(pp, sel, t124, a6, a23) == 0n : Nat}
  for h3: {G.gate_14_3(pp, sel, a18, a23) == 0n : Nat}
  for h4: {G.gate_14_4(pp, sel, a6, a18, a22, a23) == 0n : Nat}
  {a8 == F.fadd(1n+pp, a7, F.fmul(1n+pp, a23, F.fmul(1n+pp, t124, 64n))) : Nat} & {a20 == F.fadd(1n+pp, a7, tQ) : Nat} & ({a23 == 1n : Nat} -> {a6 == t124 : Nat}) & ({a23 == 1n : Nat} -> {a18 == 0n : Nat}) & Either<&1, &1, {F.fmul(1n+pp, F.fadd(1n+pp, 1n, F.fsub(1n+pp, 0n, a23)), F.fadd(1n+pp, 1n, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a6, a22)))) == 0n : Nat}, {a18 == 0n : Nat}>

# NON-VACUITY: every hypothesis of gate_14 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a6 = 9, a7 = 3, a8 = 3, a18 = 9, a20 = 7, a22 = 5, a23 = 0.
law gate_14_satisfiable:
  F.NZD(10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(5n, 10n) & L.Le(4n, 10n) & L.Le(9n, 10n) & L.Le(3n, 10n) & L.Le(3n, 10n) & L.Le(9n, 10n) & L.Le(7n, 10n) & {G.gate_14_0(10n, 1n, 5n, 3n, 3n, 0n) == 0n : Nat} & {G.gate_14_1(10n, 1n, 4n, 3n, 7n) == 0n : Nat} & {G.gate_14_2(10n, 1n, 5n, 9n, 0n) == 0n : Nat} & {G.gate_14_3(10n, 1n, 9n, 0n) == 0n : Nat} & {G.gate_14_4(10n, 1n, 9n, 9n, 5n, 0n) == 0n : Nat}

# Gate 16 "range check".
# Fixed-base running sum: each 3-bit window a4 - 8 * a14 is at most 7.
#   a4: advice column 4, rotation +0
#   a14: advice column 4, rotation +1
law gate_16:
  for +pp: Nat
  for nzd0: F.NZD(pp)
  for nzd1: F.NZD(pp)
  for nzd2: F.NZD(pp)
  for nzd3: F.NZD(pp)
  for nzd4: F.NZD(pp)
  for nzd5: F.NZD(pp)
  for nzd6: F.NZD(pp)
  for +lc7: L.Le(7n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a4: Nat
  for +a14: Nat
  for h0: {G.gate_16_0(pp, sel, a4, a14) == 0n : Nat}
  L.Le(F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n))), 7n)

# NON-VACUITY: every hypothesis of gate_16 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a4 = 2, a14 = 4.
law gate_16_satisfiable:
  F.NZD(10n) & F.NZD(10n) & F.NZD(10n) & F.NZD(10n) & F.NZD(10n) & F.NZD(10n) & F.NZD(10n) & L.Le(7n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & {G.gate_16_0(10n, 1n, 2n, 4n) == 0n : Nat}

# Gate 17 "Running sum coordinates check".
# check x: x is the Lagrange interpolation of the window (fixed coefficients f0, f3..f9);
# check y: u^2 == y + z (f2 = z); on-curve.
#   a0: advice column 0, rotation +0
#   a1: advice column 1, rotation +0
#   a4: advice column 4, rotation +0
#   a5: advice column 5, rotation +0
#   a14: advice column 4, rotation +1
#   f0: fixed column 3
#   f2: fixed column 11
#   f3: fixed column 4
#   f4: fixed column 5
#   f5: fixed column 6
#   f6: fixed column 7
#   f7: fixed column 8
#   f8: fixed column 9
#   f9: fixed column 10
law gate_17:
  for +pp: Nat
  for +lc5: L.Le(5n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a0: Nat
  for +a1: Nat
  for +a4: Nat
  for +a5: Nat
  for +a14: Nat
  for +f0: Nat
  for +f2: Nat
  for +f3: Nat
  for +f4: Nat
  for +f5: Nat
  for +f6: Nat
  for +f7: Nat
  for +f8: Nat
  for +f9: Nat
  for +la0: L.Le(a0, pp)
  for +la1: L.Le(a1, pp)
  for +lf2: L.Le(f2, pp)
  for h0: {G.gate_17_0(pp, sel, a0, a4, a14, f0, f3, f4, f5, f6, f7, f8, f9) == 0n : Nat}
  for h1: {G.gate_17_1(pp, sel, a1, a5, f2) == 0n : Nat}
  for h2: {G.gate_17_2(pp, sel, a0, a1) == 0n : Nat}
  {F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, 0n, F.fmul(1n+pp, 1n, f0)), F.fmul(1n+pp, F.fmul(1n+pp, 1n, F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), f3)), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, 1n, F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), f4)), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, 1n, F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), f5)), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, 1n, F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), f6)), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, 1n, F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), f7)), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, 1n, F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), f8)), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, 1n, F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a14, 8n)))), f9)) == a0 : Nat} & {F.fmul(1n+pp, a5, a5) == F.fadd(1n+pp, a1, f2) : Nat} & {F.fmul(1n+pp, a1, a1) == F.fadd(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, a0, a0), a0), 5n) : Nat}

# NON-VACUITY: every hypothesis of gate_17 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a0 = 5, a1 = 3, a4 = 9, a5 = 2, a14 = 2, f0 = 7, f2 = 1, f3 = 9, f4 = 8, f5 = 8, f6 = 5, f7 = 7, f8 = 1, f9 = 0.
law gate_17_satisfiable:
  L.Le(5n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(5n, 10n) & L.Le(3n, 10n) & L.Le(1n, 10n) & {G.gate_17_0(10n, 1n, 5n, 9n, 2n, 7n, 9n, 8n, 8n, 5n, 7n, 1n, 0n) == 0n : Nat} & {G.gate_17_1(10n, 1n, 3n, 2n, 1n) == 0n : Nat} & {G.gate_17_2(10n, 1n, 5n, 3n) == 0n : Nat}

# Gate 18 "Full-width fixed-base scalar mul".
# As gate 17 for a window a4, plus the window range check a4 <= 7.
#   a0: advice column 0, rotation +0
#   a1: advice column 1, rotation +0
#   a4: advice column 4, rotation +0
#   a5: advice column 5, rotation +0
#   f0: fixed column 3
#   f2: fixed column 11
#   f3: fixed column 4
#   f4: fixed column 5
#   f5: fixed column 6
#   f6: fixed column 7
#   f7: fixed column 8
#   f8: fixed column 9
#   f9: fixed column 10
law gate_18:
  for +pp: Nat
  for nzd0: F.NZD(pp)
  for nzd1: F.NZD(pp)
  for nzd2: F.NZD(pp)
  for nzd3: F.NZD(pp)
  for nzd4: F.NZD(pp)
  for nzd5: F.NZD(pp)
  for nzd6: F.NZD(pp)
  for +lc5: L.Le(5n, pp)
  for +lc7: L.Le(7n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a0: Nat
  for +a1: Nat
  for +a4: Nat
  for +a5: Nat
  for +f0: Nat
  for +f2: Nat
  for +f3: Nat
  for +f4: Nat
  for +f5: Nat
  for +f6: Nat
  for +f7: Nat
  for +f8: Nat
  for +f9: Nat
  for +la0: L.Le(a0, pp)
  for +la1: L.Le(a1, pp)
  for +la4: L.Le(a4, pp)
  for +lf2: L.Le(f2, pp)
  for h0: {G.gate_18_0(pp, sel, a0, a4, f0, f3, f4, f5, f6, f7, f8, f9) == 0n : Nat}
  for h1: {G.gate_18_1(pp, sel, a1, a5, f2) == 0n : Nat}
  for h2: {G.gate_18_2(pp, sel, a0, a1) == 0n : Nat}
  for h3: {G.gate_18_3(pp, sel, a4) == 0n : Nat}
  {F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, 0n, F.fmul(1n+pp, 1n, f0)), F.fmul(1n+pp, F.fmul(1n+pp, 1n, a4), f3)), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, 1n, a4), a4), f4)), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, 1n, a4), a4), a4), f5)), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, 1n, a4), a4), a4), a4), f6)), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, 1n, a4), a4), a4), a4), a4), f7)), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, 1n, a4), a4), a4), a4), a4), a4), f8)), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, 1n, a4), a4), a4), a4), a4), a4), a4), f9)) == a0 : Nat} & {F.fmul(1n+pp, a5, a5) == F.fadd(1n+pp, a1, f2) : Nat} & {F.fmul(1n+pp, a1, a1) == F.fadd(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, a0, a0), a0), 5n) : Nat} & L.Le(a4, 7n)

# NON-VACUITY: every hypothesis of gate_18 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a0 = 8, a1 = 0, a4 = 7, a5 = 0, f0 = 2, f2 = 0, f3 = 0, f4 = 8, f5 = 7, f6 = 4, f7 = 1, f8 = 4, f9 = 4.
law gate_18_satisfiable:
  F.NZD(10n) & F.NZD(10n) & F.NZD(10n) & F.NZD(10n) & F.NZD(10n) & F.NZD(10n) & F.NZD(10n) & L.Le(5n, 10n) & L.Le(7n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(8n, 10n) & L.Le(0n, 10n) & L.Le(7n, 10n) & L.Le(0n, 10n) & {G.gate_18_0(10n, 1n, 8n, 7n, 2n, 0n, 8n, 7n, 4n, 1n, 4n, 4n) == 0n : Nat} & {G.gate_18_1(10n, 1n, 0n, 0n, 0n) == 0n : Nat} & {G.gate_18_2(10n, 1n, 8n, 0n) == 0n : Nat} & {G.gate_18_3(10n, 1n, 7n) == 0n : Nat}

# Gate 19 "Short fixed-base mul gate".
# a5 = last window bit, a4 = sign, a1 / a3 = the y-coordinate before / after the sign: sign^2 == 1,
# a3 == +/- a1, a3 == sign * a1 (sign = +/-1 itself is short_sign in ECC.bend).
#   a1: advice column 1, rotation +0
#   a3: advice column 3, rotation +0
#   a4: advice column 4, rotation +0
#   a5: advice column 5, rotation +0
law gate_19:
  for +pp: Nat
  for nzd0: F.NZD(pp)
  for nzd1: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a1: Nat
  for +a3: Nat
  for +a4: Nat
  for +a5: Nat
  for +la1: L.Le(a1, pp)
  for +la3: L.Le(a3, pp)
  for +la5: L.Le(a5, pp)
  for h0: {G.gate_19_0(pp, sel, a5) == 0n : Nat}
  for h1: {G.gate_19_1(pp, sel, a4) == 0n : Nat}
  for h2: {G.gate_19_2(pp, sel, a1, a3) == 0n : Nat}
  for h3: {G.gate_19_3(pp, sel, a1, a3, a4) == 0n : Nat}
  Either<&1, &1, {a5 == 0n : Nat}, {a5 == 1n : Nat}> & {F.fmul(1n+pp, a4, a4) == 1n : Nat} & Either<&1, &1, {a1 == a3 : Nat}, {F.fadd(1n+pp, a1, a3) == 0n : Nat}> & {F.fmul(1n+pp, a4, a1) == a3 : Nat}

# NON-VACUITY: every hypothesis of gate_19 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a1 = 7, a3 = 4, a4 = 10, a5 = 0.
law gate_19_satisfiable:
  F.NZD(10n) & F.NZD(10n) & L.Le(1n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(7n, 10n) & L.Le(4n, 10n) & L.Le(0n, 10n) & {G.gate_19_0(10n, 1n, 0n) == 0n : Nat} & {G.gate_19_1(10n, 1n, 10n) == 0n : Nat} & {G.gate_19_2(10n, 1n, 7n, 4n) == 0n : Nat} & {G.gate_19_3(10n, 1n, 7n, 4n, 10n) == 0n : Nat}
