import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L

# Order facts over Nat for the range-check and canonicity laws (integer reasoning about
# canonical field elements). L.Le(a, b) is a <= b, witnessed by the gap; a < b is
# L.Le(1n+a, b).

def le_refl(+a: Nat) -> L.Le(a, a):
  (0n, N.add_zero_r(a))

# a <= a + c
def le_add_self(+a: Nat, +c: Nat) -> L.Le(a, Nat.add(a, c)):
  (c, {==})

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

# a <= b  ==>  c + a <= c + b
law le_add_l:
  for +c: Nat
  for +a: Nat
  for +b: Nat
  for +l: L.Le(a, b)
  L.Le(Nat.add(c, a), Nat.add(c, b))

def le_add_l(c, a, b, l):
  (+e, h) = l
  (e, Equal.trans(Nat, Nat.add(Nat.add(c, a), e), Nat.add(c, Nat.add(a, e)), Nat.add(c, b),
    N.add_assoc(c, a, e), Equal.cong(Nat, Nat, w => Nat.add(c, w), Nat.add(a, e), b, h)))

# a <= b  ==>  a + c <= b + c
law le_add_r:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for +l: L.Le(a, b)
  L.Le(Nat.add(a, c), Nat.add(b, c))

def le_add_r(a, b, c, l):
  %Equal.sym(Nat, Nat.add(a, c), Nat.add(c, a), N.add_comm(a, c)) : L.Le(_, Nat.add(b, c))
  %Equal.sym(Nat, Nat.add(b, c), Nat.add(c, b), N.add_comm(b, c)) : L.Le(Nat.add(c, a), _)
  le_add_l(c, a, b, l)

# a <= b, c <= d  ==>  a + c <= b + d
law le_add2:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for +d: Nat
  for +l1: L.Le(a, b)
  for +l2: L.Le(c, d)
  L.Le(Nat.add(a, c), Nat.add(b, d))

def le_add2(a, b, c, d, l1, l2):
  le_trans(Nat.add(a, c), Nat.add(b, c), Nat.add(b, d), le_add_r(a, b, c, l1), le_add_l(b, c, d, l2))

# a <= b  ==>  a c <= b c
law le_mul_r:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for +l: L.Le(a, b)
  L.Le(Nat.mul(a, c), Nat.mul(b, c))

def le_mul_r(a, b, c, l):
  (+e, h) = l
  (Nat.mul(e, c), Equal.trans(Nat, Nat.add(Nat.mul(a, c), Nat.mul(e, c)), Nat.mul(Nat.add(a, e), c), Nat.mul(b, c),
    Equal.sym(Nat, Nat.mul(Nat.add(a, e), c), Nat.add(Nat.mul(a, c), Nat.mul(e, c)), L.mul_add_r(a, e, c)),
    Equal.cong(Nat, Nat, w => Nat.mul(w, c), Nat.add(a, e), b, h)))

# a <= b  ==>  c a <= c b
law le_mul_l:
  for +c: Nat
  for +a: Nat
  for +b: Nat
  for +l: L.Le(a, b)
  L.Le(Nat.mul(c, a), Nat.mul(c, b))

def le_mul_l(c, a, b, l):
  %L.mul_comm(a, c) : L.Le(_, Nat.mul(c, b))
  %L.mul_comm(b, c) : L.Le(Nat.mul(a, c), _)
  le_mul_r(a, b, c, l)

# 1 + a <= 1 + b  ==>  a <= b
law le_pred:
  for +a: Nat
  for +b: Nat
  for +l: L.Le(1n+a, 1n+b)
  L.Le(a, b)

def le_pred(a, b, l):
  (+e, h) = l
  (e, L.succ_inj(Nat.add(a, e), b, h))

# a < b  ==>  a <= b
def lt_le(+a: Nat, +b: Nat, +l: L.Le(1n+a, b)) -> L.Le(a, b):
  (+e, h) = l
  (1n+e, Equal.trans(Nat, Nat.add(a, 1n+e), 1n+Nat.add(a, e), b, N.add_succ_r(a, e), h))

def succ_out(+a: Nat, +b: Nat, +k: Nat, +l: L.Le(Nat.add(a, 1n+k), Nat.add(b, 1n+k))) -> L.Le(1n+Nat.add(a, k), 1n+Nat.add(b, k)):
  %N.add_succ_r(a, k) : L.Le(_, 1n+Nat.add(b, k))
  %N.add_succ_r(b, k) : L.Le(Nat.add(a, 1n+k), _)
  l

# a + c <= b + c  ==>  a <= b
law le_cancel_r:
  for +a: Nat
  for +b: Nat
  for c: Nat
  for +l: L.Le(Nat.add(a, c), Nat.add(b, c))
  L.Le(a, b)

def le_cancel_r(a, b, c, l):
  match c:
    case 0n:
      %N.add_zero_r(a) : L.Le(_, b)
      %N.add_zero_r(b) : L.Le(Nat.add(a, 0n), _)
      l
    case 1n+(+k):
      le_cancel_r(a, b, k, le_pred(Nat.add(a, k), Nat.add(b, k), succ_out(a, b, k, l)))

# not (b + 1 + r <= b): the strict order is irreflexive.
law lt_irrefl:
  for +a: Nat
  for +l: L.Le(1n+a, a)
  Empty

def lt_go(+a: Nat, +e: Nat, h: {Nat.add(1n+a, e) == a : Nat}) -> Empty:
  match a:
    case 0n:
      L.succ_ne_zero(e, h)
    case 1n+m:
      lt_go(m, e, L.succ_inj(Nat.add(1n+m, e), m, h))

def lt_irrefl(a, l):
  (+e, h) = l
  lt_go(a, e, h)
