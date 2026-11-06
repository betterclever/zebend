import Base
import ../opt_gates/term.bend as T

# Copies of the batch inversions of the fast Halo 2 verifier over the Z/p model
# (p = 1 + bp, canonical Nats; Fp.mul is T.fmul, Fp.one() is 1n, Fp.zero() is 0n,
# Fp.inv(x) = x^(p-2) is T.finv, Fp.is_zero(x) is x == 0, and Fp.sel(Bool.to_u32(c), a, b)
# is "if c then a else b", as fp64.sel's comment says: 1 selects a, 0 selects b).
# Statement by statement and argument by argument the same as the code.

# --- crypto/field3/fp64.bend (and fq64.bend): batch_inv ------------------------------------

def bi_pre(+bp: Nat, xs: +List<Nat>, +acc: Nat) -> +List<Nat>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      +a = T.fmul(bp, acc, h)
      a <> bi_pre(bp, t, a)

def bi_back(+bp: Nat, rx: +List<Nat>, rp: +List<Nat>, +inv: Nat, out: +List<Nat>) -> +List<Nat>:
  match rx rp:
    case Con{+h, t} Con{+q, r}:
      bi_back(bp, t, r, T.fmul(bp, inv, h), T.fmul(bp, inv, q) <> out)
    case Con{_, _} Nil{}:
      inv <> out
    case Nil{} _:
      out

def bi_go(+bp: Nat, +xs: +List<Nat>, rps: +List<Nat>) -> +List<Nat>:
  match rps:
    case Con{+top, rest}:
      bi_back(bp, List.reverse(&2, Nat, xs), rest, T.finv(bp, top), Nil{})
    case Nil{}:
      Nil{}

def batch_inv(+bp: Nat, +xs: +List<Nat>) -> +List<Nat>:
  bi_go(bp, xs, List.reverse(&2, Nat, bi_pre(bp, xs, 1n)))

# --- research/perf4/v/vlib.bend: binvs (zeros masked around batch_inv) ----------------------

def nz1_b(z: Bool, +x: Nat) -> Nat:
  match z:
    case True{}:
      1n
    case False{}:
      x

def nz1(xs: +List<Nat>) -> +List<Nat>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      nz1_b(Nat.is_eq(x, 0n), x) <> nz1(t)

def z0_b(z: Bool, +i: Nat) -> Nat:
  match z:
    case True{}:
      0n
    case False{}:
      i

def z0(xs: +List<Nat>, ivs: +List<Nat>) -> +List<Nat>:
  match xs ivs:
    case Con{+x, xt} Con{+i, it}:
      z0_b(Nat.is_eq(x, 0n), i) <> z0(xt, it)
    case _ _:
      Nil{}

def binvs(+bp: Nat, +xs: +List<Nat>) -> +List<Nat>:
  z0(xs, batch_inv(bp, nz1(xs)))

# --- research/perf4/lib/msm_ba.bend: its own batch_inv --------------------------------------

def prefix(+bp: Nat, xs: +List<Nat>, +acc: Nat, out: +List<Nat>) -> +List<Nat>:
  match xs:
    case Con{x, t}:
      +c = T.fmul(bp, acc, x)
      prefix(bp, t, c, c <> out)
    case Nil{}:
      out

def back(+bp: Nat, rx: +List<Nat>, rc: +List<Nat>, +inv: Nat, out: +List<Nat>) -> +List<Nat>:
  match rx rc:
    case Con{+x, xt} Con{_, Con{+cprev, ct}}:
      back(bp, xt, cprev <> ct, T.fmul(bp, inv, x), T.fmul(bp, inv, cprev) <> out)
    case Con{_, _} Con{_, Nil{}}:
      inv <> out
    case _ _:
      out

def top_or_one(cs: +List<Nat>) -> Nat:
  match cs:
    case Con{c, _}:
      c
    case Nil{}:
      1n

def ba_batch_inv(+bp: Nat, +xs: +List<Nat>) -> +List<Nat>:
  +cs = prefix(bp, xs, 1n, Nil{})
  back(bp, List.reverse(&2, Nat, xs), cs, T.finv(bp, top_or_one(cs)), Nil{})

# --- the specification --------------------------------------------------------------------

# the product the code inverts: (..((1 x0) x1) ..) x(n-1)
def prod(+bp: Nat, xs: +List<Nat>, +acc: Nat) -> Nat:
  match xs:
    case Nil{}:
      acc
    case Con{+h, t}:
      prod(bp, t, T.fmul(bp, acc, h))

def finvs(+bp: Nat, xs: +List<Nat>) -> +List<Nat>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      T.finv(bp, h) <> finvs(bp, t)
