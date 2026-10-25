# Pippenger (bucket) multi-scalar multiplication on Pallas (copied from field3/lib64/msm_fast.bend; only the imports differ): sum_i [s_i] P_i.
#
# Scalars are cut into W = ceil(256 / c) windows of c bits. One task handles one
# (window, chunk of terms) pair: it drops each term's point into bucket d - 1 for its
# window digit d (d = 0 is skipped), then reduces the buckets with a running sum,
# which yields sum_d d * B_d. Chunks of the same window are summed, and windows are
# folded by a balanced tree that joins R_lo + 2^(h c) R_hi, so the whole MSM is a
# balanced fork-join of W x 2^cdepth tasks (`pip` on CPU threads, `pip_gpu` on the
# GPU). Additions use the complete formulas from vesta.bend, so identity bases,
# P + P and P + (-P) all behave.
#
#   +ct = MF.chunks(cdepth, n, points, scalars)   # build once (Data: reusable)
#   r   = MF.pip(c, cdepth, ct)                   # CPU threads; MF.pip_gpu on Metal
import Base
import ../halo2/lib/words.bend as Wd
import ../field3/lib64/pallas.bend as V

# --- scalar digits ---------------------------------------------------------------

def pick(i: Nat, a0: U32, a1: U32, a2: U32, a3: U32, a4: U32, a5: U32, a6: U32, a7: U32) -> U32:
  match i:
    case 0n:
      a0
    case 1n+k:
      pick(k, a1, a2, a3, a4, a5, a6, a7, 0)

def word(w: Wd.W, +i: Nat) -> U32:
  Wd.W{w0, w1, w2, w3, w4, w5, w6, w7} = w
  pick(i, w0, w1, w2, w3, w4, w5, w6, w7)

# Window: c bits starting at bit 32 * wi + sh (sh < 32, given as a Nat).
type Win is Data:
  Win{+wi: Nat, +sh: Nat, +mask: U32}

def digit_sh(+sh: Nat, +lo: U32, +hi: U32) -> U32:
  match sh:
    case 0n:
      lo
    case 1n+k:
      U32.or(U32.shrn(lo, sh), U32.shln(hi, Nat.sub(32n, sh)))

def digit(+s: Wd.W, +win: Win) -> U32:
  Win{+wi, +sh, +mask} = win
  (digit_sh(sh, word(s, wi), word(s, 1n+wi)) .&. mask : U32)

def win_of(+j: U32, +c: U32) -> Win:
  +off = (j * c : U32)
  Win{U32.to_nat((off >> 5n : U32)), U32.to_nat((off .&. 31 : U32)), ((1 << U32.to_nat(c) : U32) - 1 : U32)}

# --- buckets -----------------------------------------------------------------------

def buckets(+d: Nat) -> Array<V.Pt>:
  match d:
    case 0n:
      ALeaf{V.identity()}
    case 1n+k:
      ANode{buckets(k), buckets(k)}

def arr_of(r: Array<V.Pt> & V.Pt) -> Array<V.Pt>:
  (a, _) = r
  a

def put_fin(p: V.Pt, r: Array<V.Pt> & V.Pt, +i: U32) -> Array<V.Pt>:
  (a, old) = r
  arr_of(Array.swap(V.Pt, a, i, V.add(old, p)))

def put_if(z: Bool, a: Array<V.Pt>, +d: U32, p: V.Pt) -> Array<V.Pt>:
  match z:
    case True{}:
      a
    case False{}:
      +i = (d - 1 : U32)
      put_fin(p, Array.swap(V.Pt, a, i, V.identity()), i)

def fill(ps: +List<V.Pt>, ss: +List<Wd.W>, +win: Win, a: Array<V.Pt>) -> Array<V.Pt>:
  match ps ss:
    case Con{p, pt} Con{s, st}:
      +d = digit(s, win)
      fill(pt, st, win, put_if(U32.is_eq(d, 0), a, d, p))
    case _ _:
      a

type RS is Data:
  RS{run: V.Pt, acc: V.Pt}

# Bucket i holds digit i + 1. Walking from the top index down, `run` is the suffix sum
# and `acc` collects every suffix sum: acc = sum_i (i + 1) * B_i.
def reduce(a: Array<V.Pt>, st: RS) -> RS:
  match a:
    case ALeaf{x}:
      RS{run, acc} = st
      +r2 = V.add(run, x)
      RS{r2, V.add(acc, r2)}
    case ANode{xs, ys}:
      reduce(xs, reduce(ys, st))

def rs_acc(st: RS) -> V.Pt:
  RS{_, acc} = st
  acc

def task(+cd: Nat, ps: +List<V.Pt>, ss: +List<Wd.W>, +win: Win) -> V.Pt:
  rs_acc(reduce(fill(ps, ss, win, buckets(cd)), RS{V.identity(), V.identity()}))

# --- chunks of terms -----------------------------------------------------------------

type CT is Data:
  CLeaf{ps: +List<V.Pt>, ss: +List<Wd.W>}
  CNode{l: CT, r: CT}

def take_p(k: Nat, xs: +List<V.Pt>) -> +List<V.Pt>:
  match k xs:
    case 1n+j Con{h, t}:
      h <> take_p(j, t)
    case _ _:
      Nil{}

def take_s(k: Nat, xs: +List<Wd.W>) -> +List<Wd.W>:
  match k xs:
    case 1n+j Con{h, t}:
      h <> take_s(j, t)
    case _ _:
      Nil{}

def drop_p(k: Nat, xs: +List<V.Pt>) -> +List<V.Pt>:
  match k xs:
    case 1n+j Con{_, t}:
      drop_p(j, t)
    case _ _:
      xs

def drop_s(k: Nat, xs: +List<Wd.W>) -> +List<Wd.W>:
  match k xs:
    case 1n+j Con{_, t}:
      drop_s(j, t)
    case _ _:
      xs

# 2^d leaves of about n / 2^d terms each.
def chunks(+d: Nat, +n: U32, +ps: +List<V.Pt>, +ss: +List<Wd.W>) -> CT:
  match d:
    case 0n:
      CLeaf{ps, ss}
    case 1n+k:
      +h = (n >> 1n : U32)
      +hn = U32.to_nat(h)
      CNode{chunks(k, h, take_p(hn, ps), take_s(hn, ss)), chunks(k, (n - h : U32), drop_p(hn, ps), drop_s(hn, ss))}

# --- the fork-join -----------------------------------------------------------------

# S_j: one window over every chunk.
def wsum(+k: Nat, +cd: Nat, +ct: CT, +win: Win) -> V.Pt:
  match k ct:
    case _ CLeaf{ps, ss}:
      task(cd, ps, ss, win)
    case 1n+j CNode{l, r}:
      a b = wsum(j, cd, l, win) wsum(j, cd, r, win)
      V.add(a, b)
    case _ _:
      V.identity()

def dbl_n(n: Nat, p: V.Pt) -> V.Pt:
  match n:
    case 0n:
      p
    case 1n+k:
      dbl_n(k, V.double(p))

# sum_{t < cnt} 2^(t c) S_(lo + t), splitting the window range in half.
# `one` is cnt < 2 (passed in, since a match needs a parameter).
def wrange(+fuel: Nat, one: Bool, +k: Nat, +cd: Nat, +ct: CT, +c: U32, +lo: U32, +cnt: U32) -> V.Pt:
  match fuel one:
    case 1n+f False{}:
      +h = (cnt >> 1n : U32)
      +h2 = (cnt - h : U32)
      a b = wrange(f, U32.is_lt(h, 2), k, cd, ct, c, lo, h) wrange(f, U32.is_lt(h2, 2), k, cd, ct, c, (lo + h : U32), h2)
      V.add(a, dbl_n(U32.to_nat((h * c : U32)), b))
    case _ _:
      wsum(k, cd, ct, win_of(lo, c))

def windows(+c: U32) -> U32:
  ((256 + c - 1 : U32) / c : U32)

# c: window bits (bucket count 2^c); cdepth: log2 of the number of term chunks.
def pip(+c: U32, +cdepth: Nat, +ct: CT) -> V.Pt:
  wrange(9n, False{}, cdepth, U32.to_nat(c), ct, c, 0, windows(c))

def pip_gpu(+c: U32, +cdepth: Nat, +ct: CT) -> V.Pt:
  wrange!(9n, False{}, cdepth, U32.to_nat(c), ct, c, 0, windows(c))
