import Base
import ../field/natlemmas.bend as N

# Nat algebra shared by the primitive and Orchard-gadget proofs: multiplication,
# order, and division (Base's Nat.divmod). Bend has no ring tactic, so every step
# is an explicit rewrite.

# --- multiplication ---------------------------------------------------------

law mul_zero_r:
  for +x: Nat
  {Nat.mul(x, 0n) == 0n : Nat}

def mul_zero_r(x):
  match x:
    case 0n:
      {==}
    case 1n+p:
      mul_zero_r(p)

# y + (x + z) == x + (y + z)
law add_left_comm:
  for +x: Nat
  for +y: Nat
  for +z: Nat
  {Nat.add(y, Nat.add(x, z)) == Nat.add(x, Nat.add(y, z)) : Nat}

def add_left_comm(x, y, z):
  %N.add_assoc(y, x, z) : {_ == Nat.add(x, Nat.add(y, z)) : Nat}
  %N.add_assoc(x, y, z) : {Nat.add(Nat.add(y, x), z) == _ : Nat}
  %N.add_comm(x, y) : {Nat.add(_, z) == Nat.add(Nat.add(x, y), z) : Nat}
  {==}

law mul_succ_r:
  for +x: Nat
  for +y: Nat
  {Nat.mul(x, 1n+y) == Nat.add(x, Nat.mul(x, y)) : Nat}

def mul_succ_r(x, y):
  match x:
    case 0n:
      {==}
    case 1n+p:
      %Equal.sym(Nat, Nat.mul(p, 1n+y), Nat.add(p, Nat.mul(p, y)), mul_succ_r(p, y)) : {1n+Nat.add(y, _) == 1n+Nat.add(p, Nat.add(y, Nat.mul(p, y))) : Nat}
      %Equal.sym(Nat, Nat.add(y, Nat.add(p, Nat.mul(p, y))), Nat.add(p, Nat.add(y, Nat.mul(p, y))), add_left_comm(p, y, Nat.mul(p, y))) : {1n+_ == 1n+Nat.add(p, Nat.add(y, Nat.mul(p, y))) : Nat}
      {==}

law mul_comm:
  for +x: Nat
  for +y: Nat
  {Nat.mul(x, y) == Nat.mul(y, x) : Nat}

def mul_comm(x, y):
  match x:
    case 0n:
      Equal.sym(Nat, Nat.mul(y, 0n), 0n, mul_zero_r(y))
    case 1n+p:
      %Equal.sym(Nat, Nat.mul(y, 1n+p), Nat.add(y, Nat.mul(y, p)), mul_succ_r(y, p)) : {Nat.add(y, Nat.mul(p, y)) == _ : Nat}
      %Equal.sym(Nat, Nat.mul(p, y), Nat.mul(y, p), mul_comm(p, y)) : {Nat.add(y, _) == Nat.add(y, Nat.mul(y, p)) : Nat}
      {==}

# (a + b) * c == a * c + b * c
law mul_add_r:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  {Nat.mul(Nat.add(a, b), c) == Nat.add(Nat.mul(a, c), Nat.mul(b, c)) : Nat}

def mul_add_r(a, b, c):
  match a:
    case 0n:
      {==}
    case 1n+p:
      %Equal.sym(Nat, Nat.mul(Nat.add(p, b), c), Nat.add(Nat.mul(p, c), Nat.mul(b, c)), mul_add_r(p, b, c)) : {Nat.add(c, _) == Nat.add(Nat.add(c, Nat.mul(p, c)), Nat.mul(b, c)) : Nat}
      Equal.sym(Nat, Nat.add(Nat.add(c, Nat.mul(p, c)), Nat.mul(b, c)), Nat.add(c, Nat.add(Nat.mul(p, c), Nat.mul(b, c))), N.add_assoc(c, Nat.mul(p, c), Nat.mul(b, c)))

# a * (b + c) == a * b + a * c
law mul_add_l:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  {Nat.mul(a, Nat.add(b, c)) == Nat.add(Nat.mul(a, b), Nat.mul(a, c)) : Nat}

def mul_add_l(a, b, c):
  %mul_comm(Nat.add(b, c), a) : {_ == Nat.add(Nat.mul(a, b), Nat.mul(a, c)) : Nat}
  %mul_comm(b, a) : {Nat.mul(Nat.add(b, c), a) == Nat.add(_, Nat.mul(a, c)) : Nat}
  %mul_comm(c, a) : {Nat.mul(Nat.add(b, c), a) == Nat.add(Nat.mul(b, a), _) : Nat}
  mul_add_r(b, c, a)

# (a * b) * c == a * (b * c)
law mul_assoc:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  {Nat.mul(Nat.mul(a, b), c) == Nat.mul(a, Nat.mul(b, c)) : Nat}

def mul_assoc(a, b, c):
  match a:
    case 0n:
      {==}
    case 1n+p:
      %Equal.sym(Nat, Nat.mul(Nat.add(b, Nat.mul(p, b)), c), Nat.add(Nat.mul(b, c), Nat.mul(Nat.mul(p, b), c)), mul_add_r(b, Nat.mul(p, b), c)) : {_ == Nat.add(Nat.mul(b, c), Nat.mul(p, Nat.mul(b, c))) : Nat}
      %Equal.sym(Nat, Nat.mul(Nat.mul(p, b), c), Nat.mul(p, Nat.mul(b, c)), mul_assoc(p, b, c)) : {Nat.add(Nat.mul(b, c), _) == Nat.add(Nat.mul(b, c), Nat.mul(p, Nat.mul(b, c))) : Nat}
      {==}

law mul_one_r:
  for +x: Nat
  {Nat.mul(x, 1n) == x : Nat}

def mul_one_r(x):
  match x:
    case 0n:
      {==}
    case 1n+p:
      %Equal.sym(Nat, Nat.mul(p, 1n), p, mul_one_r(p)) : {1n+_ == 1n+p : Nat}
      {==}

# --- order --------------------------------------------------------------------

# a <= b, witnessed by the gap.
def Le(a: Nat, b: Nat) -> Data:
  Sigma<&2, &2, Nat, e => {Nat.add(a, e) == b : Nat}>

def pred(n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n+p:
      p

law succ_inj:
  for +a: Nat
  for +b: Nat
  for h: {1n+a == 1n+b : Nat}
  {a == b : Nat}

def succ_inj(a, b, h):
  Equal.cong(Nat, Nat, n => pred(n), 1n+a, 1n+b, h)

def IsSucc(n: Nat) -> Type:
  match n:
    case 0n:
      Empty
    case 1n+p:
      Unit

law succ_ne_zero:
  for -a: Nat
  for h: {1n+a == 0n : Nat}
  Empty

def succ_ne_zero(a, h):
  %h : IsSucc(_)
  Unit{}

# k + x == k + y  ==>  x == y
law add_cancel_l:
  for +k: Nat
  for +x: Nat
  for +y: Nat
  for h: {Nat.add(k, x) == Nat.add(k, y) : Nat}
  {x == y : Nat}

def add_cancel_l(k, x, y, h):
  match k:
    case 0n:
      h
    case 1n+kp:
      add_cancel_l(kp, x, y, succ_inj(Nat.add(kp, x), Nat.add(kp, y), h))

# (1 + b) + w == b is impossible.
law succ_add_ne:
  for +b: Nat
  for +w: Nat
  for h: {Nat.add(1n+b, w) == b : Nat}
  Empty

def succ_add_ne(b, w, h):
  match b:
    case 0n:
      succ_ne_zero(w, h)
    case 1n+c:
      succ_add_ne(c, w, succ_inj(Nat.add(1n+c, w), c, h))

# --- division (Base's Nat.divmod) --------------------------------------------

# Loop invariant of Nat.divmod.go, with divisor 1 + s where s = m + r:
# remainder + quotient * (1 + s) accounts for everything consumed so far.
law dm_go:
  for +n: Nat
  for +m: Nat
  for +d: Nat
  for +r: Nat
  for +s: Nat
  for h: {Nat.add(m, r) == s : Nat}
  {Nat.add(Pair.snd(Nat, Nat, Nat.divmod.go(n, m, d, r)), Nat.mul(Pair.fst(Nat, Nat, Nat.divmod.go(n, m, d, r)), 1n+s)) == Nat.add(Nat.add(r, Nat.mul(d, 1n+s)), n) : Nat}

def dm_go(n, m, d, r, s, h):
  match n:
    case 0n:
      Equal.sym(Nat, Nat.add(Nat.add(r, Nat.mul(d, 1n+s)), 0n), Nat.add(r, Nat.mul(d, 1n+s)), N.add_zero_r(Nat.add(r, Nat.mul(d, 1n+s))))
    case 1n+np:
      match m:
        case 0n:
          %Equal.sym(Nat, Nat.add(Nat.add(r, Nat.mul(d, 1n+s)), 1n+np), 1n+Nat.add(Nat.add(r, Nat.mul(d, 1n+s)), np), N.add_succ_r(Nat.add(r, Nat.mul(d, 1n+s)), np)) : {Nat.add(Pair.snd(Nat, Nat, Nat.divmod.go(np, r, 1n+d, 0n)), Nat.mul(Pair.fst(Nat, Nat, Nat.divmod.go(np, r, 1n+d, 0n)), 1n+s)) == _ : Nat}
          %Equal.sym(Nat, r, s, h) : {Nat.add(Pair.snd(Nat, Nat, Nat.divmod.go(np, _, 1n+d, 0n)), Nat.mul(Pair.fst(Nat, Nat, Nat.divmod.go(np, _, 1n+d, 0n)), 1n+s)) == 1n+Nat.add(Nat.add(_, Nat.mul(d, 1n+s)), np) : Nat}
          dm_go(np, s, 1n+d, 0n, s, N.add_zero_r(s))
        case 1n+mp:
          %Equal.sym(Nat, Nat.add(Nat.add(r, Nat.mul(d, 1n+s)), 1n+np), 1n+Nat.add(Nat.add(r, Nat.mul(d, 1n+s)), np), N.add_succ_r(Nat.add(r, Nat.mul(d, 1n+s)), np)) : {Nat.add(Pair.snd(Nat, Nat, Nat.divmod.go(np, mp, d, 1n+r)), Nat.mul(Pair.fst(Nat, Nat, Nat.divmod.go(np, mp, d, 1n+r)), 1n+s)) == _ : Nat}
          dm_go(np, mp, d, 1n+r, s, Equal.trans(Nat, Nat.add(mp, 1n+r), 1n+Nat.add(mp, r), s, N.add_succ_r(mp, r), h))

# The remainder never exceeds s.
law dm_go_le:
  for +n: Nat
  for +m: Nat
  for +d: Nat
  for +r: Nat
  for +s: Nat
  for h: {Nat.add(m, r) == s : Nat}
  Le(Pair.snd(Nat, Nat, Nat.divmod.go(n, m, d, r)), s)

def dm_go_le(n, m, d, r, s, h):
  match n:
    case 0n:
      (m, Equal.trans(Nat, Nat.add(r, m), Nat.add(m, r), s, N.add_comm(r, m), h))
    case 1n+np:
      match m:
        case 0n:
          %Equal.sym(Nat, r, s, h) : Le(Pair.snd(Nat, Nat, Nat.divmod.go(np, _, 1n+d, 0n)), s)
          dm_go_le(np, s, 1n+d, 0n, s, N.add_zero_r(s))
        case 1n+mp:
          dm_go_le(np, mp, d, 1n+r, s, Equal.trans(Nat, Nat.add(mp, 1n+r), 1n+Nat.add(mp, r), s, N.add_succ_r(mp, r), h))

# x == x mod M + (x div M) * M, for M = 1 + bp.
law div_mod:
  for +x: Nat
  for +bp: Nat
  {Nat.add(Nat.mod(x, 1n+bp), Nat.mul(Nat.div(x, 1n+bp), 1n+bp)) == x : Nat}

def div_mod(x, bp):
  dm_go(x, bp, 0n, 0n, bp, N.add_zero_r(bp))

# x mod M <= M - 1.
law mod_le:
  for +x: Nat
  for +bp: Nat
  Le(Nat.mod(x, 1n+bp), bp)

def mod_le(x, bp):
  dm_go_le(x, bp, 0n, 0n, bp, N.add_zero_r(bp))

# r1 + q1 * M == r2 + q2 * M with both remainders below M forces r1 == r2.
law uniq:
  for +bp: Nat
  for +r1: Nat
  for +q1: Nat
  for +r2: Nat
  for +q2: Nat
  for l1: Le(r1, bp)
  for l2: Le(r2, bp)
  for h: {Nat.add(r1, Nat.mul(q1, 1n+bp)) == Nat.add(r2, Nat.mul(q2, 1n+bp)) : Nat}
  {r1 == r2 : Nat}

# r == M + z together with r + e == M - 1 is impossible.
law uniq_absurd:
  for +bp: Nat
  for +r: Nat
  for +z: Nat
  for l: Le(r, bp)
  for hr: {r == Nat.add(1n+bp, z) : Nat}
  Empty

def uniq_absurd(bp, r, z, l, hr):
  (e, he) = l
  succ_add_ne(bp, Nat.add(z, e), Equal.trans(Nat, Nat.add(1n+bp, Nat.add(z, e)), Nat.add(Nat.add(1n+bp, z), e), bp, Equal.sym(Nat, Nat.add(Nat.add(1n+bp, z), e), Nat.add(1n+bp, Nat.add(z, e)), N.add_assoc(1n+bp, z, e)), Equal.trans(Nat, Nat.add(Nat.add(1n+bp, z), e), Nat.add(r, e), bp, Equal.cong(Nat, Nat, w => Nat.add(w, e), Nat.add(1n+bp, z), r, Equal.sym(Nat, r, Nat.add(1n+bp, z), hr)), he)))

def uniq(bp, r1, q1, r2, q2, l1, l2, h):
  match q1 q2:
    case 0n 0n:
      Equal.trans(Nat, r1, Nat.add(r1, 0n), r2, Equal.sym(Nat, Nat.add(r1, 0n), r1, N.add_zero_r(r1)), Equal.trans(Nat, Nat.add(r1, 0n), Nat.add(r2, 0n), r2, h, N.add_zero_r(r2)))
    case 0n 1n+b:
      Empty.absurd({r1 == r2 : Nat}, uniq_absurd(bp, r1, Nat.add(r2, Nat.mul(b, 1n+bp)), l1, Equal.trans(Nat, r1, Nat.add(r1, 0n), Nat.add(1n+bp, Nat.add(r2, Nat.mul(b, 1n+bp))), Equal.sym(Nat, Nat.add(r1, 0n), r1, N.add_zero_r(r1)), Equal.trans(Nat, Nat.add(r1, 0n), Nat.add(r2, Nat.add(1n+bp, Nat.mul(b, 1n+bp))), Nat.add(1n+bp, Nat.add(r2, Nat.mul(b, 1n+bp))), h, add_left_comm(1n+bp, r2, Nat.mul(b, 1n+bp))))))
    case 1n+a 0n:
      Empty.absurd({r1 == r2 : Nat}, uniq_absurd(bp, r2, Nat.add(r1, Nat.mul(a, 1n+bp)), l2, Equal.trans(Nat, r2, Nat.add(r2, 0n), Nat.add(1n+bp, Nat.add(r1, Nat.mul(a, 1n+bp))), Equal.sym(Nat, Nat.add(r2, 0n), r2, N.add_zero_r(r2)), Equal.trans(Nat, Nat.add(r2, 0n), Nat.add(r1, Nat.add(1n+bp, Nat.mul(a, 1n+bp))), Nat.add(1n+bp, Nat.add(r1, Nat.mul(a, 1n+bp))), Equal.sym(Nat, Nat.add(r1, Nat.add(1n+bp, Nat.mul(a, 1n+bp))), Nat.add(r2, 0n), h), add_left_comm(1n+bp, r1, Nat.mul(a, 1n+bp))))))
    case 1n+a 1n+b:
      uniq(bp, r1, a, r2, b, l1, l2, add_cancel_l(1n+bp, Nat.add(r1, Nat.mul(a, 1n+bp)), Nat.add(r2, Nat.mul(b, 1n+bp)), Equal.trans(Nat, Nat.add(1n+bp, Nat.add(r1, Nat.mul(a, 1n+bp))), Nat.add(r1, Nat.add(1n+bp, Nat.mul(a, 1n+bp))), Nat.add(1n+bp, Nat.add(r2, Nat.mul(b, 1n+bp))), Equal.sym(Nat, Nat.add(r1, Nat.add(1n+bp, Nat.mul(a, 1n+bp))), Nat.add(1n+bp, Nat.add(r1, Nat.mul(a, 1n+bp))), add_left_comm(1n+bp, r1, Nat.mul(a, 1n+bp))), Equal.trans(Nat, Nat.add(r1, Nat.add(1n+bp, Nat.mul(a, 1n+bp))), Nat.add(r2, Nat.add(1n+bp, Nat.mul(b, 1n+bp))), Nat.add(1n+bp, Nat.add(r2, Nat.mul(b, 1n+bp))), h, add_left_comm(1n+bp, r2, Nat.mul(b, 1n+bp))))))

# A value already below M is its own remainder.
law mod_small:
  for +r: Nat
  for +bp: Nat
  for l: Le(r, bp)
  {Nat.mod(r, 1n+bp) == r : Nat}

def mod_small(r, bp, l):
  uniq(bp, Nat.mod(r, 1n+bp), Nat.div(r, 1n+bp), r, 0n, mod_le(r, bp), l, Equal.trans(Nat, Nat.add(Nat.mod(r, 1n+bp), Nat.mul(Nat.div(r, 1n+bp), 1n+bp)), r, Nat.add(r, 0n), div_mod(r, bp), Equal.sym(Nat, Nat.add(r, 0n), r, N.add_zero_r(r))))

# Adding a multiple of M does not change the remainder.
law mod_add_mul:
  for +x: Nat
  for +q: Nat
  for +bp: Nat
  {Nat.mod(Nat.add(x, Nat.mul(q, 1n+bp)), 1n+bp) == Nat.mod(x, 1n+bp) : Nat}

def mod_add_mul(x, q, bp):
  uniq(bp, Nat.mod(Nat.add(x, Nat.mul(q, 1n+bp)), 1n+bp), Nat.div(Nat.add(x, Nat.mul(q, 1n+bp)), 1n+bp), Nat.mod(x, 1n+bp), Nat.add(Nat.div(x, 1n+bp), q), mod_le(Nat.add(x, Nat.mul(q, 1n+bp)), bp), mod_le(x, bp), Equal.trans(Nat, Nat.add(Nat.mod(Nat.add(x, Nat.mul(q, 1n+bp)), 1n+bp), Nat.mul(Nat.div(Nat.add(x, Nat.mul(q, 1n+bp)), 1n+bp), 1n+bp)), Nat.add(x, Nat.mul(q, 1n+bp)), Nat.add(Nat.mod(x, 1n+bp), Nat.mul(Nat.add(Nat.div(x, 1n+bp), q), 1n+bp)), div_mod(Nat.add(x, Nat.mul(q, 1n+bp)), bp), Equal.trans(Nat, Nat.add(x, Nat.mul(q, 1n+bp)), Nat.add(Nat.add(Nat.mod(x, 1n+bp), Nat.mul(Nat.div(x, 1n+bp), 1n+bp)), Nat.mul(q, 1n+bp)), Nat.add(Nat.mod(x, 1n+bp), Nat.mul(Nat.add(Nat.div(x, 1n+bp), q), 1n+bp)), Equal.cong(Nat, Nat, w => Nat.add(w, Nat.mul(q, 1n+bp)), x, Nat.add(Nat.mod(x, 1n+bp), Nat.mul(Nat.div(x, 1n+bp), 1n+bp)), Equal.sym(Nat, Nat.add(Nat.mod(x, 1n+bp), Nat.mul(Nat.div(x, 1n+bp), 1n+bp)), x, div_mod(x, bp))), Equal.trans(Nat, Nat.add(Nat.add(Nat.mod(x, 1n+bp), Nat.mul(Nat.div(x, 1n+bp), 1n+bp)), Nat.mul(q, 1n+bp)), Nat.add(Nat.mod(x, 1n+bp), Nat.add(Nat.mul(Nat.div(x, 1n+bp), 1n+bp), Nat.mul(q, 1n+bp))), Nat.add(Nat.mod(x, 1n+bp), Nat.mul(Nat.add(Nat.div(x, 1n+bp), q), 1n+bp)), N.add_assoc(Nat.mod(x, 1n+bp), Nat.mul(Nat.div(x, 1n+bp), 1n+bp), Nat.mul(q, 1n+bp)), Equal.cong(Nat, Nat, w => Nat.add(Nat.mod(x, 1n+bp), w), Nat.add(Nat.mul(Nat.div(x, 1n+bp), 1n+bp), Nat.mul(q, 1n+bp)), Nat.mul(Nat.add(Nat.div(x, 1n+bp), q), 1n+bp), Equal.sym(Nat, Nat.mul(Nat.add(Nat.div(x, 1n+bp), q), 1n+bp), Nat.add(Nat.mul(Nat.div(x, 1n+bp), 1n+bp), Nat.mul(q, 1n+bp)), mul_add_r(Nat.div(x, 1n+bp), q, 1n+bp)))))))

# (r + u) + v == (r + v) + u
law add_right_comm:
  for +r: Nat
  for +u: Nat
  for +v: Nat
  {Nat.add(Nat.add(r, u), v) == Nat.add(Nat.add(r, v), u) : Nat}

def add_right_comm(r, u, v):
  %Equal.sym(Nat, Nat.add(Nat.add(r, u), v), Nat.add(r, Nat.add(u, v)), N.add_assoc(r, u, v)) : {_ == Nat.add(Nat.add(r, v), u) : Nat}
  %Equal.sym(Nat, Nat.add(Nat.add(r, v), u), Nat.add(r, Nat.add(v, u)), N.add_assoc(r, v, u)) : {Nat.add(r, Nat.add(u, v)) == _ : Nat}
  %N.add_comm(v, u) : {Nat.add(r, _) == Nat.add(r, Nat.add(v, u)) : Nat}
  {==}

law mul_one_l:
  for +x: Nat
  {Nat.mul(1n, x) == x : Nat}

def mul_one_l(x):
  N.add_zero_r(x)

# Reducing an addend mod M does not change the sum mod M.
law mod_add_mod_l:
  for +a: Nat
  for +b: Nat
  for +bp: Nat
  {Nat.mod(Nat.add(Nat.mod(a, 1n+bp), b), 1n+bp) == Nat.mod(Nat.add(a, b), 1n+bp) : Nat}

def mod_add_mod_l(a, b, bp):
  %div_mod(a, bp) : {Nat.mod(Nat.add(Nat.mod(a, 1n+bp), b), 1n+bp) == Nat.mod(Nat.add(_, b), 1n+bp) : Nat}
  %add_right_comm(Nat.mod(a, 1n+bp), b, Nat.mul(Nat.div(a, 1n+bp), 1n+bp)) : {Nat.mod(Nat.add(Nat.mod(a, 1n+bp), b), 1n+bp) == Nat.mod(_, 1n+bp) : Nat}
  Equal.sym(Nat, Nat.mod(Nat.add(Nat.add(Nat.mod(a, 1n+bp), b), Nat.mul(Nat.div(a, 1n+bp), 1n+bp)), 1n+bp), Nat.mod(Nat.add(Nat.mod(a, 1n+bp), b), 1n+bp), mod_add_mul(Nat.add(Nat.mod(a, 1n+bp), b), Nat.div(a, 1n+bp), bp))

law mod_add_mod_r:
  for +a: Nat
  for +b: Nat
  for +bp: Nat
  {Nat.mod(Nat.add(a, Nat.mod(b, 1n+bp)), 1n+bp) == Nat.mod(Nat.add(a, b), 1n+bp) : Nat}

def mod_add_mod_r(a, b, bp):
  %N.add_comm(Nat.mod(b, 1n+bp), a) : {Nat.mod(_, 1n+bp) == Nat.mod(Nat.add(a, b), 1n+bp) : Nat}
  %N.add_comm(b, a) : {Nat.mod(Nat.add(Nat.mod(b, 1n+bp), a), 1n+bp) == Nat.mod(_, 1n+bp) : Nat}
  mod_add_mod_l(b, a, bp)

# Adding M itself does not change the remainder.
law mod_add_self:
  for +x: Nat
  for +bp: Nat
  {Nat.mod(Nat.add(x, 1n+bp), 1n+bp) == Nat.mod(x, 1n+bp) : Nat}

def mod_add_self(x, bp):
  %mul_one_l(1n+bp) : {Nat.mod(Nat.add(x, _), 1n+bp) == Nat.mod(x, 1n+bp) : Nat}
  mod_add_mul(x, 1n, bp)

# Truncated subtraction undoes addition when y <= a.
law sub_add:
  for +a: Nat
  for +y: Nat
  for l: Le(y, a)
  {Nat.add(y, Nat.sub(a, y)) == a : Nat}

def sub_add_s(+ap: Nat, +yp: Nat, l: Le(1n+yp, 1n+ap)) -> Le(yp, ap):
  (+e, he) = l
  (e, succ_inj(Nat.add(yp, e), ap, he))

def sub_add_z(-yp: Nat, l: Le(1n+yp, 0n)) -> {Nat.add(1n+yp, Nat.sub(0n, 1n+yp)) == 0n : Nat}:
  (e, he) = l
  Empty.absurd({Nat.add(1n+yp, Nat.sub(0n, 1n+yp)) == 0n : Nat}, succ_ne_zero(Nat.add(yp, e), he))

def sub_add(a, y, l):
  match a:
    case 0n:
      match y:
        case 0n:
          {==}
        case 1n+yp:
          sub_add_z(yp, l)
    case 1n+ap:
      match y:
        case 0n:
          {==}
        case 1n+yp:
          Equal.cong(Nat, Nat, w => 1n+w, Nat.add(yp, Nat.sub(ap, yp)), ap, sub_add(ap, yp, sub_add_s(ap, yp, l)))

# Reducing a factor mod M does not change the product mod M.
law mod_mul_mod_l:
  for +a: Nat
  for +b: Nat
  for +bp: Nat
  {Nat.mod(Nat.mul(Nat.mod(a, 1n+bp), b), 1n+bp) == Nat.mod(Nat.mul(a, b), 1n+bp) : Nat}

def mod_mul_mod_l(a, b, bp):
  %div_mod(a, bp) : {Nat.mod(Nat.mul(Nat.mod(a, 1n+bp), b), 1n+bp) == Nat.mod(Nat.mul(_, b), 1n+bp) : Nat}
  %Equal.sym(Nat, Nat.mul(Nat.add(Nat.mod(a, 1n+bp), Nat.mul(Nat.div(a, 1n+bp), 1n+bp)), b), Nat.add(Nat.mul(Nat.mod(a, 1n+bp), b), Nat.mul(Nat.mul(Nat.div(a, 1n+bp), 1n+bp), b)), mul_add_r(Nat.mod(a, 1n+bp), Nat.mul(Nat.div(a, 1n+bp), 1n+bp), b)) : {Nat.mod(Nat.mul(Nat.mod(a, 1n+bp), b), 1n+bp) == Nat.mod(_, 1n+bp) : Nat}
  %Equal.sym(Nat, Nat.mul(Nat.mul(Nat.div(a, 1n+bp), 1n+bp), b), Nat.mul(Nat.div(a, 1n+bp), Nat.mul(1n+bp, b)), mul_assoc(Nat.div(a, 1n+bp), 1n+bp, b)) : {Nat.mod(Nat.mul(Nat.mod(a, 1n+bp), b), 1n+bp) == Nat.mod(Nat.add(Nat.mul(Nat.mod(a, 1n+bp), b), _), 1n+bp) : Nat}
  %mul_comm(b, 1n+bp) : {Nat.mod(Nat.mul(Nat.mod(a, 1n+bp), b), 1n+bp) == Nat.mod(Nat.add(Nat.mul(Nat.mod(a, 1n+bp), b), Nat.mul(Nat.div(a, 1n+bp), _)), 1n+bp) : Nat}
  %mul_assoc(Nat.div(a, 1n+bp), b, 1n+bp) : {Nat.mod(Nat.mul(Nat.mod(a, 1n+bp), b), 1n+bp) == Nat.mod(Nat.add(Nat.mul(Nat.mod(a, 1n+bp), b), _), 1n+bp) : Nat}
  Equal.sym(Nat, Nat.mod(Nat.add(Nat.mul(Nat.mod(a, 1n+bp), b), Nat.mul(Nat.mul(Nat.div(a, 1n+bp), b), 1n+bp)), 1n+bp), Nat.mod(Nat.mul(Nat.mod(a, 1n+bp), b), 1n+bp), mod_add_mul(Nat.mul(Nat.mod(a, 1n+bp), b), Nat.mul(Nat.div(a, 1n+bp), b), bp))

law mod_mul_mod_r:
  for +a: Nat
  for +b: Nat
  for +bp: Nat
  {Nat.mod(Nat.mul(a, Nat.mod(b, 1n+bp)), 1n+bp) == Nat.mod(Nat.mul(a, b), 1n+bp) : Nat}

def mod_mul_mod_r(a, b, bp):
  %mul_comm(Nat.mod(b, 1n+bp), a) : {Nat.mod(_, 1n+bp) == Nat.mod(Nat.mul(a, b), 1n+bp) : Nat}
  %mul_comm(b, a) : {Nat.mod(Nat.mul(Nat.mod(b, 1n+bp), a), 1n+bp) == Nat.mod(_, 1n+bp) : Nat}
  mod_mul_mod_l(b, a, bp)
