import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L
import ./fieldmodel.bend as F
import ./evals.bend as E

# Lemmas shared by the generated per-gate laws (lawgen.py) and the hand-written ECC,
# range-check and canonicity laws: order facts, implications from a bit, the selector
# strip for gates whose selector factor carries a cell, and field associativity.

def le_0(+pp: Nat) -> L.Le(0n, pp):
  (pp, {==})

# a <= b, b <= c  ==>  a <= c
law le_trans:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for +lab: L.Le(a, b)
  for +lbc: L.Le(b, c)
  L.Le(a, c)

def le_trans(a, b, c, lab, lbc):
  (+e1, h1) = lab
  (+e2, h2) = lbc
  (Nat.add(e1, e2),
    Equal.trans(Nat, Nat.add(a, Nat.add(e1, e2)), Nat.add(Nat.add(a, e1), e2), c,
      Equal.sym(Nat, Nat.add(Nat.add(a, e1), e2), Nat.add(a, Nat.add(e1, e2)), N.add_assoc(a, e1, e2)),
      Equal.trans(Nat, Nat.add(Nat.add(a, e1), e2), Nat.add(b, e2), c,
        Equal.cong(Nat, Nat, w => Nat.add(w, e2), Nat.add(a, e1), b, h1), h2)))

# c == x, c <= k  ==>  x <= k
law le_eq:
  for +c: Nat
  for +x: Nat
  for +k: Nat
  for +e: {c == x : Nat}
  for +l: L.Le(c, k)
  L.Le(x, k)

def le_eq(c, x, k, e, l):
  %e : L.Le(_, k)
  l

# b == 1 and b * x == 0  ==>  x == 0, for canonical x.
law one_mul_zero:
  for +pp: Nat
  for +b: Nat
  for +x: Nat
  for +lx: L.Le(x, pp)
  for z: {b == 1n : Nat}
  for h: {F.fmul(1n+pp, b, x) == 0n : Nat}
  {x == 0n : Nat}

def one_mul_zero(pp, b, x, lx, z, h):
  %E.fmul_1(pp, x, lx) : {_ == 0n : Nat}
  %z : {F.fmul(1n+pp, _, x) == 0n : Nat}
  h

# (a * b) * c == a * (b * c) in Fp.
law fmul_assoc:
  for +pp: Nat
  for +a: Nat
  for +b: Nat
  for +c: Nat
  {F.fmul(1n+pp, F.fmul(1n+pp, a, b), c) == F.fmul(1n+pp, a, F.fmul(1n+pp, b, c)) : Nat}

def fmul_assoc(pp, a, b, c):
  %Equal.sym(Nat, Nat.mod(Nat.mul(Nat.mod(Nat.mul(a, b), 1n+pp), c), 1n+pp), Nat.mod(Nat.mul(Nat.mul(a, b), c), 1n+pp), L.mod_mul_mod_l(Nat.mul(a, b), c, pp)) : {_ == F.fmul(1n+pp, a, F.fmul(1n+pp, b, c)) : Nat}
  %Equal.sym(Nat, Nat.mod(Nat.mul(a, Nat.mod(Nat.mul(b, c), 1n+pp)), 1n+pp), Nat.mod(Nat.mul(a, Nat.mul(b, c)), 1n+pp), L.mod_mul_mod_r(a, Nat.mul(b, c), pp)) : {Nat.mod(Nat.mul(Nat.mul(a, b), c), 1n+pp) == _ : Nat}
  %Equal.sym(Nat, Nat.mul(Nat.mul(a, b), c), Nat.mul(a, Nat.mul(b, c)), L.mul_assoc(a, b, c)) : {Nat.mod(_, 1n+pp) == Nat.mod(Nat.mul(a, Nat.mul(b, c)), 1n+pp) : Nat}
  {==}

# A gate whose compressed selector factor is multiplied by a cell x before the body
# (halo2 writes q * x * body): with an invertible selector, x * body vanishes.
law strip_inv_l:
  for +pp: Nat
  for +sel: Nat
  for +x: Nat
  for +body: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for h: {F.fmul(1n+pp, F.fmul(1n+pp, sel, x), body) == 0n : Nat}
  {F.fmul(1n+pp, x, body) == 0n : Nat}

def strip_inv_l(pp, sel, x, body, si, inv, h):
  E.strip_inv(pp, sel, F.fmul(1n+pp, x, body), si, inv, E.le_fmul(pp, x, body),
    Equal.trans(Nat, F.fmul(1n+pp, sel, F.fmul(1n+pp, x, body)), F.fmul(1n+pp, F.fmul(1n+pp, sel, x), body), 0n,
      Equal.sym(Nat, F.fmul(1n+pp, F.fmul(1n+pp, sel, x), body), F.fmul(1n+pp, sel, F.fmul(1n+pp, x, body)), fmul_assoc(pp, sel, x, body)), h))

# n + 1 + r <= n is impossible.
law gt_absurd:
  for +n: Nat
  for +r: Nat
  for +l: L.Le(1n+Nat.add(n, r), n)
  Empty

def gt_go(+n: Nat, +r: Nat, +e: Nat, h: {Nat.add(1n+Nat.add(n, r), e) == n : Nat}) -> Empty:
  match n:
    case 0n:
      L.succ_ne_zero(Nat.add(r, e), h)
    case 1n+m:
      gt_go(m, r, e, L.succ_inj(Nat.add(1n+Nat.add(m, r), e), m, h))

def gt_absurd(n, r, l):
  (+e, h) = l
  gt_go(n, r, e, h)

# --- commutative-ring rearrangements in Fp (Bend has no ring tactic) ----------------

law fmul_comm:
  for +pp: Nat
  for +a: Nat
  for +b: Nat
  {F.fmul(1n+pp, a, b) == F.fmul(1n+pp, b, a) : Nat}

def fmul_comm(pp, a, b):
  Equal.cong(Nat, Nat, w => Nat.mod(w, 1n+pp), Nat.mul(a, b), Nat.mul(b, a), L.mul_comm(a, b))

# (a b)(c d) == (a c)(b d) over Nat.
law nswap4:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for +d: Nat
  {Nat.mul(Nat.mul(a, b), Nat.mul(c, d)) == Nat.mul(Nat.mul(a, c), Nat.mul(b, d)) : Nat}

def nswap4(a, b, c, d):
  %Equal.sym(Nat, Nat.mul(Nat.mul(a, b), Nat.mul(c, d)), Nat.mul(a, Nat.mul(b, Nat.mul(c, d))), L.mul_assoc(a, b, Nat.mul(c, d))) : {_ == Nat.mul(Nat.mul(a, c), Nat.mul(b, d)) : Nat}
  %Equal.sym(Nat, Nat.mul(Nat.mul(a, c), Nat.mul(b, d)), Nat.mul(a, Nat.mul(c, Nat.mul(b, d))), L.mul_assoc(a, c, Nat.mul(b, d))) : {Nat.mul(a, Nat.mul(b, Nat.mul(c, d))) == _ : Nat}
  %L.mul_assoc(b, c, d) : {Nat.mul(a, _) == Nat.mul(a, Nat.mul(c, Nat.mul(b, d))) : Nat}
  %L.mul_assoc(c, b, d) : {Nat.mul(a, Nat.mul(Nat.mul(b, c), d)) == Nat.mul(a, _) : Nat}
  %L.mul_comm(c, b) : {Nat.mul(a, Nat.mul(_, d)) == Nat.mul(a, Nat.mul(Nat.mul(c, b), d)) : Nat}
  {==}

# (a b)(c d) in Fp is ((a b)(c d) mod p).
law fmul22:
  for +pp: Nat
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for +d: Nat
  {F.fmul(1n+pp, F.fmul(1n+pp, a, b), F.fmul(1n+pp, c, d)) == Nat.mod(Nat.mul(Nat.mul(a, b), Nat.mul(c, d)), 1n+pp) : Nat}

def fmul22(pp, a, b, c, d):
  Equal.trans(Nat, F.fmul(1n+pp, F.fmul(1n+pp, a, b), F.fmul(1n+pp, c, d)), Nat.mod(Nat.mul(Nat.mul(a, b), F.fmul(1n+pp, c, d)), 1n+pp), Nat.mod(Nat.mul(Nat.mul(a, b), Nat.mul(c, d)), 1n+pp),
    L.mod_mul_mod_l(Nat.mul(a, b), F.fmul(1n+pp, c, d), pp), L.mod_mul_mod_r(Nat.mul(a, b), Nat.mul(c, d), pp))

# (a b)(c d) == (a c)(b d) in Fp.
law fswap4:
  for +pp: Nat
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for +d: Nat
  {F.fmul(1n+pp, F.fmul(1n+pp, a, b), F.fmul(1n+pp, c, d)) == F.fmul(1n+pp, F.fmul(1n+pp, a, c), F.fmul(1n+pp, b, d)) : Nat}

def fswap4(pp, a, b, c, d):
  Equal.trans(Nat, F.fmul(1n+pp, F.fmul(1n+pp, a, b), F.fmul(1n+pp, c, d)), Nat.mod(Nat.mul(Nat.mul(a, c), Nat.mul(b, d)), 1n+pp), F.fmul(1n+pp, F.fmul(1n+pp, a, c), F.fmul(1n+pp, b, d)),
    Equal.trans(Nat, F.fmul(1n+pp, F.fmul(1n+pp, a, b), F.fmul(1n+pp, c, d)), Nat.mod(Nat.mul(Nat.mul(a, b), Nat.mul(c, d)), 1n+pp), Nat.mod(Nat.mul(Nat.mul(a, c), Nat.mul(b, d)), 1n+pp),
      fmul22(pp, a, b, c, d), Equal.cong(Nat, Nat, w => Nat.mod(w, 1n+pp), Nat.mul(Nat.mul(a, b), Nat.mul(c, d)), Nat.mul(Nat.mul(a, c), Nat.mul(b, d)), nswap4(a, b, c, d))),
    Equal.sym(Nat, F.fmul(1n+pp, F.fmul(1n+pp, a, c), F.fmul(1n+pp, b, d)), Nat.mod(Nat.mul(Nat.mul(a, c), Nat.mul(b, d)), 1n+pp), fmul22(pp, a, c, b, d)))

# Inverses multiply: ai a == 1 and bi b == 1  ==>  (ai bi)(a b) == 1.
law inv_mul:
  for +pp: Nat
  for +l1: L.Le(1n, pp)
  for +a: Nat
  for +ai: Nat
  for +b: Nat
  for +bi: Nat
  for +ha: {F.fmul(1n+pp, ai, a) == 1n : Nat}
  for +hb: {F.fmul(1n+pp, bi, b) == 1n : Nat}
  {F.fmul(1n+pp, F.fmul(1n+pp, ai, bi), F.fmul(1n+pp, a, b)) == 1n : Nat}

def inv_mul(pp, l1, a, ai, b, bi, ha, hb):
  %Equal.sym(Nat, F.fmul(1n+pp, F.fmul(1n+pp, ai, bi), F.fmul(1n+pp, a, b)), F.fmul(1n+pp, F.fmul(1n+pp, ai, a), F.fmul(1n+pp, bi, b)), fswap4(pp, ai, bi, a, b)) : {_ == 1n : Nat}
  %Equal.sym(Nat, F.fmul(1n+pp, ai, a), 1n, ha) : {F.fmul(1n+pp, _, F.fmul(1n+pp, bi, b)) == 1n : Nat}
  %Equal.sym(Nat, F.fmul(1n+pp, bi, b), 1n, hb) : {F.fmul(1n+pp, 1n, _) == 1n : Nat}
  E.fmul_1(pp, 1n, l1)

# Cancelling an invertible factor: (y d) di == y when di d == 1.
law cancel:
  for +pp: Nat
  for +y: Nat
  for +d: Nat
  for +di: Nat
  for +inv: {F.fmul(1n+pp, di, d) == 1n : Nat}
  for +ly: L.Le(y, pp)
  {F.fmul(1n+pp, F.fmul(1n+pp, y, d), di) == y : Nat}

def cancel(pp, y, d, di, inv, ly):
  %Equal.sym(Nat, F.fmul(1n+pp, F.fmul(1n+pp, y, d), di), F.fmul(1n+pp, y, F.fmul(1n+pp, d, di)), fmul_assoc(pp, y, d, di)) : {_ == y : Nat}
  %fmul_comm(pp, di, d) : {F.fmul(1n+pp, y, _) == y : Nat}
  %Equal.sym(Nat, F.fmul(1n+pp, di, d), 1n, inv) : {F.fmul(1n+pp, y, _) == y : Nat}
  %fmul_comm(pp, 1n, y) : {_ == y : Nat}
  E.fmul_1(pp, y, ly)

# (a e) b == (a b) e
law rearr1:
  for +pp: Nat
  for +a: Nat
  for +e: Nat
  for +b: Nat
  {F.fmul(1n+pp, F.fmul(1n+pp, a, e), b) == F.fmul(1n+pp, F.fmul(1n+pp, a, b), e) : Nat}

def rearr1(pp, a, e, b):
  %Equal.sym(Nat, F.fmul(1n+pp, F.fmul(1n+pp, a, e), b), F.fmul(1n+pp, a, F.fmul(1n+pp, e, b)), fmul_assoc(pp, a, e, b)) : {_ == F.fmul(1n+pp, F.fmul(1n+pp, a, b), e) : Nat}
  %Equal.sym(Nat, F.fmul(1n+pp, F.fmul(1n+pp, a, b), e), F.fmul(1n+pp, a, F.fmul(1n+pp, b, e)), fmul_assoc(pp, a, b, e)) : {F.fmul(1n+pp, a, F.fmul(1n+pp, e, b)) == _ : Nat}
  %fmul_comm(pp, b, e) : {F.fmul(1n+pp, a, _) == F.fmul(1n+pp, a, F.fmul(1n+pp, b, e)) : Nat}
  {==}

# ((a a) b) b == (a b)(a b)
law rearr2:
  for +pp: Nat
  for +a: Nat
  for +b: Nat
  {F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, a, a), b), b) == F.fmul(1n+pp, F.fmul(1n+pp, a, b), F.fmul(1n+pp, a, b)) : Nat}

def rearr2(pp, a, b):
  %Equal.sym(Nat, F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, a, a), b), b), F.fmul(1n+pp, F.fmul(1n+pp, a, a), F.fmul(1n+pp, b, b)), fmul_assoc(pp, F.fmul(1n+pp, a, a), b, b)) : {_ == F.fmul(1n+pp, F.fmul(1n+pp, a, b), F.fmul(1n+pp, a, b)) : Nat}
  Equal.sym(Nat, F.fmul(1n+pp, F.fmul(1n+pp, a, b), F.fmul(1n+pp, a, b)), F.fmul(1n+pp, F.fmul(1n+pp, a, a), F.fmul(1n+pp, b, b)), fswap4(pp, a, b, a, b))

# x + (0 - x) == 0 for canonical x.
law self_cancel:
  for +pp: Nat
  for +x: Nat
  for +lx: L.Le(x, pp)
  {F.fadd(1n+pp, x, F.fsub(1n+pp, 0n, x)) == 0n : Nat}

def self_cancel(pp, x, lx):
  %Equal.sym(Nat, Nat.mod(Nat.add(x, Nat.mod(Nat.add(0n, Nat.sub(1n+pp, x)), 1n+pp)), 1n+pp), Nat.mod(Nat.add(x, Nat.add(0n, Nat.sub(1n+pp, x))), 1n+pp), L.mod_add_mod_r(x, Nat.add(0n, Nat.sub(1n+pp, x)), pp)) : {_ == 0n : Nat}
  %Equal.sym(Nat, Nat.add(x, Nat.sub(1n+pp, x)), 1n+pp, L.sub_add(1n+pp, x, F.le_succ(x, pp, lx))) : {Nat.mod(_, 1n+pp) == 0n : Nat}
  L.mod_add_self(0n, pp)

# u == v (canonical)  ==>  u - v == 0
law sub_self:
  for +pp: Nat
  for +u: Nat
  for +v: Nat
  for +lv: L.Le(v, pp)
  for +e: {u == v : Nat}
  {F.fadd(1n+pp, u, F.fsub(1n+pp, 0n, v)) == 0n : Nat}

def sub_self(pp, u, v, lv, e):
  %Equal.sym(Nat, u, v, e) : {F.fadd(1n+pp, _, F.fsub(1n+pp, 0n, v)) == 0n : Nat}
  self_cancel(pp, v, lv)

# The guard 1 - x y of the complete-addition gate is 1 when x == 0.
law guard_one:
  for +pp: Nat
  for +l1: L.Le(1n, pp)
  for +x: Nat
  for +y: Nat
  for +z: {x == 0n : Nat}
  {F.fadd(1n+pp, 1n, F.fsub(1n+pp, 0n, F.fmul(1n+pp, x, y))) == 1n : Nat}

def guard_one(pp, l1, x, y, z):
  %Equal.sym(Nat, x, 0n, z) : {F.fadd(1n+pp, 1n, F.fsub(1n+pp, 0n, F.fmul(1n+pp, _, y))) == 1n : Nat}
  E.one_minus_zero(pp, l1)

# The guard (1 - x y) - u w is 1 when x == 0 and u == 0.
law guard_one2:
  for +pp: Nat
  for +l1: L.Le(1n, pp)
  for +x: Nat
  for +y: Nat
  for +u: Nat
  for +w: Nat
  for +zx: {x == 0n : Nat}
  for +zu: {u == 0n : Nat}
  {F.fadd(1n+pp, F.fadd(1n+pp, 1n, F.fsub(1n+pp, 0n, F.fmul(1n+pp, x, y))), F.fsub(1n+pp, 0n, F.fmul(1n+pp, u, w))) == 1n : Nat}

def guard_one2(pp, l1, x, y, u, w, zx, zu):
  %Equal.sym(Nat, F.fadd(1n+pp, 1n, F.fsub(1n+pp, 0n, F.fmul(1n+pp, x, y))), 1n, guard_one(pp, l1, x, y, zx)) : {F.fadd(1n+pp, _, F.fsub(1n+pp, 0n, F.fmul(1n+pp, u, w))) == 1n : Nat}
  guard_one(pp, l1, u, w, zu)
