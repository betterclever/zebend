# Batch-affine Pippenger with buckets in flat arrays (perf3).
#
# Same digits and window split as msm_ba.msm9, but each window keeps its buckets in one
# Array<U32> (16 words per bucket: affine x then y, Montgomery limbs) plus an occupancy
# array, updated in place. A pass drops each point into an empty bucket or queues ONE
# addition for an occupied bucket; a point whose bucket already has a queued addition is
# deferred to the next pass. Every pass ends with one flush: all queued additions share a
# single field inversion (Montgomery's trick). Equal-x pairs (doubling or cancellation)
# take the complete projective path, so every input is handled.
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ../fq32.bend as B
import ../lib32/vesta.bend as V
import ./msm_ba.bend as BA

# --- 8-word field elements in a flat array ------------------------------------------------

def ga8(r: Array<U32> & U32, +o: U32, v0: U32, v1: U32, v2: U32, v3: U32, v4: U32, v5: U32, v6: U32) -> Array<U32> & B.Fq:
  (a, v7) = r
  (a, B.Fq{v0, v1, v2, v3, v4, v5, v6, v7})

def ga7(r: Array<U32> & U32, +o: U32, v0: U32, v1: U32, v2: U32, v3: U32, v4: U32, v5: U32) -> Array<U32> & B.Fq:
  (a, v6) = r
  ga8(a[(o + 7 : U32)], o, v0, v1, v2, v3, v4, v5, v6)

def ga6(r: Array<U32> & U32, +o: U32, v0: U32, v1: U32, v2: U32, v3: U32, v4: U32) -> Array<U32> & B.Fq:
  (a, v5) = r
  ga7(a[(o + 6 : U32)], o, v0, v1, v2, v3, v4, v5)

def ga5(r: Array<U32> & U32, +o: U32, v0: U32, v1: U32, v2: U32, v3: U32) -> Array<U32> & B.Fq:
  (a, v4) = r
  ga6(a[(o + 5 : U32)], o, v0, v1, v2, v3, v4)

def ga4(r: Array<U32> & U32, +o: U32, v0: U32, v1: U32, v2: U32) -> Array<U32> & B.Fq:
  (a, v3) = r
  ga5(a[(o + 4 : U32)], o, v0, v1, v2, v3)

def ga3(r: Array<U32> & U32, +o: U32, v0: U32, v1: U32) -> Array<U32> & B.Fq:
  (a, v2) = r
  ga4(a[(o + 3 : U32)], o, v0, v1, v2)

def ga2(r: Array<U32> & U32, +o: U32, v0: U32) -> Array<U32> & B.Fq:
  (a, v1) = r
  ga3(a[(o + 2 : U32)], o, v0, v1)

def ga1(r: Array<U32> & U32, +o: U32) -> Array<U32> & B.Fq:
  (a, v0) = r
  ga2(a[(o + 1 : U32)], o, v0)

def ga(a: Array<U32>, +o: U32) -> Array<U32> & B.Fq:
  ga1(a[o], o)

def sa(a: Array<U32>, +o: U32, x: B.Fq) -> Array<U32>:
  B.Fq{v0, v1, v2, v3, v4, v5, v6, v7} = x
  a[o] <- v0
  a[(o + 1 : U32)] <- v1
  a[(o + 2 : U32)] <- v2
  a[(o + 3 : U32)] <- v3
  a[(o + 4 : U32)] <- v4
  a[(o + 5 : U32)] <- v5
  a[(o + 6 : U32)] <- v6
  a[(o + 7 : U32)] <- v7

# --- per-window state ----------------------------------------------------------------------

type QE is Data:
  QE{b: U32, x: B.Fq, y: B.Fq}

type ST is Type:
  ST{bk: Array<U32>, oc: Array<U32>, q: List<QE>, df: List<QE>}

# bucket b: occupancy 0 = empty, 1 = holds a point, 2 = holds a point and has a queued add.
def put0(bk: Array<U32>, oc: Array<U32>, q: List<QE>, df: List<QE>, +b: U32, x: B.Fq, y: B.Fq) -> ST:
  +o = (b * 16 : U32)
  bk2 = sa(sa(bk, o, x), (o + 8 : U32), y)
  oc[b] <- 1
  ST{bk2, oc, q, df}

def at_occ(n: Nat, oc: Array<U32>, bk: Array<U32>, q: List<QE>, df: List<QE>, +b: U32, x: B.Fq, y: B.Fq) -> ST:
  match n:
    case 0n:
      put0(bk, oc, q, df, b, x, y)
    case 1n:
      oc[b] <- 2
      ST{bk, oc, QE{b, x, y} <> q, df}
    case _:
      ST{bk, oc, q, QE{b, x, y} <> df}

def at_occ_r(r: Array<U32> & U32, bk: Array<U32>, q: List<QE>, df: List<QE>, +b: U32, x: B.Fq, y: B.Fq) -> ST:
  (oc, o) = r
  at_occ(U32.to_nat(o), oc, bk, q, df, b, x, y)

def place(st: ST, +b: U32, x: B.Fq, y: B.Fq) -> ST:
  ST{bk, oc, q, df} = st
  at_occ_r(oc[b], bk, q, df, b, x, y)

def place_sd(z: Bool, st: ST, +m: U32, +neg: U32, x: B.Fq, +y: B.Fq) -> ST:
  match z:
    case True{}:
      st
    case False{}:
      place(st, m, x, B.sel(neg, B.neg(y), y))

def place_ap(st: ST, p: BA.AP, sd: BA.SD) -> ST:
  match p:
    case BA.ANone{}:
      st
    case BA.AP{x, y}:
      BA.SD{+m, +neg} = sd
      place_sd(U32.is_eq(m, 0), st, m, neg, x, y)

# First pass: the window's digits for every base.
def pass0(ps: +List<BA.AP>, ks: +List<BA.W9>, +j: U32, +c: U32, st: ST) -> ST:
  match ps ks:
    case Con{+p, pt} Con{+k, kt}:
      pass0(pt, kt, j, c, place_ap(st, p, BA.digit9(k, j, c)))
    case _ _:
      st

# Later passes: deferred (bucket, point) pairs.
def passq(xs: List<QE>, st: ST) -> ST:
  match xs:
    case Con{QE{+b, x, y}, t}:
      passq(t, place(st, b, x, y))
    case Nil{}:
      st

# --- flush: all queued additions with one inversion -------------------------------------------

type FE is Data:
  FE{b: U32, x1: B.Fq, y1: B.Fq, x2: B.Fq, y2: B.Fq}

type CL is Type:
  CL{bk: Array<U32>, fs: List<FE>, ds: +List<B.Fq>}

def den_of(+x1: B.Fq, +x2: B.Fq) -> B.Fq:
  B.sel(B.eq(x1, x2), B.one(), B.sub(x2, x1))

def col_y(r: Array<U32> & B.Fq, fs: List<FE>, ds: +List<B.Fq>, +b: U32, +x1: B.Fq, +x2: B.Fq, y2: B.Fq) -> CL:
  (bk, y1) = r
  CL{bk, FE{b, x1, y1, x2, y2} <> fs, den_of(x1, x2) <> ds}

def col_x(r: Array<U32> & B.Fq, fs: List<FE>, ds: +List<B.Fq>, +b: U32, x2: B.Fq, y2: B.Fq) -> CL:
  (bk, x1) = r
  col_y(ga(bk, (b * 16 + 8 : U32)), fs, ds, b, x1, x2, y2)

# Read each queued bucket point; build the pair list and the denominators (same order).
def collect(q: List<QE>, cl: CL) -> CL:
  match q:
    case Con{QE{+b, x, y}, t}:
      CL{bk, fs, ds} = cl
      collect(t, col_x(ga(bk, (b * 16 : U32)), fs, ds, b, x, y))
    case Nil{}:
      cl

# Result of one queued pair: 0 = affine sum, 1 = equal x (complete fallback, may cancel).
def pair_sum(eqx: Bool, +x1: B.Fq, +y1: B.Fq, +x2: B.Fq, +y2: B.Fq, +inv: B.Fq) -> BA.AP:
  match eqx:
    case False{}:
      BA.add_aff(x1, y1, x2, y2, inv)
    case True{}:
      BA.norm_one(V.add(V.Pt{x1, y1, B.one()}, V.Pt{x2, y2, B.one()}))

def store(p: BA.AP, bk: Array<U32>, oc: Array<U32>, +b: U32) -> Array<U32> & Array<U32>:
  match p:
    case BA.AP{x, y}:
      +o = (b * 16 : U32)
      oc[b] <- 1
      (sa(sa(bk, o, x), (o + 8 : U32), y), oc)
    case BA.ANone{}:
      oc[b] <- 0
      (bk, oc)

def apply(fs: List<FE>, invs: +List<B.Fq>, r: Array<U32> & Array<U32>) -> Array<U32> & Array<U32>:
  match fs invs:
    case Con{FE{+b, +x1, +y1, +x2, +y2}, ft} Con{+inv, it}:
      (bk, oc) = r
      apply(ft, it, store(pair_sum(B.is_eq(x1, x2), x1, y1, x2, y2, inv), bk, oc, b))
    case _ _:
      r

def flushed(r: Array<U32> & Array<U32>, df: List<QE>) -> ST:
  (bk, oc) = r
  ST{bk, oc, Nil{}, df}

def flush_cl(cl: CL, oc: Array<U32>, df: List<QE>) -> ST:
  CL{bk, fs, +ds} = cl
  # fs and ds are both newest-first, so they stay aligned with batch_inv's same-order output.
  flushed(apply(fs, BA.batch_inv(ds), (bk, oc)), df)

def flush(st: ST) -> ST:
  ST{bk, oc, q, df} = st
  flush_cl(collect(q, CL{bk, Nil{}, Nil{}}), oc, df)

# Flush, then replay the deferred points; repeat until nothing is deferred.
def more_df(df: List<QE>, bk: Array<U32>, oc: Array<U32>, q: List<QE>) -> ST & Bool:
  match df:
    case Nil{}:
      (ST{bk, oc, q, Nil{}}, False{})
    case Con{h, t}:
      (ST{bk, oc, q, h <> t}, True{})

def with_more(st: ST) -> ST & Bool:
  ST{bk, oc, q, df} = st
  more_df(df, bk, oc, q)

def replay(st: ST) -> ST:
  ST{bk, oc, q, df} = st
  passq(df, ST{bk, oc, q, Nil{}})

def drain(fuel: Nat, p: ST & Bool) -> ST:
  match fuel:
    case 0n:
      (st, _) = p
      st
    case 1n+f:
      (st, more) = p
      match more:
        case True{}:
          drain(f, with_more(flush(replay(st))))
        case False{}:
          st

# --- bucket reduction: sum_b b * B_b with a running suffix sum ----------------------------------

def pt_y(r: Array<U32> & B.Fq, x: B.Fq) -> Array<U32> & V.Aff:
  (bk, y) = r
  (bk, V.Aff{x, y})

def pt_x(r: Array<U32> & B.Fq, +b: U32) -> Array<U32> & V.Aff:
  (bk, x) = r
  pt_y(ga(bk, (b * 16 + 8 : U32)), x)

def add_r(r: Array<U32> & V.Aff, run: V.Pt) -> Array<U32> & V.Pt:
  (bk, a) = r
  (bk, V.add_aff(run, a))

def step_run(n: Nat, bk: Array<U32>, +b: U32, run: V.Pt) -> Array<U32> & V.Pt:
  match n:
    case 1n:
      add_r(pt_x(ga(bk, (b * 16 : U32)), b), run)
    case _:
      (bk, run)

type R3 is Type:
  R3{oc: Array<U32>, bk: Array<U32>, run: V.Pt}

def r3(oc: Array<U32>, r: Array<U32> & V.Pt) -> R3:
  (bk, run) = r
  R3{oc, bk, run}

def step2(ro: Array<U32> & U32, bk: Array<U32>, +b: U32, run: V.Pt) -> R3:
  (oc, o) = ro
  r3(oc, step_run(U32.to_nat(o), bk, b, run))

# st = (occupancy, (buckets, run)) with run = B_top + ... + B_b; adds run into acc, moves to b - 1.
def red(n: Nat, +b: U32, st: R3, acc: V.Pt) -> V.Pt:
  match n:
    case 0n:
      acc
    case 1n+k:
      R3{oc, bk, +run} = st
      +b1 = (b - 1 : U32)
      red(k, b1, step2(oc[b1], bk, b1, run), V.add(acc, run))

# --- one window, and the windowed MSM --------------------------------------------------------

def reduce_st(st: ST, +half: U32) -> V.Pt:
  ST{bk, oc, _, _} = st
  red(U32.to_nat(half), half, step2(oc[half], bk, half, V.identity()), V.identity())

def window_sum_arr(+c: U32, +aps: +List<BA.AP>, +ks: +List<BA.W9>, +j: U32) -> V.Pt:
  +half = (1 << U32.to_nat((c - 1 : U32)) : U32)
  st0 = pass0(aps, ks, j, c, ST{[0 : U32^U32.to_nat((c + 4 : U32))], [0 : U32^U32.to_nat(c)], Nil{}, Nil{}})
  reduce_st(drain(4096n, with_more(flush(st0))), half)

def wrange_arr(+fuel: Nat, one: Bool, +c: U32, +aps: +List<BA.AP>, +ks: +List<BA.W9>, +lo: U32, +cnt: U32) -> V.Pt:
  match fuel one:
    case 1n+f False{}:
      +h = (cnt >> 1n : U32)
      +h2 = (cnt - h : U32)
      a b = wrange_arr(f, U32.is_lt(h, 2), c, aps, ks, lo, h) wrange_arr(f, U32.is_lt(h2, 2), c, aps, ks, (lo + h : U32), h2)
      V.add(a, BA.dbl_n(U32.to_nat((h * c : U32)), b))
    case _ _:
      window_sum_arr(c, aps, ks, lo)

# sum_i [s_i] P_i: msm_ba.msm9 digits and window split, array buckets (c in 4..16).
def msm_arr(+c: U32, +ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  wrange_arr(9n, False{}, c, BA.normalize(ps), BA.offset_all(ss, BA.hconst(c)), 0, BA.windows9(c))
