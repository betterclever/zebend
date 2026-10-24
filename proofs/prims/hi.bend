import Base
import ../field/natlemmas.bend as N
import ./natlib.bend as L

# Splitting a double-width value x < M^2 (M = 1 + bp) into a low and a high digit:
# x == (x mod M) + (x div M) * M with x div M < M, so the high digit survives the
# conversion back to a single word. Generic in bp; the U32 laws use bp = 2^32 - 1.

# The largest double-width value: M^2 - 1 = bp + bp * M.
def TB(+bp: Nat) -> Nat:
  Nat.add(bp, Nat.mul(bp, 1n+bp))

def le_trans(+a: Nat, +b: Nat, +c: Nat, +l1: L.Le(a, b), +l2: L.Le(b, c)) -> L.Le(a, c):
  (+e1, h1) = l1
  (+e2, h2) = l2
  (Nat.add(e1, e2), Equal.trans(Nat, Nat.add(a, Nat.add(e1, e2)), Nat.add(Nat.add(a, e1), e2), c,
    Equal.sym(Nat, Nat.add(Nat.add(a, e1), e2), Nat.add(a, Nat.add(e1, e2)), N.add_assoc(a, e1, e2)),
    Equal.trans(Nat, Nat.add(Nat.add(a, e1), e2), Nat.add(b, e2), c, Equal.cong(Nat, Nat, w => Nat.add(w, e2), Nat.add(a, e1), b, h1), h2)))

def le_mul_r(+c: Nat, +x: Nat, +y: Nat, +l: L.Le(x, y)) -> L.Le(Nat.mul(c, x), Nat.mul(c, y)):
  (+e, h) = l
  (Nat.mul(c, e), Equal.trans(Nat, Nat.add(Nat.mul(c, x), Nat.mul(c, e)), Nat.mul(c, Nat.add(x, e)), Nat.mul(c, y),
    Equal.sym(Nat, Nat.mul(c, Nat.add(x, e)), Nat.add(Nat.mul(c, x), Nat.mul(c, e)), L.mul_add_l(c, x, e)),
    Equal.cong(Nat, Nat, w => Nat.mul(c, w), Nat.add(x, e), y, h)))

def le_mul_l(+c: Nat, +x: Nat, +y: Nat, +l: L.Le(x, y)) -> L.Le(Nat.mul(x, c), Nat.mul(y, c)):
  (+e, h) = l
  (Nat.mul(e, c), Equal.trans(Nat, Nat.add(Nat.mul(x, c), Nat.mul(e, c)), Nat.mul(Nat.add(x, e), c), Nat.mul(y, c),
    Equal.sym(Nat, Nat.mul(Nat.add(x, e), c), Nat.add(Nat.mul(x, c), Nat.mul(e, c)), L.mul_add_r(x, e, c)),
    Equal.cong(Nat, Nat, w => Nat.mul(w, c), Nat.add(x, e), y, h)))

def le_add(+a: Nat, +b: Nat, +c: Nat, +d: Nat, +l1: L.Le(a, b), +l2: L.Le(c, d)) -> L.Le(Nat.add(a, c), Nat.add(b, d)):
  (+e1, h1) = l1
  (+e2, h2) = l2
  (Nat.add(e1, e2), Equal.trans(Nat, Nat.add(Nat.add(a, c), Nat.add(e1, e2)), Nat.add(Nat.add(a, e1), Nat.add(c, e2)), Nat.add(b, d),
    N.swap_mid(a, c, e1, e2),
    Equal.trans(Nat, Nat.add(Nat.add(a, e1), Nat.add(c, e2)), Nat.add(b, Nat.add(c, e2)), Nat.add(b, d),
      Equal.cong(Nat, Nat, w => Nat.add(w, Nat.add(c, e2)), Nat.add(a, e1), b, h1),
      Equal.cong(Nat, Nat, w => Nat.add(b, w), Nat.add(c, e2), d, h2))))

# (bp + bp) + bp*bp == TB(bp)
def tb_eq(+bp: Nat) -> {Nat.add(Nat.add(bp, bp), Nat.mul(bp, bp)) == TB(bp) : Nat}:
  Equal.trans(Nat, Nat.add(Nat.add(bp, bp), Nat.mul(bp, bp)), Nat.add(bp, Nat.add(bp, Nat.mul(bp, bp))), TB(bp),
    N.add_assoc(bp, bp, Nat.mul(bp, bp)),
    Equal.cong(Nat, Nat, w => Nat.add(bp, w), Nat.add(bp, Nat.mul(bp, bp)), Nat.mul(bp, 1n+bp), Equal.sym(Nat, Nat.mul(bp, 1n+bp), Nat.add(bp, Nat.mul(bp, bp)), L.mul_succ_r(bp, bp))))

def le_sq(+bp: Nat, +a: Nat, +b: Nat, +la: L.Le(a, bp), +lb: L.Le(b, bp)) -> L.Le(Nat.mul(a, b), Nat.mul(bp, bp)):
  le_trans(Nat.mul(a, b), Nat.mul(bp, b), Nat.mul(bp, bp), le_mul_l(b, a, bp, la), le_mul_r(bp, b, bp, lb))

law bnd_mul:
  for +bp: Nat
  for +a: Nat
  for +b: Nat
  for +la: L.Le(a, bp)
  for +lb: L.Le(b, bp)
  L.Le(Nat.mul(a, b), TB(bp))

def bnd_mul(bp, a, b, la, lb):
  le_trans(Nat.mul(a, b), Nat.mul(bp, bp), TB(bp), le_sq(bp, a, b, la, lb),
    (Nat.add(bp, bp), Equal.trans(Nat, Nat.add(Nat.mul(bp, bp), Nat.add(bp, bp)), Nat.add(Nat.add(bp, bp), Nat.mul(bp, bp)), TB(bp), N.add_comm(Nat.mul(bp, bp), Nat.add(bp, bp)), tb_eq(bp))))

law bnd_add:
  for +bp: Nat
  for +a: Nat
  for +b: Nat
  for +la: L.Le(a, bp)
  for +lb: L.Le(b, bp)
  L.Le(Nat.add(a, b), TB(bp))

def bnd_add(bp, a, b, la, lb):
  le_trans(Nat.add(a, b), Nat.add(bp, bp), TB(bp), le_add(a, bp, b, bp, la, lb), (Nat.mul(bp, bp), tb_eq(bp)))

# a * b + c + d still fits: (M-1)^2 + 2(M-1) == M^2 - 1.
law bnd_mac:
  for +bp: Nat
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for +d: Nat
  for +la: L.Le(a, bp)
  for +lb: L.Le(b, bp)
  for +lc: L.Le(c, bp)
  for +ld: L.Le(d, bp)
  L.Le(Nat.add(Nat.add(Nat.mul(a, b), c), d), TB(bp))

def bnd_mac(bp, a, b, c, d, la, lb, lc, ld):
  le_trans(Nat.add(Nat.add(Nat.mul(a, b), c), d), Nat.add(Nat.add(Nat.mul(bp, bp), bp), bp), TB(bp),
    le_add(Nat.add(Nat.mul(a, b), c), Nat.add(Nat.mul(bp, bp), bp), d, bp, le_add(Nat.mul(a, b), Nat.mul(bp, bp), c, bp, le_sq(bp, a, b, la, lb), lc), ld),
    (0n, Equal.trans(Nat, Nat.add(Nat.add(Nat.add(Nat.mul(bp, bp), bp), bp), 0n), Nat.add(Nat.add(Nat.mul(bp, bp), bp), bp), TB(bp), N.add_zero_r(Nat.add(Nat.add(Nat.mul(bp, bp), bp), bp)),
      Equal.trans(Nat, Nat.add(Nat.add(Nat.mul(bp, bp), bp), bp), Nat.add(Nat.mul(bp, bp), Nat.add(bp, bp)), TB(bp), N.add_assoc(Nat.mul(bp, bp), bp, bp),
        Equal.trans(Nat, Nat.add(Nat.mul(bp, bp), Nat.add(bp, bp)), Nat.add(Nat.add(bp, bp), Nat.mul(bp, bp)), TB(bp), N.add_comm(Nat.mul(bp, bp), Nat.add(bp, bp)), tb_eq(bp))))))

def le_s(+dp: Nat, +bq: Nat, +l: L.Le(dp, bq)) -> L.Le(1n+dp, 1n+bq):
  (+e, h) = l
  (e, Equal.cong(Nat, Nat, w => 1n+w, Nat.add(dp, e), bq, h))

def gt_s(+dp: Nat, +bq: Nat, +s: Sigma<&2, &2, Nat, z => {dp == Nat.add(1n+bq, z) : Nat}>) -> Sigma<&2, &2, Nat, z => {1n+dp == Nat.add(2n+bq, z) : Nat}>:
  (+z, h) = s
  (z, Equal.cong(Nat, Nat, w => 1n+w, dp, Nat.add(1n+bq, z), h))

def le_or_gt_s(+bq: Nat, +dp: Nat, e: Either<&1, &1, L.Le(dp, bq), Sigma<&2, &2, Nat, z => {dp == Nat.add(1n+bq, z) : Nat}>>) -> Either<&1, &1, L.Le(1n+dp, 1n+bq), Sigma<&2, &2, Nat, z => {1n+dp == Nat.add(2n+bq, z) : Nat}>>:
  match e:
    case Inl{l}:
      Inl{le_s(dp, bq, l)}
    case Inr{s}:
      Inr{gt_s(dp, bq, s)}

law le_or_gt:
  for +d: Nat
  for +bp: Nat
  Either<&1, &1, L.Le(d, bp), Sigma<&2, &2, Nat, z => {d == Nat.add(1n+bp, z) : Nat}>>

def le_or_gt(d, bp):
  match d bp:
    case 0n bp:
      Inl{(bp, {==})}
    case 1n+dp 0n:
      Inr{(dp, {==})}
    case 1n+dp 1n+bq:
      le_or_gt_s(bq, dp, le_or_gt(dp, bq))

# (r + (a + (b + c))) + e == b + (a + (r + (c + e)))
def perm5(+r: Nat, +a: Nat, +b: Nat, +c: Nat, +e: Nat) -> {Nat.add(Nat.add(r, Nat.add(a, Nat.add(b, c))), e) == Nat.add(b, Nat.add(a, Nat.add(r, Nat.add(c, e)))) : Nat}:
  Equal.trans(Nat, Nat.add(Nat.add(r, Nat.add(a, Nat.add(b, c))), e), Nat.add(r, Nat.add(Nat.add(a, Nat.add(b, c)), e)), Nat.add(b, Nat.add(a, Nat.add(r, Nat.add(c, e)))),
    N.add_assoc(r, Nat.add(a, Nat.add(b, c)), e),
  Equal.trans(Nat, Nat.add(r, Nat.add(Nat.add(a, Nat.add(b, c)), e)), Nat.add(r, Nat.add(a, Nat.add(Nat.add(b, c), e))), Nat.add(b, Nat.add(a, Nat.add(r, Nat.add(c, e)))),
    Equal.cong(Nat, Nat, w => Nat.add(r, w), Nat.add(Nat.add(a, Nat.add(b, c)), e), Nat.add(a, Nat.add(Nat.add(b, c), e)), N.add_assoc(a, Nat.add(b, c), e)),
  Equal.trans(Nat, Nat.add(r, Nat.add(a, Nat.add(Nat.add(b, c), e))), Nat.add(r, Nat.add(a, Nat.add(b, Nat.add(c, e)))), Nat.add(b, Nat.add(a, Nat.add(r, Nat.add(c, e)))),
    Equal.cong(Nat, Nat, w => Nat.add(r, Nat.add(a, w)), Nat.add(Nat.add(b, c), e), Nat.add(b, Nat.add(c, e)), N.add_assoc(b, c, e)),
  Equal.trans(Nat, Nat.add(r, Nat.add(a, Nat.add(b, Nat.add(c, e)))), Nat.add(a, Nat.add(r, Nat.add(b, Nat.add(c, e)))), Nat.add(b, Nat.add(a, Nat.add(r, Nat.add(c, e)))),
    L.add_left_comm(a, r, Nat.add(b, Nat.add(c, e))),
  Equal.trans(Nat, Nat.add(a, Nat.add(r, Nat.add(b, Nat.add(c, e)))), Nat.add(a, Nat.add(b, Nat.add(r, Nat.add(c, e)))), Nat.add(b, Nat.add(a, Nat.add(r, Nat.add(c, e)))),
    Equal.cong(Nat, Nat, w => Nat.add(a, w), Nat.add(r, Nat.add(b, Nat.add(c, e))), Nat.add(b, Nat.add(r, Nat.add(c, e))), L.add_left_comm(b, r, Nat.add(c, e))),
    L.add_left_comm(b, a, Nat.add(r, Nat.add(c, e))))))))

# x <= M^2 - 1 and x div M == M + z cannot both hold.
def gt_absurd(+bp: Nat, +x: Nat, +l: L.Le(x, TB(bp)), +s: Sigma<&2, &2, Nat, z => {Nat.div(x, 1n+bp) == Nat.add(1n+bp, z) : Nat}>) -> Empty:
  (+e, he) = l
  (+z, hz) = s
  L.succ_add_ne(bp, Nat.add(Nat.mod(x, 1n+bp), Nat.add(Nat.mul(z, 1n+bp), e)),
    L.add_cancel_l(Nat.mul(bp, 1n+bp), Nat.add(1n+bp, Nat.add(Nat.mod(x, 1n+bp), Nat.add(Nat.mul(z, 1n+bp), e))), bp,
      Equal.trans(Nat, Nat.add(Nat.mul(bp, 1n+bp), Nat.add(1n+bp, Nat.add(Nat.mod(x, 1n+bp), Nat.add(Nat.mul(z, 1n+bp), e)))), Nat.add(Nat.add(Nat.mod(x, 1n+bp), Nat.add(1n+bp, Nat.add(Nat.mul(bp, 1n+bp), Nat.mul(z, 1n+bp)))), e), Nat.add(Nat.mul(bp, 1n+bp), bp),
        Equal.sym(Nat, Nat.add(Nat.add(Nat.mod(x, 1n+bp), Nat.add(1n+bp, Nat.add(Nat.mul(bp, 1n+bp), Nat.mul(z, 1n+bp)))), e), Nat.add(Nat.mul(bp, 1n+bp), Nat.add(1n+bp, Nat.add(Nat.mod(x, 1n+bp), Nat.add(Nat.mul(z, 1n+bp), e)))), perm5(Nat.mod(x, 1n+bp), 1n+bp, Nat.mul(bp, 1n+bp), Nat.mul(z, 1n+bp), e)),
      Equal.trans(Nat, Nat.add(Nat.add(Nat.mod(x, 1n+bp), Nat.add(1n+bp, Nat.add(Nat.mul(bp, 1n+bp), Nat.mul(z, 1n+bp)))), e), Nat.add(Nat.add(Nat.mod(x, 1n+bp), Nat.mul(Nat.add(1n+bp, z), 1n+bp)), e), Nat.add(Nat.mul(bp, 1n+bp), bp),
        Equal.cong(Nat, Nat, w => Nat.add(Nat.add(Nat.mod(x, 1n+bp), Nat.add(1n+bp, w)), e), Nat.add(Nat.mul(bp, 1n+bp), Nat.mul(z, 1n+bp)), Nat.mul(Nat.add(bp, z), 1n+bp), Equal.sym(Nat, Nat.mul(Nat.add(bp, z), 1n+bp), Nat.add(Nat.mul(bp, 1n+bp), Nat.mul(z, 1n+bp)), L.mul_add_r(bp, z, 1n+bp))),
      Equal.trans(Nat, Nat.add(Nat.add(Nat.mod(x, 1n+bp), Nat.mul(Nat.add(1n+bp, z), 1n+bp)), e), Nat.add(Nat.add(Nat.mod(x, 1n+bp), Nat.mul(Nat.div(x, 1n+bp), 1n+bp)), e), Nat.add(Nat.mul(bp, 1n+bp), bp),
        Equal.cong(Nat, Nat, w => Nat.add(Nat.add(Nat.mod(x, 1n+bp), Nat.mul(w, 1n+bp)), e), Nat.add(1n+bp, z), Nat.div(x, 1n+bp), Equal.sym(Nat, Nat.div(x, 1n+bp), Nat.add(1n+bp, z), hz)),
      Equal.trans(Nat, Nat.add(Nat.add(Nat.mod(x, 1n+bp), Nat.mul(Nat.div(x, 1n+bp), 1n+bp)), e), Nat.add(x, e), Nat.add(Nat.mul(bp, 1n+bp), bp),
        Equal.cong(Nat, Nat, w => Nat.add(w, e), Nat.add(Nat.mod(x, 1n+bp), Nat.mul(Nat.div(x, 1n+bp), 1n+bp)), x, L.div_mod(x, bp)),
      Equal.trans(Nat, Nat.add(x, e), TB(bp), Nat.add(Nat.mul(bp, 1n+bp), bp), he, N.add_comm(bp, Nat.mul(bp, 1n+bp)))))))))

def db_go(+bp: Nat, +x: Nat, +l: L.Le(x, TB(bp)), e: Either<&1, &1, L.Le(Nat.div(x, 1n+bp), bp), Sigma<&2, &2, Nat, z => {Nat.div(x, 1n+bp) == Nat.add(1n+bp, z) : Nat}>>) -> L.Le(Nat.div(x, 1n+bp), bp):
  match e:
    case Inl{h}:
      h
    case Inr{s}:
      Empty.absurd(L.Le(Nat.div(x, 1n+bp), bp), gt_absurd(bp, x, l, s))

# The high digit of a double-width value is a single digit.
law div_bound:
  for +bp: Nat
  for +x: Nat
  for +l: L.Le(x, TB(bp))
  L.Le(Nat.div(x, 1n+bp), bp)

def div_bound(bp, x, l):
  db_go(bp, x, l, le_or_gt(Nat.div(x, 1n+bp), bp))

# lo == x mod M and t == (x div M) mod M give lo + t * M == x.
law hi_split:
  for +bp: Nat
  for +x: Nat
  for +lo: Nat
  for +t: Nat
  for hlo: {lo == Nat.mod(x, 1n+bp) : Nat}
  for ht: {t == Nat.mod(Nat.div(x, 1n+bp), 1n+bp) : Nat}
  for +l: L.Le(x, TB(bp))
  {Nat.add(lo, Nat.mul(t, 1n+bp)) == x : Nat}

def hi_split(bp, x, lo, t, hlo, ht, l):
  %Equal.sym(Nat, lo, Nat.mod(x, 1n+bp), hlo) : {Nat.add(_, Nat.mul(t, 1n+bp)) == x : Nat}
  %Equal.sym(Nat, t, Nat.div(x, 1n+bp), Equal.trans(Nat, t, Nat.mod(Nat.div(x, 1n+bp), 1n+bp), Nat.div(x, 1n+bp), ht, L.mod_small(Nat.div(x, 1n+bp), bp, div_bound(bp, x, l)))) : {Nat.add(Nat.mod(x, 1n+bp), Nat.mul(_, 1n+bp)) == x : Nat}
  L.div_mod(x, bp)

# M * M == 1 + TB(bp): the double-width modulus.
def sq_tb(+bp: Nat) -> {Nat.mul(1n+bp, 1n+bp) == 1n+TB(bp) : Nat}:
  {==}

def le_zero_go(+a: Nat, +e: Nat, h: {Nat.add(a, e) == 0n : Nat}) -> {a == 0n : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      Empty.absurd({1n+p == 0n : Nat}, L.succ_ne_zero(Nat.add(p, e), h))

def le_zero(+a: Nat, +l: L.Le(a, 0n)) -> {a == 0n : Nat}:
  (+e, h) = l
  le_zero_go(a, e, h)

law div_one:
  for +y: Nat
  {Nat.div(y, 1n) == y : Nat}

def div_one(y):
  Equal.trans(Nat, Nat.div(y, 1n), Nat.add(Nat.mod(y, 1n), Nat.mul(Nat.div(y, 1n), 1n)), y,
    Equal.trans(Nat, Nat.div(y, 1n), Nat.add(0n, Nat.mul(Nat.div(y, 1n), 1n)), Nat.add(Nat.mod(y, 1n), Nat.mul(Nat.div(y, 1n), 1n)),
      Equal.sym(Nat, Nat.mul(Nat.div(y, 1n), 1n), Nat.div(y, 1n), L.mul_one_r(Nat.div(y, 1n))),
      Equal.cong(Nat, Nat, w => Nat.add(w, Nat.mul(Nat.div(y, 1n), 1n)), 0n, Nat.mod(y, 1n), Equal.sym(Nat, Nat.mod(y, 1n), 0n, le_zero(Nat.mod(y, 1n), L.mod_le(y, 0n))))),
    L.div_mod(y, 0n))
