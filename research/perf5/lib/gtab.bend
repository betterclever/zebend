# Fixed-base tables for the 2^k IPA generators G, in a flat file loaded with File.read_words.
#
# Table (window width c, W = ceil(257 / c) windows, the carry-free signed digits of
# msm_ba.msm9): entry (i, j) = 2^(c j) G_i, affine, Montgomery limbs, 16 words, at word
# 16 + 16 (i W + j). Words 0..15: header [magic, n, c, W, 0...].
# With the table, sum_i [s_i] G_i needs no doublings and no per-window bucket reduction: every
# (i, j) term goes into ONE set of 2^(c-1) buckets (per task), so the bucket reduction is paid
# once per task instead of once per window. Tasks split the bases i into chunks.
#
# The table is computed by Bend (`gen`, from params_g.bin; v/gtab_gen) and cached on disk; at
# load it must match params_g.bin (`check`): header, every entry (i, 0) equal to G_i, and
# random entries (i, j) equal to 2^c (i, j-1). It is trusted like params_g.bin itself.
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ../../../crypto/field3/fq64.bend as B
import ../../../crypto/field3/lib64/vesta.bend as V
import ./vesta_lz.bend as VL
import ./msm_ba.bend as BA

def magic() -> U32:
  1195721026

def ap_at_16(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32, +w11: U32, +w12: U32, +w13: U32, +w14: U32) -> Array<U32> & BA.AP:
  (a, +w15) = r
  (a, BA.AP{B.Fq{w0, w1, w2, w3, w4, w5, w6, w7}, B.Fq{w8, w9, w10, w11, w12, w13, w14, w15}})

def ap_at_15(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32, +w11: U32, +w12: U32, +w13: U32) -> Array<U32> & BA.AP:
  (a, +w14) = r
  ap_at_16(a[(o + 15 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14)

def ap_at_14(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32, +w11: U32, +w12: U32) -> Array<U32> & BA.AP:
  (a, +w13) = r
  ap_at_15(a[(o + 14 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13)

def ap_at_13(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32, +w11: U32) -> Array<U32> & BA.AP:
  (a, +w12) = r
  ap_at_14(a[(o + 13 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12)

def ap_at_12(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32) -> Array<U32> & BA.AP:
  (a, +w11) = r
  ap_at_13(a[(o + 12 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11)

def ap_at_11(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32) -> Array<U32> & BA.AP:
  (a, +w10) = r
  ap_at_12(a[(o + 11 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10)

def ap_at_10(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32) -> Array<U32> & BA.AP:
  (a, +w9) = r
  ap_at_11(a[(o + 10 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8, w9)

def ap_at_9(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32) -> Array<U32> & BA.AP:
  (a, +w8) = r
  ap_at_10(a[(o + 9 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7, w8)

def ap_at_8(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32) -> Array<U32> & BA.AP:
  (a, +w7) = r
  ap_at_9(a[(o + 8 : U32)], o, w0, w1, w2, w3, w4, w5, w6, w7)

def ap_at_7(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32) -> Array<U32> & BA.AP:
  (a, +w6) = r
  ap_at_8(a[(o + 7 : U32)], o, w0, w1, w2, w3, w4, w5, w6)

def ap_at_6(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32) -> Array<U32> & BA.AP:
  (a, +w5) = r
  ap_at_7(a[(o + 6 : U32)], o, w0, w1, w2, w3, w4, w5)

def ap_at_5(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32, +w3: U32) -> Array<U32> & BA.AP:
  (a, +w4) = r
  ap_at_6(a[(o + 5 : U32)], o, w0, w1, w2, w3, w4)

def ap_at_4(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32, +w2: U32) -> Array<U32> & BA.AP:
  (a, +w3) = r
  ap_at_5(a[(o + 4 : U32)], o, w0, w1, w2, w3)

def ap_at_3(r: Array<U32> & U32, +o: U32, +w0: U32, +w1: U32) -> Array<U32> & BA.AP:
  (a, +w2) = r
  ap_at_4(a[(o + 3 : U32)], o, w0, w1, w2)

def ap_at_2(r: Array<U32> & U32, +o: U32, +w0: U32) -> Array<U32> & BA.AP:
  (a, +w1) = r
  ap_at_3(a[(o + 2 : U32)], o, w0, w1)

def ap_at_1(r: Array<U32> & U32, +o: U32) -> Array<U32> & BA.AP:
  (a, +w0) = r
  ap_at_2(a[(o + 1 : U32)], o, w0)

def ap_at(a: Array<U32>, +o: U32) -> Array<U32> & BA.AP:
  ap_at_1(a[o], o)

def put_ap(a: Array<U32>, +o: U32, +p: BA.AP) -> Array<U32>:
  match p:
    case BA.AP{+x, +y}:
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
      a
    case BA.ANone{}:
      a

def dbl_n(n: Nat, +p: V.Pt) -> V.Pt:
  match n:
    case 0n:
      p
    case 1n+k:
      dbl_n(k, VL.double(p))

def nwin(+c: U32) -> U32:
  BA.windows9(c)

def nbytes(+n: U32, +c: U32) -> U32:
  ((16 + 16 * n * nwin(c)) * 4 : U32)

# --- generation ------------------------------------------------------------------------

# 2^(c j) P for j = 0 .. w-1
def wbases(w: Nat, +c: Nat, +p: V.Pt) -> +List<V.Pt>:
  match w:
    case 0n:
      Nil{}
    case 1n+k:
      p <> wbases(k, c, dbl_n(c, p))

def gen_par(+fuel: Nat, +cnt: Nat, +w: Nat, +c: Nat, +ps: +List<V.Pt>) -> +List<V.Pt>:
  match fuel cnt ps:
    case _ 0n _:
      Nil{}
    case _ 1n Con{+p, _}:
      wbases(w, c, p)
    case 1n+f _ _:
      +h = Nat.div(cnt, 2n)
      x y = gen_par(f, h, w, c, List.take(&2, V.Pt, ps, h)) gen_par(f, Nat.sub(cnt, h), w, c, List.drop(&2, V.Pt, ps, h))
      List.append(&2, V.Pt, x, y)
    case _ _ _:
      Nil{}

def fill(xs: +List<BA.AP>, a: Array<U32>, +o: U32) -> Array<U32>:
  match xs:
    case Nil{}:
      a
    case Con{+p, t}:
      fill(t, put_ap(a, o, p), (o + 16 : U32))

# the table words for bases gs and window width c, in an array of 2^lg words
def gen(+c: U32, +gs: +List<V.Pt>, +lg: Nat) -> Array<U32>:
  +n = List.length(&2, V.Pt, gs)
  +w = nwin(c)
  +aps = BA.normalize(gen_par(32n, n, U32.to_nat(w), U32.to_nat(c), gs))
  a = [0 : U32^lg]
  a[0] <- magic()
  a[1] <- U32.from_nat(n)
  a[2] <- c
  a[3] <- w
  fill(aps, a, 16)

# --- loading checks ------------------------------------------------------------------------

def ap_eq(+a: BA.AP, +b: BA.AP) -> U32:
  match a b:
    case BA.AP{+x1, +y1} BA.AP{+x2, +y2}:
      (B.eq(x1, x2) .&. B.eq(y1, y2) : U32)
    case _ _:
      0

def g_aff(+p: V.Pt) -> BA.AP:
  V.Pt{+x, +y, _} = p
  BA.AP{x, y}

# r holds entry (i, 0); gs the generators from i on
def chk0(gs: +List<V.Pt>, +w: U32, +i: U32, +acc: U32, r: Array<U32> & BA.AP) -> U32:
  match gs:
    case Nil{}:
      (a, +e) = r
      acc
    case Con{+g, t}:
      (a, +e) = r
      chk0(t, w, (i + 1 : U32), (acc .&. ap_eq(e, g_aff(g)) : U32), ap_at(a, (16 + 16 * (i + 1) * w : U32)))

def chk_step2(r: Array<U32> & BA.AP, +c: U32, +e0: BA.AP) -> Array<U32> & U32:
  (a, +e1) = r
  (a, Bool.to_u32(V.is_eq(dbl_n(U32.to_nat(c), BA.ap_to_pt(e0)), BA.ap_to_pt(e1))))

def chk_step1(r: Array<U32> & BA.AP, +w: U32, +c: U32, +i: U32, +j: U32) -> Array<U32> & U32:
  (a, +e0) = r
  chk_step2(ap_at(a, (16 + 16 * (i * w + j) : U32)), c, e0)

# entry (i, j) == 2^c entry (i, j-1), j >= 1
def chk_step(a: Array<U32>, +w: U32, +c: U32, +i: U32, +j: U32) -> Array<U32> & U32:
  chk_step1(ap_at(a, (16 + 16 * (i * w + j - 1) : U32)), w, c, i, j)

def chk_rand(rs: +List<U32>, +n: U32, +w: U32, +c: U32, +acc: U32, q: Array<U32> & U32) -> U32:
  match rs:
    case Con{+r, t}:
      (a, +ok) = q
      chk_rand(t, n, w, c, (acc .&. ok : U32), chk_step(a, w, c, (r % n : U32), (1 + ((r >> 16n) % (w - 1)) : U32)))
    case Nil{}:
      (a, +ok) = q
      (acc .&. ok : U32)

def check_f(p: Array<U32> & Array<U32>, +okh: U32, +w: U32, +n: U32, +c: U32, +gs: +List<V.Pt>, +rs: +List<U32>) -> U32:
  (a1, a2) = p
  (okh .&. chk0(gs, w, 0, 1, ap_at(a1, 16)) .&. chk_rand(rs, n, w, c, 1, (a2, 1)) : U32)

def hchk(r: Array<U32> & U32, +want: U32, +ok: U32) -> Array<U32> & U32:
  (a, +v) = r
  (a, (ok .&. Bool.to_u32(U32.is_eq(v, want)) : U32))

def hdr3(r: Array<U32> & U32, +w: U32) -> Array<U32> & U32:
  (a, +ok) = r
  hchk(a[3], w, ok)

def hdr2(r: Array<U32> & U32, +c: U32, +w: U32) -> Array<U32> & U32:
  (a, +ok) = r
  hdr3(hchk(a[2], c, ok), w)

def hdr1(r: Array<U32> & U32, +n: U32, +c: U32, +w: U32) -> Array<U32> & U32:
  (a, +ok) = r
  hdr2(hchk(a[1], n, ok), c, w)

def check_h(h: Array<U32> & U32, +n: U32, +w: U32, +c: U32, +gs: +List<V.Pt>, +rs: +List<U32>) -> U32:
  (a, +okh) = h
  check_f(Array.fork(U32, a), okh, w, n, c, gs, rs)

# 1 iff the table has the right header for (gs, c), entry (i, 0) = G_i for every i, and the
# entries at the random positions rs are 2^c times their predecessors.
def check(a: Array<U32>, +c: U32, +gs: +List<V.Pt>, +rs: +List<U32>) -> U32:
  +n = U32.from_nat(List.length(&2, V.Pt, gs))
  +w = nwin(c)
  check_h(hdr1(hchk(a[0], magic(), 1), n, c, w), n, w, c, gs, rs)

# --- the fixed-base MSM ------------------------------------------------------------------

def next_ks(wrap: Bool, +k: BA.W9, kt: +List<BA.W9>) -> +List<BA.W9>:
  match wrap:
    case True{}:
      kt
    case False{}:
      k <> kt

# rem terms left; r holds entry (i, j), the term of base i (offset scalar: head of ks) in window j
def fillk(rem: Nat, +w: U32, +c: U32, +i: U32, +j: U32, ks: +List<BA.W9>, b: Array<+List<BA.AP>>, r: Array<U32> & BA.AP) -> Array<+List<BA.AP>>:
  match rem ks:
    case 1n+m Con{+k, kt}:
      (a, +p) = r
      b2 = BA.put(p, BA.digit9(k, j, c), b)
      +j2 = (j + 1 : U32)
      +wrap = U32.is_ge(j2, w)
      +wu = Bool.to_u32(wrap)
      +i3 = (i + wu : U32)
      +j3 = (j2 * (1 - wu) : U32)
      fillk(m, w, c, i3, j3, next_ks(wrap, k, kt), b2, ap_at(a, (16 + 16 * (i3 * w + j3) : U32)))
    case _ _:
      (a, +p) = r
      b

# sum over bases i0 .. i0+cnt-1 of [k_i - H] G_i (ks: the offset scalars of those bases)
def chunk_sum(a: Array<U32>, +w: U32, +c: U32, +i0: U32, +ks: +List<BA.W9>, +cnt: Nat) -> V.Pt:
  +rem = Nat.mul(cnt, U32.to_nat(w))
  +bs = BA.flat(fillk(rem, w, c, i0, 0, ks, BA.empty(U32.to_nat((c - 1 : U32))), ap_at(a, (16 + 16 * i0 * w : U32))), Nil{})
  +summed = BA.rounds(32n, BA.small(bs), bs)
  BA.rs_acc(BA.reduce(List.reverse(&2, +List<BA.AP>, summed), BA.RS{V.identity(), V.identity()}))

def gpar(+fuel: Nat, +w: U32, +c: U32, +i0: U32, +ks: +List<BA.W9>, +cnt: Nat, +tasks: Nat, p: Array<U32> & Array<U32>) -> V.Pt:
  match fuel tasks:
    case 1n+f 1n+1n+_:
      (a1, a2) = p
      +th = Nat.div(tasks, 2n)
      +h = Nat.div(Nat.mul(cnt, th), tasks)
      x y = gpar(f, w, c, i0, List.take(&2, BA.W9, ks, h), h, th, Array.fork(U32, a1)) gpar(f, w, c, (i0 + U32.from_nat(h) : U32), List.drop(&2, BA.W9, ks, h), Nat.sub(cnt, h), Nat.sub(tasks, th), Array.fork(U32, a2))
      VL.add(x, y)
    case _ _:
      (a1, a2) = p
      chunk_sum(a1, w, c, i0, ks, cnt)

# sum_i [s_i] G_i over the table's n bases (ss canonical, < 2^255), in `tasks` parallel chunks
def msm(a: Array<U32>, +c: U32, +ss: +List<Wd.W>, +tasks: Nat) -> V.Pt:
  +ks = BA.offset_all(ss, BA.hconst(c))
  gpar(16n, nwin(c), c, 0, ks, List.length(&2, BA.W9, ks), tasks, Array.fork(U32, a))
