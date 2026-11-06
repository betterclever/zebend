import Base
import ../prims/natlib.bend as L
import ../opt_gates/term.bend as T
import ../ring/expr.bend as X
import ./model.bend as M

# The curve formulas of the fast Halo 2 verifier (model.bend: crypto/field3/lib64/vesta.bend's
# add, add_aff, double and msm_ba.add_aff, statement by statement) compute the chord-and-
# tangent group law of y^2 = x^3 + b, in Z/p with p = 1 + bp, for every b; add_is_b5 and its
# companions tie the code's mul15 to b = 5.
#
# Hypotheses, all explicit: l1 (p >= 2); every variable canonical (hc); M.Rep(X, Y, Z, zi,
# x, y): the projective point has Z zi == 1 and affine coordinates x = X zi, y = Y zi;
# M.OnCurve: y^2 == x^3 + b; an inverse for the denominator of the slope (di for x2 - x1,
# ti for 2 y); M.NoT2 (no point of order 2) only for the "!= 0" laws. No law assumes p prime.

# --- vesta.add (RCB Algorithm 7), P != +-Q: the chord ------------------------------------

law add_chord_x:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +X1: Nat
  for +Y1: Nat
  for +Z1: Nat
  for +zi1: Nat
  for +x1: Nat
  for +y1: Nat
  for +X2: Nat
  for +Y2: Nat
  for +Z2: Nat
  for +zi2: Nat
  for +x2: Nat
  for +y2: Nat
  for +di: Nat
  for +hc: X.Canon(bp, [b, X1, Y1, Z1, zi1, x1, y1, X2, Y2, Z2, zi2, x2, y2, di])
  for +r1: M.Rep(bp, X1, Y1, Z1, zi1, x1, y1)
  for +r2: M.Rep(bp, X2, Y2, Z2, zi2, x2, y2)
  for +on1: M.OnCurve(bp, b, x1, y1)
  for +on2: M.OnCurve(bp, b, x2, y2)
  for +hd: {T.fmul(bp, T.fsub(bp, x2, x1), di) == 1n : Nat}
  {M.px(M.addb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Pt{X2, Y2, Z2})) == T.fmul(bp, M.chord_x(bp, x1, y1, x2, y2, di), M.pz(M.addb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Pt{X2, Y2, Z2}))) : Nat}

law add_chord_y:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +X1: Nat
  for +Y1: Nat
  for +Z1: Nat
  for +zi1: Nat
  for +x1: Nat
  for +y1: Nat
  for +X2: Nat
  for +Y2: Nat
  for +Z2: Nat
  for +zi2: Nat
  for +x2: Nat
  for +y2: Nat
  for +di: Nat
  for +hc: X.Canon(bp, [b, X1, Y1, Z1, zi1, x1, y1, X2, Y2, Z2, zi2, x2, y2, di])
  for +r1: M.Rep(bp, X1, Y1, Z1, zi1, x1, y1)
  for +r2: M.Rep(bp, X2, Y2, Z2, zi2, x2, y2)
  for +on1: M.OnCurve(bp, b, x1, y1)
  for +on2: M.OnCurve(bp, b, x2, y2)
  for +hd: {T.fmul(bp, T.fsub(bp, x2, x1), di) == 1n : Nat}
  {M.py(M.addb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Pt{X2, Y2, Z2})) == T.fmul(bp, M.chord_y(bp, x1, y1, x2, y2, di), M.pz(M.addb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Pt{X2, Y2, Z2}))) : Nat}

# ... and Z3 != 0, so the output is the affine point (chord_x, chord_y): Z3 = 0 would make
# P - Q a point (x, 0) of order 2.
law add_chord_nz:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +X1: Nat
  for +Y1: Nat
  for +Z1: Nat
  for +zi1: Nat
  for +x1: Nat
  for +y1: Nat
  for +X2: Nat
  for +Y2: Nat
  for +Z2: Nat
  for +zi2: Nat
  for +x2: Nat
  for +y2: Nat
  for +di: Nat
  for +hc: X.Canon(bp, [b, X1, Y1, Z1, zi1, x1, y1, X2, Y2, Z2, zi2, x2, y2, di])
  for +r1: M.Rep(bp, X1, Y1, Z1, zi1, x1, y1)
  for +r2: M.Rep(bp, X2, Y2, Z2, zi2, x2, y2)
  for +on1: M.OnCurve(bp, b, x1, y1)
  for +on2: M.OnCurve(bp, b, x2, y2)
  for +hd: {T.fmul(bp, T.fsub(bp, x2, x1), di) == 1n : Nat}
  for not2: M.NoT2(bp, b)
  {M.pz(M.addb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Pt{X2, Y2, Z2})) != 0n : Nat}

# --- vesta.add, P == Q: the tangent ---------------------------------------------------------

law add_tan_x:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +X1: Nat
  for +Y1: Nat
  for +Z1: Nat
  for +zi1: Nat
  for +X2: Nat
  for +Y2: Nat
  for +Z2: Nat
  for +zi2: Nat
  for +x: Nat
  for +y: Nat
  for +ti: Nat
  for +hc: X.Canon(bp, [b, X1, Y1, Z1, zi1, X2, Y2, Z2, zi2, x, y, ti])
  for +r1: M.Rep(bp, X1, Y1, Z1, zi1, x, y)
  for +r2: M.Rep(bp, X2, Y2, Z2, zi2, x, y)
  for +on: M.OnCurve(bp, b, x, y)
  for +ht: {T.fmul(bp, T.fadd(bp, y, y), ti) == 1n : Nat}
  {M.px(M.addb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Pt{X2, Y2, Z2})) == T.fmul(bp, M.tan_x(bp, x, ti), M.pz(M.addb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Pt{X2, Y2, Z2}))) : Nat}

law add_tan_y:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +X1: Nat
  for +Y1: Nat
  for +Z1: Nat
  for +zi1: Nat
  for +X2: Nat
  for +Y2: Nat
  for +Z2: Nat
  for +zi2: Nat
  for +x: Nat
  for +y: Nat
  for +ti: Nat
  for +hc: X.Canon(bp, [b, X1, Y1, Z1, zi1, X2, Y2, Z2, zi2, x, y, ti])
  for +r1: M.Rep(bp, X1, Y1, Z1, zi1, x, y)
  for +r2: M.Rep(bp, X2, Y2, Z2, zi2, x, y)
  for +on: M.OnCurve(bp, b, x, y)
  for +ht: {T.fmul(bp, T.fadd(bp, y, y), ti) == 1n : Nat}
  {M.py(M.addb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Pt{X2, Y2, Z2})) == T.fmul(bp, M.tan_y(bp, x, y, ti), M.pz(M.addb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Pt{X2, Y2, Z2}))) : Nat}

# ... and Z3 != 0 (Z3 = (2y)^3 Z1^2 Z2^2: an explicit inverse exists)
law add_tan_nz:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +X1: Nat
  for +Y1: Nat
  for +Z1: Nat
  for +zi1: Nat
  for +X2: Nat
  for +Y2: Nat
  for +Z2: Nat
  for +zi2: Nat
  for +x: Nat
  for +y: Nat
  for +ti: Nat
  for +hc: X.Canon(bp, [b, X1, Y1, Z1, zi1, X2, Y2, Z2, zi2, x, y, ti])
  for +r1: M.Rep(bp, X1, Y1, Z1, zi1, x, y)
  for +r2: M.Rep(bp, X2, Y2, Z2, zi2, x, y)
  for +on: M.OnCurve(bp, b, x, y)
  for +ht: {T.fmul(bp, T.fadd(bp, y, y), ti) == 1n : Nat}
  {M.pz(M.addb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Pt{X2, Y2, Z2})) != 0n : Nat}

# --- vesta.add, Q == -P: the identity (0 : Y3 : 0) with Y3 != 0 ----------------------------

law add_neg_x:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +X1: Nat
  for +Y1: Nat
  for +Z1: Nat
  for +zi1: Nat
  for +X2: Nat
  for +Y2: Nat
  for +Z2: Nat
  for +zi2: Nat
  for +x: Nat
  for +y: Nat
  for +hc: X.Canon(bp, [b, X1, Y1, Z1, zi1, X2, Y2, Z2, zi2, x, y])
  for +r1: M.Rep(bp, X1, Y1, Z1, zi1, x, y)
  for +r2: M.Rep(bp, X2, Y2, Z2, zi2, x, T.fneg(bp, y))
  for +on: M.OnCurve(bp, b, x, y)
  {M.px(M.addb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Pt{X2, Y2, Z2})) == 0n : Nat}

law add_neg_z:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +X1: Nat
  for +Y1: Nat
  for +Z1: Nat
  for +zi1: Nat
  for +X2: Nat
  for +Y2: Nat
  for +Z2: Nat
  for +zi2: Nat
  for +x: Nat
  for +y: Nat
  for +hc: X.Canon(bp, [b, X1, Y1, Z1, zi1, X2, Y2, Z2, zi2, x, y])
  for +r1: M.Rep(bp, X1, Y1, Z1, zi1, x, y)
  for +r2: M.Rep(bp, X2, Y2, Z2, zi2, x, T.fneg(bp, y))
  for +on: M.OnCurve(bp, b, x, y)
  {M.pz(M.addb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Pt{X2, Y2, Z2})) == 0n : Nat}

# Y3 != 0: Y3 = y(2P) (2y)^3 Z1^2 Z2^2, and y(2P) = 0 would make 2P a point of order 2
law add_neg_y_nz:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +X1: Nat
  for +Y1: Nat
  for +Z1: Nat
  for +zi1: Nat
  for +X2: Nat
  for +Y2: Nat
  for +Z2: Nat
  for +zi2: Nat
  for +x: Nat
  for +y: Nat
  for +ti: Nat
  for +hc: X.Canon(bp, [b, X1, Y1, Z1, zi1, X2, Y2, Z2, zi2, x, y, ti])
  for +r1: M.Rep(bp, X1, Y1, Z1, zi1, x, y)
  for +r2: M.Rep(bp, X2, Y2, Z2, zi2, x, T.fneg(bp, y))
  for +on: M.OnCurve(bp, b, x, y)
  for +ht: {T.fmul(bp, T.fadd(bp, y, y), ti) == 1n : Nat}
  for not2: M.NoT2(bp, b)
  {M.py(M.addb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Pt{X2, Y2, Z2})) != 0n : Nat}

# --- vesta.add with the identity (0 : Y : 0) on either side: a multiple of the other point ----

law add_id_l:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +Y1: Nat
  for +X2: Nat
  for +Y2: Nat
  for +Z2: Nat
  for +hc: X.Canon(bp, [b, Y1, X2, Y2, Z2])
  {M.addb(bp, M.b3(bp, b), M.Pt{0n, Y1, 0n}, M.Pt{X2, Y2, Z2}) == M.Pt{T.fmul(bp, T.fmul(bp, T.fmul(bp, Y1, Y1), Y2), X2), T.fmul(bp, T.fmul(bp, T.fmul(bp, Y1, Y1), Y2), Y2), T.fmul(bp, T.fmul(bp, T.fmul(bp, Y1, Y1), Y2), Z2)} : M.Pt}

law add_id_r:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +X1: Nat
  for +Y1: Nat
  for +Z1: Nat
  for +Y2: Nat
  for +hc: X.Canon(bp, [b, X1, Y1, Z1, Y2])
  {M.addb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Pt{0n, Y2, 0n}) == M.Pt{T.fmul(bp, T.fmul(bp, Y1, T.fmul(bp, Y2, Y2)), X1), T.fmul(bp, T.fmul(bp, Y1, T.fmul(bp, Y2, Y2)), Y1), T.fmul(bp, T.fmul(bp, Y1, T.fmul(bp, Y2, Y2)), Z1)} : M.Pt}

# --- vesta.add_aff (RCB Algorithm 8) ------------------------------------------------------

# add_aff(P, (x2, y2)) is add(P, (x2 : y2 : 1)), for all inputs: every law above about add
# holds for add_aff with Z2 = 1. (As vesta.bend says, (0, 0), the encoding of the identity,
# is not a valid second argument: it is not on the curve.)
law aff_is_add:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +X1: Nat
  for +Y1: Nat
  for +Z1: Nat
  for +x2: Nat
  for +y2: Nat
  for +hc: X.Canon(bp, [b, X1, Y1, Z1, x2, y2])
  {M.add_affb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Aff{x2, y2}) == M.addb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Pt{x2, y2, 1n}) : M.Pt}

law aff_chord_x:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +X1: Nat
  for +Y1: Nat
  for +Z1: Nat
  for +zi1: Nat
  for +x1: Nat
  for +y1: Nat
  for +x2: Nat
  for +y2: Nat
  for +di: Nat
  for +hc: X.Canon(bp, [b, X1, Y1, Z1, zi1, x1, y1, x2, y2, di])
  for +r1: M.Rep(bp, X1, Y1, Z1, zi1, x1, y1)
  for +on1: M.OnCurve(bp, b, x1, y1)
  for +on2: M.OnCurve(bp, b, x2, y2)
  for +hd: {T.fmul(bp, T.fsub(bp, x2, x1), di) == 1n : Nat}
  {M.px(M.add_affb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Aff{x2, y2})) == T.fmul(bp, M.chord_x(bp, x1, y1, x2, y2, di), M.pz(M.add_affb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Aff{x2, y2}))) : Nat}

law aff_chord_y:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +X1: Nat
  for +Y1: Nat
  for +Z1: Nat
  for +zi1: Nat
  for +x1: Nat
  for +y1: Nat
  for +x2: Nat
  for +y2: Nat
  for +di: Nat
  for +hc: X.Canon(bp, [b, X1, Y1, Z1, zi1, x1, y1, x2, y2, di])
  for +r1: M.Rep(bp, X1, Y1, Z1, zi1, x1, y1)
  for +on1: M.OnCurve(bp, b, x1, y1)
  for +on2: M.OnCurve(bp, b, x2, y2)
  for +hd: {T.fmul(bp, T.fsub(bp, x2, x1), di) == 1n : Nat}
  {M.py(M.add_affb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Aff{x2, y2})) == T.fmul(bp, M.chord_y(bp, x1, y1, x2, y2, di), M.pz(M.add_affb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}, M.Aff{x2, y2}))) : Nat}

# --- vesta.double (RCB Algorithm 9) ---------------------------------------------------------

law dbl_tan_x:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +X1: Nat
  for +Y1: Nat
  for +Z1: Nat
  for +zi1: Nat
  for +x: Nat
  for +y: Nat
  for +ti: Nat
  for +hc: X.Canon(bp, [b, X1, Y1, Z1, zi1, x, y, ti])
  for +r1: M.Rep(bp, X1, Y1, Z1, zi1, x, y)
  for +on: M.OnCurve(bp, b, x, y)
  for +ht: {T.fmul(bp, T.fadd(bp, y, y), ti) == 1n : Nat}
  {M.px(M.doubleb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1})) == T.fmul(bp, M.tan_x(bp, x, ti), M.pz(M.doubleb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}))) : Nat}

law dbl_tan_y:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +X1: Nat
  for +Y1: Nat
  for +Z1: Nat
  for +zi1: Nat
  for +x: Nat
  for +y: Nat
  for +ti: Nat
  for +hc: X.Canon(bp, [b, X1, Y1, Z1, zi1, x, y, ti])
  for +r1: M.Rep(bp, X1, Y1, Z1, zi1, x, y)
  for +on: M.OnCurve(bp, b, x, y)
  for +ht: {T.fmul(bp, T.fadd(bp, y, y), ti) == 1n : Nat}
  {M.py(M.doubleb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1})) == T.fmul(bp, M.tan_y(bp, x, y, ti), M.pz(M.doubleb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}))) : Nat}

# ... and Z3 != 0 (Z3 = (2y)^3 Z^4)
law dbl_tan_nz:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +X1: Nat
  for +Y1: Nat
  for +Z1: Nat
  for +zi1: Nat
  for +x: Nat
  for +y: Nat
  for +ti: Nat
  for +hc: X.Canon(bp, [b, X1, Y1, Z1, zi1, x, y, ti])
  for +r1: M.Rep(bp, X1, Y1, Z1, zi1, x, y)
  for +on: M.OnCurve(bp, b, x, y)
  for +ht: {T.fmul(bp, T.fadd(bp, y, y), ti) == 1n : Nat}
  {M.pz(M.doubleb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1})) != 0n : Nat}

# doubling the identity (0 : Y : 0) gives the identity (0 : Y^4 : 0)
law dbl_id:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +Y: Nat
  for +hc: X.Canon(bp, [b, Y])
  {M.doubleb(bp, M.b3(bp, b), M.Pt{0n, Y, 0n}) == M.Pt{0n, T.fmul(bp, T.fmul(bp, Y, Y), T.fmul(bp, Y, Y)), 0n} : M.Pt}

law dbl_on_curve:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +X1: Nat
  for +Y1: Nat
  for +Z1: Nat
  for +hc: X.Canon(bp, [b, X1, Y1, Z1])
  for +on1: M.OnCurveP(bp, b, M.Pt{X1, Y1, Z1})
  M.OnCurveP(bp, b, M.doubleb(bp, M.b3(bp, b), M.Pt{X1, Y1, Z1}))

# --- the chord and the tangent, and msm_ba.add_aff ------------------------------------------

# msm_ba.add_aff (with inv from the batch inversion of x2 - x1) is the chord, by definition.
law aadd_is_chord:
  for +bp: Nat
  for +x1: Nat
  for +y1: Nat
  for +x2: Nat
  for +y2: Nat
  for +inv: Nat
  {M.aadd(bp, x1, y1, x2, y2, inv) == M.Aff{M.chord_x(bp, x1, y1, x2, y2, inv), M.chord_y(bp, x1, y1, x2, y2, inv)} : M.Aff}

law chord_on_curve:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +x1: Nat
  for +y1: Nat
  for +x2: Nat
  for +y2: Nat
  for +di: Nat
  for +hc: X.Canon(bp, [b, x1, y1, x2, y2, di])
  for +on1: M.OnCurve(bp, b, x1, y1)
  for +on2: M.OnCurve(bp, b, x2, y2)
  for +hd: {T.fmul(bp, T.fsub(bp, x2, x1), di) == 1n : Nat}
  M.OnCurve(bp, b, M.chord_x(bp, x1, y1, x2, y2, di), M.chord_y(bp, x1, y1, x2, y2, di))

law tan_on_curve:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +b: Nat
  for +x: Nat
  for +y: Nat
  for +ti: Nat
  for +hc: X.Canon(bp, [b, x, y, ti])
  for +on: M.OnCurve(bp, b, x, y)
  for +ht: {T.fmul(bp, T.fadd(bp, y, y), ti) == 1n : Nat}
  M.OnCurve(bp, b, M.tan_x(bp, x, ti), M.tan_y(bp, x, y, ti))

# --- the code's mul15 is the b = 5 instance ---------------------------------------------------

law add_is_b5:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +X1: Nat
  for +Y1: Nat
  for +Z1: Nat
  for +X2: Nat
  for +Y2: Nat
  for +Z2: Nat
  {M.add(bp, M.Pt{X1, Y1, Z1}, M.Pt{X2, Y2, Z2}) == M.addb(bp, M.b3(bp, Nat.mod(5n, 1n+bp)), M.Pt{X1, Y1, Z1}, M.Pt{X2, Y2, Z2}) : M.Pt}

law aff_is_b5:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +X1: Nat
  for +Y1: Nat
  for +Z1: Nat
  for +x2: Nat
  for +y2: Nat
  for +lz: L.Le(Z1, bp)
  {M.add_aff(bp, M.Pt{X1, Y1, Z1}, M.Aff{x2, y2}) == M.add_affb(bp, M.b3(bp, Nat.mod(5n, 1n+bp)), M.Pt{X1, Y1, Z1}, M.Aff{x2, y2}) : M.Pt}

law dbl_is_b5:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +X1: Nat
  for +Y1: Nat
  for +Z1: Nat
  {M.double(bp, M.Pt{X1, Y1, Z1}) == M.doubleb(bp, M.b3(bp, Nat.mod(5n, 1n+bp)), M.Pt{X1, Y1, Z1}) : M.Pt}

# --- non-vacuity: y^2 = x^3 + 5 over Z/7 (7 points, prime order like Pallas and Vesta) ------

law not2_7:
  M.NoT2(6n, 5n)

# P = (3, 2), Q = (5, 2), both with Z = 1; 1 / (5 - 3) = 4
law chord_sat:
  Sigma<&2, &2, L.Le(1n, 6n), _ => Sigma<&2, &2, X.Canon(6n, [5n, 3n, 2n, 1n, 1n, 3n, 2n, 5n, 2n, 1n, 1n, 5n, 2n, 4n]), _ => Sigma<&2, &2, M.Rep(6n, 3n, 2n, 1n, 1n, 3n, 2n), _ => Sigma<&2, &2, M.Rep(6n, 5n, 2n, 1n, 1n, 5n, 2n), _ => Sigma<&2, &2, M.OnCurve(6n, 5n, 3n, 2n), _ => Sigma<&2, &2, M.OnCurve(6n, 5n, 5n, 2n), _ => {T.fmul(6n, T.fsub(6n, 5n, 3n), 4n) == 1n : Nat}>>>>>>

# P = Q = (3, 2); 1 / (2 * 2) = 2
law tan_sat:
  Sigma<&2, &2, X.Canon(6n, [5n, 3n, 2n, 1n, 1n, 3n, 2n, 1n, 1n, 3n, 2n, 2n]), _ => Sigma<&2, &2, M.Rep(6n, 3n, 2n, 1n, 1n, 3n, 2n), _ => Sigma<&2, &2, M.OnCurve(6n, 5n, 3n, 2n), _ => {T.fmul(6n, T.fadd(6n, 2n, 2n), 2n) == 1n : Nat}>>>

# P = (3, 2), Q = (3, 5) = -P
law neg_sat:
  Sigma<&2, &2, X.Canon(6n, [5n, 3n, 2n, 1n, 1n, 3n, 5n, 1n, 1n, 3n, 2n, 2n]), _ => M.Rep(6n, 3n, 5n, 1n, 1n, 3n, T.fneg(6n, 2n))>

# (3 : 2 : 1) is on the curve, projectively
law on_curve_sat:
  M.OnCurveP(6n, 5n, M.Pt{3n, 2n, 1n})
