import Base
import ../prims/natlib.bend as L
import ../opt_gates/term.bend as T
import ../ring/expr.bend as X
import ./model.bend as M
import ./certs/unscale.bend as CU

# Glue between the generated identities (certs/*.bend, lem_<name>) and the laws.

def pt_eq(+a: Nat, +b: Nat, +c: Nat, +a2: Nat, +b2: Nat, +c2: Nat, ha: {a == a2 : Nat}, hb: {b == b2 : Nat}, hc: {c == c2 : Nat}) -> {M.Pt{a, b, c} == M.Pt{a2, b2, c2} : M.Pt}:
  %ha : {M.Pt{a, b, c} == M.Pt{_, b2, c2} : M.Pt}
  %hb : {M.Pt{a, b, c} == M.Pt{a, _, c2} : M.Pt}
  %hc : {M.Pt{a, b, c} == M.Pt{a, b, _} : M.Pt}
  {==}

# A projective point with Z zi == 1 and affine coordinates x = X zi, y = Y zi is (Z x, Z y, Z).
def rep(+bp: Nat, +l1: L.Le(1n, bp), +X: Nat, +Y: Nat, +Z: Nat, +zi: Nat, +x: Nat, +y: Nat, +lX: L.Le(X, bp), +lY: L.Le(Y, bp), +lZ: L.Le(Z, bp), +lzi: L.Le(zi, bp), +hz: {T.fmul(bp, Z, zi) == 1n : Nat}, hx: {T.fmul(bp, X, zi) == x : Nat}, hy: {T.fmul(bp, Y, zi) == y : Nat}) -> {M.Pt{X, Y, Z} == M.Pt{T.fmul(bp, Z, x), T.fmul(bp, Z, y), Z} : M.Pt}:
  +ex = Equal.trans(Nat, X, T.fmul(bp, Z, T.fmul(bp, X, zi)), T.fmul(bp, Z, x), CU.lem_unscale(bp, l1, X, Z, zi, lX, lZ, lzi, hz), Equal.cong(Nat, Nat, w => T.fmul(bp, Z, w), T.fmul(bp, X, zi), x, hx))
  +ey = Equal.trans(Nat, Y, T.fmul(bp, Z, T.fmul(bp, Y, zi)), T.fmul(bp, Z, y), CU.lem_unscale(bp, l1, Y, Z, zi, lY, lZ, lzi, hz), Equal.cong(Nat, Nat, w => T.fmul(bp, Z, w), T.fmul(bp, Y, zi), y, hy))
  pt_eq(X, Y, Z, T.fmul(bp, Z, x), T.fmul(bp, Z, y), Z, ex, ey, {==})

# rewrite the two points of a statement
def tr2(-F: M.Pt -> M.Pt -> Type, +p: M.Pt, +p2: M.Pt, +q: M.Pt, +q2: M.Pt, e1: {p == p2 : M.Pt}, e2: {q == q2 : M.Pt}, h: F(p2, q2)) -> F(p, q):
  %Equal.sym(M.Pt, p, p2, e1) : F(_, q)
  %Equal.sym(M.Pt, q, q2, e2) : F(p2, _)
  h

def tr1(-F: M.Pt -> Type, +p: M.Pt, +p2: M.Pt, e1: {p == p2 : M.Pt}, h: F(p2)) -> F(p):
  %Equal.sym(M.Pt, p, p2, e1) : F(_)
  h

def le_eq(+bp: Nat, +u: Nat, +v: Nat, e: {u == v : Nat}, l: L.Le(v, bp)) -> L.Le(u, bp):
  %Equal.sym(Nat, u, v, e) : L.Le(_, bp)
  l

def fmul_le(+bp: Nat, +x: Nat, +y: Nat) -> L.Le(T.fmul(bp, x, y), bp):
  L.mod_le(Nat.mul(x, y), bp)

def fsub_le(+bp: Nat, +x: Nat, +y: Nat) -> L.Le(T.fsub(bp, x, y), bp):
  L.mod_le(Nat.add(x, Nat.sub(1n+bp, y)), bp)

def fadd_le(+bp: Nat, +x: Nat, +y: Nat) -> L.Le(T.fadd(bp, x, y), bp):
  L.mod_le(Nat.add(x, y), bp)

def fneg_le(+bp: Nat, +y: Nat) -> L.Le(T.fneg(bp, y), bp):
  L.mod_le(Nat.sub(1n+bp, y), bp)

# points are equal when their coordinates are
def pt_ext(+p: M.Pt, +q: M.Pt) -> {M.px(p) == M.px(q) : Nat} -> {M.py(p) == M.py(q) : Nat} -> {M.pz(p) == M.pz(q) : Nat} -> {p == q : M.Pt}:
  match p q:
    case M.Pt{+a, +b, +c} M.Pt{+a2, +b2, +c2}:
      ha => hb => hc => pt_eq(a, b, c, a2, b2, c2, ha, hb, hc)

# z w == 1 makes z nonzero
def inv_nz(+bp: Nat, +z: Nat, +w: Nat, h: {T.fmul(bp, z, w) == 1n : Nat}) -> {z != 0n : Nat}:
  z0 => L.succ_ne_zero(0n, Equal.sym(Nat, 0n, 1n, Equal.trans(Nat, 0n, T.fmul(bp, 0n, w), 1n, Equal.sym(Nat, T.fmul(bp, 0n, w), 0n, X.mod_zero(bp)), Equal.trans(Nat, T.fmul(bp, 0n, w), T.fmul(bp, z, w), 1n, Equal.cong(Nat, Nat, v => T.fmul(bp, v, w), 0n, z, Equal.sym(Nat, z, 0n, z0)), h))))

# a point (x, y) on the curve has y != 0 when there is no point of order 2
def y_nz(+bp: Nat, +b: Nat, +x: Nat, +y: Nat, +lx: L.Le(x, bp), hon: M.OnCurve(bp, b, x, y), not2: M.NoT2(bp, b)) -> {y != 0n : Nat}:
  y0 => not2(x, lx, Equal.trans(Nat, T.fadd(bp, T.fmul(bp, x, T.fmul(bp, x, x)), b), T.fmul(bp, y, y), 0n, Equal.sym(Nat, T.fmul(bp, y, y), T.fadd(bp, T.fmul(bp, x, T.fmul(bp, x, x)), b), hon), Equal.trans(Nat, T.fmul(bp, y, y), T.fmul(bp, 0n, 0n), 0n, Equal.cong(Nat, Nat, v => T.fmul(bp, v, v), y, 0n, y0), X.mod_zero(bp))))

# z w == y with y != 0 makes z nonzero
def mul_nz(+bp: Nat, +z: Nat, +w: Nat, +y: Nat, h: {T.fmul(bp, z, w) == y : Nat}, hy: {y != 0n : Nat}) -> {z != 0n : Nat}:
  z0 => hy(Equal.trans(Nat, y, T.fmul(bp, 0n, w), 0n, Equal.trans(Nat, y, T.fmul(bp, z, w), T.fmul(bp, 0n, w), Equal.sym(Nat, T.fmul(bp, z, w), y, h), Equal.cong(Nat, Nat, v => T.fmul(bp, v, w), z, 0n, z0)), X.mod_zero(bp)))
