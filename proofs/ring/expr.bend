import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L
import ../opt_gates/term.bend as T

# Ring expressions, their meaning in Z/p, and their meaning as Nat polynomials.
#
# Z/p is the model of every other proof directory: p = 1 + bp, elements are canonical Nats
# (<= bp), and T.fadd / T.fsub / T.fmul / T.fneg (opt_gates/term.bend) are + - * and
# negation mod p. Nothing here assumes p prime.
#
#   V{i}   the i-th variable (env[i]); every law takes its variables canonical
#   C{n}   the constant n mod p
#   Pp{}   the Nat bp = p - 1, i.e. -1 in Z/p; it appears only in certificates
#
# nv reads an expression as a Nat polynomial in which subtraction is replaced by
# multiplication by bp: x - y  ~>  x + bp*y, which is congruent to x - y mod p. So the
# value in Z/p is always nv mod p (ev_nv below), and identities in Z/p reduce to
# identities between Nat polynomials (cert.bend).

type E is Data:
  V{i: Nat}
  C{n: Nat}
  Pp{}
  Ad{a: E, b: E}
  Sb{a: E, b: E}
  Ml{a: E, b: E}
  Ng{a: E}

def ev(+bp: Nat, +env: +List<Nat>, t: E) -> Nat:
  match t:
    case V{i}:
      T.nth(env, i)
    case C{n}:
      Nat.mod(n, 1n+bp)
    case Pp{}:
      bp
    case Ad{a, b}:
      T.fadd(bp, ev(bp, env, a), ev(bp, env, b))
    case Sb{a, b}:
      T.fsub(bp, ev(bp, env, a), ev(bp, env, b))
    case Ml{a, b}:
      T.fmul(bp, ev(bp, env, a), ev(bp, env, b))
    case Ng{a}:
      T.fneg(bp, ev(bp, env, a))

def nv(+bp: Nat, +env: +List<Nat>, t: E) -> Nat:
  match t:
    case V{i}:
      T.nth(env, i)
    case C{n}:
      n
    case Pp{}:
      bp
    case Ad{a, b}:
      Nat.add(nv(bp, env, a), nv(bp, env, b))
    case Sb{a, b}:
      Nat.add(nv(bp, env, a), Nat.mul(bp, nv(bp, env, b)))
    case Ml{a, b}:
      Nat.mul(nv(bp, env, a), nv(bp, env, b))
    case Ng{a}:
      Nat.mul(bp, nv(bp, env, a))

# Every element of env is canonical.
def Canon(+bp: Nat, xs: +List<Nat>) -> Data:
  match xs:
    case Nil{}:
      Unit
    case Con{+h, t}:
      Sigma<&2, &2, L.Le(h, bp), _ => Canon(bp, t)>

def nth_le(+bp: Nat, +xs: +List<Nat>, +hc: Canon(bp, xs), +i: Nat) -> L.Le(T.nth(xs, i), bp):
  match xs:
    case Nil{}:
      (bp, {==})
    case Con{+h, t}:
      (+lh, +lt) = hc
      match i:
        case 0n:
          lh
        case 1n+j:
          nth_le(bp, t, lt, j)

# --- the congruences ------------------------------------------------------------------

def mod_zero(+bp: Nat) -> {Nat.mod(0n, 1n+bp) == 0n : Nat}:
  L.mod_small(0n, bp, (bp, {==}))

def le_succ(+r: Nat, +bp: Nat, l: L.Le(r, bp)) -> L.Le(r, 1n+bp):
  (+e, he) = l
  (1n+e, Equal.trans(Nat, Nat.add(r, 1n+e), 1n+Nat.add(r, e), 1n+bp, N.add_succ_r(r, e), Equal.cong(Nat, Nat, w => 1n+w, Nat.add(r, e), bp, he)))

# (p - r) + (r + r*bp) == bp*r + p, for r <= bp
def e2(+bp: Nat, +r: Nat, l: L.Le(r, bp)) -> {Nat.add(Nat.sub(1n+bp, r), Nat.add(r, Nat.mul(r, bp))) == Nat.add(Nat.mul(bp, r), 1n+bp) : Nat}:
  %N.add_assoc(Nat.sub(1n+bp, r), r, Nat.mul(r, bp)) : {_ == Nat.add(Nat.mul(bp, r), 1n+bp) : Nat}
  %Equal.sym(Nat, Nat.add(Nat.sub(1n+bp, r), r), 1n+bp, Equal.trans(Nat, Nat.add(Nat.sub(1n+bp, r), r), Nat.add(r, Nat.sub(1n+bp, r)), 1n+bp, N.add_comm(Nat.sub(1n+bp, r), r), L.sub_add(1n+bp, r, le_succ(r, bp, l)))) : {Nat.add(_, Nat.mul(r, bp)) == Nat.add(Nat.mul(bp, r), 1n+bp) : Nat}
  Equal.trans(Nat, Nat.add(1n+bp, Nat.mul(r, bp)), Nat.add(Nat.mul(r, bp), 1n+bp), Nat.add(Nat.mul(bp, r), 1n+bp), N.add_comm(1n+bp, Nat.mul(r, bp)), Equal.cong(Nat, Nat, w => Nat.add(w, 1n+bp), Nat.mul(r, bp), Nat.mul(bp, r), L.mul_comm(r, bp)))

# (p - r) mod p == (bp * r) mod p, for r <= bp
def negr(+bp: Nat, +r: Nat, l: L.Le(r, bp)) -> {Nat.mod(Nat.sub(1n+bp, r), 1n+bp) == Nat.mod(Nat.mul(bp, r), 1n+bp) : Nat}:
  Equal.trans(Nat, Nat.mod(Nat.sub(1n+bp, r), 1n+bp), Nat.mod(Nat.add(Nat.sub(1n+bp, r), Nat.mul(r, 1n+bp)), 1n+bp), Nat.mod(Nat.mul(bp, r), 1n+bp),
    Equal.sym(Nat, Nat.mod(Nat.add(Nat.sub(1n+bp, r), Nat.mul(r, 1n+bp)), 1n+bp), Nat.mod(Nat.sub(1n+bp, r), 1n+bp), L.mod_add_mul(Nat.sub(1n+bp, r), r, bp)),
  Equal.trans(Nat, Nat.mod(Nat.add(Nat.sub(1n+bp, r), Nat.mul(r, 1n+bp)), 1n+bp), Nat.mod(Nat.add(Nat.mul(bp, r), 1n+bp), 1n+bp), Nat.mod(Nat.mul(bp, r), 1n+bp),
    Equal.cong(Nat, Nat, w => Nat.mod(w, 1n+bp), Nat.add(Nat.sub(1n+bp, r), Nat.mul(r, 1n+bp)), Nat.add(Nat.mul(bp, r), 1n+bp),
      Equal.trans(Nat, Nat.add(Nat.sub(1n+bp, r), Nat.mul(r, 1n+bp)), Nat.add(Nat.sub(1n+bp, r), Nat.add(r, Nat.mul(r, bp))), Nat.add(Nat.mul(bp, r), 1n+bp),
        Equal.cong(Nat, Nat, w => Nat.add(Nat.sub(1n+bp, r), w), Nat.mul(r, 1n+bp), Nat.add(r, Nat.mul(r, bp)), L.mul_succ_r(r, bp)),
        e2(bp, r, l))),
    L.mod_add_self(Nat.mul(bp, r), bp)))

# (p - (x mod p)) mod p == (bp * x) mod p
def negc(+bp: Nat, +x: Nat) -> {Nat.mod(Nat.sub(1n+bp, Nat.mod(x, 1n+bp)), 1n+bp) == Nat.mod(Nat.mul(bp, x), 1n+bp) : Nat}:
  Equal.trans(Nat, Nat.mod(Nat.sub(1n+bp, Nat.mod(x, 1n+bp)), 1n+bp), Nat.mod(Nat.mul(bp, Nat.mod(x, 1n+bp)), 1n+bp), Nat.mod(Nat.mul(bp, x), 1n+bp), negr(bp, Nat.mod(x, 1n+bp), L.mod_le(x, bp)), L.mod_mul_mod_r(bp, x, bp))

# (x mod p) - (y mod p) == (x + bp*y) mod p
def sub_c(+bp: Nat, +x: Nat, +y: Nat) -> {T.fsub(bp, Nat.mod(x, 1n+bp), Nat.mod(y, 1n+bp)) == Nat.mod(Nat.add(x, Nat.mul(bp, y)), 1n+bp) : Nat}:
  +s = Nat.sub(1n+bp, Nat.mod(y, 1n+bp))
  Equal.trans(Nat, Nat.mod(Nat.add(Nat.mod(x, 1n+bp), s), 1n+bp), Nat.mod(Nat.add(x, s), 1n+bp), Nat.mod(Nat.add(x, Nat.mul(bp, y)), 1n+bp), L.mod_add_mod_l(x, s, bp),
  Equal.trans(Nat, Nat.mod(Nat.add(x, s), 1n+bp), Nat.mod(Nat.add(x, Nat.mod(s, 1n+bp)), 1n+bp), Nat.mod(Nat.add(x, Nat.mul(bp, y)), 1n+bp), Equal.sym(Nat, Nat.mod(Nat.add(x, Nat.mod(s, 1n+bp)), 1n+bp), Nat.mod(Nat.add(x, s), 1n+bp), L.mod_add_mod_r(x, s, bp)),
  Equal.trans(Nat, Nat.mod(Nat.add(x, Nat.mod(s, 1n+bp)), 1n+bp), Nat.mod(Nat.add(x, Nat.mod(Nat.mul(bp, y), 1n+bp)), 1n+bp), Nat.mod(Nat.add(x, Nat.mul(bp, y)), 1n+bp), Equal.cong(Nat, Nat, w => Nat.mod(Nat.add(x, w), 1n+bp), Nat.mod(s, 1n+bp), Nat.mod(Nat.mul(bp, y), 1n+bp), negc(bp, y)), L.mod_add_mod_r(x, Nat.mul(bp, y), bp))))

# --- the value in Z/p is the Nat polynomial mod p ------------------------------------------

def ev_nv(+bp: Nat, +env: +List<Nat>, +hc: Canon(bp, env), t: E) -> {ev(bp, env, t) == Nat.mod(nv(bp, env, t), 1n+bp) : Nat}:
  match t:
    case V{+i}:
      Equal.sym(Nat, Nat.mod(T.nth(env, i), 1n+bp), T.nth(env, i), L.mod_small(T.nth(env, i), bp, nth_le(bp, env, hc, i)))
    case C{n}:
      {==}
    case Pp{}:
      Equal.sym(Nat, Nat.mod(bp, 1n+bp), bp, L.mod_small(bp, bp, (0n, N.add_zero_r(bp))))
    case Ad{+a, +b}:
      %Equal.sym(Nat, ev(bp, env, a), Nat.mod(nv(bp, env, a), 1n+bp), ev_nv(bp, env, hc, a)) : {T.fadd(bp, _, ev(bp, env, b)) == Nat.mod(Nat.add(nv(bp, env, a), nv(bp, env, b)), 1n+bp) : Nat}
      %Equal.sym(Nat, ev(bp, env, b), Nat.mod(nv(bp, env, b), 1n+bp), ev_nv(bp, env, hc, b)) : {T.fadd(bp, Nat.mod(nv(bp, env, a), 1n+bp), _) == Nat.mod(Nat.add(nv(bp, env, a), nv(bp, env, b)), 1n+bp) : Nat}
      Equal.trans(Nat, Nat.mod(Nat.add(Nat.mod(nv(bp, env, a), 1n+bp), Nat.mod(nv(bp, env, b), 1n+bp)), 1n+bp), Nat.mod(Nat.add(nv(bp, env, a), Nat.mod(nv(bp, env, b), 1n+bp)), 1n+bp), Nat.mod(Nat.add(nv(bp, env, a), nv(bp, env, b)), 1n+bp), L.mod_add_mod_l(nv(bp, env, a), Nat.mod(nv(bp, env, b), 1n+bp), bp), L.mod_add_mod_r(nv(bp, env, a), nv(bp, env, b), bp))
    case Ml{+a, +b}:
      %Equal.sym(Nat, ev(bp, env, a), Nat.mod(nv(bp, env, a), 1n+bp), ev_nv(bp, env, hc, a)) : {T.fmul(bp, _, ev(bp, env, b)) == Nat.mod(Nat.mul(nv(bp, env, a), nv(bp, env, b)), 1n+bp) : Nat}
      %Equal.sym(Nat, ev(bp, env, b), Nat.mod(nv(bp, env, b), 1n+bp), ev_nv(bp, env, hc, b)) : {T.fmul(bp, Nat.mod(nv(bp, env, a), 1n+bp), _) == Nat.mod(Nat.mul(nv(bp, env, a), nv(bp, env, b)), 1n+bp) : Nat}
      Equal.trans(Nat, Nat.mod(Nat.mul(Nat.mod(nv(bp, env, a), 1n+bp), Nat.mod(nv(bp, env, b), 1n+bp)), 1n+bp), Nat.mod(Nat.mul(nv(bp, env, a), Nat.mod(nv(bp, env, b), 1n+bp)), 1n+bp), Nat.mod(Nat.mul(nv(bp, env, a), nv(bp, env, b)), 1n+bp), L.mod_mul_mod_l(nv(bp, env, a), Nat.mod(nv(bp, env, b), 1n+bp), bp), L.mod_mul_mod_r(nv(bp, env, a), nv(bp, env, b), bp))
    case Sb{+a, +b}:
      %Equal.sym(Nat, ev(bp, env, a), Nat.mod(nv(bp, env, a), 1n+bp), ev_nv(bp, env, hc, a)) : {T.fsub(bp, _, ev(bp, env, b)) == Nat.mod(Nat.add(nv(bp, env, a), Nat.mul(bp, nv(bp, env, b))), 1n+bp) : Nat}
      %Equal.sym(Nat, ev(bp, env, b), Nat.mod(nv(bp, env, b), 1n+bp), ev_nv(bp, env, hc, b)) : {T.fsub(bp, Nat.mod(nv(bp, env, a), 1n+bp), _) == Nat.mod(Nat.add(nv(bp, env, a), Nat.mul(bp, nv(bp, env, b))), 1n+bp) : Nat}
      sub_c(bp, nv(bp, env, a), nv(bp, env, b))
    case Ng{+a}:
      %Equal.sym(Nat, ev(bp, env, a), Nat.mod(nv(bp, env, a), 1n+bp), ev_nv(bp, env, hc, a)) : {T.fneg(bp, _) == Nat.mod(Nat.mul(bp, nv(bp, env, a)), 1n+bp) : Nat}
      negc(bp, nv(bp, env, a))
