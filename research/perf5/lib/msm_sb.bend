# Sorted-bucket, batch-affine, signed-digit Pippenger MSM on Vesta, on flat arrays.
#
# Same group result as msm_ba.msm9 (carry-free signed c-bit digits, 2^(c-1) buckets per window),
# but no lists in the hot loops:
#   * the bases (affine, identity bases dropped) live in one flat Array<V.Aff> (16 words each),
#     the offset scalars k + H (msm_ba.W9) in a flat Array<U32> (16 words each);
#   * per window, terms are counting-sorted by bucket digit: a count pass, a prefix pass, and a
#     scatter pass that copies the signed point into its bucket's contiguous segment of `tmp`;
#   * each level of the bucket trees adds adjacent pairs of every segment in place, with one
#     shared field inversion per level (Montgomery's trick: prefix products and denominators in
#     the flat array `sc`, a backward pass turns them into inverses, a forward pass adds);
#   * buckets are reduced by running sums; windows are combined with doublings, in parallel.
# The identity is stored as x with top limb 0xFFFFFFFF (canonical field elements are < 2^255).
# Pairs with an identity member, or with equal x (P + P, P + (-P)), skip the shared inversion
# and use the complete projective formulas (msm_ba.psum's fallback), so every input is exact.
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ../../../crypto/field3/fq64.bend as B
import ../../../crypto/field3/lib64/vesta.bend as V
import ./vesta_lz.bend as VL
import ./msm_ba.bend as BA

# --- points with the identity sentinel -------------------------------------------------

def top() -> U32:
  4294967295

def idp() -> V.Aff:
  V.Aff{B.Fq{0, 0, 0, 0, 0, 0, 0, top()}, B.zero()}

def is_id(+x: B.Fq) -> Bool:
  B.Fq{_, _, _, _, _, _, _, +l7} = x
  U32.is_eq(l7, top())

def of_ap(+a: BA.AP) -> V.Aff:
  match a:
    case BA.AP{+x, +y}:
      V.Aff{x, y}
    case BA.ANone{}:
      idp()

def of_b(b: Bool, +x: B.Fq, +y: B.Fq) -> BA.AP:
  match b:
    case True{}:
      BA.ANone{}
    case False{}:
      BA.AP{x, y}

def to_ap(+p: V.Aff) -> BA.AP:
  V.Aff{+x, +y} = p
  of_b(is_id(x), x, y)

def neg_if(b: Bool, +p: V.Aff) -> V.Aff:
  match b:
    case True{}:
      V.Aff{+x, +y} = p
      V.Aff{x, B.neg(y)}
    case False{}:
      p

# Pair kind: 0 = affine add with the shared inversion; 1 = anything else (identity, equal x).
def kind(+a: V.Aff, +b: V.Aff) -> U32:
  V.Aff{+x1, _} = a
  V.Aff{+x2, _} = b
  Bool.to_u32(Bool.or(Bool.or(is_id(x1), is_id(x2)), B.is_eq(x1, x2)))

def den_k(+k: U32, +a: V.Aff, +b: V.Aff) -> B.Fq:
  V.Aff{+x1, _} = a
  V.Aff{+x2, _} = b
  B.sel(k, B.one(), B.sub(x2, x1))

def add_k(k: Nat, +a: V.Aff, +b: V.Aff, +inv: B.Fq) -> V.Aff:
  match k:
    case 0n:
      V.Aff{+x1, +y1} = a
      V.Aff{+x2, +y2} = b
      +lam = B.mul(B.sub(y2, y1), inv)
      +x3 = B.sub(B.sub(B.sqr(lam), x1), x2)
      V.Aff{x3, B.sub(B.mul(lam, B.sub(x1, x3)), y1)}
    case _:
      of_ap(BA.psum(to_ap(a), to_ap(b), B.one()))


# --- digits ------------------------------------------------------------------------------

# Window digit code of a term: 2 m + neg, m in [0, 2^(c-1)]. u = the c bits of k' at (wi, sh).
def code(b: Bool, +u: U32, +half: U32) -> U32:
  match b:
    case True{}:
      ((u - half : U32) * 2 : U32)
    case False{}:
      ((half - u : U32) * 2 + 1 : U32)

def digit2(r: Array<U32> & U32, +lo: U32, +sh: U32, +mask: U32, +half: U32) -> Array<U32> & U32:
  (ks, +hi) = r
  +u = (U32.or((lo >> U32.to_nat(sh) : U32), BA.hi_part(U32.is_eq(sh, 0), hi, sh)) .&. mask : U32)
  (ks, code(U32.is_ge(u, half), u, half))

def digit1(r: Array<U32> & U32, +o: U32, +sh: U32, +mask: U32, +half: U32) -> Array<U32> & U32:
  (ks, +lo) = r
  digit2(ks[(o + 1 : U32)], lo, sh, mask, half)

def digit(ks: Array<U32>, +o: U32, +sh: U32, +mask: U32, +half: U32) -> Array<U32> & U32:
  digit1(ks[o], o, sh, mask, half)

# --- pass 1: digits and bucket counts ----------------------------------------------------
# cn: [m] bucket length, [h2 + m] segment start, [2 h2 + m] scatter cursor (h2 = 2^c > half).

type CW is Type:
  CW{i: U32, ks: Array<U32>, dg: Array<U32>, cn: Array<U32>}

def cnt_c(r: Array<U32> & U32, +m: U32, +i: U32, ks: Array<U32>, dg: Array<U32>) -> CW:
  (cn, +l) = r
  cn[m] <- (l + 1 : U32)
  CW{(i + 1 : U32), ks, dg, cn}

def cnt_d(r: Array<U32> & U32, +i: U32, dg: Array<U32>, cn: Array<U32>) -> CW:
  (ks, +e) = r
  dg[i] <- e
  +m = (e >> 1n : U32)
  cnt_c(cn[m], m, i, ks, dg)

def cnt_step(r: CW, +wi: U32, +sh: U32, +mask: U32, +half: U32) -> CW:
  CW{+i, ks, dg, cn} = r
  cnt_d(digit(ks, (i * 16 + wi : U32), sh, mask, half), i, dg, cn)

def count(fuel: Nat, r: CW, +wi: U32, +sh: U32, +mask: U32, +half: U32) -> CW:
  match fuel:
    case 1n+f:
      count(f, cnt_step(r, wi, sh, mask, half), wi, sh, mask, half)
    case 0n:
      r

# --- pass 2: segment starts (bucket 1 first), cursors, the largest bucket ------------------

type ST is Type:
  ST{m: U32, acc: U32, mx: U32, cn: Array<U32>}

def st_l(r: Array<U32> & U32, +m: U32, +h2: U32, +acc: U32, +mx: U32) -> ST:
  (cn, +l) = r
  cn[(h2 + m : U32)] <- acc
  cn[(h2 + h2 + m : U32)] <- acc
  ST{(m + 1 : U32), (acc + l : U32), U32.max(mx, l), cn}

def st_step(r: ST, +h2: U32) -> ST:
  ST{+m, +acc, +mx, cn} = r
  st_l(cn[m], m, h2, acc, mx)

def starts(fuel: Nat, r: ST, +h2: U32) -> ST:
  match fuel:
    case 1n+f:
      starts(f, st_step(r, h2), h2)
    case 0n:
      r

# --- pass 3: every term with a non-zero digit, signed, into its bucket's segment -------------

type XS is Type:
  XS{i: U32, dg: Array<U32>, cn: Array<U32>, pts: Array<V.Aff>, tmp: Array<V.Aff>}

def sc_q(r: Array<V.Aff> & V.Aff, +pos: U32, +i: U32, +e: U32, dg: Array<U32>, cn: Array<U32>, tmp: Array<V.Aff>) -> XS:
  (pts, +p) = r
  tmp = Array.set(V.Aff, tmp, pos, neg_if(U32.is_eq((e .&. 1 : U32), 1), p))
  XS{(i + 1 : U32), dg, cn, pts, tmp}

def sc_p(r: Array<U32> & U32, +k: U32, +i: U32, +e: U32, dg: Array<U32>, pts: Array<V.Aff>, tmp: Array<V.Aff>) -> XS:
  (cn, +pos) = r
  cn[k] <- (pos + 1 : U32)
  sc_q(Array.get(V.Aff, pts, i), pos, i, e, dg, cn, tmp)

def sc_m(z: Bool, +i: U32, +e: U32, +h22: U32, dg: Array<U32>, cn: Array<U32>, pts: Array<V.Aff>, tmp: Array<V.Aff>) -> XS:
  match z:
    case True{}:
      XS{(i + 1 : U32), dg, cn, pts, tmp}
    case False{}:
      +k = (h22 + (e >> 1n) : U32)
      sc_p(cn[k], k, i, e, dg, pts, tmp)

def sc_e(r: Array<U32> & U32, +i: U32, +h22: U32, cn: Array<U32>, pts: Array<V.Aff>, tmp: Array<V.Aff>) -> XS:
  (dg, +e) = r
  sc_m(U32.is_lt(e, 2), i, e, h22, dg, cn, pts, tmp)

def sc_step(r: XS, +h22: U32) -> XS:
  XS{+i, dg, cn, pts, tmp} = r
  sc_e(dg[i], i, h22, cn, pts, tmp)

def scatter(fuel: Nat, r: XS, +h22: U32) -> XS:
  match fuel:
    case 1n+f:
      scatter(f, sc_step(r, h22), h22)
    case 0n:
      r

# --- one level of the bucket trees ------------------------------------------------------
# LV: bucket m (segment start s, length l), pair k, pair counter t, prefix product acc, the
# largest new bucket length mx.

type LV is Type:
  LV{m: U32, s: U32, l: U32, k: U32, t: U32, acc: B.Fq, mx: U32, cn: Array<U32>, tmp: Array<V.Aff>, sc: Array<V.Aff>}

def lv_s(r: Array<U32> & U32, +m: U32, +l: U32, +t: U32, +acc: B.Fq, +mx: U32, tmp: Array<V.Aff>, sc: Array<V.Aff>) -> LV:
  (cn, +s) = r
  LV{m, s, l, 0, t, acc, mx, cn, tmp, sc}

def lv_l(r: Array<U32> & U32, +m: U32, +h2: U32, +t: U32, +acc: B.Fq, +mx: U32, tmp: Array<V.Aff>, sc: Array<V.Aff>) -> LV:
  (cn, +l) = r
  lv_s(cn[(h2 + m : U32)], m, l, t, acc, mx, tmp, sc)

# load bucket m's length and start into the state
def lv_open(r: LV, +h2: U32) -> LV:
  LV{+m, _, _, _, +t, +acc, +mx, cn, tmp, sc} = r
  lv_l(cn[m], m, h2, t, acc, mx, tmp, sc)

def lv_np(r: LV) -> LV & Nat:
  LV{+m, +s, +l, +k, +t, +acc, +mx, cn, tmp, sc} = r
  (LV{m, s, l, k, t, acc, mx, cn, tmp, sc}, U32.to_nat((l >> 1n : U32)))

# pass A, one pair: sc[t] = (d_0 ... d_(t-1), d_t)
def pa_b(r: Array<V.Aff> & V.Aff, +a: V.Aff, +m: U32, +s: U32, +l: U32, +k: U32, +t: U32, +acc: B.Fq, +mx: U32, cn: Array<U32>, sc: Array<V.Aff>) -> LV:
  (tmp, +b) = r
  +d = den_k(kind(a, b), a, b)
  sc = Array.set(V.Aff, sc, t, V.Aff{acc, d})
  LV{m, s, l, (k + 1 : U32), (t + 1 : U32), B.mul(acc, d), mx, cn, tmp, sc}

def pa_a(r: Array<V.Aff> & V.Aff, +o: U32, +m: U32, +s: U32, +l: U32, +k: U32, +t: U32, +acc: B.Fq, +mx: U32, cn: Array<U32>, sc: Array<V.Aff>) -> LV:
  (tmp, +a) = r
  pa_b(Array.get(V.Aff, tmp, (o + 1 : U32)), a, m, s, l, k, t, acc, mx, cn, sc)

def pa_step(r: LV) -> LV:
  LV{+m, +s, +l, +k, +t, +acc, +mx, cn, tmp, sc} = r
  +o = (s + k + k : U32)
  pa_a(Array.get(V.Aff, tmp, o), o, m, s, l, k, t, acc, mx, cn, sc)

def pa_pairs(fuel: Nat, r: LV) -> LV:
  match fuel:
    case 1n+f:
      pa_pairs(f, pa_step(r))
    case 0n:
      r

def pa_go(p: LV & Nat) -> LV:
  (r, +np) = p
  pa_pairs(np, r)

def lv_next(r: LV) -> LV:
  LV{+m, +s, +l, +k, +t, +acc, +mx, cn, tmp, sc} = r
  LV{(m + 1 : U32), s, l, k, t, acc, mx, cn, tmp, sc}

def pa_bk(fuel: Nat, r: LV, +h2: U32) -> LV:
  match fuel:
    case 1n+f:
      pa_bk(f, lv_next(pa_go(lv_np(lv_open(r, h2)))), h2)
    case 0n:
      r

# pass B (backward): sc[t].x = d_t^-1; inv enters as (d_0 ... d_t)^-1
type PB is Type:
  PB{t: U32, inv: B.Fq, sc: Array<V.Aff>}

def pb_q(r: Array<V.Aff> & V.Aff, +t: U32, +inv: B.Fq) -> PB:
  (sc, +q) = r
  V.Aff{+pre, +d} = q
  sc = Array.set(V.Aff, sc, t, V.Aff{B.mul(inv, pre), d})
  PB{(t - 1 : U32), B.mul(inv, d), sc}

def pb_step(r: PB) -> PB:
  PB{+t, +inv, sc} = r
  pb_q(Array.get(V.Aff, sc, t), t, inv)

def pb(fuel: Nat, r: PB) -> PB:
  match fuel:
    case 1n+f:
      pb(f, pb_step(r))
    case 0n:
      r

def pb_sc(r: PB) -> Array<V.Aff>:
  PB{_, _, sc} = r
  sc

def inv_of(+q: V.Aff) -> B.Fq:
  V.Aff{+x, _} = q
  x

# pass C, one pair: pair k of the segment at s becomes element s + k (in place, s + k <= s + 2 k)
def pc_q(r: Array<V.Aff> & V.Aff, +a: V.Aff, +b: V.Aff, +m: U32, +s: U32, +l: U32, +k: U32, +t: U32, +acc: B.Fq, +mx: U32, cn: Array<U32>, tmp: Array<V.Aff>) -> LV:
  (sc, +q) = r
  tmp = Array.set(V.Aff, tmp, (s + k : U32), add_k(U32.to_nat(kind(a, b)), a, b, inv_of(q)))
  LV{m, s, l, (k + 1 : U32), (t + 1 : U32), acc, mx, cn, tmp, sc}

def pc_b(r: Array<V.Aff> & V.Aff, +a: V.Aff, +m: U32, +s: U32, +l: U32, +k: U32, +t: U32, +acc: B.Fq, +mx: U32, cn: Array<U32>, sc: Array<V.Aff>) -> LV:
  (tmp, +b) = r
  pc_q(Array.get(V.Aff, sc, t), a, b, m, s, l, k, t, acc, mx, cn, tmp)

def pc_a(r: Array<V.Aff> & V.Aff, +o: U32, +m: U32, +s: U32, +l: U32, +k: U32, +t: U32, +acc: B.Fq, +mx: U32, cn: Array<U32>, sc: Array<V.Aff>) -> LV:
  (tmp, +a) = r
  pc_b(Array.get(V.Aff, tmp, (o + 1 : U32)), a, m, s, l, k, t, acc, mx, cn, sc)

def pc_step(r: LV) -> LV:
  LV{+m, +s, +l, +k, +t, +acc, +mx, cn, tmp, sc} = r
  +o = (s + k + k : U32)
  pc_a(Array.get(V.Aff, tmp, o), o, m, s, l, k, t, acc, mx, cn, sc)

def pc_pairs(fuel: Nat, r: LV) -> LV:
  match fuel:
    case 1n+f:
      pc_pairs(f, pc_step(r))
    case 0n:
      r

def pc_go(p: LV & Nat) -> LV:
  (r, +np) = p
  pc_pairs(np, r)

def pc_o(r: Array<V.Aff> & V.Aff, +dst: U32, +m: U32, +s: U32, +l: U32, +k: U32, +t: U32, +acc: B.Fq, +mx: U32, cn: Array<U32>, sc: Array<V.Aff>) -> LV:
  (tmp, +p) = r
  tmp = Array.set(V.Aff, tmp, dst, p)
  LV{m, s, l, k, t, acc, mx, cn, tmp, sc}

def pc_odd(odd: Bool, +m: U32, +s: U32, +l: U32, +k: U32, +t: U32, +acc: B.Fq, +mx: U32, cn: Array<U32>, tmp: Array<V.Aff>, sc: Array<V.Aff>) -> LV:
  match odd:
    case True{}:
      pc_o(Array.get(V.Aff, tmp, (s + l - 1 : U32)), (s + k : U32), m, s, l, k, t, acc, mx, cn, sc)
    case False{}:
      LV{m, s, l, k, t, acc, mx, cn, tmp, sc}

# after bucket m's pairs (k = l / 2): carry an odd element, store the new length, next bucket
def pc_close(r: LV) -> LV:
  LV{+m, +s, +l, +k, +t, +acc, +mx, cn, tmp, sc} = r
  +l2 = (l - k : U32)
  cn[m] <- l2
  lv_next(pc_odd(U32.is_eq((l .&. 1 : U32), 1), m, s, l, k, t, acc, U32.max(mx, l2), cn, tmp, sc))

def pc_bk(fuel: Nat, r: LV, +h2: U32) -> LV:
  match fuel:
    case 1n+f:
      pc_bk(f, pc_close(pc_go(lv_np(lv_open(r, h2)))), h2)
    case 0n:
      r

# --- levels ---------------------------------------------------------------------------------

type LC is Type:
  LC{mx: U32, cn: Array<U32>, tmp: Array<V.Aff>, sc: Array<V.Aff>}

def lv_fin(r: LV) -> LC:
  LV{_, _, _, _, _, _, +mx, cn, tmp, sc} = r
  LC{mx, cn, tmp, sc}

def lv_bc(r: LV, +half: U32, +h2: U32) -> LC:
  LV{_, _, _, _, +t, +acc, _, cn, tmp, sc} = r
  sc2 = pb_sc(pb(U32.to_nat(t), PB{(t - 1 : U32), B.inv(acc), sc}))
  lv_fin(pc_bk(U32.to_nat(half), LV{1, 0, 0, 0, 0, B.one(), 0, cn, tmp, sc2}, h2))

def level(more: Bool, r: LC, +half: U32, +h2: U32) -> LC:
  match more:
    case True{}:
      LC{_, cn, tmp, sc} = r
      lv_bc(pa_bk(U32.to_nat(half), LV{1, 0, 0, 0, 0, B.one(), 0, cn, tmp, sc}, h2), half, h2)
    case False{}:
      r

def lc_more(r: LC) -> LC & Bool:
  LC{+mx, cn, tmp, sc} = r
  (LC{mx, cn, tmp, sc}, U32.is_gt(mx, 1))

def level_p(p: LC & Bool, +half: U32, +h2: U32) -> LC:
  (r, more) = p
  level(more, r, half, h2)

def levels(fuel: Nat, r: LC, +half: U32, +h2: U32) -> LC:
  match fuel:
    case 1n+f:
      levels(f, level_p(lc_more(r), half, h2), half, h2)
    case 0n:
      r

# --- bucket reduction ----------------------------------------------------------------------

type RD is Type:
  RD{m: U32, run: V.Pt, acc: V.Pt, cn: Array<U32>, tmp: Array<V.Aff>}

def add_one_b(b: Bool, +run: V.Pt, +p: V.Aff) -> V.Pt:
  match b:
    case True{}:
      run
    case False{}:
      VL.add_aff(run, p)

def add_one(+run: V.Pt, +p: V.Aff) -> V.Pt:
  V.Aff{+x, _} = p
  add_one_b(is_id(x), run, p)

def rd_n(+m: U32, +r2: V.Pt, +acc: V.Pt, cn: Array<U32>, tmp: Array<V.Aff>) -> RD:
  RD{(m - 1 : U32), r2, VL.add(acc, r2), cn, tmp}

def rd_p(r: Array<V.Aff> & V.Aff, +m: U32, +run: V.Pt, +acc: V.Pt, cn: Array<U32>) -> RD:
  (tmp, +p) = r
  rd_n(m, add_one(run, p), acc, cn, tmp)

def rd_s(one: Bool, r: Array<U32> & U32, +m: U32, +run: V.Pt, +acc: V.Pt, tmp: Array<V.Aff>) -> RD:
  match one:
    case True{}:
      (cn, +s) = r
      rd_p(Array.get(V.Aff, tmp, s), m, run, acc, cn)
    case False{}:
      (cn, _) = r
      rd_n(m, run, acc, cn, tmp)

def rd_l(r: Array<U32> & U32, +m: U32, +h2: U32, +run: V.Pt, +acc: V.Pt, tmp: Array<V.Aff>) -> RD:
  (cn, +l) = r
  rd_s(U32.is_eq(l, 1), cn[(h2 + m : U32)], m, run, acc, tmp)

def rd_step(r: RD, +h2: U32) -> RD:
  RD{+m, +run, +acc, cn, tmp} = r
  rd_l(cn[m], m, h2, run, acc, tmp)

# buckets from the top digit down: run = suffix sum, acc = sum_m m B_m
def reduce(fuel: Nat, r: RD, +h2: U32) -> RD:
  match fuel:
    case 1n+f:
      reduce(f, rd_step(r, h2), h2)
    case 0n:
      r

def rd_acc(r: RD) -> V.Pt:
  RD{_, _, +acc, _, _} = r
  acc

# --- bucket reduction by rows and columns ---------------------------------------------------
# With m = i L + j (L = 2^a, 0 <= j < L, 0 <= i <= H = half / L):
#     sum_m m B_m = L sum_i i R_i + sum_j j C_j,   R_i = sum_j B_(i L + j),  C_j = sum_i B_(i L + j).
# Every bucket goes into one row and one column segment of rc (empty slots hold the identity);
# the segments are summed by the same batch-affine levels as the buckets, and only the two short
# running sums (H and L - 1 terms) use projective additions, instead of 2 per bucket.

type RF is Type:
  RF{m: U32, cn: Array<U32>, tmp: Array<V.Aff>, rc: Array<V.Aff>}

def rf_p(r: Array<V.Aff> & V.Aff, +m: U32, +a: U32, +lm: U32, +hh1: U32, +base: U32, cn: Array<U32>, rc: Array<V.Aff>) -> RF:
  (tmp, +p) = r
  rc = Array.set(V.Aff, rc, m, p)
  rc = Array.set(V.Aff, rc, (base + (m .&. lm) * hh1 + (m >> U32.to_nat(a)) : U32), p)
  RF{(m + 1 : U32), cn, tmp, rc}

def rf_s(one: Bool, r: Array<U32> & U32, +m: U32, +a: U32, +lm: U32, +hh1: U32, +base: U32, tmp: Array<V.Aff>, rc: Array<V.Aff>) -> RF:
  match one:
    case True{}:
      (cn, +s) = r
      rf_p(Array.get(V.Aff, tmp, s), m, a, lm, hh1, base, cn, rc)
    case False{}:
      (cn, _) = r
      RF{(m + 1 : U32), cn, tmp, rc}

def rf_l(r: Array<U32> & U32, +m: U32, +h2: U32, +a: U32, +lm: U32, +hh1: U32, +base: U32, tmp: Array<V.Aff>, rc: Array<V.Aff>) -> RF:
  (cn, +l) = r
  rf_s(U32.is_eq(l, 1), cn[(h2 + m : U32)], m, a, lm, hh1, base, tmp, rc)

def rf_step(r: RF, +h2: U32, +a: U32, +lm: U32, +hh1: U32, +base: U32) -> RF:
  RF{+m, cn, tmp, rc} = r
  rf_l(cn[m], m, h2, a, lm, hh1, base, tmp, rc)

def rfill(fuel: Nat, r: RF, +h2: U32, +a: U32, +lm: U32, +hh1: U32, +base: U32) -> RF:
  match fuel:
    case 1n+f:
      rfill(f, rf_step(r, h2, a, lm, hh1, base), h2, a, lm, hh1, base)
    case 0n:
      r

# segments g, g+1, ... of length len, back to back from st
type SG is Type:
  SG{g: U32, st: U32, cn: Array<U32>}

def sg_step(r: SG, +h2: U32, +len: U32) -> SG:
  SG{+g, +st, cn} = r
  cn[g] <- len
  cn[(h2 + g : U32)] <- st
  SG{(g + 1 : U32), (st + len : U32), cn}

def segs(fuel: Nat, r: SG, +h2: U32, +len: U32) -> SG:
  match fuel:
    case 1n+f:
      segs(f, sg_step(r, h2, len), h2, len)
    case 0n:
      r

def sg_cn(r: SG) -> Array<U32>:
  SG{_, _, cn} = r
  cn

type BR is Type:
  BR{p: V.Pt, tmp: Array<V.Aff>}

# rows are segments 1 .. H+1 (weight i = segment - 1), columns H+2 .. H+1+L (j = segment - H - 2)
def red4(r: RD, +a: U32, +hh: U32, +ll: U32, +h2: U32) -> V.Pt:
  RD{_, _, +s1, cn, rc} = r
  VL.add(BA.dbl_n(U32.to_nat(a), s1), rd_acc(reduce(U32.to_nat((ll - 1 : U32)), RD{(hh + ll + 1 : U32), V.identity(), V.identity(), cn, rc}, h2)))

def red3(r: LC, +a: U32, +hh: U32, +ll: U32, +h2: U32) -> V.Pt:
  LC{_, cn, rc, _} = r
  red4(reduce(U32.to_nat(hh), RD{(hh + 1 : U32), V.identity(), V.identity(), cn, rc}, h2), a, hh, ll, h2)

def red2(r: RF, +c: U32, +h2: U32, +a: U32, +ll: U32, +hh: U32) -> BR:
  RF{_, _, tmp, rc} = r
  +lr = Nat.add(U32.to_nat(c), 1n)
  +lc = U32.to_nat(c)
  cn0 = [0 : U32^lr]
  cn1 = sg_cn(segs(U32.to_nat(ll), SG{(hh + 2 : U32), ((hh + 1) * ll : U32), sg_cn(segs(U32.to_nat((hh + 1 : U32)), SG{1, 0, cn0}, h2, ll))}, h2, (hh + 1 : U32)))
  sc2 = [V.Aff{B.zero(), B.zero()} : V.Aff^lc]
  BR{red3(levels(32n, LC{U32.max(ll, (hh + 1 : U32)), cn1, rc, sc2}, (hh + 1 + ll : U32), h2), a, hh, ll, h2), tmp}

# sum_m m B_m over the buckets left by the levels (bucket m: tmp[start] when its length is 1)
def bred(+c: U32, +half: U32, +h2: U32, cn: Array<U32>, tmp: Array<V.Aff>) -> BR:
  +a = ((c - 1 : U32) >> 1n : U32)
  +ll = (1 << U32.to_nat(a) : U32)
  +hh = (half >> U32.to_nat(a) : U32)
  +lr = Nat.add(U32.to_nat(c), 1n)
  rc = [idp() : V.Aff^lr]
  red2(rfill(U32.to_nat(half), RF{1, cn, tmp, rc}, h2, a, (ll - 1 : U32), (hh + 1 : U32), ((hh + 1) * ll : U32)), c, h2, a, ll, hh)

# --- one window ----------------------------------------------------------------------------
# A task runs a range of windows one after another and reuses its scratch arrays (dg, tmp, sc:
# every cell a window reads is written by that window first), so they are allocated and filled
# once per task instead of once per window.

type WR is Type:
  WR{p: V.Pt, ks: Array<U32>, pts: Array<V.Aff>, dg: Array<U32>, tmp: Array<V.Aff>, sc: Array<V.Aff>}

def win5(r: BR, ks: Array<U32>, pts: Array<V.Aff>, dg: Array<U32>, sc: Array<V.Aff>) -> WR:
  BR{+p, tmp} = r
  WR{p, ks, pts, dg, tmp, sc}

def win4(r: LC, +c: U32, +half: U32, +h2: U32, ks: Array<U32>, pts: Array<V.Aff>, dg: Array<U32>) -> WR:
  LC{_, cn, tmp, sc} = r
  win5(bred(c, half, h2, cn, tmp), ks, pts, dg, sc)

def win3(r: XS, +mx: U32, +c: U32, +half: U32, +h2: U32, ks: Array<U32>, sc: Array<V.Aff>) -> WR:
  XS{_, dg, cn, pts, tmp} = r
  win4(levels(32n, LC{mx, cn, tmp, sc}, half, h2), c, half, h2, ks, pts, dg)

def win2(r: ST, dg: Array<U32>, pts: Array<V.Aff>, tmp: Array<V.Aff>, sc: Array<V.Aff>, ks: Array<U32>, +n: U32, +c: U32, +half: U32, +h2: U32) -> WR:
  ST{_, _, +mx, cn} = r
  win3(scatter(U32.to_nat(n), XS{0, dg, cn, pts, tmp}, (h2 + h2 : U32)), mx, c, half, h2, ks, sc)

def win1(r: CW, pts: Array<V.Aff>, tmp: Array<V.Aff>, sc: Array<V.Aff>, +n: U32, +c: U32, +half: U32, +h2: U32) -> WR:
  CW{_, ks, dg, cn} = r
  win2(starts(U32.to_nat(half), ST{1, 0, 0, cn}, h2), dg, pts, tmp, sc, ks, n, c, half, h2)

# sum_m m B_m for window j
def window(+c: U32, +j: U32, +n: U32, ks: Array<U32>, pts: Array<V.Aff>, dg: Array<U32>, tmp: Array<V.Aff>, sc: Array<V.Aff>) -> WR:
  +off = (j * c : U32)
  +half = (1 << U32.to_nat((c - 1 : U32)) : U32)
  +h2 = (1 << U32.to_nat(c) : U32)
  +mask = (h2 - 1 : U32)
  +lc = Nat.add(U32.to_nat(c), 2n)
  cn = [0 : U32^lc]
  win1(count(U32.to_nat(n), CW{0, ks, dg, cn}, (off >> 5n : U32), (off .&. 31 : U32), mask, half), pts, tmp, sc, n, c, half, h2)

# windows j, j-1, ..., by Horner: acc = 2^c acc + S_j
type WQ is Type:
  WQ{j: U32, acc: V.Pt, ks: Array<U32>, pts: Array<V.Aff>, dg: Array<U32>, tmp: Array<V.Aff>, sc: Array<V.Aff>}

def wq_fin(r: WR, +j: U32, +acc: V.Pt, +c: U32) -> WQ:
  WR{+p, ks, pts, dg, tmp, sc} = r
  WQ{(j - 1 : U32), VL.add(BA.dbl_n(U32.to_nat(c), acc), p), ks, pts, dg, tmp, sc}

def wq_step(r: WQ, +c: U32, +n: U32) -> WQ:
  WQ{+j, +acc, ks, pts, dg, tmp, sc} = r
  wq_fin(window(c, j, n, ks, pts, dg, tmp, sc), j, acc, c)

def wseq(fuel: Nat, r: WQ, +c: U32, +n: U32) -> WQ:
  match fuel:
    case 1n+f:
      wseq(f, wq_step(r, c, n), c, n)
    case 0n:
      r

def wq_acc(r: WQ) -> V.Pt:
  WQ{_, +acc, _, _, _, _, _} = r
  acc

# sum_(t < cnt) 2^(c t) S_(lo + t), one task (lg: log2 of the arrays' size, 2^lg >= n)
def wleaf(+c: U32, +n: U32, +lg: Nat, ks: Array<U32>, pts: Array<V.Aff>, +lo: U32, +cnt: U32) -> V.Pt:
  +lgs = Nat.sub(lg, 1n)
  dg = [0 : U32^lg]
  tmp = [idp() : V.Aff^lg]
  sc = [V.Aff{B.zero(), B.zero()} : V.Aff^lgs]
  wq_acc(wseq(U32.to_nat(cnt), WQ{(lo + cnt - 1 : U32), V.identity(), ks, pts, dg, tmp, sc}, c, n))

# windows split in halves (run in parallel) down to at most wpt windows per task
def wrange(+fuel: Nat, one: Bool, +c: U32, +n: U32, +lg: Nat, +wpt: U32, ka: Array<U32> & Array<U32>, pa: Array<V.Aff> & Array<V.Aff>, +lo: U32, +cnt: U32) -> V.Pt:
  match fuel one:
    case 1n+f False{}:
      (k1, k2) = ka
      (p1, p2) = pa
      +h = (cnt >> 1n : U32)
      +h2 = (cnt - h : U32)
      a b = wrange(f, U32.is_le(h, wpt), c, n, lg, wpt, Array.fork(U32, k1), Array.fork(V.Aff, p1), lo, h) wrange(f, U32.is_le(h2, wpt), c, n, lg, wpt, Array.fork(U32, k2), Array.fork(V.Aff, p2), (lo + h : U32), h2)
      VL.add(a, BA.dbl_n(U32.to_nat((h * c : U32)), b))
    case _ _:
      (k1, _) = ka
      (p1, _) = pa
      wleaf(c, n, lg, k1, p1, lo, cnt)

# --- loading a chunk into flat arrays --------------------------------------------------------
# Bases go to pts as they come; a projective base with z != 1 is also queued (zs: the prefix
# product before it and its z; zi: its index in pts) for one shared inversion, then scaled.
# Identity bases (z = 0) are dropped with their scalars. Scalars go to ks as k + H (msm_ba.add9).
type LD is Type:
  LD{ks: Array<U32>, pts: Array<V.Aff>, zs: Array<V.Aff>, zi: Array<U32>, n: U32, q: U32, acc: B.Fq}

def put_k(ks: Array<U32>, +o: U32, +k: BA.W9) -> Array<U32>:
  BA.W9{+w, +hi} = k
  Wd.W{+w0, +w1, +w2, +w3, +w4, +w5, +w6, +w7} = w
  ks[o] <- w0
  ks[(o + 1 : U32)] <- w1
  ks[(o + 2 : U32)] <- w2
  ks[(o + 3 : U32)] <- w3
  ks[(o + 4 : U32)] <- w4
  ks[(o + 5 : U32)] <- w5
  ks[(o + 6 : U32)] <- w6
  ks[(o + 7 : U32)] <- w7
  ks[(o + 8 : U32)] <- hi
  ks

# 0: identity (z = 0), 1: affine (z = 1), 2: z to invert
def zkind(+z: B.Fq) -> U32:
  (2 - B.eq(z, B.zero()) - B.eq(z, B.zero()) - B.eq(z, B.one()) : U32)

def load_k(+zk: U32, +x: B.Fq, +y: B.Fq, +z: B.Fq, +k: BA.W9, r: LD) -> LD:
  match zk:
    case 0:
      r
    case 1:
      LD{ks, pts, zs, zi, +n, +q, +acc} = r
      pts = Array.set(V.Aff, pts, n, V.Aff{x, y})
      LD{put_k(ks, (n * 16 : U32), k), pts, zs, zi, (n + 1 : U32), q, acc}
    case _:
      LD{ks, pts, zs, zi, +n, +q, +acc} = r
      pts = Array.set(V.Aff, pts, n, V.Aff{x, y})
      zs = Array.set(V.Aff, zs, q, V.Aff{acc, z})
      zi[q] <- n
      LD{put_k(ks, (n * 16 : U32), k), pts, zs, zi, (n + 1 : U32), (q + 1 : U32), B.mul(acc, z)}

def load_pt(+p: V.Pt, +k: BA.W9, r: LD) -> LD:
  V.Pt{+x, +y, +z} = p
  load_k(zkind(z), x, y, z, k, r)

def load(ps: +List<V.Pt>, ss: +List<Wd.W>, +h: BA.W9, r: LD) -> LD:
  match ps ss:
    case Con{+p, pt} Con{+s, st}:
      load(pt, st, h, load_pt(p, BA.add9(s, h), r))
    case _ _:
      r

# backward over the queue: zinv_t = inv * (z_0 ... z_(t-1)), then inv *= z_t
type NZ is Type:
  NZ{t: U32, inv: B.Fq, pts: Array<V.Aff>, zs: Array<V.Aff>, zi: Array<U32>}

def nz_p(r: Array<V.Aff> & V.Aff, +i: U32, +zinv: B.Fq) -> Array<V.Aff>:
  (pts, +p) = r
  V.Aff{+x, +y} = p
  Array.set(V.Aff, pts, i, V.Aff{B.mul(x, zinv), B.mul(y, zinv)})

def nz_i(r: Array<U32> & U32, +t: U32, +inv: B.Fq, +pre: B.Fq, +z: B.Fq, pts: Array<V.Aff>, zs: Array<V.Aff>) -> NZ:
  (zi, +i) = r
  NZ{(t - 1 : U32), B.mul(inv, z), nz_p(Array.get(V.Aff, pts, i), i, B.mul(inv, pre)), zs, zi}

def nz_q(r: Array<V.Aff> & V.Aff, +t: U32, +inv: B.Fq, pts: Array<V.Aff>, zi: Array<U32>) -> NZ:
  (zs, +e) = r
  V.Aff{+pre, +z} = e
  nz_i(zi[t], t, inv, pre, z, pts, zs)

def nz_step(r: NZ) -> NZ:
  NZ{+t, +inv, pts, zs, zi} = r
  nz_q(Array.get(V.Aff, zs, t), t, inv, pts, zi)

def nz(fuel: Nat, r: NZ) -> NZ:
  match fuel:
    case 1n+f:
      nz(f, nz_step(r))
    case 0n:
      r

def nz_pts(r: NZ) -> Array<V.Aff>:
  NZ{_, _, pts, _, _} = r
  pts

def run(r: LD, +c: U32, +lg: Nat, +wpt: U32) -> V.Pt:
  LD{ks, pts, zs, zi, +n, +q, +acc} = r
  pts2 = nz_pts(nz(U32.to_nat(q), NZ{(q - 1 : U32), B.inv(acc), pts, zs, zi}))
  +nw = BA.windows9(c)
  wrange(9n, U32.is_le(nw, wpt), c, n, lg, wpt, Array.fork(U32, ks), Array.fork(V.Aff, pts2), 0, nw)

# sum_i [s_i] P_i (scalars canonical, < 2^255), carry-free signed c-bit windows (c in 4..16),
# windows in parallel.
def msm9w(+c: U32, +wpt: U32, +ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  +len = U32.from_nat(List.length(&2, V.Pt, ps))
  +lg = Nat.add(U32.log2((U32.max(len, 2) - 1 : U32)), 1n)
  +lk = Nat.add(lg, 4n)
  ks = [0 : U32^lk]
  pts = [idp() : V.Aff^lg]
  zs = [idp() : V.Aff^lg]
  zi = [0 : U32^lg]
  run(load(ps, ss, BA.hconst(c), LD{ks, pts, zs, zi, 0, 0, B.one()}), c, lg, wpt)

# One window per task: on 18 threads the extra tasks pay more than reusing the scratch arrays
# (2 windows per task: 1T final -3%, 18T final +10..20%).
def msm9(+c: U32, +ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  msm9w(c, 1, ps, ss)

# --- chunks ---------------------------------------------------------------------------------

def mpar(+fuel: Nat, +cnt: Nat, +len: Nat, +c: U32, +ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  match fuel cnt:
    case 1n+f 1n+1n+_:
      +h = Nat.div(cnt, 2n)
      +m = Nat.div(Nat.mul(len, h), cnt)
      a b = mpar(f, h, m, c, List.take(&2, V.Pt, ps, m), List.take(&2, Wd.W, ss, m)) mpar(f, Nat.sub(cnt, h), Nat.sub(len, m), c, List.drop(&2, V.Pt, ps, m), List.drop(&2, Wd.W, ss, m))
      VL.add(a, b)
    case _ _:
      msm9(c, ps, ss)

def msm_par(+c: U32, +cnt: Nat, +ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  mpar(16n, cnt, List.length(&2, V.Pt, ps), c, ps, ss)

# Window width and chunk count by the number of terms (M5 Max, 1 thread, t/msm_main mode 10).
# Per-term cost FALLS with n here (flat buckets stay cheap as they grow, and the per-window
# bucket reduction is amortised over more terms): n = 65,536 is best at c = 13, 262,144 at
# c = 15 (880 ms as one chunk vs 987 ms as 4 chunks of 65,536). Chunks only bound memory.
def chunk_terms() -> Nat:
  262144n

def sel_u(b: Bool, +x: U32, +y: U32) -> U32:
  match b:
    case True{}:
      x
    case False{}:
      y

def pick_c(+m: Nat) -> U32:
  sel_u(Nat.is_lt(m, 256n), 6, sel_u(Nat.is_lt(m, 1024n), 7, sel_u(Nat.is_lt(m, 3072n), 9, sel_u(Nat.is_lt(m, 12288n), 10, sel_u(Nat.is_lt(m, 24000n), 11, sel_u(Nat.is_lt(m, 40000n), 12, sel_u(Nat.is_lt(m, 150000n), 13, sel_u(Nat.is_lt(m, 220000n), 14, 15))))))))

def msm_auto(+ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  +n = List.length(&2, V.Pt, ps)
  +cnt = Nat.max(1n, Nat.div(Nat.add(n, Nat.sub(chunk_terms(), 1n)), chunk_terms()))
  mpar(32n, cnt, n, pick_c(Nat.div(n, cnt)), ps, ss)
