# Fixed-base scalar multiplication with precomputed comb tables (Vesta).
#
# For a base P and window width c, window j holds the affine multiples d * 2^(c j) * P for
# d = 1 .. 2^(c-1), as a complete binary tree. A canonical scalar is recoded into signed c-bit
# digits (msm_ba.recode: |digit| <= 2^(c-1)); [s] P is then one mixed addition per non-zero
# digit, with no doublings. Sums of several fixed-base products share one accumulator.
#
# Exactness: every table entry is a non-identity point (d 2^(c j) is never a multiple of the
# prime group order), and V.add_aff (RCB Algorithm 8) is complete for any accumulator and a
# non-identity affine addend, so the result is the same group element as V.scalar_mul.
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ../../../crypto/field3/fq64.bend as B
import ../../../crypto/field3/lib64/vesta.bend as V
import ./vesta_lz.bend as VL
import ./msm_ba.bend as BA
import ./gtab.bend as GT

type T is Data:
  TL{a: BA.AP}
  TN{l: T, r: T}

# one table per base: windows least significant first
type Tab is Data:
  Tab{ws: +List<T>}

def head_ap(xs: +List<BA.AP>) -> BA.AP:
  match xs:
    case Con{+h, _}:
      h
    case Nil{}:
      BA.ANone{}

def pow2(n: Nat) -> Nat:
  match n:
    case 0n:
      1n
    case 1n+k:
      Nat.mul(2n, pow2(k))

def tbuild(+d: Nat, +xs: +List<BA.AP>) -> T:
  match d:
    case 0n:
      TL{head_ap(xs)}
    case 1n+k:
      +h = pow2(k)
      TN{tbuild(k, List.take(&2, BA.AP, xs, h)), tbuild(k, List.drop(&2, BA.AP, xs, h))}

def child(lo: Bool, +l: T, +r: T) -> T:
  match lo:
    case True{}:
      l
    case False{}:
      r

# entry i (0-based) of a depth-d tree, most significant index bit first
def tget(+d: Nat, +i: U32, +t: T) -> BA.AP:
  match d t:
    case _ TL{+a}:
      a
    case 1n+k TN{+l, +r}:
      tget(k, i, child(U32.is_eq((U32.shrn(i, k) .&. 1 : U32), 0), l, r))
    case _ _:
      BA.ANone{}

# [P, 2P, ..., mP] (projective)
def mults(m: Nat, +p: V.Pt, +acc: V.Pt) -> +List<V.Pt>:
  match m:
    case 0n:
      Nil{}
    case 1n+k:
      acc <> mults(k, p, VL.add(acc, p))

def dbl_n(n: Nat, +p: V.Pt) -> V.Pt:
  match n:
    case 0n:
      p
    case 1n+k:
      dbl_n(k, VL.double(p))

# the window bases 2^(c j) P for j = 0 .. nw-1
def wbases(nw: Nat, +c: Nat, +p: V.Pt) -> +List<V.Pt>:
  match nw:
    case 0n:
      Nil{}
    case 1n+k:
      p <> wbases(k, c, dbl_n(c, p))

def window(+c: Nat, +b: V.Pt) -> T:
  +m = pow2(Nat.sub(c, 1n))
  tbuild(Nat.sub(c, 1n), BA.normalize(mults(m, b, b)))

# windows of a base, built in parallel
def wpar(+fuel: Nat, +cnt: Nat, +c: Nat, +bs: +List<V.Pt>) -> +List<T>:
  match fuel cnt bs:
    case _ 0n _:
      Nil{}
    case _ 1n Con{+b, _}:
      window(c, b) <> Nil{}
    case 1n+f _ _:
      +h = Nat.div(cnt, 2n)
      x y = wpar(f, h, c, List.take(&2, V.Pt, bs, h)) wpar(f, Nat.sub(cnt, h), c, List.drop(&2, V.Pt, bs, h))
      List.append(&2, T, x, y)
    case _ _ _:
      Nil{}

def nwin(+c: Nat) -> Nat:
  U32.to_nat(BA.windows(U32.from_nat(c)))

def table(+c: Nat, +p: V.Pt) -> Tab:
  +nw = nwin(c)
  Tab{wpar(16n, nw, c, wbases(nw, c, p))}

# tables for a list of bases, in parallel
def tables(+fuel: Nat, +cnt: Nat, +c: Nat, +ps: +List<V.Pt>) -> +List<Tab>:
  match fuel cnt ps:
    case _ 0n _:
      Nil{}
    case _ 1n Con{+p, _}:
      table(c, p) <> Nil{}
    case 1n+f _ _:
      +h = Nat.div(cnt, 2n)
      x y = tables(f, h, c, List.take(&2, V.Pt, ps, h)) tables(f, Nat.sub(cnt, h), c, List.drop(&2, V.Pt, ps, h))
      List.append(&2, Tab, x, y)
    case _ _ _:
      Nil{}

def make(+c: Nat, +ps: +List<V.Pt>) -> +List<Tab>:
  tables(16n, List.length(&2, V.Pt, ps), c, ps)

# acc + sum over windows of digit_j * (window j entry)
def add_d(+acc: V.Pt, +a: BA.AP) -> V.Pt:
  match a:
    case BA.AP{+x, +y}:
      VL.add_aff(acc, V.Aff{x, y})
    case BA.ANone{}:
      acc

def step(z: Bool, +d: Nat, +m: U32, +neg: U32, +t: T, +acc: V.Pt) -> V.Pt:
  match z:
    case True{}:
      acc
    case False{}:
      add_d(acc, BA.signed_pt(neg, tget(d, (m - 1 : U32), t)))

def walk(+d: Nat, ws: +List<T>, ds: +List<BA.SD>, +acc: V.Pt) -> V.Pt:
  match ws ds:
    case Con{+t, wt} Con{BA.SD{+m, +neg}, dt}:
      walk(d, wt, dt, step(U32.is_eq(m, 0), d, m, neg, t, acc))
    case _ _:
      acc

# acc + [s] P, s canonical (< 2^255), P given by its table
def mul_add(+c: Nat, +tab: Tab, +s: Wd.W, +acc: V.Pt) -> V.Pt:
  Tab{+ws} = tab
  +nw = nwin(c)
  walk(Nat.sub(c, 1n), ws, BA.recode(nw, s, U32.from_nat(c), 0, 0), acc)

# 1 * P as the table holds it (window 0, digit 1): mul_add with s = 1 adds exactly this entry
def first_ap(+c: Nat, +tab: Tab) -> BA.AP:
  Tab{+ws} = tab
  match ws:
    case Con{+t, _}:
      tget(Nat.sub(c, 1n), 0, t)
    case Nil{}:
      BA.ANone{}

# acc + sum_j [s_j] P_j
def msm_add(+c: Nat, tabs: +List<Tab>, ss: +List<Wd.W>, +acc: V.Pt) -> V.Pt:
  match tabs ss:
    case Con{+t, tt} Con{+s, st}:
      msm_add(c, tt, st, mul_add(c, t, s, acc))
    case _ _:
      acc

# --- flat tables (perf5) ----------------------------------------------------------------
# The same entries d * 2^(c j) * P_b (d = 1 .. h, h = 2^(c-1)) in one Array<U32>, 16 words each,
# at word 16 + 16 ((b nw + j) h + d - 1); header [present = 1, n bases, c, nw]. A lookup is an
# index, not a walk down a shared tree (a match on a shared node copies it, so the tree walk
# allocated on every digit). Tasks share the array through Array.fork, as gtab and msm_sb do.

# [d * 2^(c j) * P for d = 1 .. h] for j = 0 .. nw-1, window after window
def base_mults(nw: Nat, +c: Nat, +p: V.Pt) -> +List<V.Pt>:
  match nw:
    case 0n:
      Nil{}
    case 1n+k:
      List.append(&2, V.Pt, mults(pow2(Nat.sub(c, 1n)), p, p), base_mults(k, c, dbl_n(c, p)))

def flat_par(+fuel: Nat, +cnt: Nat, +c: Nat, +ps: +List<V.Pt>) -> +List<BA.AP>:
  match fuel cnt ps:
    case _ 0n _:
      Nil{}
    case _ 1n Con{+p, _}:
      BA.normalize(base_mults(nwin(c), c, p))
    case 1n+f _ _:
      +h = Nat.div(cnt, 2n)
      x y = flat_par(f, h, c, List.take(&2, V.Pt, ps, h)) flat_par(f, Nat.sub(cnt, h), c, List.drop(&2, V.Pt, ps, h))
      List.append(&2, BA.AP, x, y)
    case _ _ _:
      Nil{}

def flat_lg(+words: U32) -> Nat:
  Nat.add(U32.log2((words - 1 : U32)), 1n)

def make_flat(+c: Nat, +ps: +List<V.Pt>) -> Array<U32>:
  +n = List.length(&2, V.Pt, ps)
  +h = U32.from_nat(pow2(Nat.sub(c, 1n)))
  +nw = U32.from_nat(nwin(c))
  +aps = flat_par(16n, n, c, ps)
  a = [0 : U32^flat_lg((16 + 16 * U32.from_nat(n) * nw * h : U32))]
  a[0] <- 1
  a[1] <- U32.from_nat(n)
  a[2] <- U32.from_nat(c)
  a[3] <- nw
  GT.fill(aps, a, 16)

# no table: comms_any then takes the GLV path
def no_flat() -> Array<U32>:
  [0 : U32^4n]

def add_if(z: Bool, +acc: V.Pt, +p: BA.AP) -> V.Pt:
  match z:
    case True{}:
      acc
    case False{}:
      add_d(acc, p)

def fw_step(r: Array<U32> & BA.AP, +z: Bool, +neg: U32, +acc: V.Pt) -> Array<U32> & V.Pt:
  (a, +p) = r
  (a, add_if(z, acc, BA.signed_pt(neg, p)))

# ds first (it shrinks), r = (table, acc) last (matched after ds); o: word offset of the current window's entry d = 1. A zero digit reads
# entry 1 and adds nothing.
def fwalk(ds: +List<BA.SD>, +h: U32, +o: U32, r: Array<U32> & V.Pt) -> Array<U32> & V.Pt:
  match ds:
    case Con{BA.SD{+m, +neg}, dt}:
      (a, +acc) = r
      +z = U32.is_eq(m, 0)
      fwalk(dt, h, (o + 16 * h : U32), fw_step(GT.ap_at(a, (o + 16 * (m - 1 + Bool.to_u32(z)) : U32)), z, neg, acc))
    case Nil{}:
      r

# acc + [s] P_b, s canonical (< 2^255): the same additions, in the same order, as mul_add
def mul_add_f(a: Array<U32>, +c: Nat, +b: U32, +s: Wd.W, +acc: V.Pt) -> Array<U32> & V.Pt:
  +nw = nwin(c)
  +h = U32.from_nat(pow2(Nat.sub(c, 1n)))
  fwalk(BA.recode(nw, s, U32.from_nat(c), 0, 0), h, (16 + 16 * b * U32.from_nat(nw) * h : U32), (a, acc))

# 1 * P_b as the table holds it (first_ap)
def first_f(a: Array<U32>, +c: Nat, +b: U32) -> Array<U32> & BA.AP:
  GT.ap_at(a, (16 + 16 * b * U32.from_nat(nwin(c)) * U32.from_nat(pow2(Nat.sub(c, 1n))) : U32))
