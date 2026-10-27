# Signed-digit Pippenger MSM on Jubjub: sum_i [s_i] P_i, for affine (Niels) bases.
#
# Scalars (< 2^255) get signed c-bit digits in [-2^(c-1), 2^(c-1)] (recoding with carries,
# as research/perf3/lib_64/msm_ba.bend), so a window has 2^(c-1) buckets. Buckets are extended
# points held in a Bend Array; every term with a nonzero digit d is added (mixed Niels
# addition, 7M, complete) to bucket |d|, negated when d < 0. Buckets are reduced with
# running sums, and windows are combined by a balanced fork-join (parallel across CPU
# threads). Edwards addition is complete, so no special cases arise.
import Base
import ../../halo2/lib/words.bend as Wd
import ../jubjub/fr.bend as F
import ../jubjub/jubjub.bend as J

# --- signed digits ------------------------------------------------------------------

def wpick_n(+i: Nat, w: Wd.W) -> U32:
  match i w:
    case 0n Wd.W{w0, _, _, _, _, _, _, _}:
      w0
    case 1n Wd.W{_, w1, _, _, _, _, _, _}:
      w1
    case 2n Wd.W{_, _, w2, _, _, _, _, _}:
      w2
    case 3n Wd.W{_, _, _, w3, _, _, _, _}:
      w3
    case 4n Wd.W{_, _, _, _, w4, _, _, _}:
      w4
    case 5n Wd.W{_, _, _, _, _, w5, _, _}:
      w5
    case 6n Wd.W{_, _, _, _, _, _, w6, _}:
      w6
    case 7n Wd.W{_, _, _, _, _, _, _, w7}:
      w7
    case _ _:
      0

def wpick(+i: U32, +w: Wd.W) -> U32:
  wpick_n(U32.to_nat(i), w)

def hi_part(z: Bool, +v: U32, +sh: U32) -> U32:
  match z:
    case True{}:
      0
    case False{}:
      U32.shln(v, U32.to_nat((32 - sh : U32)))

# c bits of w starting at bit `off` (c <= 16).
def bits(+w: Wd.W, +off: U32, +c: U32) -> U32:
  +wi = (off >> 5n : U32)
  +sh = (off .&. 31 : U32)
  +lo = (wpick(wi, w) >> U32.to_nat(sh) : U32)
  +both = U32.or(lo, hi_part(U32.is_eq(sh, 0), wpick((wi + 1 : U32), w), sh))
  (both .&. ((1 << U32.to_nat(c) : U32) - 1 : U32) : U32)

type SD is Data:
  SD{m: U32, neg: U32}

def sd_b(b: Bool, +raw: U32, +c: U32) -> SD:
  match b:
    case True{}:
      SD{((1 << U32.to_nat(c) : U32) - raw : U32), 1}
    case False{}:
      SD{raw, 0}

def sd_step(+raw: U32, +c: U32) -> SD:
  sd_b(U32.is_gt(raw, (1 << U32.to_nat((c - 1 : U32)) : U32)), raw, c)

def sd_neg(sd: SD) -> U32:
  SD{_, neg} = sd
  neg

def recode(n: Nat, +w: Wd.W, +c: U32, +j: U32, +carry: U32) -> +List<SD>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      +raw = (bits(w, (j * c : U32), c) + carry : U32)
      +sd = sd_step(raw, c)
      sd <> recode(k, w, c, (j + 1 : U32), sd_neg(sd))

def windows(+c: U32) -> U32:
  ((((256 + c - 1 : U32) / c : U32) + 1) : U32)

def heads(ls: +List<+List<SD>>) -> +List<SD>:
  match ls:
    case Con{Con{h, _}, t}:
      h <> heads(t)
    case Con{Nil{}, t}:
      SD{0, 0} <> heads(t)
    case Nil{}:
      Nil{}

def tails(ls: +List<+List<SD>>) -> +List<+List<SD>>:
  match ls:
    case Con{Con{_, r}, t}:
      r <> tails(t)
    case Con{Nil{}, t}:
      Nil{} <> tails(t)
    case Nil{}:
      Nil{}

def transpose(n: Nat, +ls: +List<+List<SD>>) -> +List<+List<SD>>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      heads(ls) <> transpose(k, tails(ls))

def all_digits(ss: +List<Wd.W>, +nw: Nat, +c: U32) -> +List<+List<SD>>:
  match ss:
    case Con{+s, t}:
      recode(nw, s, c, 0, 0) <> all_digits(t, nw, c)
    case Nil{}:
      Nil{}

# --- buckets -----------------------------------------------------------------------

def empty(+d: Nat) -> Array<J.Pt>:
  match d:
    case 0n:
      ALeaf{J.identity()}
    case 1n+k:
      ANode{empty(k), empty(k)}

def arr_of(r: Array<J.Pt> & J.Pt) -> Array<J.Pt>:
  (a, _) = r
  a

def add_fin(n: J.Ni, r: Array<J.Pt> & J.Pt, +i: U32) -> Array<J.Pt>:
  (a, old) = r
  arr_of(Array.swap(J.Pt, a, i, J.add_ni(old, n)))

def neg_b(b: Bool, n: J.Ni) -> J.Ni:
  match b:
    case True{}:
      J.ni_neg(n)
    case False{}:
      n

def put_if(skip: Bool, a: Array<J.Pt>, +i: U32, n: J.Ni) -> Array<J.Pt>:
  match skip:
    case True{}:
      a
    case False{}:
      add_fin(n, Array.swap(J.Pt, a, i, J.identity()), i)

def put(+n: J.Ni, +sd: SD, a: Array<J.Pt>) -> Array<J.Pt>:
  SD{+m, +neg} = sd
  put_if(U32.is_eq(m, 0), a, (m - 1 : U32), neg_b(U32.is_eq(neg, 1), n))

def fill(ns: +List<J.Ni>, ds: +List<SD>, a: Array<J.Pt>) -> Array<J.Pt>:
  match ns ds:
    case Con{+n, nt} Con{+d, dt}:
      fill(nt, dt, put(n, d, a))
    case _ _:
      a

# Buckets in index order (digit 1 first).
def flat(a: Array<J.Pt>, out: +List<J.Pt>) -> +List<J.Pt>:
  match a:
    case ALeaf{x}:
      x <> out
    case ANode{lo, hi}:
      flat(lo, flat(hi, out))

type RS is Data:
  RS{run: J.Pt, acc: J.Pt}

# Buckets highest digit first: run = suffix sum, acc = sum_d d * B_d.
def reduce(bs: +List<J.Pt>, st: RS) -> RS:
  match bs:
    case Con{+b, t}:
      RS{+run, +acc} = st
      +r2 = J.add(run, b)
      reduce(t, RS{r2, J.add(acc, r2)})
    case Nil{}:
      st

def rs_acc(st: RS) -> J.Pt:
  RS{_, acc} = st
  acc

def window_sum(+c: U32, +ns: +List<J.Ni>, ds: +List<SD>) -> J.Pt:
  +bs = flat(fill(ns, ds, empty(U32.to_nat((c - 1 : U32)))), Nil{})
  rs_acc(reduce(List.reverse(&2, J.Pt, bs), RS{J.identity(), J.identity()}))

def dbl_n(n: Nat, p: J.Pt) -> J.Pt:
  match n:
    case 0n:
      p
    case 1n+k:
      dbl_n(k, J.double(p))

def take_w(k: Nat, xs: +List<+List<SD>>) -> +List<+List<SD>>:
  match k xs:
    case 1n+j Con{+h, t}:
      h <> take_w(j, t)
    case _ _:
      Nil{}

def drop_w(k: Nat, xs: +List<+List<SD>>) -> +List<+List<SD>>:
  match k xs:
    case 1n+j Con{_, t}:
      drop_w(j, t)
    case _ _:
      xs

def head_w(xs: +List<+List<SD>>) -> +List<SD>:
  match xs:
    case Con{+h, _}:
      h
    case Nil{}:
      Nil{}

# sum_t 2^(c t) S_t over `cnt` windows, split in halves and run in parallel.
def wrange(+fuel: Nat, one: Bool, +c: U32, +ns: +List<J.Ni>, +wins: +List<+List<SD>>, +cnt: U32) -> J.Pt:
  match fuel one:
    case 1n+f False{}:
      +h = (cnt >> 1n : U32)
      +h2 = (cnt - h : U32)
      +hn = U32.to_nat(h)
      a b = wrange(f, U32.is_lt(h, 2), c, ns, take_w(hn, wins), h) wrange(f, U32.is_lt(h2, 2), c, ns, drop_w(hn, wins), h2)
      J.add(a, dbl_n(U32.to_nat((h * c : U32)), b))
    case _ _:
      window_sum(c, ns, head_w(wins))

# sum_i [s_i] P_i (P_i in Niels form) with c-bit signed windows (c in 2..16).
def msm(+c: U32, +ns: +List<J.Ni>, +ss: +List<Wd.W>) -> J.Pt:
  +nw = windows(c)
  +wins = transpose(U32.to_nat(nw), all_digits(ss, U32.to_nat(nw), c))
  wrange(9n, False{}, c, ns, wins, nw)
