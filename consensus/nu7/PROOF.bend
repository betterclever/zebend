# Proofs for LAWS.bend.
import Base
import ../../proofs/field/natlemmas.bend as NL
import ../../proofs/prims/natlib.bend as L
import ../issuance/issuance.bend as I
import ./nu7.bend as N
import ./era7.bend as E
import ./LAWS.bend as Laws

# ================================================================ order helpers
# (le_refl .. mul_mono_l and the halving lemmas as in consensus/issuance/PROOF.bend)

law le_refl:
  for +a: Nat
  L.Le(a, a)

def le_refl(a):
  (0n, NL.add_zero_r(a))

law le_trans_eq:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for +e1: Nat
  for +e2: Nat
  for p1: {Nat.add(a, e1) == b : Nat}
  for p2: {Nat.add(b, e2) == c : Nat}
  {Nat.add(a, Nat.add(e1, e2)) == c : Nat}

def le_trans_eq(a, b, c, e1, e2, p1, p2):
  %NL.add_assoc(a, e1, e2) : {_ == c : Nat}
  %Equal.sym(Nat, Nat.add(a, e1), b, p1) : {Nat.add(_, e2) == c : Nat}
  p2

law le_trans:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for l1: L.Le(a, b)
  for l2: L.Le(b, c)
  L.Le(a, c)

def le_trans(a, b, c, l1, l2):
  (+e1, p1) = l1
  (+e2, p2) = l2
  (Nat.add(e1, e2), le_trans_eq(a, b, c, e1, e2, p1, p2))

law add_mono_eq:
  for +k: Nat
  for +a: Nat
  for +b: Nat
  for +e: Nat
  for p: {Nat.add(a, e) == b : Nat}
  {Nat.add(Nat.add(k, a), e) == Nat.add(k, b) : Nat}

def add_mono_eq(k, a, b, e, p):
  %Equal.sym(Nat, Nat.add(Nat.add(k, a), e), Nat.add(k, Nat.add(a, e)), NL.add_assoc(k, a, e)) : {_ == Nat.add(k, b) : Nat}
  %p : {Nat.add(k, Nat.add(a, e)) == Nat.add(k, _) : Nat}
  {==}

law add_mono_l:
  for +k: Nat
  for +a: Nat
  for +b: Nat
  for l: L.Le(a, b)
  L.Le(Nat.add(k, a), Nat.add(k, b))

def add_mono_l(k, a, b, l):
  (+e, p) = l
  (e, add_mono_eq(k, a, b, e, p))

law mul_mono_eq:
  for +n: Nat
  for +a: Nat
  for +b: Nat
  for +e: Nat
  for p: {Nat.add(a, e) == b : Nat}
  {Nat.add(Nat.mul(n, a), Nat.mul(n, e)) == Nat.mul(n, b) : Nat}

def mul_mono_eq(n, a, b, e, p):
  %L.mul_add_l(n, a, e) : {_ == Nat.mul(n, b) : Nat}
  %p : {Nat.mul(n, Nat.add(a, e)) == Nat.mul(n, _) : Nat}
  {==}

law mul_mono_l:
  for +n: Nat
  for +a: Nat
  for +b: Nat
  for l: L.Le(a, b)
  L.Le(Nat.mul(n, a), Nat.mul(n, b))

def mul_mono_l(n, a, b, l):
  (+e, p) = l
  (Nat.mul(n, e), mul_mono_eq(n, a, b, e, p))

# a + c <= b + d from a <= b and c <= d.
law add_le_add_eq:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for +d: Nat
  for +e1: Nat
  for +e2: Nat
  for p1: {Nat.add(a, e1) == b : Nat}
  for p2: {Nat.add(c, e2) == d : Nat}
  {Nat.add(Nat.add(a, c), Nat.add(e1, e2)) == Nat.add(b, d) : Nat}

def add_le_add_eq(a, b, c, d, e1, e2, p1, p2):
  %NL.swap_mid(a, e1, c, e2) : {_ == Nat.add(b, d) : Nat}
  %Equal.sym(Nat, Nat.add(a, e1), b, p1) : {Nat.add(_, Nat.add(c, e2)) == Nat.add(b, d) : Nat}
  %Equal.sym(Nat, Nat.add(c, e2), d, p2) : {Nat.add(b, _) == Nat.add(b, d) : Nat}
  {==}

law add_le_add:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for +d: Nat
  for l1: L.Le(a, b)
  for l2: L.Le(c, d)
  L.Le(Nat.add(a, c), Nat.add(b, d))

def add_le_add(a, b, c, d, l1, l2):
  (+e1, p1) = l1
  (+e2, p2) = l2
  (Nat.add(e1, e2), add_le_add_eq(a, b, c, d, e1, e2, p1, p2))

# ================================================================ division

# Multiplication by a positive number is injective.
law mul_cancel:
  for +a: Nat
  for +b: Nat
  for +bp: Nat
  for h: {Nat.mul(a, 1n+bp) == Nat.mul(b, 1n+bp) : Nat}
  {a == b : Nat}

def mul_cancel(a, b, bp, h):
  match a b:
    case 0n 0n:
      {==}
    case 0n 1n+q:
      Empty.absurd({0n == 1n+q : Nat}, L.succ_ne_zero(Nat.add(bp, Nat.mul(q, 1n+bp)), Equal.sym(Nat, 0n, 1n+Nat.add(bp, Nat.mul(q, 1n+bp)), h)))
    case 1n+p 0n:
      Empty.absurd({1n+p == 0n : Nat}, L.succ_ne_zero(Nat.add(bp, Nat.mul(p, 1n+bp)), h))
    case 1n+p 1n+q:
      Equal.cong(Nat, Nat, n => 1n+n, p, q, mul_cancel(p, q, bp, L.add_cancel_l(1n+bp, Nat.mul(p, 1n+bp), Nat.mul(q, 1n+bp), h)))

law qu_eq:
  for +bp: Nat
  for +x: Nat
  for +r: Nat
  for +q: Nat
  for u: {Nat.mod(x, 1n+bp) == r : Nat}
  for h: {Nat.add(r, Nat.mul(q, 1n+bp)) == x : Nat}
  {Nat.add(Nat.mod(x, 1n+bp), Nat.mul(Nat.div(x, 1n+bp), 1n+bp)) == Nat.add(Nat.mod(x, 1n+bp), Nat.mul(q, 1n+bp)) : Nat}

def qu_eq(bp, x, r, q, u, h):
  %Equal.sym(Nat, Nat.mod(x, 1n+bp), r, u) : {Nat.add(Nat.mod(x, 1n+bp), Nat.mul(Nat.div(x, 1n+bp), 1n+bp)) == Nat.add(_, Nat.mul(q, 1n+bp)) : Nat}
  Equal.trans(Nat, Nat.add(Nat.mod(x, 1n+bp), Nat.mul(Nat.div(x, 1n+bp), 1n+bp)), x, Nat.add(r, Nat.mul(q, 1n+bp)), L.div_mod(x, bp), Equal.sym(Nat, Nat.add(r, Nat.mul(q, 1n+bp)), x, h))

# The quotient is determined: x == r + q M with r < M forces x div M == q.
law quot_uniq:
  for +bp: Nat
  for +x: Nat
  for +r: Nat
  for +q: Nat
  for l: L.Le(r, bp)
  for +h: {Nat.add(r, Nat.mul(q, 1n+bp)) == x : Nat}
  {Nat.div(x, 1n+bp) == q : Nat}

def quot_uniq(bp, x, r, q, l, h):
  +u = L.uniq(bp, Nat.mod(x, 1n+bp), Nat.div(x, 1n+bp), r, q, L.mod_le(x, bp), l,
         Equal.trans(Nat, Nat.add(Nat.mod(x, 1n+bp), Nat.mul(Nat.div(x, 1n+bp), 1n+bp)), x, Nat.add(r, Nat.mul(q, 1n+bp)), L.div_mod(x, bp), Equal.sym(Nat, Nat.add(r, Nat.mul(q, 1n+bp)), x, h)))
  mul_cancel(Nat.div(x, 1n+bp), q, bp,
    L.add_cancel_l(Nat.mod(x, 1n+bp), Nat.mul(Nat.div(x, 1n+bp), 1n+bp), Nat.mul(q, 1n+bp), qu_eq(bp, x, r, q, u, h)))

# 3 * (x div 3) <= x.
law three_div_le:
  for +x: Nat
  L.Le(Nat.mul(3n, Nat.div(x, 3n)), x)

def three_div_le(x):
  %L.mul_comm(Nat.div(x, 3n), 3n) : L.Le(_, x)
  (Nat.mod(x, 3n), Equal.trans(Nat, Nat.add(Nat.mul(Nat.div(x, 3n), 3n), Nat.mod(x, 3n)), Nat.add(Nat.mod(x, 3n), Nat.mul(Nat.div(x, 3n), 3n)), x,
    NL.add_comm(Nat.mul(Nat.div(x, 3n), 3n), Nat.mod(x, 3n)), L.div_mod(x, 2n)))

# x <= 3 * (x div 3) + 2.
law three_div_ge_eq:
  for +x: Nat
  for +e: Nat
  for he: {Nat.add(Nat.mod(x, 3n), e) == 2n : Nat}
  {Nat.add(x, e) == Nat.add(Nat.mul(3n, Nat.div(x, 3n)), 2n) : Nat}

def three_div_ge_eq(x, e, he):
  %L.div_mod(x, 2n) : {Nat.add(_, e) == Nat.add(Nat.mul(3n, Nat.div(x, 3n)), 2n) : Nat}
  %L.add_right_comm(Nat.mod(x, 3n), e, Nat.mul(Nat.div(x, 3n), 3n)) : {_ == Nat.add(Nat.mul(3n, Nat.div(x, 3n)), 2n) : Nat}
  %Equal.sym(Nat, Nat.add(Nat.mod(x, 3n), e), 2n, he) : {Nat.add(_, Nat.mul(Nat.div(x, 3n), 3n)) == Nat.add(Nat.mul(3n, Nat.div(x, 3n)), 2n) : Nat}
  %L.mul_comm(Nat.div(x, 3n), 3n) : {Nat.add(2n, Nat.mul(Nat.div(x, 3n), 3n)) == Nat.add(_, 2n) : Nat}
  NL.add_comm(2n, Nat.mul(Nat.div(x, 3n), 3n))

law three_div_ge:
  for +x: Nat
  L.Le(x, Nat.add(Nat.mul(3n, Nat.div(x, 3n)), 2n))

law three_div_ge_of:
  for +x: Nat
  for l: L.Le(Nat.mod(x, 3n), 2n)
  L.Le(x, Nat.add(Nat.mul(3n, Nat.div(x, 3n)), 2n))

def three_div_ge_of(x, l):
  (+e, he) = l
  (e, three_div_ge_eq(x, e, he))

def three_div_ge(x):
  three_div_ge_of(x, L.mod_le(x, 2n))

# ================================================================ issuance laws

def Laws.per_time_le(k, m):
  three_div_le(I.halve(k, m))

def Laws.per_time_ge(k, m):
  three_div_ge(I.halve(k, m))

law tr_eq:
  for +y: Nat
  for +d: Nat
  {Nat.mul(Nat.mul(3n, y), d) == Nat.mul(y, Nat.mul(3n, d)) : Nat}

def tr_eq(y, d):
  %L.mul_comm(y, 3n) : {Nat.mul(_, d) == Nat.mul(y, Nat.mul(3n, d)) : Nat}
  L.mul_assoc(y, 3n, d)

def Laws.transition_era_le(x, y, s):
  %Equal.sym(Nat, Nat.mul(Nat.mul(3n, y), Nat.div(s, 3n)), Nat.mul(y, Nat.mul(3n, Nat.div(s, 3n))), tr_eq(y, Nat.div(s, 3n))) : L.Le(Nat.add(Nat.mul(x, s), _), Nat.mul(Nat.add(x, y), s))
  %Equal.sym(Nat, Nat.mul(Nat.add(x, y), s), Nat.add(Nat.mul(x, s), Nat.mul(y, s)), L.mul_add_r(x, y, s)) : L.Le(Nat.add(Nat.mul(x, s), Nat.mul(y, Nat.mul(3n, Nat.div(s, 3n)))), _)
  add_mono_l(Nat.mul(x, s), Nat.mul(y, Nat.mul(3n, Nat.div(s, 3n))), Nat.mul(y, s), mul_mono_l(y, Nat.mul(3n, Nat.div(s, 3n)), s, three_div_le(s)))

# --- the 75 s schedule's geometric bound (consensus/issuance/PROOF.bend) ---

law half_split:
  for +x: Nat
  {Nat.add(Nat.mod(x, 2n), Nat.add(Nat.div(x, 2n), Nat.div(x, 2n))) == x : Nat}

def half_split(x):
  %Equal.trans(Nat, Nat.mul(Nat.div(x, 2n), 2n), Nat.add(Nat.div(x, 2n), Nat.mul(Nat.div(x, 2n), 1n)), Nat.add(Nat.div(x, 2n), Nat.div(x, 2n)), L.mul_succ_r(Nat.div(x, 2n), 1n), Equal.cong(Nat, Nat, y => Nat.add(Nat.div(x, 2n), y), Nat.mul(Nat.div(x, 2n), 1n), Nat.div(x, 2n), L.mul_one_r(Nat.div(x, 2n)))) : {Nat.add(Nat.mod(x, 2n), _) == x : Nat}
  L.div_mod(x, 1n)

law two_half_eq:
  for +x: Nat
  {Nat.add(Nat.add(Nat.div(x, 2n), Nat.div(x, 2n)), Nat.mod(x, 2n)) == x : Nat}

def two_half_eq(x):
  %Equal.sym(Nat, Nat.add(Nat.add(Nat.div(x, 2n), Nat.div(x, 2n)), Nat.mod(x, 2n)), Nat.add(Nat.mod(x, 2n), Nat.add(Nat.div(x, 2n), Nat.div(x, 2n))), NL.add_comm(Nat.add(Nat.div(x, 2n), Nat.div(x, 2n)), Nat.mod(x, 2n))) : {_ == x : Nat}
  half_split(x)

law two_half_le:
  for +x: Nat
  L.Le(Nat.add(Nat.div(x, 2n), Nat.div(x, 2n)), x)

def two_half_le(x):
  (Nat.mod(x, 2n), two_half_eq(x))

law total_le:
  for +K: Nat
  for +m: Nat
  L.Le(I.total(K, m), Nat.add(m, m))

def total_le(K, m):
  match K:
    case 0n:
      (Nat.add(m, m), {==})
    case 1n+p:
      add_mono_l(m, I.total(p, Nat.div(m, 2n)), m,
        le_trans(I.total(p, Nat.div(m, 2n)), Nat.add(Nat.div(m, 2n), Nat.div(m, 2n)), m,
          total_le(p, Nat.div(m, 2n)), two_half_le(m)))

# 3 * total7(K, m) <= total(K, m): every NU7 era issues at most the 75 s era's subsidy.
law total7_le:
  for +K: Nat
  for +m: Nat
  L.Le(Nat.mul(3n, N.total7(K, m)), I.total(K, m))

def total7_le(K, m):
  match K:
    case 0n:
      (0n, {==})
    case 1n+p:
      %Equal.sym(Nat, Nat.mul(3n, Nat.add(Nat.div(m, 3n), N.total7(p, Nat.div(m, 2n)))), Nat.add(Nat.mul(3n, Nat.div(m, 3n)), Nat.mul(3n, N.total7(p, Nat.div(m, 2n)))), L.mul_add_l(3n, Nat.div(m, 3n), N.total7(p, Nat.div(m, 2n)))) : L.Le(_, Nat.add(m, I.total(p, Nat.div(m, 2n))))
      add_le_add(Nat.mul(3n, Nat.div(m, 3n)), m, Nat.mul(3n, N.total7(p, Nat.div(m, 2n))), I.total(p, Nat.div(m, 2n)),
        three_div_le(m), total7_le(p, Nat.div(m, 2n)))

law cap_eq:
  for +n: Nat
  for +t: Nat
  {Nat.mul(Nat.mul(3n, n), t) == Nat.mul(n, Nat.mul(3n, t)) : Nat}

def cap_eq(n, t):
  tr_eq(n, t)

def Laws.cap_nu7(n, K, m):
  %Equal.sym(Nat, Nat.mul(Nat.mul(3n, n), N.total7(K, m)), Nat.mul(n, Nat.mul(3n, N.total7(K, m))), cap_eq(n, N.total7(K, m))) : L.Le(_, Nat.mul(n, Nat.add(m, m)))
  le_trans(Nat.mul(n, Nat.mul(3n, N.total7(K, m))), Nat.mul(n, I.total(K, m)), Nat.mul(n, Nat.add(m, m)),
    mul_mono_l(n, Nat.mul(3n, N.total7(K, m)), I.total(K, m), total7_le(K, m)),
    mul_mono_l(n, I.total(K, m), Nat.add(m, m), total_le(K, m)))

# --- halving continuity -----------------------------------------------------

law sub_self:
  for +a: Nat
  {Nat.sub(a, a) == 0n : Nat}

def sub_self(a):
  match a:
    case 0n:
      {==}
    case 1n+p:
      sub_self(p)

# mul(3, M) with M = 1 + bp is 1 + (bp + 2 + 2bp): the remainder bound scales.
law three_rem_eq:
  for +ivp: Nat
  {Nat.add(ivp, Nat.mul(2n, 1n+ivp)) == Nat.add(ivp, Nat.add(2n, Nat.mul(2n, ivp))) : Nat}

def three_rem_eq(ivp):
  %Equal.sym(Nat, Nat.mul(2n, 1n+ivp), Nat.add(2n, Nat.mul(2n, ivp)), L.mul_succ_r(2n, ivp)) : {Nat.add(ivp, _) == Nat.add(ivp, Nat.add(2n, Nat.mul(2n, ivp))) : Nat}
  {==}

law three_rem:
  for +r: Nat
  for +ivp: Nat
  for l: L.Le(r, ivp)
  L.Le(Nat.mul(3n, r), Nat.add(ivp, Nat.mul(2n, 1n+ivp)))

def three_rem(r, ivp, l):
  %Equal.sym(Nat, Nat.add(ivp, Nat.mul(2n, 1n+ivp)), Nat.add(ivp, Nat.add(2n, Nat.mul(2n, ivp))), three_rem_eq(ivp)) : L.Le(Nat.mul(3n, r), _)
  le_trans(Nat.mul(3n, r), Nat.mul(3n, ivp), Nat.add(ivp, Nat.add(2n, Nat.mul(2n, ivp))),
    mul_mono_l(3n, r, ivp, l),
    add_mono_l(ivp, Nat.mul(2n, ivp), Nat.add(2n, Nat.mul(2n, ivp)), (2n, NL.add_comm(Nat.mul(2n, ivp), 2n))))

# 3 x == 3 (x mod M) + (x div M) (3 M).
law three_split:
  for +x: Nat
  for +ivp: Nat
  {Nat.add(Nat.mul(3n, Nat.mod(x, 1n+ivp)), Nat.mul(Nat.div(x, 1n+ivp), Nat.mul(3n, 1n+ivp))) == Nat.mul(3n, x) : Nat}

def three_split(x, ivp):
  %L.mul_assoc(Nat.div(x, 1n+ivp), 3n, 1n+ivp) : {Nat.add(Nat.mul(3n, Nat.mod(x, 1n+ivp)), _) == Nat.mul(3n, x) : Nat}
  %L.mul_comm(3n, Nat.div(x, 1n+ivp)) : {Nat.add(Nat.mul(3n, Nat.mod(x, 1n+ivp)), Nat.mul(_, 1n+ivp)) == Nat.mul(3n, x) : Nat}
  %Equal.sym(Nat, Nat.mul(Nat.mul(3n, Nat.div(x, 1n+ivp)), 1n+ivp), Nat.mul(3n, Nat.mul(Nat.div(x, 1n+ivp), 1n+ivp)), L.mul_assoc(3n, Nat.div(x, 1n+ivp), 1n+ivp)) : {Nat.add(Nat.mul(3n, Nat.mod(x, 1n+ivp)), _) == Nat.mul(3n, x) : Nat}
  %L.mul_add_l(3n, Nat.mod(x, 1n+ivp), Nat.mul(Nat.div(x, 1n+ivp), 1n+ivp)) : {_ == Nat.mul(3n, x) : Nat}
  %L.div_mod(x, ivp) : {Nat.mul(3n, Nat.add(Nat.mod(x, 1n+ivp), Nat.mul(Nat.div(x, 1n+ivp), 1n+ivp))) == Nat.mul(3n, _) : Nat}
  {==}

law div_mul3:
  for +x: Nat
  for +ivp: Nat
  {Nat.div(Nat.mul(3n, x), Nat.mul(3n, 1n+ivp)) == Nat.div(x, 1n+ivp) : Nat}

def div_mul3(x, ivp):
  quot_uniq(Nat.add(ivp, Nat.mul(2n, 1n+ivp)), Nat.mul(3n, x), Nat.mul(3n, Nat.mod(x, 1n+ivp)), Nat.div(x, 1n+ivp),
    three_rem(Nat.mod(x, 1n+ivp), ivp, L.mod_le(x, ivp)), three_split(x, ivp))

def Laws.halving_continuous(s, b, a, ivp):
  +x = Nat.add(Nat.mul(2n, Nat.sub(b, s)), Nat.sub(a, b))
  %Equal.sym(Nat, Nat.sub(a, a), 0n, sub_self(a)) : {Nat.div(Nat.add(Nat.mul(3n, x), _), Nat.mul(3n, 1n+ivp)) == Nat.div(x, 1n+ivp) : Nat}
  %Equal.sym(Nat, Nat.add(Nat.mul(3n, x), 0n), Nat.mul(3n, x), NL.add_zero_r(Nat.mul(3n, x))) : {Nat.div(_, Nat.mul(3n, 1n+ivp)) == Nat.div(x, 1n+ivp) : Nat}
  div_mul3(x, ivp)

# ================================================================ NSM laws

# (x + q M) div M == (x div M) + q.
law div_shift:
  for +x: Nat
  for +q: Nat
  for +bp: Nat
  {Nat.div(Nat.add(x, Nat.mul(q, 1n+bp)), 1n+bp) == Nat.add(Nat.div(x, 1n+bp), q) : Nat}

law div_shift_eq:
  for +x: Nat
  for +q: Nat
  for +bp: Nat
  {Nat.add(Nat.mod(x, 1n+bp), Nat.mul(Nat.add(Nat.div(x, 1n+bp), q), 1n+bp)) == Nat.add(x, Nat.mul(q, 1n+bp)) : Nat}

def div_shift_eq(x, q, bp):
  %Equal.sym(Nat, Nat.mul(Nat.add(Nat.div(x, 1n+bp), q), 1n+bp), Nat.add(Nat.mul(Nat.div(x, 1n+bp), 1n+bp), Nat.mul(q, 1n+bp)), L.mul_add_r(Nat.div(x, 1n+bp), q, 1n+bp)) : {Nat.add(Nat.mod(x, 1n+bp), _) == Nat.add(x, Nat.mul(q, 1n+bp)) : Nat}
  %NL.add_assoc(Nat.mod(x, 1n+bp), Nat.mul(Nat.div(x, 1n+bp), 1n+bp), Nat.mul(q, 1n+bp)) : {_ == Nat.add(x, Nat.mul(q, 1n+bp)) : Nat}
  %L.div_mod(x, bp) : {Nat.add(Nat.add(Nat.mod(x, 1n+bp), Nat.mul(Nat.div(x, 1n+bp), 1n+bp)), Nat.mul(q, 1n+bp)) == Nat.add(_, Nat.mul(q, 1n+bp)) : Nat}
  {==}

def div_shift(x, q, bp):
  quot_uniq(bp, Nat.add(x, Nat.mul(q, 1n+bp)), Nat.mod(x, 1n+bp), Nat.add(Nat.div(x, 1n+bp), q), L.mod_le(x, bp), div_shift_eq(x, q, bp))

# 6 f == 6 r + (6 q) 10 with f == r + q 10.
law six_split:
  for +f: Nat
  {Nat.mul(6n, f) == Nat.add(Nat.mul(6n, Nat.mod(f, 10n)), Nat.mul(Nat.mul(6n, Nat.div(f, 10n)), 10n)) : Nat}

def six_split(f):
  %Equal.sym(Nat, Nat.mul(Nat.mul(6n, Nat.div(f, 10n)), 10n), Nat.mul(6n, Nat.mul(Nat.div(f, 10n), 10n)), L.mul_assoc(6n, Nat.div(f, 10n), 10n)) : {Nat.mul(6n, f) == Nat.add(Nat.mul(6n, Nat.mod(f, 10n)), _) : Nat}
  %L.mul_add_l(6n, Nat.mod(f, 10n), Nat.mul(Nat.div(f, 10n), 10n)) : {Nat.mul(6n, f) == _ : Nat}
  %L.div_mod(f, 9n) : {Nat.mul(6n, _) == Nat.mul(6n, Nat.add(Nat.mod(f, 10n), Nat.mul(Nat.div(f, 10n), 10n))) : Nat}
  {==}

def Laws.contribution_exact(f):
  %Equal.sym(Nat, Nat.mul(6n, f), Nat.add(Nat.mul(6n, Nat.mod(f, 10n)), Nat.mul(Nat.mul(6n, Nat.div(f, 10n)), 10n)), six_split(f)) : {N.nsm_contribution_n(f) == Nat.div(_, 10n) : Nat}
  %Equal.sym(Nat, Nat.div(Nat.add(Nat.mul(6n, Nat.mod(f, 10n)), Nat.mul(Nat.mul(6n, Nat.div(f, 10n)), 10n)), 10n), Nat.add(Nat.div(Nat.mul(6n, Nat.mod(f, 10n)), 10n), Nat.mul(6n, Nat.div(f, 10n))), div_shift(Nat.mul(6n, Nat.mod(f, 10n)), Nat.mul(6n, Nat.div(f, 10n)), 9n)) : {N.nsm_contribution_n(f) == _ : Nat}
  NL.add_comm(Nat.mul(6n, Nat.div(f, 10n)), Nat.div(Nat.mul(6n, Nat.mod(f, 10n)), 10n))

# For r <= 9: floor(6 r / 10) <= r (checked digit by digit).
law small_le:
  for +r: Nat
  for l: L.Le(r, 9n)
  L.Le(Nat.div(Nat.mul(6n, r), 10n), r)

def small_absurd(+t: Nat, +e: Nat, h: {Nat.add(10n+t, e) == 9n : Nat}) -> Empty:
  L.succ_add_ne(9n, Nat.add(t, e), h)

def small_le(r, l):
  match r:
    case 0n:
      (0n, {==})
    case 1n+r1:
      match r1:
        case 0n:
          (1n, {==})
        case 1n+r2:
          match r2:
            case 0n:
              (1n, {==})
            case 1n+r3:
              match r3:
                case 0n:
                  (2n, {==})
                case 1n+r4:
                  match r4:
                    case 0n:
                      (2n, {==})
                    case 1n+r5:
                      match r5:
                        case 0n:
                          (2n, {==})
                        case 1n+r6:
                          match r6:
                            case 0n:
                              (3n, {==})
                            case 1n+r7:
                              match r7:
                                case 0n:
                                  (3n, {==})
                                case 1n+r8:
                                  match r8:
                                    case 0n:
                                      (4n, {==})
                                    case 1n+r9:
                                      match r9:
                                        case 0n:
                                          (4n, {==})
                                        case 1n+t:
                                          (+e, he) = l
                                          Empty.absurd(L.Le(Nat.div(Nat.mul(6n, 10n+t), 10n), 10n+t), small_absurd(t, e, he))

# 6 q <= q 10.
law six_le_ten:
  for +q: Nat
  L.Le(Nat.mul(6n, q), Nat.mul(q, 10n))

def six_le_ten(q):
  %L.mul_comm(10n, q) : L.Le(Nat.mul(6n, q), _)
  (Nat.mul(4n, q), Equal.sym(Nat, Nat.mul(10n, q), Nat.add(Nat.mul(6n, q), Nat.mul(4n, q)), L.mul_add_r(6n, 4n, q)))

def Laws.contribution_le(f):
  %NL.add_comm(Nat.div(Nat.mul(6n, Nat.mod(f, 10n)), 10n), Nat.mul(6n, Nat.div(f, 10n))) : L.Le(_, f)
  %L.div_mod(f, 9n) : L.Le(Nat.add(Nat.div(Nat.mul(6n, Nat.mod(f, 10n)), 10n), Nat.mul(6n, Nat.div(f, 10n))), _)
  add_le_add(Nat.div(Nat.mul(6n, Nat.mod(f, 10n)), 10n), Nat.mod(f, 10n), Nat.mul(6n, Nat.div(f, 10n)), Nat.mul(Nat.div(f, 10n), 10n),
    small_le(Nat.mod(f, 10n), L.mod_le(f, 9n)),
    six_le_ten(Nat.div(f, 10n)))

def Laws.fee_split_conserves(f):
  L.sub_add(f, N.nsm_contribution_n(f), Laws.contribution_le(f))

# --- reissuance --------------------------------------------------------------

# Division is monotone: x <= y implies x div M <= y div M.
law div_mono:
  for +x: Nat
  for +y: Nat
  for +bp: Nat
  for l: L.Le(x, y)
  L.Le(Nat.div(x, 1n+bp), Nat.div(y, 1n+bp))

law div_mono_eq:
  for +x: Nat
  for +e: Nat
  for +bp: Nat
  {Nat.div(Nat.add(x, e), 1n+bp) == Nat.add(Nat.div(Nat.add(Nat.mod(x, 1n+bp), e), 1n+bp), Nat.div(x, 1n+bp)) : Nat}

def div_mono_eq(x, e, bp):
  %L.div_mod(x, bp) : {Nat.div(Nat.add(_, e), 1n+bp) == Nat.add(Nat.div(Nat.add(Nat.mod(x, 1n+bp), e), 1n+bp), Nat.div(x, 1n+bp)) : Nat}
  %L.add_right_comm(Nat.mod(x, 1n+bp), e, Nat.mul(Nat.div(x, 1n+bp), 1n+bp)) : {Nat.div(_, 1n+bp) == Nat.add(Nat.div(Nat.add(Nat.mod(x, 1n+bp), e), 1n+bp), Nat.div(x, 1n+bp)) : Nat}
  div_shift(Nat.add(Nat.mod(x, 1n+bp), e), Nat.div(x, 1n+bp), bp)

def div_mono(x, y, bp, l):
  (+e, he) = l
  %he : L.Le(Nat.div(x, 1n+bp), Nat.div(_, 1n+bp))
  %Equal.sym(Nat, Nat.div(Nat.add(x, e), 1n+bp), Nat.add(Nat.div(Nat.add(Nat.mod(x, 1n+bp), e), 1n+bp), Nat.div(x, 1n+bp)), div_mono_eq(x, e, bp)) : L.Le(Nat.div(x, 1n+bp), _)
  (Nat.div(Nat.add(Nat.mod(x, 1n+bp), e), 1n+bp), NL.add_comm(Nat.div(x, 1n+bp), Nat.div(Nat.add(Nat.mod(x, 1n+bp), e), 1n+bp)))

law reissue_top:
  for +dp: Nat
  for +bal: Nat
  {Nat.div(Nat.add(Nat.mul(1n+dp, bal), dp), 1n+dp) == bal : Nat}

def reissue_top(dp, bal):
  quot_uniq(dp, Nat.add(Nat.mul(1n+dp, bal), dp), dp, bal, le_refl(dp),
    Equal.trans(Nat, Nat.add(dp, Nat.mul(bal, 1n+dp)), Nat.add(Nat.mul(bal, 1n+dp), dp), Nat.add(Nat.mul(1n+dp, bal), dp),
      NL.add_comm(dp, Nat.mul(bal, 1n+dp)),
      Equal.cong(Nat, Nat, z => Nat.add(z, dp), Nat.mul(bal, 1n+dp), Nat.mul(1n+dp, bal), L.mul_comm(bal, 1n+dp))))

# c <= d implies c x <= d x.
law mul_mono_r:
  for +c: Nat
  for +d: Nat
  for +x: Nat
  for l: L.Le(c, d)
  L.Le(Nat.mul(c, x), Nat.mul(d, x))

def mul_mono_r(c, d, x, l):
  %L.mul_comm(x, c) : L.Le(_, Nat.mul(d, x))
  %L.mul_comm(x, d) : L.Le(Nat.mul(x, c), _)
  mul_mono_l(x, c, d, l)

law reissue_pre:
  for +c: Nat
  for +dp: Nat
  for +bal: Nat
  for l: L.Le(c, 1n+dp)
  L.Le(Nat.add(Nat.mul(c, bal), dp), Nat.add(Nat.mul(1n+dp, bal), dp))

def reissue_pre(c, dp, bal, l):
  %NL.add_comm(dp, Nat.mul(c, bal)) : L.Le(_, Nat.add(Nat.mul(1n+dp, bal), dp))
  %NL.add_comm(dp, Nat.mul(1n+dp, bal)) : L.Le(Nat.add(dp, Nat.mul(c, bal)), _)
  add_mono_l(dp, Nat.mul(c, bal), Nat.mul(1n+dp, bal), mul_mono_r(c, 1n+dp, bal, l))

def Laws.reissue_le(c, dp, bal, l):
  %reissue_top(dp, bal) : L.Le(N.reissue_n(c, dp, bal), _)
  div_mono(Nat.add(Nat.mul(c, bal), dp), Nat.add(Nat.mul(1n+dp, bal), dp), dp, reissue_pre(c, dp, bal, l))

# --- NSM conservation ----------------------------------------------------------

law swap3:
  for +x: Nat
  for +y: Nat
  for +c: Nat
  {Nat.add(x, Nat.add(y, c)) == Nat.add(Nat.add(c, x), y) : Nat}

def swap3(x, y, c):
  %NL.add_comm(c, y) : {Nat.add(x, _) == Nat.add(Nat.add(c, x), y) : Nat}
  %NL.add_comm(x, c) : {Nat.add(x, Nat.add(c, y)) == Nat.add(_, y) : Nat}
  %NL.add_assoc(x, c, y) : {_ == Nat.add(Nat.add(x, c), y) : Nat}
  {==}

def Laws.nsm_conserves(i, v, s, a, c, la, lc):
  +t = Nat.add(Nat.add(i, s), a)
  %Equal.sym(Nat, Nat.add(Nat.sub(t, c), Nat.add(Nat.sub(v, a), c)), Nat.add(Nat.add(c, Nat.sub(t, c)), Nat.sub(v, a)), swap3(Nat.sub(t, c), Nat.sub(v, a), c)) : {_ == Nat.add(Nat.add(i, v), s) : Nat}
  %Equal.sym(Nat, Nat.add(c, Nat.sub(t, c)), t, L.sub_add(t, c, lc)) : {Nat.add(_, Nat.sub(v, a)) == Nat.add(Nat.add(i, v), s) : Nat}
  %Equal.sym(Nat, Nat.add(Nat.add(Nat.add(i, s), a), Nat.sub(v, a)), Nat.add(Nat.add(i, s), Nat.add(a, Nat.sub(v, a))), NL.add_assoc(Nat.add(i, s), a, Nat.sub(v, a))) : {_ == Nat.add(Nat.add(i, v), s) : Nat}
  %Equal.sym(Nat, Nat.add(a, Nat.sub(v, a)), v, L.sub_add(v, a, la)) : {Nat.add(Nat.add(i, s), _) == Nat.add(Nat.add(i, v), s) : Nat}
  L.add_right_comm(i, s, v)

# ================================================================ difficulty laws
# (as proofs/difficulty/PROOF.bend, with the NU7 era)

def IsTrue(b: Bool) -> Type:
  match b:
    case False{}:
      Empty
    case True{}:
      Unit

def false_not_true(e: {False{} == True{} : Bool}) -> Empty:
  %Equal.sym(Bool, False{}, True{}, e) : IsTrue(_)
  Unit{}

def absurd(-A: Type, bot: Empty) -> A:
  match bot:

def succ(n: Nat) -> Nat:
  1n+n

def add0(n: Nat) -> {Nat.add(n, 0n) == n : Nat}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      Equal.cong(Nat, Nat, succ, Nat.add(p, 0n), p, add0(p))

def not_lt.step(-p: Nat, -q: Nat, r: &d: Nat -> {Nat.add(q, d) == p : Nat}) -> &d: Nat -> {Nat.add(1n+q, d) == 1n+p : Nat}:
  (d, pr) = r
  (d, Equal.cong(Nat, Nat, succ, Nat.add(q, d), p, pr))

def not_lt.go(x: Nat, +m: Nat) -> {Nat.is_lt(x, m) == False{} : Bool} -> &d: Nat -> {Nat.add(m, d) == x : Nat}:
  match x m:
    case 0n 0n:
      e => (0n, {==})
    case 0n 1n+q:
      e => absurd(&d: Nat -> {Nat.add(1n+q, d) == 0n : Nat}, false_not_true(Equal.sym(Bool, True{}, False{}, e)))
    case 1n+p 0n:
      e => (1n+p, {==})
    case 1n+p 1n+q:
      e => not_lt.step(p, q, not_lt.go(p, q, e))

def gap(e: E.Era) -> &k: Nat -> {Nat.add(E.MIN_TS(e), k) == E.MAX_TS(e) : Nat}:
  match e:
    case E.Pre{}:
      (1224n, {==})
    case E.Post{}:
      (612n, {==})
    case E.Nu7{}:
      (1224n, {==})

def ge.hi(+e: E.Era, +x: Nat, b: Bool) -> {Nat.is_lt(x, E.MIN_TS(e)) == False{} : Bool} -> {Nat.is_lt(E.MAX_TS(e), x) == b : Bool} -> &k: Nat -> {Nat.add(E.MIN_TS(e), k) == E.clamp.hi(e, b, x) : Nat}:
  match b:
    case True{}:
      lo => h => gap(e)
    case False{}:
      lo => h => not_lt.go(x, E.MIN_TS(e), lo)

def ge.lo(+e: E.Era, +x: Nat, b: Bool) -> {Nat.is_lt(x, E.MIN_TS(e)) == b : Bool} -> &k: Nat -> {Nat.add(E.MIN_TS(e), k) == E.clamp.lo(e, b, x) : Nat}:
  match b:
    case True{}:
      h => (0n, add0(E.MIN_TS(e)))
    case False{}:
      h => ge.hi(e, x, Nat.is_lt(E.MAX_TS(e), x), h, {==})

def le.hi(+e: E.Era, +x: Nat, b: Bool) -> {Nat.is_lt(E.MAX_TS(e), x) == b : Bool} -> &k: Nat -> {Nat.add(E.clamp.hi(e, b, x), k) == E.MAX_TS(e) : Nat}:
  match b:
    case True{}:
      h => (0n, add0(E.MAX_TS(e)))
    case False{}:
      h => not_lt.go(E.MAX_TS(e), x, h)

def le.lo(+e: E.Era, +x: Nat, b: Bool) -> {Nat.is_lt(x, E.MIN_TS(e)) == b : Bool} -> &k: Nat -> {Nat.add(E.clamp.lo(e, b, x), k) == E.MAX_TS(e) : Nat}:
  match b:
    case True{}:
      h => gap(e)
    case False{}:
      h => le.hi(e, x, Nat.is_lt(E.MAX_TS(e), x), {==})

def Laws.timespan_ge_min(e, neg, mag):
  +z = E.damp(e, neg, mag)
  ge.lo(e, z, Nat.is_lt(z, E.MIN_TS(e)), {==})

def Laws.timespan_le_max(e, neg, mag):
  +z = E.damp(e, neg, mag)
  le.lo(e, z, Nat.is_lt(z, E.MIN_TS(e)), {==})

def Laws.on_schedule(e):
  match e:
    case E.Pre{}:
      {==}
    case E.Post{}:
      {==}
    case E.Nu7{}:
      {==}

def Laws.nu7_window_wallclock():
  {==}

def agree.hi(b: Bool, x: Nat) -> {E.clamp.hi(E.Nu7{}, b, x) == E.clamp.hi(E.Pre{}, b, x) : Nat}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def agree.lo(b: Bool, +x: Nat) -> {E.clamp.lo(E.Nu7{}, b, x) == E.clamp.lo(E.Pre{}, b, x) : Nat}:
  match b:
    case True{}:
      {==}
    case False{}:
      agree.hi(Nat.is_lt(3366n, x), x)

def agree.clamp(+x: Nat) -> {E.clamp(E.Nu7{}, x) == E.clamp(E.Pre{}, x) : Nat}:
  agree.lo(Nat.is_lt(x, 2142n), x)

def agree.pos(b: Bool, +mag: Nat) -> {E.damp.pos(E.Nu7{}, b, mag) == E.damp.pos(E.Pre{}, b, mag) : Nat}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def agree.damp(neg: Bool, +mag: Nat) -> {E.damp(E.Nu7{}, neg, mag) == E.damp(E.Pre{}, neg, mag) : Nat}:
  match neg:
    case True{}:
      {==}
    case False{}:
      agree.pos(Nat.is_lt(mag, 2550n), mag)

def clamp_nu7(z: Nat) -> Nat:
  E.clamp(E.Nu7{}, z)

def Laws.nu7_timespan_is_pre(neg, mag):
  Equal.trans(Nat, E.timespan(E.Nu7{}, neg, mag), E.clamp(E.Nu7{}, E.damp(E.Pre{}, neg, mag)), E.timespan(E.Pre{}, neg, mag),
    Equal.cong(Nat, Nat, clamp_nu7, E.damp(E.Nu7{}, neg, mag), E.damp(E.Pre{}, neg, mag), agree.damp(neg, mag)),
    agree.clamp(E.damp(E.Pre{}, neg, mag)))
