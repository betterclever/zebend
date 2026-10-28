import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L

# Expressions of the generated verifier's field arithmetic, their meaning in Z/p, and a
# normaliser `nf` that applies exactly the value-preserving rewrites of opt_gates.py.
#
#   A{i}      an atom: a parameter, a list read L.bfat(n, xs), or the result of any call
#             that is not field arithmetic (transcript, points, ...), numbered per function
#   K{i}      the constant K<i>(); K0() is the field's one and K1() its zero (opt_gates.py
#             asserts both); every other constant is left symbolic
#   Ad Sb Ml  L.badd, L.bsub, L.bmul
#   Ng Iv     L.bneg, L.binv
#
# The model: Z/p with p = 1 + bp, bp >= 1 (so 1 is canonical). Every value is a canonical
# Nat (< p): atoms and the symbolic constants are taken mod p.

type T is Data:
  A{i: Nat}
  K{i: Nat}
  Ad{a: T, b: T}
  Sb{a: T, b: T}
  Ml{a: T, b: T}
  Ng{a: T}
  Iv{a: T}

# --- the field model -----------------------------------------------------------------

def fadd(+bp: Nat, x: Nat, y: Nat) -> Nat:
  Nat.mod(Nat.add(x, y), 1n+bp)

def fsub(+bp: Nat, x: Nat, y: Nat) -> Nat:
  Nat.mod(Nat.add(x, Nat.sub(1n+bp, y)), 1n+bp)

def fmul(+bp: Nat, x: Nat, y: Nat) -> Nat:
  Nat.mod(Nat.mul(x, y), 1n+bp)

def fneg(+bp: Nat, y: Nat) -> Nat:
  Nat.mod(Nat.sub(1n+bp, y), 1n+bp)

# Fp.inv(x) = x^(p-2). Only congruence is used: no rewrite rule touches an inversion.
def finv(+bp: Nat, +x: Nat) -> Nat:
  Nat.mod(Nat.pow(x, Nat.sub(bp, 1n)), 1n+bp)

def nth(xs: +List<Nat>, i: Nat) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{+h, t}:
      match i:
        case 0n:
          h
        case 1n+j:
          nth(t, j)

# K0 = 1, K1 = 0, K<2+k> = cs[k] mod p (arbitrary).
def kv(+bp: Nat, +cs: +List<Nat>, i: Nat) -> Nat:
  match i:
    case 0n:
      1n
    case 1n+j:
      match j:
        case 0n:
          0n
        case 1n+k:
          Nat.mod(nth(cs, k), 1n+bp)

def ev(+bp: Nat, +env: +List<Nat>, +cs: +List<Nat>, t: T) -> Nat:
  match t:
    case A{i}:
      Nat.mod(nth(env, i), 1n+bp)
    case K{i}:
      kv(bp, cs, i)
    case Ad{a, b}:
      fadd(bp, ev(bp, env, cs, a), ev(bp, env, cs, b))
    case Sb{a, b}:
      fsub(bp, ev(bp, env, cs, a), ev(bp, env, cs, b))
    case Ml{a, b}:
      fmul(bp, ev(bp, env, cs, a), ev(bp, env, cs, b))
    case Ng{a}:
      fneg(bp, ev(bp, env, cs, a))
    case Iv{a}:
      finv(bp, ev(bp, env, cs, a))

def evs(+bp: Nat, +env: +List<Nat>, +cs: +List<Nat>, ts: +List<T>) -> +List<Nat>:
  match ts:
    case Nil{}:
      Nil{}
    case Con{+t, rest}:
      ev(bp, env, cs, t) <> evs(bp, env, cs, rest)

# --- a structural order (any total order works; only nf's determinism matters) -------

def tag(+t: T) -> Nat:
  match t:
    case A{i}:
      0n
    case K{i}:
      1n
    case Ad{a, b}:
      2n
    case Sb{a, b}:
      3n
    case Ml{a, b}:
      4n
    case Ng{a}:
      5n
    case Iv{a}:
      6n

def teq(+a: T, +b: T) -> Bool:
  match a b:
    case A{i} A{j}:
      Nat.is_eq(i, j)
    case K{i} K{j}:
      Nat.is_eq(i, j)
    case Ad{a1, a2} Ad{b1, b2}:
      teq(a1, b1) && teq(a2, b2)
    case Sb{a1, a2} Sb{b1, b2}:
      teq(a1, b1) && teq(a2, b2)
    case Ml{a1, a2} Ml{b1, b2}:
      teq(a1, b1) && teq(a2, b2)
    case Ng{a1} Ng{b1}:
      teq(a1, b1)
    case Iv{a1} Iv{b1}:
      teq(a1, b1)
    case _ _:
      False{}

def lex(c1: Bool, e1: Bool, c2: Bool) -> Bool:
  match c1:
    case True{}:
      True{}
    case False{}:
      e1 && c2

def tlt(+a: T, +b: T) -> Bool:
  match a b:
    case A{i} A{j}:
      Nat.is_lt(i, j)
    case K{i} K{j}:
      Nat.is_lt(i, j)
    case Ad{a1, a2} Ad{b1, b2}:
      lex(tlt(a1, b1), teq(a1, b1), tlt(a2, b2))
    case Sb{a1, a2} Sb{b1, b2}:
      lex(tlt(a1, b1), teq(a1, b1), tlt(a2, b2))
    case Ml{a1, a2} Ml{b1, b2}:
      lex(tlt(a1, b1), teq(a1, b1), tlt(a2, b2))
    case Ng{a1} Ng{b1}:
      tlt(a1, b1)
    case Iv{a1} Iv{b1}:
      tlt(a1, b1)
    case _ _:
      Nat.is_lt(tag(a), tag(b))

# --- smart constructors: the rewrite rules -------------------------------------------

# Rule -0 = 0.
def ng_k(+i: Nat) -> T:
  match i:
    case 0n:
      Ng{K{0n}}
    case 1n+j:
      match j:
        case 0n:
          K{1n}
        case 1n+k:
          Ng{K{2n+k}}

def mk_ng(+a: T) -> T:
  match a:
    case K{+i}:
      ng_k(i)
    case _:
      Ng{a}

# Rule x - 0 = x.
def sb_k(+a: T, +i: Nat) -> T:
  match i:
    case 0n:
      Sb{a, K{0n}}
    case 1n+j:
      match j:
        case 0n:
          a
        case 1n+k:
          Sb{a, K{2n+k}}

def mk_sb(+a: T, +b: T) -> T:
  match b:
    case K{+i}:
      sb_k(a, i)
    case _:
      Sb{a, b}

# Commutativity: the smaller operand first.
def ord_ad(c: Bool, +a: T, +b: T) -> T:
  match c:
    case True{}:
      Ad{b, a}
    case False{}:
      Ad{a, b}

def ord_ml(c: Bool, +a: T, +b: T) -> T:
  match c:
    case True{}:
      Ml{b, a}
    case False{}:
      Ml{a, b}

# Rules x + 0 = x, 0 + x = x (after the negation rules, as opt_gates.py orders them).
def ad_kb(+a: T, +i: Nat) -> T:
  match i:
    case 0n:
      ord_ad(tlt(K{0n}, a), a, K{0n})
    case 1n+j:
      match j:
        case 0n:
          a
        case 1n+k:
          ord_ad(tlt(K{2n+k}, a), a, K{2n+k})

def ad_fb(+a: T, +b: T) -> T:
  match b:
    case K{+i}:
      ad_kb(a, i)
    case _:
      ord_ad(tlt(b, a), a, b)

def ad_ka(+i: Nat, +b: T) -> T:
  match i:
    case 0n:
      ad_fb(K{0n}, b)
    case 1n+j:
      match j:
        case 0n:
          b
        case 1n+k:
          ad_fb(K{2n+k}, b)

def ad_f(+a: T, +b: T) -> T:
  match a:
    case K{+i}:
      ad_ka(i, b)
    case _:
      ad_fb(a, b)

# Rules a + (-c) = a - c, then (-c) + b = b - c.
def ad_a(+a: T, +b: T) -> T:
  match a:
    case Ng{+c}:
      mk_sb(b, c)
    case _:
      ad_f(a, b)

def mk_ad(+a: T, +b: T) -> T:
  match b:
    case Ng{+c}:
      mk_sb(a, c)
    case _:
      ad_a(a, b)

# Rules x * 1 = x, 1 * x = x, x * 0 = 0, 0 * x = 0.
def ml_kb(+a: T, +i: Nat) -> T:
  match i:
    case 0n:
      a
    case 1n+j:
      match j:
        case 0n:
          K{1n}
        case 1n+k:
          ord_ml(tlt(K{2n+k}, a), a, K{2n+k})

def ml_b(+a: T, +b: T) -> T:
  match b:
    case K{+i}:
      ml_kb(a, i)
    case _:
      ord_ml(tlt(b, a), a, b)

def ml_ka(+i: Nat, +b: T) -> T:
  match i:
    case 0n:
      b
    case 1n+j:
      match j:
        case 0n:
          K{1n}
        case 1n+k:
          ml_b(K{2n+k}, b)

def mk_ml(+a: T, +b: T) -> T:
  match a:
    case K{+i}:
      ml_ka(i, b)
    case _:
      ml_b(a, b)

def nf(t: T) -> T:
  match t:
    case A{i}:
      A{i}
    case K{i}:
      K{i}
    case Ad{a, b}:
      mk_ad(nf(a), nf(b))
    case Sb{a, b}:
      mk_sb(nf(a), nf(b))
    case Ml{a, b}:
      mk_ml(nf(a), nf(b))
    case Ng{a}:
      mk_ng(nf(a))
    case Iv{a}:
      Iv{nf(a)}

def nfs(ts: +List<T>) -> +List<T>:
  match ts:
    case Nil{}:
      Nil{}
    case Con{+t, rest}:
      nf(t) <> nfs(rest)
