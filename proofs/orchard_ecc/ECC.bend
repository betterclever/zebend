import Base
import ../prims/natlib.bend as L
import ../orchard/fieldmodel.bend as F
import ./gates_model.bend as G

# What Orchard's ECC addition gates compute, stated about the generated polynomials
# (gates_model.bend). Fp = Z/p, p = 1 + pp. "x != 0" is stated as "x has an inverse"
# (xi * x == 1): in Fp the two are the same, and an inverse is data a law can use twice.
# Every law has a non-vacuity companion: all of its hypotheses at once, at p = 11 (pp = 10),
# on a concrete row, with sel = si = 1.

# --- complete addition (gate 6 "complete addition") -------------------------------------
# Cells: a0 = x_p, a1 = y_p, a2 = x_q, a3 = y_q, a4 = lambda, a5 = alpha, a6 = beta,
# a7 = gamma, a8 = delta, a12 = x_r, a13 = y_r (R = P + Q). The identity is (0, 0).
# The five laws cover every case of (P, Q): P = O; Q = O; Q = -P (x_q = x_p, y_q + y_p = 0);
# P, Q != O with x_q != x_p; P, Q != O with x_q = x_p and y_q + y_p != 0 (doubling).
# (That the five cases are exhaustive is the field fact that every element is zero or
# invertible, not restated here.)

# P = O (x_p == 0): R = Q. Constraints "4a"/"4b" (gate_6_6, gate_6_7).
law cadd_p_identity:
  for +pp: Nat
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a0: Nat
  for +a2: Nat
  for +a3: Nat
  for +a6: Nat
  for +a12: Nat
  for +a13: Nat
  for +la2: L.Le(a2, pp)
  for +la3: L.Le(a3, pp)
  for +la12: L.Le(a12, pp)
  for +la13: L.Le(a13, pp)
  for +z: {a0 == 0n : Nat}
  for h6: {G.gate_6_6(pp, sel, a0, a2, a6, a12) == 0n : Nat}
  for h7: {G.gate_6_7(pp, sel, a0, a3, a6, a13) == 0n : Nat}
  {a12 == a2 : Nat} & {a13 == a3 : Nat}

law cadd_p_identity_satisfiable:
  L.Le(1n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(3n, 10n) & L.Le(4n, 10n) & L.Le(3n, 10n) & L.Le(4n, 10n) & {0n == 0n : Nat}
    & {G.gate_6_6(10n, 1n, 0n, 3n, 0n, 3n) == 0n : Nat} & {G.gate_6_7(10n, 1n, 0n, 4n, 0n, 4n) == 0n : Nat}

# Q = O (x_q == 0): R = P. Constraints "5a"/"5b" (gate_6_8, gate_6_9).
law cadd_q_identity:
  for +pp: Nat
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a0: Nat
  for +a1: Nat
  for +a2: Nat
  for +a7: Nat
  for +a12: Nat
  for +a13: Nat
  for +la0: L.Le(a0, pp)
  for +la1: L.Le(a1, pp)
  for +la12: L.Le(a12, pp)
  for +la13: L.Le(a13, pp)
  for +z: {a2 == 0n : Nat}
  for h8: {G.gate_6_8(pp, sel, a0, a2, a7, a12) == 0n : Nat}
  for h9: {G.gate_6_9(pp, sel, a1, a2, a7, a13) == 0n : Nat}
  {a12 == a0 : Nat} & {a13 == a1 : Nat}

law cadd_q_identity_satisfiable:
  L.Le(1n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(3n, 10n) & L.Le(4n, 10n) & L.Le(3n, 10n) & L.Le(4n, 10n) & {0n == 0n : Nat}
    & {G.gate_6_8(10n, 1n, 3n, 0n, 0n, 3n) == 0n : Nat} & {G.gate_6_9(10n, 1n, 4n, 0n, 0n, 4n) == 0n : Nat}

# Q = -P (x_q == x_p and y_q + y_p == 0): R = O = (0, 0). Constraints "6a"/"6b"
# (gate_6_10, gate_6_11), whatever alpha and delta are.
law cadd_inverse:
  for +pp: Nat
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a0: Nat
  for +a1: Nat
  for +a2: Nat
  for +a3: Nat
  for +a5: Nat
  for +a8: Nat
  for +a12: Nat
  for +a13: Nat
  for +la0: L.Le(a0, pp)
  for +la12: L.Le(a12, pp)
  for +la13: L.Le(a13, pp)
  for +zx: {a2 == a0 : Nat}
  for +zy: {F.fadd(1n+pp, a3, a1) == 0n : Nat}
  for h10: {G.gate_6_10(pp, sel, a0, a1, a2, a3, a5, a8, a12) == 0n : Nat}
  for h11: {G.gate_6_11(pp, sel, a0, a1, a2, a3, a5, a8, a13) == 0n : Nat}
  {a12 == 0n : Nat} & {a13 == 0n : Nat}

law cadd_inverse_satisfiable:
  L.Le(1n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(3n, 10n) & L.Le(0n, 10n) & L.Le(0n, 10n) & {3n == 3n : Nat} & {F.fadd(11n, 7n, 4n) == 0n : Nat}
    & {G.gate_6_10(10n, 1n, 3n, 4n, 3n, 7n, 0n, 0n, 0n) == 0n : Nat} & {G.gate_6_11(10n, 1n, 3n, 4n, 3n, 7n, 0n, 0n, 0n) == 0n : Nat}

# P, Q != O and x_q != x_p (all three invertible): lambda is the chord slope,
# (x_q - x_p) lambda == y_q - y_p, and R is the chord-rule sum:
# x_r == lambda^2 - x_p - x_q, y_r == lambda (x_p - x_r) - y_p.
# Constraints "1", "3a", "3b" (gate_6_0, gate_6_2, gate_6_3).
law cadd_distinct:
  for +pp: Nat
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a0: Nat
  for +a1: Nat
  for +a2: Nat
  for +a3: Nat
  for +a4: Nat
  for +a12: Nat
  for +a13: Nat
  for +la12: L.Le(a12, pp)
  for +la13: L.Le(a13, pp)
  for +ip: Nat
  for +hp: {F.fmul(1n+pp, ip, a0) == 1n : Nat}
  for +iq: Nat
  for +hq: {F.fmul(1n+pp, iq, a2) == 1n : Nat}
  for +id: Nat
  for +hd: {F.fmul(1n+pp, id, F.fadd(1n+pp, a2, F.fsub(1n+pp, 0n, a0))) == 1n : Nat}
  for h0: {G.gate_6_0(pp, sel, a0, a1, a2, a3, a4) == 0n : Nat}
  for h2: {G.gate_6_2(pp, sel, a0, a2, a4, a12) == 0n : Nat}
  for h3: {G.gate_6_3(pp, sel, a0, a1, a2, a4, a12, a13) == 0n : Nat}
  {F.fmul(1n+pp, F.fadd(1n+pp, a2, F.fsub(1n+pp, 0n, a0)), a4) == F.fadd(1n+pp, a3, F.fsub(1n+pp, 0n, a1)) : Nat}
    & {F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a4, a4), F.fsub(1n+pp, 0n, a0)), F.fsub(1n+pp, 0n, a2)) == a12 : Nat}
    & {F.fadd(1n+pp, F.fmul(1n+pp, a4, F.fadd(1n+pp, a0, F.fsub(1n+pp, 0n, a12))), F.fsub(1n+pp, 0n, a1)) == a13 : Nat}

# Row: x_p = 1, y_p = 0, x_q = 2, y_q = 5, lambda = 5, x_r = 0, y_r = 5; inverses 1, 6, 1.
law cadd_distinct_satisfiable:
  L.Le(1n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(0n, 10n) & L.Le(5n, 10n)
    & {F.fmul(11n, 1n, 1n) == 1n : Nat} & {F.fmul(11n, 6n, 2n) == 1n : Nat} & {F.fmul(11n, 1n, F.fadd(11n, 2n, F.fsub(11n, 0n, 1n))) == 1n : Nat}
    & {G.gate_6_0(10n, 1n, 1n, 0n, 2n, 5n, 5n) == 0n : Nat} & {G.gate_6_2(10n, 1n, 1n, 2n, 5n, 0n) == 0n : Nat} & {G.gate_6_3(10n, 1n, 1n, 0n, 2n, 5n, 0n, 5n) == 0n : Nat}

# Doubling: P, Q != O, x_q == x_p and y_q + y_p invertible: lambda is the tangent slope,
# 2 y_p lambda == 3 x_p^2, and R is given by the same formulas.
# Constraints "2", "3c", "3d" (gate_6_1, gate_6_4, gate_6_5).
law cadd_double:
  for +pp: Nat
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a0: Nat
  for +a1: Nat
  for +a2: Nat
  for +a3: Nat
  for +a4: Nat
  for +a5: Nat
  for +a12: Nat
  for +a13: Nat
  for +la0: L.Le(a0, pp)
  for +la12: L.Le(a12, pp)
  for +la13: L.Le(a13, pp)
  for +zx: {a2 == a0 : Nat}
  for +ip: Nat
  for +hp: {F.fmul(1n+pp, ip, a0) == 1n : Nat}
  for +iq: Nat
  for +hq: {F.fmul(1n+pp, iq, a2) == 1n : Nat}
  for +iy: Nat
  for +hs: {F.fmul(1n+pp, iy, F.fadd(1n+pp, a3, a1)) == 1n : Nat}
  for h1: {G.gate_6_1(pp, sel, a0, a1, a2, a4, a5) == 0n : Nat}
  for h4: {G.gate_6_4(pp, sel, a0, a1, a2, a3, a4, a12) == 0n : Nat}
  for h5: {G.gate_6_5(pp, sel, a0, a1, a2, a3, a4, a12, a13) == 0n : Nat}
  {F.fmul(1n+pp, F.fmul(1n+pp, 2n, a1), a4) == F.fmul(1n+pp, 3n, F.fmul(1n+pp, a0, a0)) : Nat}
    & {F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a4, a4), F.fsub(1n+pp, 0n, a0)), F.fsub(1n+pp, 0n, a2)) == a12 : Nat}
    & {F.fadd(1n+pp, F.fmul(1n+pp, a4, F.fadd(1n+pp, a0, F.fsub(1n+pp, 0n, a12))), F.fsub(1n+pp, 0n, a1)) == a13 : Nat}

# Row: x_p = x_q = 2, y_p = y_q = 3, lambda = 2, alpha = 0, x_r = 0, y_r = 1; inverses 6, 6, 2.
law cadd_double_satisfiable:
  L.Le(1n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(2n, 10n) & L.Le(0n, 10n) & L.Le(1n, 10n) & {2n == 2n : Nat}
    & {F.fmul(11n, 6n, 2n) == 1n : Nat} & {F.fmul(11n, 6n, 2n) == 1n : Nat} & {F.fmul(11n, 2n, F.fadd(11n, 3n, 3n)) == 1n : Nat}
    & {G.gate_6_1(10n, 1n, 2n, 3n, 2n, 2n, 0n) == 0n : Nat} & {G.gate_6_4(10n, 1n, 2n, 3n, 2n, 3n, 2n, 0n) == 0n : Nat} & {G.gate_6_5(10n, 1n, 2n, 3n, 2n, 3n, 2n, 0n, 1n) == 0n : Nat}

# --- incomplete addition (gate 5 "incomplete addition") -----------------------------------
# Cells: a0 = x_p, a1 = y_p, a2 = x_q, a3 = y_q, a12 = x_r, a13 = y_r. With x_p != x_q
# (d = x_p - x_q invertible, d * di == 1) and lambda = (y_p - y_q) / (x_p - x_q), the two
# constraints say exactly that R is the chord-rule sum: x_r + x_q + x_p == lambda^2 and
# y_r + y_q == lambda (x_q - x_r). Constraints "x_r", "y_r" (gate_5_0, gate_5_1).
law incomplete_add:
  for +pp: Nat
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a0: Nat
  for +a1: Nat
  for +a2: Nat
  for +a3: Nat
  for +a12: Nat
  for +a13: Nat
  for +di: Nat
  for +hd: {F.fmul(1n+pp, di, F.fadd(1n+pp, a0, F.fsub(1n+pp, 0n, a2))) == 1n : Nat}
  for h0: {G.gate_5_0(pp, sel, a0, a1, a2, a3, a12) == 0n : Nat}
  for h1: {G.gate_5_1(pp, sel, a0, a1, a2, a3, a12, a13) == 0n : Nat}
  {F.fadd(1n+pp, F.fadd(1n+pp, a12, a2), a0) == F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a1, F.fsub(1n+pp, 0n, a3)), di), F.fmul(1n+pp, F.fadd(1n+pp, a1, F.fsub(1n+pp, 0n, a3)), di)) : Nat}
    & {F.fadd(1n+pp, a13, a3) == F.fmul(1n+pp, F.fmul(1n+pp, F.fadd(1n+pp, a1, F.fsub(1n+pp, 0n, a3)), di), F.fadd(1n+pp, a2, F.fsub(1n+pp, 0n, a12))) : Nat}

# Row: x_p = 1, y_p = 0, x_q = 2, y_q = 1, x_r = 9, y_r = 3, di = 10 (lambda = 1).
law incomplete_add_satisfiable:
  {F.fmul(11n, 1n, 1n) == 1n : Nat} & {F.fmul(11n, 10n, F.fadd(11n, 1n, F.fsub(11n, 0n, 2n))) == 1n : Nat}
    & {G.gate_5_0(10n, 1n, 1n, 0n, 2n, 1n, 9n) == 0n : Nat} & {G.gate_5_1(10n, 1n, 1n, 0n, 2n, 1n, 9n, 3n) == 0n : Nat}

# --- LSB of variable-base mul (gate 15 "LSB check") ---------------------------------------
# k = a10 - 2 a9 is the scalar's last bit. If k == 0 the final row subtracts the base:
# x_p (a0) equals the base's x (a16) and y_p (a1) is minus the base's y (a17); if k == 1
# the point used is (0, 0). All three constraints ("bool_check", "lsb_x", "lsb_y").
law lsb_check:
  for +pp: Nat
  for nzd: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a0: Nat
  for +a1: Nat
  for +a9: Nat
  for +a10: Nat
  for +a16: Nat
  for +a17: Nat
  for +la0: L.Le(a0, pp)
  for +la1: L.Le(a1, pp)
  for +la16: L.Le(a16, pp)
  for h0: {G.gate_15_0(pp, sel, a9, a10) == 0n : Nat}
  for h1: {G.gate_15_1(pp, sel, a0, a9, a10, a16) == 0n : Nat}
  for h2: {G.gate_15_2(pp, sel, a1, a9, a10, a17) == 0n : Nat}
  Either<&1, &1,
    {F.fadd(1n+pp, a10, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a9, 2n))) == 0n : Nat} & {a0 == a16 : Nat} & {F.fadd(1n+pp, a1, a17) == 0n : Nat},
    {F.fadd(1n+pp, a10, F.fsub(1n+pp, 0n, F.fmul(1n+pp, a9, 2n))) == 1n : Nat} & {a0 == 0n : Nat} & {a1 == 0n : Nat}>

law lsb_check_satisfiable:
  F.NZD(10n) & L.Le(1n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(3n, 10n) & L.Le(4n, 10n) & L.Le(3n, 10n)
    & {G.gate_15_0(10n, 1n, 0n, 0n) == 0n : Nat} & {G.gate_15_1(10n, 1n, 3n, 0n, 0n, 3n) == 0n : Nat} & {G.gate_15_2(10n, 1n, 4n, 0n, 0n, 7n) == 0n : Nat}

# --- sign of short fixed-base mul (gate 19, "sign_check") ---------------------------------
# sign^2 == 1 forces sign == 1 or sign == -1 (sign + 1 == 0).
law short_sign:
  for +pp: Nat
  for nzd: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +sel: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +a4: Nat
  for +la4: L.Le(a4, pp)
  for h: {G.gate_19_1(pp, sel, a4) == 0n : Nat}
  Either<&1, &1, {a4 == 1n : Nat}, {F.fadd(1n+pp, a4, 1n) == 0n : Nat}>

law short_sign_satisfiable:
  F.NZD(10n) & L.Le(1n, 10n) & {F.fmul(11n, 1n, 1n) == 1n : Nat} & L.Le(10n, 10n) & {G.gate_19_1(10n, 1n, 10n) == 0n : Nat}
