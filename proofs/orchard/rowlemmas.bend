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
