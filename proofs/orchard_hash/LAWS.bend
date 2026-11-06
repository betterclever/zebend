import Base
import ../prims/natlib.bend as L
import ../orchard/fieldmodel.bend as F
import ./gates_model.bend as G

# The equations of Orchard's Poseidon and Sinsemilla gates, stated about the generated gate
# polynomials (gates_model.bend, emitted by gen.py from zcash/halo2/gen/orchard_cs.bend). These
# gates are algebraic identities: each law turns 'the polynomial vanishes' into the equation
# X == Y the chip intends, with an invertible selector and canonical cells. Fp = Z/p,
# p = 1 + pp; large constants (MDS entries, 2^k) are parameters listed in gates_model.bend.

# Gate 21 "full round".
# Poseidon full round: the next state (a22, a18, a19) is MDS * (state + round constants)^5, with
# state a6, a7, a8 and round constants f4, f5, f6; the MDS entries are the parameters c<hex>.
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a8: advice column 8, rotation +0
#   a18: advice column 7, rotation +1
#   a19: advice column 8, rotation +1
#   a22: advice column 6, rotation +1
#   f4: fixed column 5
#   f5: fixed column 6
#   f6: fixed column 7
law gate_21:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +c07c045d5: Nat
  for +c0ab5e5b8: Nat
  for +c1d1aab4e: Nat
  for +c22f5b5e1: Nat
  for +c23316263: Nat
  for +c25cae259: Nat
  for +c2e29dd59: Nat
  for +c31916628: Nat
  for +c3bf76308: Nat
  for +a6: Nat
  for +a7: Nat
  for +a8: Nat
  for +a18: Nat
  for +a19: Nat
  for +a22: Nat
  for +f4: Nat
  for +f5: Nat
  for +f6: Nat
  for +la18: L.Le(a18, pp)
  for +la19: L.Le(a19, pp)
  for +la22: L.Le(a22, pp)
  for h0: {G.gate_21_0(pp, sel, c07c045d5, c0ab5e5b8, c31916628, a6, a7, a8, a22, f4, f5, f6) == 0n : Nat}
  for h1: {G.gate_21_1(pp, sel, c22f5b5e1, c23316263, c25cae259, a6, a7, a8, a18, f4, f5, f6) == 0n : Nat}
  for h2: {G.gate_21_2(pp, sel, c1d1aab4e, c2e29dd59, c3bf76308, a6, a7, a8, a19, f4, f5, f6) == 0n : Nat}
  {F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a6, f4), F.fadd(1n+pp, a6, f4)), F.fmul(1n+pp, F.fadd(1n+pp, a6, f4), F.fadd(1n+pp, a6, f4))), F.fadd(1n+pp, a6, f4)), c0ab5e5b8), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a7, f5), F.fadd(1n+pp, a7, f5)), F.fmul(1n+pp, F.fadd(1n+pp, a7, f5), F.fadd(1n+pp, a7, f5))), F.fadd(1n+pp, a7, f5)), c31916628)), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a8, f6), F.fadd(1n+pp, a8, f6)), F.fmul(1n+pp, F.fadd(1n+pp, a8, f6), F.fadd(1n+pp, a8, f6))), F.fadd(1n+pp, a8, f6)), c07c045d5)) == a22 : Nat} & {F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a6, f4), F.fadd(1n+pp, a6, f4)), F.fmul(1n+pp, F.fadd(1n+pp, a6, f4), F.fadd(1n+pp, a6, f4))), F.fadd(1n+pp, a6, f4)), c23316263), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a7, f5), F.fadd(1n+pp, a7, f5)), F.fmul(1n+pp, F.fadd(1n+pp, a7, f5), F.fadd(1n+pp, a7, f5))), F.fadd(1n+pp, a7, f5)), c25cae259)), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a8, f6), F.fadd(1n+pp, a8, f6)), F.fmul(1n+pp, F.fadd(1n+pp, a8, f6), F.fadd(1n+pp, a8, f6))), F.fadd(1n+pp, a8, f6)), c22f5b5e1)) == a18 : Nat} & {F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a6, f4), F.fadd(1n+pp, a6, f4)), F.fmul(1n+pp, F.fadd(1n+pp, a6, f4), F.fadd(1n+pp, a6, f4))), F.fadd(1n+pp, a6, f4)), c2e29dd59), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a7, f5), F.fadd(1n+pp, a7, f5)), F.fmul(1n+pp, F.fadd(1n+pp, a7, f5), F.fadd(1n+pp, a7, f5))), F.fadd(1n+pp, a7, f5)), c1d1aab4e)), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a8, f6), F.fadd(1n+pp, a8, f6)), F.fmul(1n+pp, F.fadd(1n+pp, a8, f6), F.fadd(1n+pp, a8, f6))), F.fadd(1n+pp, a8, f6)), c3bf76308)) == a19 : Nat}

# NON-VACUITY: every hypothesis of gate_21 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a6 = 0, a7 = 3, a8 = 7, a18 = 10, a19 = 1, a22 = 1, f4 = 4, f5 = 3, f6 = 8.
law gate_21_satisfiable:
  {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(10n, 10n) & L.Le(1n, 10n) & L.Le(1n, 10n) & {G.gate_21_0(10n, 1n, 0n, 2n, 1n, 0n, 3n, 7n, 1n, 4n, 3n, 8n) == 0n : Nat} & {G.gate_21_1(10n, 1n, 1n, 5n, 7n, 0n, 3n, 7n, 10n, 4n, 3n, 8n) == 0n : Nat} & {G.gate_21_2(10n, 1n, 10n, 4n, 7n, 0n, 3n, 7n, 1n, 4n, 3n, 8n) == 0n : Nat}

# Gate 22 "partial rounds".
# Two Poseidon partial rounds per row (halo2_poseidon's pow5 chip): a5 is the first S-box output,
# the last three equations equate the second half-round with the inverse-MDS image of the next state.
#   a5: advice column 5, rotation +0
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a8: advice column 8, rotation +0
#   a18: advice column 7, rotation +1
#   a19: advice column 8, rotation +1
#   a22: advice column 6, rotation +1
#   f4: fixed column 5
#   f5: fixed column 6
#   f6: fixed column 7
#   f7: fixed column 8
#   f8: fixed column 9
#   f9: fixed column 10
law gate_22:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +c07bf3684: Nat
  for +c07c045d5: Nat
  for +c0952e024: Nat
  for +c0ab5e5b8: Nat
  for +c0d0c2efd: Nat
  for +c1d1aab4e: Nat
  for +c1ec73725: Nat
  for +c22f5b5e1: Nat
  for +c23316263: Nat
  for +c25cae259: Nat
  for +c2aec6906: Nat
  for +c2cc057f3: Nat
  for +c2e29dd59: Nat
  for +c2eae5df8: Nat
  for +c2fcbba6f: Nat
  for +c31916628: Nat
  for +c32e7c439: Nat
  for +c3bf76308: Nat
  for +a5: Nat
  for +a6: Nat
  for +a7: Nat
  for +a8: Nat
  for +a18: Nat
  for +a19: Nat
  for +a22: Nat
  for +f4: Nat
  for +f5: Nat
  for +f6: Nat
  for +f7: Nat
  for +f8: Nat
  for +f9: Nat
  for +la5: L.Le(a5, pp)
  for h0: {G.gate_22_0(pp, sel, a5, a6, f4) == 0n : Nat}
  for h1: {G.gate_22_1(pp, sel, c07c045d5, c0ab5e5b8, c2cc057f3, c2eae5df8, c31916628, c32e7c439, a5, a7, a8, a18, a19, a22, f5, f6, f7) == 0n : Nat}
  for h2: {G.gate_22_2(pp, sel, c07bf3684, c0952e024, c22f5b5e1, c23316263, c25cae259, c2aec6906, a5, a7, a8, a18, a19, a22, f5, f6, f8) == 0n : Nat}
  for h3: {G.gate_22_3(pp, sel, c0d0c2efd, c1d1aab4e, c1ec73725, c2e29dd59, c2fcbba6f, c3bf76308, a5, a7, a8, a18, a19, a22, f5, f6, f9) == 0n : Nat}
  {F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a6, f4), F.fadd(1n+pp, a6, f4)), F.fmul(1n+pp, F.fadd(1n+pp, a6, f4), F.fadd(1n+pp, a6, f4))), F.fadd(1n+pp, a6, f4)) == a5 : Nat} & {F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a5, c0ab5e5b8), F.fmul(1n+pp, F.fadd(1n+pp, a7, f5), c31916628)), F.fmul(1n+pp, F.fadd(1n+pp, a8, f6), c07c045d5)), f7), F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a5, c0ab5e5b8), F.fmul(1n+pp, F.fadd(1n+pp, a7, f5), c31916628)), F.fmul(1n+pp, F.fadd(1n+pp, a8, f6), c07c045d5)), f7)), F.fmul(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a5, c0ab5e5b8), F.fmul(1n+pp, F.fadd(1n+pp, a7, f5), c31916628)), F.fmul(1n+pp, F.fadd(1n+pp, a8, f6), c07c045d5)), f7), F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a5, c0ab5e5b8), F.fmul(1n+pp, F.fadd(1n+pp, a7, f5), c31916628)), F.fmul(1n+pp, F.fadd(1n+pp, a8, f6), c07c045d5)), f7))), F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a5, c0ab5e5b8), F.fmul(1n+pp, F.fadd(1n+pp, a7, f5), c31916628)), F.fmul(1n+pp, F.fadd(1n+pp, a8, f6), c07c045d5)), f7)) == F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a22, c2cc057f3), F.fmul(1n+pp, a18, c32e7c439)), F.fmul(1n+pp, a19, c2eae5df8)) : Nat} & {F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a5, c23316263), F.fmul(1n+pp, F.fadd(1n+pp, a7, f5), c25cae259)), F.fmul(1n+pp, F.fadd(1n+pp, a8, f6), c22f5b5e1)), f8) == F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a22, c07bf3684), F.fmul(1n+pp, a18, c2aec6906)), F.fmul(1n+pp, a19, c0952e024)) : Nat} & {F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a5, c2e29dd59), F.fmul(1n+pp, F.fadd(1n+pp, a7, f5), c1d1aab4e)), F.fmul(1n+pp, F.fadd(1n+pp, a8, f6), c3bf76308)), f9) == F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a22, c2fcbba6f), F.fmul(1n+pp, a18, c1ec73725)), F.fmul(1n+pp, a19, c0d0c2efd)) : Nat}

# NON-VACUITY: every hypothesis of gate_22 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a5 = 1, a6 = 1, a7 = 0, a8 = 6, a18 = 0, a19 = 1, a22 = 3, f4 = 0, f5 = 8, f6 = 7, f7 = 1, f8 = 9, f9 = 3.
law gate_22_satisfiable:
  {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(1n, 10n) & {G.gate_22_0(10n, 1n, 1n, 1n, 0n) == 0n : Nat} & {G.gate_22_1(10n, 1n, 0n, 2n, 1n, 8n, 1n, 0n, 1n, 0n, 6n, 0n, 1n, 3n, 8n, 7n, 1n) == 0n : Nat} & {G.gate_22_2(10n, 1n, 2n, 0n, 1n, 5n, 7n, 3n, 1n, 0n, 6n, 0n, 1n, 3n, 8n, 7n, 9n) == 0n : Nat} & {G.gate_22_3(10n, 1n, 6n, 10n, 7n, 4n, 6n, 7n, 1n, 0n, 6n, 0n, 1n, 3n, 8n, 7n, 3n) == 0n : Nat}

# Gate 23 "pad-and-add".
# Poseidon absorption: next state = state + message.
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a18: advice column 7, rotation +1
#   a19: advice column 8, rotation +1
#   a20: advice column 6, rotation -1
#   a22: advice column 6, rotation +1
#   a23: advice column 7, rotation -1
#   a24: advice column 8, rotation -1
law gate_23:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a6: Nat
  for +a7: Nat
  for +a18: Nat
  for +a19: Nat
  for +a20: Nat
  for +a22: Nat
  for +a23: Nat
  for +a24: Nat
  for +la18: L.Le(a18, pp)
  for +la19: L.Le(a19, pp)
  for +la22: L.Le(a22, pp)
  for +la24: L.Le(a24, pp)
  for h0: {G.gate_23_0(pp, sel, a6, a20, a22) == 0n : Nat}
  for h1: {G.gate_23_1(pp, sel, a7, a18, a23) == 0n : Nat}
  for h2: {G.gate_23_2(pp, sel, a19, a24) == 0n : Nat}
  {F.fadd(1n+pp, a20, a6) == a22 : Nat} & {F.fadd(1n+pp, a23, a7) == a18 : Nat} & {a24 == a19 : Nat}

# NON-VACUITY: every hypothesis of gate_23 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a6 = 6, a7 = 9, a18 = 10, a19 = 0, a20 = 0, a22 = 6, a23 = 1, a24 = 0.
law gate_23_satisfiable:
  {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(10n, 10n) & L.Le(0n, 10n) & L.Le(6n, 10n) & L.Le(0n, 10n) & {G.gate_23_0(10n, 1n, 6n, 0n, 6n) == 0n : Nat} & {G.gate_23_1(10n, 1n, 9n, 10n, 1n) == 0n : Nat} & {G.gate_23_2(10n, 1n, 0n, 0n) == 0n : Nat}

# Gate 24 "Initial y_Q".
# Sinsemilla (first chip): 2 * y_Q (fixed f0) from the first row's x_A, x_P, lambda_1, lambda_2.
#   a0: advice column 0, rotation +0
#   a1: advice column 1, rotation +0
#   a3: advice column 3, rotation +0
#   a4: advice column 4, rotation +0
#   f0: fixed column 3
law gate_24:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a0: Nat
  for +a1: Nat
  for +a3: Nat
  for +a4: Nat
  for +f0: Nat
  for h0: {G.gate_24_0(pp, sel, a0, a1, a3, a4, f0) == 0n : Nat}
  {F.fmul(1n+pp, f0, 2n) == F.fmul(1n+pp, F.fadd(1n+pp, a3, a4), F.fadd(1n+pp, a0, F.fsub(1n+pp, 0n, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a3, a3), F.fsub(1n+pp, 0n, a0)), F.fsub(1n+pp, 0n, a1))))) : Nat}

# NON-VACUITY: every hypothesis of gate_24 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a0 = 8, a1 = 3, a3 = 10, a4 = 6, f0 = 1.
law gate_24_satisfiable:
  {F.fmul(11n, 1n, 1n) == 1n : Nat} & {G.gate_24_0(10n, 1n, 8n, 3n, 10n, 6n, 1n) == 0n : Nat}

# Gate 25 "Sinsemilla gate".
# Sinsemilla round (first chip): secant line and y check; f10 is the q_s2 / q_s3 tag.
#   a0: advice column 0, rotation +0
#   a1: advice column 1, rotation +0
#   a3: advice column 3, rotation +0
#   a4: advice column 4, rotation +0
#   a13: advice column 3, rotation +1
#   a14: advice column 4, rotation +1
#   a16: advice column 0, rotation +1
#   a17: advice column 1, rotation +1
#   f10: fixed column 12
law gate_25:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a0: Nat
  for +a1: Nat
  for +a3: Nat
  for +a4: Nat
  for +a13: Nat
  for +a14: Nat
  for +a16: Nat
  for +a17: Nat
  for +f10: Nat
  for h0: {G.gate_25_0(pp, sel, a0, a1, a3, a4, a16) == 0n : Nat}
  for h1: {G.gate_25_1(pp, sel, a0, a1, a3, a4, a13, a14, a16, a17, f10) == 0n : Nat}
  {F.fmul(1n+pp, a4, a4) == F.fadd(1n+pp, F.fadd(1n+pp, a16, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a3, a3), F.fsub(1n+pp, 0n, a0)), F.fsub(1n+pp, 0n, a1))), a0) : Nat} & {F.fmul(1n+pp, F.fmul(1n+pp, a4, 4n), F.fadd(1n+pp, a0, F.fsub(1n+pp, 0n, a16))) == F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a3, a4), F.fadd(1n+pp, a0, F.fsub(1n+pp, 0n, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a3, a3), F.fsub(1n+pp, 0n, a0)), F.fsub(1n+pp, 0n, a1))))), 2n), F.fmul(1n+pp, F.fadd(1n+pp, 2n, F.fsub(1n+pp, 0n, F.fmul(1n+pp, f10, F.fadd(1n+pp, f10, F.fsub(1n+pp, 0n, 1n))))), F.fmul(1n+pp, F.fadd(1n+pp, a13, a14), F.fadd(1n+pp, a16, F.fsub(1n+pp, 0n, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a13, a13), F.fsub(1n+pp, 0n, a16)), F.fsub(1n+pp, 0n, a17))))))), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, f10, F.fadd(1n+pp, f10, F.fsub(1n+pp, 0n, 1n))), 2n), a13)) : Nat}

# NON-VACUITY: every hypothesis of gate_25 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a0 = 6, a1 = 6, a3 = 5, a4 = 6, a13 = 0, a14 = 0, a16 = 6, a17 = 6, f10 = 7.
law gate_25_satisfiable:
  {F.fmul(11n, 1n, 1n) == 1n : Nat} & {G.gate_25_0(10n, 1n, 6n, 6n, 5n, 6n, 6n) == 0n : Nat} & {G.gate_25_1(10n, 1n, 6n, 6n, 5n, 6n, 0n, 0n, 6n, 6n, 7n) == 0n : Nat}

# Gate 28 "Initial y_Q".
# Sinsemilla (second chip).
#   a5: advice column 5, rotation +0
#   a6: advice column 6, rotation +0
#   a8: advice column 8, rotation +0
#   a9: advice column 9, rotation +0
#   f3: fixed column 4
law gate_28:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a5: Nat
  for +a6: Nat
  for +a8: Nat
  for +a9: Nat
  for +f3: Nat
  for h0: {G.gate_28_0(pp, sel, a5, a6, a8, a9, f3) == 0n : Nat}
  {F.fmul(1n+pp, f3, 2n) == F.fmul(1n+pp, F.fadd(1n+pp, a8, a9), F.fadd(1n+pp, a5, F.fsub(1n+pp, 0n, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a8, a8), F.fsub(1n+pp, 0n, a5)), F.fsub(1n+pp, 0n, a6))))) : Nat}

# NON-VACUITY: every hypothesis of gate_28 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a5 = 0, a6 = 3, a8 = 1, a9 = 5, f3 = 6.
law gate_28_satisfiable:
  {F.fmul(11n, 1n, 1n) == 1n : Nat} & {G.gate_28_0(10n, 1n, 0n, 3n, 1n, 5n, 6n) == 0n : Nat}

# Gate 29 "Sinsemilla gate".
# Sinsemilla round (second chip).
#   a5: advice column 5, rotation +0
#   a6: advice column 6, rotation +0
#   a8: advice column 8, rotation +0
#   a9: advice column 9, rotation +0
#   a10: advice column 9, rotation +1
#   a15: advice column 5, rotation +1
#   a19: advice column 8, rotation +1
#   a22: advice column 6, rotation +1
#   f13: fixed column 13
law gate_29:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a5: Nat
  for +a6: Nat
  for +a8: Nat
  for +a9: Nat
  for +a10: Nat
  for +a15: Nat
  for +a19: Nat
  for +a22: Nat
  for +f13: Nat
  for h0: {G.gate_29_0(pp, sel, a5, a6, a8, a9, a15) == 0n : Nat}
  for h1: {G.gate_29_1(pp, sel, a5, a6, a8, a9, a10, a15, a19, a22, f13) == 0n : Nat}
  {F.fmul(1n+pp, a9, a9) == F.fadd(1n+pp, F.fadd(1n+pp, a15, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a8, a8), F.fsub(1n+pp, 0n, a5)), F.fsub(1n+pp, 0n, a6))), a5) : Nat} & {F.fmul(1n+pp, F.fmul(1n+pp, a9, 4n), F.fadd(1n+pp, a5, F.fsub(1n+pp, 0n, a15))) == F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a8, a9), F.fadd(1n+pp, a5, F.fsub(1n+pp, 0n, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a8, a8), F.fsub(1n+pp, 0n, a5)), F.fsub(1n+pp, 0n, a6))))), 2n), F.fmul(1n+pp, F.fadd(1n+pp, 2n, F.fsub(1n+pp, 0n, F.fmul(1n+pp, f13, F.fadd(1n+pp, f13, F.fsub(1n+pp, 0n, 1n))))), F.fmul(1n+pp, F.fadd(1n+pp, a19, a10), F.fadd(1n+pp, a15, F.fsub(1n+pp, 0n, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a19, a19), F.fsub(1n+pp, 0n, a15)), F.fsub(1n+pp, 0n, a22))))))), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, f13, F.fadd(1n+pp, f13, F.fsub(1n+pp, 0n, 1n))), 2n), a19)) : Nat}

# NON-VACUITY: every hypothesis of gate_29 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a5 = 1, a6 = 5, a8 = 9, a9 = 4, a10 = 10, a15 = 6, a19 = 1, a22 = 0, f13 = 5.
law gate_29_satisfiable:
  {F.fmul(11n, 1n, 1n) == 1n : Nat} & {G.gate_29_0(10n, 1n, 1n, 5n, 9n, 4n, 6n) == 0n : Nat} & {G.gate_29_1(10n, 1n, 1n, 5n, 9n, 4n, 10n, 6n, 1n, 0n, 5n) == 0n : Nat}

# Gate 30 "a' = b ⋅ swap + a ⋅ (1-swap)".
# The second conditional-swap instance (../orchard's cond_swap is gate 26).
#   a5: advice column 5, rotation +0
#   a6: advice column 6, rotation +0
#   a7: advice column 7, rotation +0
#   a8: advice column 8, rotation +0
#   a9: advice column 9, rotation +0
law gate_30:
  for +pp: Nat
  for nzd0: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a5: Nat
  for +a6: Nat
  for +a7: Nat
  for +a8: Nat
  for +a9: Nat
  for +la7: L.Le(a7, pp)
  for +la8: L.Le(a8, pp)
  for +la9: L.Le(a9, pp)
  for h0: {G.gate_30_0(pp, sel, a5, a6, a7, a9) == 0n : Nat}
  for h1: {G.gate_30_1(pp, sel, a5, a6, a8, a9) == 0n : Nat}
  for h2: {G.gate_30_2(pp, sel, a9) == 0n : Nat}
  {a7 == F.fadd(1n+pp, F.fmul(1n+pp, a9, a6), F.fmul(1n+pp, F.fadd(1n+pp, 1n, F.fsub(1n+pp, 0n, a9)), a5)) : Nat} & {a8 == F.fadd(1n+pp, F.fmul(1n+pp, a9, a5), F.fmul(1n+pp, F.fadd(1n+pp, 1n, F.fsub(1n+pp, 0n, a9)), a6)) : Nat} & Either<&1, &1, {a9 == 0n : Nat}, {a9 == 1n : Nat}>

# NON-VACUITY: every hypothesis of gate_30 holds at once for p = 11 (pp = 10), sel = si = 1,
# the large constants reduced mod 11, and the row a5 = 5, a6 = 6, a7 = 5, a8 = 6, a9 = 0.
law gate_30_satisfiable:
  F.NZD(10n) & L.Le(1n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(5n, 10n) & L.Le(6n, 10n) & L.Le(0n, 10n) & {G.gate_30_0(10n, 1n, 5n, 6n, 5n, 0n) == 0n : Nat} & {G.gate_30_1(10n, 1n, 5n, 6n, 6n, 0n) == 0n : Nat} & {G.gate_30_2(10n, 1n, 0n) == 0n : Nat}
