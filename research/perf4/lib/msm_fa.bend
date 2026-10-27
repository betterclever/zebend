# Batch-affine bucket accumulation over a FLAT bucket array (File.read_words-era arrays: one
# flat block, ~0.2 ns per element access), as a drop-in for msm_ba.window_sum9.
#
# Bucket b (0 .. 2^(c-1)-1) lives at words 17b .. 17b+16: x (8 words), y (8 words, Montgomery
# limbs), flag (0 empty, 1 holds a point, 2 holds a point with an addition pending). Terms are
# streamed: a term for an empty bucket is stored; for a full bucket it becomes a pending affine
# addition (bucket point + term); for a pending bucket it is deferred to the next pass. Pending
# additions share one field inversion (Montgomery's trick) per flush. Pairs with equal x use
# msm_ba.psum's complete fallback (P + P, P + (-P) = identity: the bucket becomes empty again),
# so every input is handled and the window sum is the same group element as window_sum9's.
# Each pass consumes at least one term, so passes are bounded by the fuel below.
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ../../../crypto/field3/fq64.bend as B
import ../../../crypto/field3/lib64/vesta.bend as V
import ./vesta_lz.bend as VL
import ./msm_ba.bend as BA

# a term: bucket index and the (signed) affine point
type DT is Data:
  DT{b: U32, x: B.Fq, y: B.Fq}

# a pending addition: bucket b holds (x1, y1); add (x2, y2)
type PE is Data:
  PE{b: U32, x1: B.Fq, y1: B.Fq, x2: B.Fq, y2: B.Fq}

type FS is Type:
  FS{a: Array<U32>, p: +List<PE>, n: Nat, d: +List<DT>}

def mk_ap(+f: U32, +x: B.Fq, +y: B.Fq) -> BA.AP:
  match f:
    case 1:
      BA.AP{x, y}
    case _:
      BA.ANone{}

def bk_at_17(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32, +w11: U32, +w12: U32, +w13: U32, +w14: U32, +w15: U32) -> Array<U32> & BA.AP:
  (a, +w16) = r
  (a, mk_ap(w16, B.Fq{w0, w1, w2, w3, w4, w5, w6, w7}, B.Fq{w8, w9, w10, w11, w12, w13, w14, w15}))

def bk_at_16(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32, +w11: U32, +w12: U32, +w13: U32, +w14: U32) -> Array<U32> & BA.AP:
  (a, +w15) = r
  bk_at_17(a[(o + 16 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15)

def bk_at_15(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32, +w11: U32, +w12: U32, +w13: U32) -> Array<U32> & BA.AP:
  (a, +w14) = r
  bk_at_16(a[(o + 15 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14)

def bk_at_14(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32, +w11: U32, +w12: U32) -> Array<U32> & BA.AP:
  (a, +w13) = r
  bk_at_15(a[(o + 14 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13)

def bk_at_13(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32, +w11: U32) -> Array<U32> & BA.AP:
  (a, +w12) = r
  bk_at_14(a[(o + 13 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12)

def bk_at_12(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32) -> Array<U32> & BA.AP:
  (a, +w11) = r
  bk_at_13(a[(o + 12 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11)

def bk_at_11(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32) -> Array<U32> & BA.AP:
  (a, +w10) = r
  bk_at_12(a[(o + 11 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10)

def bk_at_10(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32) -> Array<U32> & BA.AP:
  (a, +w9) = r
  bk_at_11(a[(o + 10 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8, w9)

def bk_at_9(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32) -> Array<U32> & BA.AP:
  (a, +w8) = r
  bk_at_10(a[(o + 9 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8)

def bk_at_8(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32) -> Array<U32> & BA.AP:
  (a, +w7) = r
  bk_at_9(a[(o + 8 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7)

def bk_at_7(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32) -> Array<U32> & BA.AP:
  (a, +w6) = r
  bk_at_8(a[(o + 7 : U32)], o, w0, w1, w2, w3, w4, w5, w6)

def bk_at_6(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32) -> Array<U32> & BA.AP:
  (a, +w5) = r
  bk_at_7(a[(o + 6 : U32)], o, w0, w1, w2, w3, w4, w5)

def bk_at_5(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32) -> Array<U32> & BA.AP:
  (a, +w4) = r
  bk_at_6(a[(o + 5 : U32)], o, w0, w1, w2, w3, w4)

def bk_at_4(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32) -> Array<U32> & BA.AP:
  (a, +w3) = r
  bk_at_5(a[(o + 4 : U32)], o, w0, w1, w2, w3)

def bk_at_3(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32) -> Array<U32> & BA.AP:
  (a, +w2) = r
  bk_at_4(a[(o + 3 : U32)], o, w0, w1, w2)

def bk_at_2(r: Array<U32> & U32, +o: U32, +w0: U32) -> Array<U32> & BA.AP:
  (a, +w1) = r
  bk_at_3(a[(o + 2 : U32)], o, w0, w1)

def bk_at_1(r: Array<U32> & U32, +o: U32) -> Array<U32> & BA.AP:
  (a, +w0) = r
  bk_at_2(a[(o + 1 : U32)], o, w0)

def bk_at(a: Array<U32>, +o: U32) -> Array<U32> & BA.AP:
  bk_at_1(a[o], o)

def bk_put(a: Array<U32>, +o: U32, +x: B.Fq, +y: B.Fq, +f: U32) -> Array<U32>:
  B.Fq{+x0, +x1, +x2, +x3, +x4, +x5, +x6, +x7} = x
  B.Fq{+y0, +y1, +y2, +y3, +y4, +y5, +y6, +y7} = y
  a[(o + 0 : U32)] <- x0
  a[(o + 1 : U32)] <- x1
  a[(o + 2 : U32)] <- x2
  a[(o + 3 : U32)] <- x3
  a[(o + 4 : U32)] <- x4
  a[(o + 5 : U32)] <- x5
  a[(o + 6 : U32)] <- x6
  a[(o + 7 : U32)] <- x7
  a[(o + 8 : U32)] <- y0
  a[(o + 9 : U32)] <- y1
  a[(o + 10 : U32)] <- y2
  a[(o + 11 : U32)] <- y3
  a[(o + 12 : U32)] <- y4
  a[(o + 13 : U32)] <- y5
  a[(o + 14 : U32)] <- y6
  a[(o + 15 : U32)] <- y7
  a[(o + 16 : U32)] <- f
  a

def bk_flag(a: Array<U32>, +b: U32) -> Array<U32> & U32:
  a[(17 * b + 16 : U32)]

# --- flush: all pending additions with one inversion ---------------------------------------

def dens(ps: +List<PE>) -> +List<B.Fq>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{PE{_, +x1, +y1, +x2, +y2}, t}:
      BA.den(BA.AP{x1, y1}, BA.AP{x2, y2}) <> dens(t)

def bk_set(a: Array<U32>, +b: U32, +s: BA.AP) -> Array<U32>:
  match s:
    case BA.AP{+x, +y}:
      bk_put(a, (17 * b : U32), x, y, 1)
    case BA.ANone{}:
      bk_put(a, (17 * b : U32), B.zero(), B.zero(), 0)

def apply(ps: +List<PE>, ivs: +List<B.Fq>, a: Array<U32>) -> Array<U32>:
  match ps ivs:
    case Con{PE{+b, +x1, +y1, +x2, +y2}, pt} Con{+iv, it}:
      apply(pt, it, bk_set(a, b, BA.psum(BA.AP{x1, y1}, BA.AP{x2, y2}, iv)))
    case _ _:
      a

def flush(a: Array<U32>, +p: +List<PE>, +d: +List<DT>) -> FS:
  FS{apply(p, BA.batch_inv(dens(p)), a), Nil{}, 0n, d}

# --- one term ---------------------------------------------------------------------------

def pend2(+q: BA.AP, a: Array<U32>, +b: U32, +x: B.Fq, +y: B.Fq, +p: +List<PE>, +n: Nat, +d: +List<DT>) -> FS:
  match q:
    case BA.AP{+x1, +y1}:
      a[(17 * b + 16 : U32)] <- 2
      FS{a, PE{b, x1, y1, x, y} <> p, Nat.add(n, 1n), d}
    case BA.ANone{}:
      FS{bk_put(a, (17 * b : U32), x, y, 1), p, n, d}

def pend(r: Array<U32> & BA.AP, +b: U32, +x: B.Fq, +y: B.Fq, +p: +List<PE>, +n: Nat, +d: +List<DT>) -> FS:
  (a, +q) = r
  pend2(q, a, b, x, y, p, n, d)

def act(+f: U32, a: Array<U32>, +b: U32, +x: B.Fq, +y: B.Fq, +p: +List<PE>, +n: Nat, +d: +List<DT>) -> FS:
  match f:
    case 0:
      FS{bk_put(a, (17 * b : U32), x, y, 1), p, n, d}
    case 1:
      pend(bk_at(a, (17 * b : U32)), b, x, y, p, n, d)
    case _:
      FS{a, p, n, DT{b, x, y} <> d}

def act_r(r: Array<U32> & U32, +b: U32, +x: B.Fq, +y: B.Fq, +p: +List<PE>, +n: Nat, +d: +List<DT>) -> FS:
  (a, +f) = r
  act(f, a, b, x, y, p, n, d)

def full_or(full: Bool, a: Array<U32>, +p: +List<PE>, +n: Nat, +d: +List<DT>) -> FS:
  match full:
    case True{}:
      flush(a, p, d)
    case False{}:
      FS{a, p, n, d}

def step2(st: FS, +lim: Nat) -> FS:
  FS{a, +p, +n, +d} = st
  full_or(Nat.is_ge(n, lim), a, p, n, d)

def step(+t: DT, +lim: Nat, st: FS) -> FS:
  DT{+b, +x, +y} = t
  FS{a, +p, +n, +d} = st
  step2(act_r(bk_flag(a, b), b, x, y, p, n, d), lim)

def flush_last(st: FS) -> Array<U32>:
  FS{a, +p, +n, +d} = st
  apply(p, BA.batch_inv(dens(p)), a)

# every term into the buckets; deferred terms are re-run until none is left
def pass(fuel: Nat, ts: +List<DT>, +lim: Nat, st: FS) -> Array<U32>:
  match fuel ts st:
    case 1n+f Con{+t, rest} _:
      pass(f, rest, lim, step(t, lim, st))
    case 1n+f Nil{} FS{a, p, n, d}:
      match d:
        case Nil{}:
          flush_last(FS{a, p, n, Nil{}})
        case Con{+h, dt}:
          pass(f, h <> dt, lim, flush(a, p, Nil{}))
    case _ _ _:
      flush_last(st)

# --- terms of one window, reduction -------------------------------------------------------

def term2(skip: Bool, +m: U32, +p: BA.AP, +rest: +List<DT>) -> +List<DT>:
  match skip p:
    case False{} BA.AP{+x, +y}:
      DT{(m - 1 : U32), x, y} <> rest
    case _ _:
      rest

def term(+sd: BA.SD, +p: BA.AP, +rest: +List<DT>) -> +List<DT>:
  BA.SD{+m, +neg} = sd
  term2(Bool.or(U32.is_eq(m, 0), BA.is_none(p)), m, BA.signed_pt(neg, p), rest)

def terms(aps: +List<BA.AP>, ks: +List<BA.W9>, +j: U32, +c: U32) -> +List<DT>:
  match aps ks:
    case Con{+p, pt} Con{+k, kt}:
      term(BA.digit9(k, j, c), p, terms(pt, kt, j, c))
    case _ _:
      Nil{}

# buckets from the top: run = suffix sum, acc = sum_b (b+1) * bucket_b
def red(k: Nat, +b: U32, +run: V.Pt, +acc: V.Pt, r: Array<U32> & BA.AP) -> V.Pt:
  match k:
    case 0n:
      (a, +q) = r
      acc
    case 1n+m:
      (a, +q) = r
      +run2 = BA.add_b(run, q <> Nil{})
      red(m, (b - 1 : U32), run2, VL.add(acc, run2), bk_at(a, (17 * (b - 1 + Bool.to_u32(U32.is_eq(b, 0))) : U32)))

def lg_bk(+c: U32) -> Nat:
  Nat.add(U32.to_nat(c), 4n)

def window(+c: U32, +aps: +List<BA.AP>, +ks: +List<BA.W9>, +j: U32) -> V.Pt:
  +nb = (1 << U32.to_nat((c - 1 : U32)) : U32)
  +ts = terms(aps, ks, j, c)
  +len = List.length(&2, DT, ts)
  a0 = [0 : U32^lg_bk(c)]
  +lim = U32.to_nat((nb >> 1n : U32))
  +fuel = Nat.add(Nat.mul(len, len), Nat.add(Nat.mul(4n, len), 16n))
  red(U32.to_nat(nb), (nb - 1 : U32), V.identity(), V.identity(), bk_at(pass(fuel, ts, lim, FS{a0, Nil{}, 0n, Nil{}}), (17 * (nb - 1) : U32)))

def wrange(+fuel: Nat, one: Bool, +c: U32, +aps: +List<BA.AP>, +ks: +List<BA.W9>, +lo: U32, +cnt: U32) -> V.Pt:
  match fuel one:
    case 1n+f False{}:
      +h = (cnt >> 1n : U32)
      +h2 = (cnt - h : U32)
      a b = wrange(f, U32.is_lt(h, 2), c, aps, ks, lo, h) wrange(f, U32.is_lt(h2, 2), c, aps, ks, (lo + h : U32), h2)
      VL.add(a, BA.dbl_n(U32.to_nat((h * c : U32)), b))
    case _ _:
      window(c, aps, ks, lo)

# sum_i [s_i] P_i, carry-free signed c-bit windows (as msm_ba.msm9), flat-array buckets
def msm(+c: U32, +ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  wrange(9n, False{}, c, BA.normalize(ps), BA.offset_all(ss, BA.hconst(c)), 0, BA.windows9(c))
