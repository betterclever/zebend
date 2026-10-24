# Signed-digit, batch-affine Pippenger MSM on Vesta: sum_i [s_i] P_i.
#
# 1. Points are normalised to affine with one shared inversion (identity bases drop out).
# 2. Scalars (canonical, < 2^255) get signed c-bit digits in [-2^(c-1), 2^(c-1)], so each
#    window needs only 2^(c-1) buckets. `msm9` uses carry-free recoding (k + H, see below) so
#    every window computes its own digits; `msm` recodes with carries up front.
# 3. Per window, every term goes into bucket |d| (negated when d < 0). Each bucket is
#    summed by a balanced tree of affine additions; all additions of one tree level,
#    across all buckets of the window, share a single field inversion (Montgomery's trick).
#    Pairs with equal x (P = Q or P = -Q) skip the inversion and use the complete
#    projective formulas, so every input is handled.
# 4. Buckets are reduced by running sums; windows are combined by a balanced fork-join.
#
# Field-agnostic: only the aliases B (base field) and V (curve) name the field.
import Base
import ../../halo2/lib/words.bend as Wd
import ../intrinsics.bend as I
import ../fq32.bend as B
import ../lib32/vesta.bend as V

# --- affine points with a "none" (identity) case ----------------------------------

type AP is Data:
  ANone{}
  AP{x: B.Fq, y: B.Fq}

def ap_neg(a: AP) -> AP:
  match a:
    case AP{x, y}:
      AP{x, B.neg(y)}
    case ANone{}:
      ANone{}

def ap_to_pt(a: AP) -> V.Pt:
  match a:
    case AP{x, y}:
      V.Pt{x, y, B.one()}
    case ANone{}:
      V.identity()

# --- batch inversion ---------------------------------------------------------------

# Prefix products, newest first: [c_k, ..., c_0] with c_i = a_0 ... a_i.
def prefix(xs: +List<B.Fq>, +acc: B.Fq, out: +List<B.Fq>) -> +List<B.Fq>:
  match xs:
    case Con{x, t}:
      +c = B.mul(acc, x)
      prefix(t, c, c <> out)
    case Nil{}:
      out

# Walk back: inv = (a_0 ... a_i)^-1; a_i^-1 = inv * c_(i-1); then inv *= a_i.
def back(rx: +List<B.Fq>, rc: +List<B.Fq>, +inv: B.Fq, out: +List<B.Fq>) -> +List<B.Fq>:
  match rx rc:
    case Con{+x, xt} Con{_, Con{+cprev, ct}}:
      back(xt, cprev <> ct, B.mul(inv, x), B.mul(inv, cprev) <> out)
    case Con{_, _} Con{_, Nil{}}:
      inv <> out
    case _ _:
      out

def top_or_one(cs: +List<B.Fq>) -> B.Fq:
  match cs:
    case Con{c, _}:
      c
    case Nil{}:
      B.one()

# Inverses of a list of non-zero elements, same order, one field inversion.
def batch_inv(+xs: +List<B.Fq>) -> +List<B.Fq>:
  +cs = prefix(xs, B.one(), Nil{})
  back(List.reverse(&2, B.Fq, xs), cs, B.inv(top_or_one(cs)), Nil{})

# --- normalising the bases -----------------------------------------------------------

def z_or_one(+p: V.Pt) -> B.Fq:
  V.Pt{_, _, z} = p
  B.sel(B.eq(z, B.zero()), B.one(), z)

def zs(ps: +List<V.Pt>) -> +List<B.Fq>:
  match ps:
    case Con{+p, t}:
      z_or_one(p) <> zs(t)
    case Nil{}:
      Nil{}

def norm_b(b: Bool, +x: B.Fq, +y: B.Fq, +zi: B.Fq) -> AP:
  match b:
    case True{}:
      ANone{}
    case False{}:
      AP{B.mul(x, zi), B.mul(y, zi)}

def norm1(+p: V.Pt, +zi: B.Fq) -> AP:
  V.Pt{+x, +y, +z} = p
  norm_b(B.is_zero(z), x, y, zi)

def norm_go(ps: +List<V.Pt>, zinv: +List<B.Fq>) -> +List<AP>:
  match ps zinv:
    case Con{+p, pt} Con{+zi, it}:
      norm1(p, zi) <> norm_go(pt, it)
    case _ _:
      Nil{}

def normalize(+ps: +List<V.Pt>) -> +List<AP>:
  norm_go(ps, batch_inv(zs(ps)))

# --- signed digits (with carries) ----------------------------------------------------

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

# A signed digit: magnitude and sign (1 = negative).
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

# Digits for windows j = 0 .. n-1 (least significant first).
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

# --- buckets -------------------------------------------------------------------------

def empty(+d: Nat) -> Array<+List<AP>>:
  match d:
    case 0n:
      ALeaf{Nil{}}
    case 1n+k:
      ANode{empty(k), empty(k)}

def arr_of(r: Array<+List<AP>> & +List<AP>) -> Array<+List<AP>>:
  (a, _) = r
  a

def push_fin(p: AP, r: Array<+List<AP>> & +List<AP>, +i: U32) -> Array<+List<AP>>:
  (a, old) = r
  arr_of(Array.swap(+List<AP>, a, i, p <> old))

def neg_b(b: Bool, p: AP) -> AP:
  match b:
    case True{}:
      ap_neg(p)
    case False{}:
      p

def signed_pt(+neg: U32, p: AP) -> AP:
  neg_b(U32.is_eq(neg, 1), p)

def is_none(+p: AP) -> Bool:
  match p:
    case ANone{}:
      True{}
    case AP{_, _}:
      False{}

def put_if(skip: Bool, a: Array<+List<AP>>, +i: U32, p: AP) -> Array<+List<AP>>:
  match skip:
    case True{}:
      a
    case False{}:
      push_fin(p, Array.swap(+List<AP>, a, i, Nil{}), i)

def put(+p: AP, +sd: SD, a: Array<+List<AP>>) -> Array<+List<AP>>:
  SD{+m, +neg} = sd
  put_if(Bool.or(U32.is_eq(m, 0), is_none(p)), a, (m - 1 : U32), signed_pt(neg, p))

def fill(ps: +List<AP>, ds: +List<SD>, a: Array<+List<AP>>) -> Array<+List<AP>>:
  match ps ds:
    case Con{+p, pt} Con{+d, dt}:
      fill(pt, dt, put(p, d, a))
    case _ _:
      a

# Bucket lists in index order (bucket for digit 1 first).
def flat(a: Array<+List<AP>>, out: +List<+List<AP>>) -> +List<+List<AP>>:
  match a:
    case ALeaf{x}:
      x <> out
    case ANode{lo, hi}:
      flat(lo, flat(hi, out))

# --- batch-affine bucket summation ---------------------------------------------------------

# Pair kind: 0 = affine add with inversion; 1 = equal x (complete fallback); 2 = a is none; 3 = b is none.
def kind(+a: AP, +b: AP) -> U32:
  match a b:
    case ANone{} _:
      2
    case _ ANone{}:
      3
    case AP{+x1, _} AP{+x2, _}:
      Bool.to_u32(B.is_eq(x1, x2))

def den_b(z: Bool, a: AP, b: AP) -> B.Fq:
  match z a b:
    case True{} AP{x1, _} AP{x2, _}:
      B.sub(x2, x1)
    case _ _ _:
      B.one()

def den(+a: AP, +b: AP) -> B.Fq:
  den_b(U32.is_eq(kind(a, b), 0), a, b)

def cden(l: +List<AP>, out: +List<B.Fq>) -> +List<B.Fq>:
  match l:
    case Con{+a, Con{+b, t}}:
      cden(t, den(a, b) <> out)
    case _:
      out

def collect(bs: +List<+List<AP>>, out: +List<B.Fq>) -> +List<B.Fq>:
  match bs:
    case Con{+l, t}:
      collect(t, cden(l, out))
    case Nil{}:
      out

# Single-point normalisation for the rare fallback pairs.
def norm_one(+p: V.Pt) -> AP:
  V.Pt{_, _, +z} = p
  norm1(p, B.inv(z))

def add_aff(+x1: B.Fq, +y1: B.Fq, +x2: B.Fq, +y2: B.Fq, +inv: B.Fq) -> AP:
  +lam = B.mul(B.sub(y2, y1), inv)
  +x3 = B.sub(B.sub(B.sqr(lam), x1), x2)
  AP{x3, B.sub(B.mul(lam, B.sub(x1, x3)), y1)}

def psum_k(k: Nat, +a: AP, +b: AP, +inv: B.Fq) -> AP:
  match k a b:
    case 0n AP{+x1, +y1} AP{+x2, +y2}:
      add_aff(x1, y1, x2, y2, inv)
    case 1n _ _:
      norm_one(V.add(ap_to_pt(a), ap_to_pt(b)))
    case 2n _ _:
      b
    case _ _ _:
      a

def psum(+a: AP, +b: AP, +inv: B.Fq) -> AP:
  psum_k(U32.to_nat(kind(a, b)), a, b, inv)

type RB is Data:
  RB{out: +List<AP>, inv: +List<B.Fq>}

def rb_cons(+s: AP, r: RB) -> RB:
  RB{o, i} = r
  RB{s <> o, i}

def rbucket(l: +List<AP>, invs: +List<B.Fq>) -> RB:
  match l invs:
    case Con{+a, Con{+b, t}} Con{+iv, it}:
      rb_cons(psum(a, b, iv), rbucket(t, it))
    case _ _:
      RB{l, invs}

def rb_out(r: RB) -> +List<AP>:
  RB{o, _} = r
  o

def rb_inv(r: RB) -> +List<B.Fq>:
  RB{_, i} = r
  i

def rebuild(bs: +List<+List<AP>>, invs: +List<B.Fq>) -> +List<+List<AP>>:
  match bs:
    case Con{+l, t}:
      +r = rbucket(l, invs)
      rb_out(r) <> rebuild(t, rb_inv(r))
    case Nil{}:
      Nil{}

def small(bs: +List<+List<AP>>) -> Bool:
  match bs:
    case Con{Con{_, Con{_, _}}, _}:
      False{}
    case Con{_, t}:
      small(t)
    case Nil{}:
      True{}

def rounds(fuel: Nat, done: Bool, +bs: +List<+List<AP>>) -> +List<+List<AP>>:
  match fuel done:
    case 1n+f False{}:
      +nb = rebuild(bs, batch_inv(List.reverse(&2, B.Fq, collect(bs, Nil{}))))
      rounds(f, small(nb), nb)
    case _ _:
      bs

# --- bucket reduction and windows ------------------------------------------------------------

type RS is Data:
  RS{run: V.Pt, acc: V.Pt}

def add_b(+run: V.Pt, l: +List<AP>) -> V.Pt:
  match l:
    case Con{AP{+x, +y}, _}:
      V.add_aff(run, V.Aff{x, y})
    case _:
      run

# Buckets highest digit first: run = suffix sum, acc = sum_d d * B_d.
def reduce(bs: +List<+List<AP>>, st: RS) -> RS:
  match bs:
    case Con{+l, t}:
      RS{+run, +acc} = st
      +r2 = add_b(run, l)
      reduce(t, RS{r2, V.add(acc, r2)})
    case Nil{}:
      st

def rs_acc(st: RS) -> V.Pt:
  RS{_, acc} = st
  acc

def window_sum(+c: U32, +aps: +List<AP>, ds: +List<SD>) -> V.Pt:
  +bs = flat(fill(aps, ds, empty(U32.to_nat((c - 1 : U32)))), Nil{})
  +summed = rounds(32n, small(bs), bs)
  rs_acc(reduce(List.reverse(&2, +List<AP>, summed), RS{V.identity(), V.identity()}))

def dbl_n(n: Nat, p: V.Pt) -> V.Pt:
  match n:
    case 0n:
      p
    case 1n+k:
      dbl_n(k, V.double(p))

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
def wrange(+fuel: Nat, one: Bool, +c: U32, +aps: +List<AP>, +wins: +List<+List<SD>>, +cnt: U32) -> V.Pt:
  match fuel one:
    case 1n+f False{}:
      +h = (cnt >> 1n : U32)
      +h2 = (cnt - h : U32)
      +hn = U32.to_nat(h)
      a b = wrange(f, U32.is_lt(h, 2), c, aps, take_w(hn, wins), h) wrange(f, U32.is_lt(h2, 2), c, aps, drop_w(hn, wins), h2)
      V.add(a, dbl_n(U32.to_nat((h * c : U32)), b))
    case _ _:
      window_sum(c, aps, head_w(wins))

# sum_i [s_i] P_i with c-bit signed windows (c in 2..16).
def msm(+c: U32, +ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  +nw = windows(c)
  +wins = transpose(U32.to_nat(nw), all_digits(ss, U32.to_nat(nw), c))
  wrange(9n, False{}, c, normalize(ps), wins, nw)

def msm_gpu(+c: U32, +ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  +nw = windows(c)
  +wins = transpose(U32.to_nat(nw), all_digits(ss, U32.to_nat(nw), c))
  wrange!(9n, False{}, c, normalize(ps), wins, nw)

# --- carry-free signed digits ---------------------------------------------------------------
# k' = k + H with H = sum_{j<W} 2^(c j) 2^(c-1). Then k = sum_j (u_j - 2^(c-1)) 2^(c j), where the
# u_j are the plain c-bit windows of k', so each window's digit is computed on its own (no carry
# chain between windows). With c W >= 257 and k < 2^255, k' < 2^(c W) fits in 9 words.

type W9 is Data:
  W9{lo: Wd.W, hi: U32}

def windows9(+c: U32) -> U32:
  ((257 + c - 1 : U32) / c : U32)

def hconst_n(n: Nat) -> W9:
  match n:
    case 4n:
      W9{Wd.W{2290649224, 2290649224, 2290649224, 2290649224, 2290649224, 2290649224, 2290649224, 2290649224}, 8}
    case 5n:
      W9{Wd.W{554189328, 138547332, 1108378657, 277094664, 2216757314, 554189328, 138547332, 1108378657}, 8}
    case 6n:
      W9{Wd.W{545392672, 136348168, 2181570690, 545392672, 136348168, 2181570690, 545392672, 136348168}, 2}
    case 7n:
      W9{Wd.W{135274560, 1082196484, 67637280, 541098242, 33818640, 270549121, 2164392968, 135274560}, 4}
    case 8n:
      W9{Wd.W{2155905152, 2155905152, 2155905152, 2155905152, 2155905152, 2155905152, 2155905152, 2155905152}, 128}
    case 9n:
      W9{Wd.W{67240192, 1075843080, 33620096, 537921540, 16810048, 268960770, 8405024, 134480385}, 16}
    case 10n:
      W9{Wd.W{537395712, 134348928, 33587232, 8396808, 2149582850, 537395712, 134348928, 33587232}, 8}
    case 11n:
      W9{Wd.W{2098176, 4196353, 8392706, 16785412, 33570824, 67141648, 134283296, 268566592}, 128}
    case 12n:
      W9{Wd.W{8390656, 134250504, 2148008064, 8390656, 134250504, 2148008064, 8390656, 134250504}, 128}
    case 13n:
      W9{Wd.W{33558528, 524352, 67117057, 1048704, 134234114, 2097408, 268468228, 4194816}, 8}
    case 14n:
      W9{Wd.W{134225920, 8389120, 524320, 536903682, 33556480, 2097280, 2147614728, 134225920}, 512}
    case 15n:
      W9{Wd.W{536887296, 134221824, 33555456, 8388864, 2097216, 524304, 131076, 1073774593}, 8192}
    case 16n:
      W9{Wd.W{2147516416, 2147516416, 2147516416, 2147516416, 2147516416, 2147516416, 2147516416, 2147516416}, 32768}
    case _:
      W9{Wd.zero(), 0}

def hconst(+c: U32) -> W9:
  hconst_n(U32.to_nat(c))

def add9(k: Wd.W, h: W9) -> W9:
  Wd.W{+k0, +k1, +k2, +k3, +k4, +k5, +k6, +k7} = k
  W9{hw, +h8} = h
  Wd.W{+h0, +h1, +h2, +h3, +h4, +h5, +h6, +h7} = hw
  +s0 = (k0 + h0 + 0 : U32)
  +c0 = I.addc(k0, h0, 0)
  +s1 = (k1 + h1 + c0 : U32)
  +c1 = I.addc(k1, h1, c0)
  +s2 = (k2 + h2 + c1 : U32)
  +c2 = I.addc(k2, h2, c1)
  +s3 = (k3 + h3 + c2 : U32)
  +c3 = I.addc(k3, h3, c2)
  +s4 = (k4 + h4 + c3 : U32)
  +c4 = I.addc(k4, h4, c3)
  +s5 = (k5 + h5 + c4 : U32)
  +c5 = I.addc(k5, h5, c4)
  +s6 = (k6 + h6 + c5 : U32)
  +c6 = I.addc(k6, h6, c5)
  +s7 = (k7 + h7 + c6 : U32)
  +c7 = I.addc(k7, h7, c6)
  W9{Wd.W{s0, s1, s2, s3, s4, s5, s6, s7}, (h8 + c7 : U32)}

def offset_all(ss: +List<Wd.W>, +h: W9) -> +List<W9>:
  match ss:
    case Con{+s, t}:
      add9(s, h) <> offset_all(t, h)
    case Nil{}:
      Nil{}

def wpick9_n(+i: Nat, w: W9) -> U32:
  match i w:
    case 8n W9{_, hi}:
      hi
    case _ W9{lo, _}:
      wpick_n(i, lo)

# c bits of k' starting at bit off.
def bits9(+w: W9, +off: U32, +c: U32) -> U32:
  +wi = (off >> 5n : U32)
  +sh = (off .&. 31 : U32)
  +lo = (wpick9_n(U32.to_nat(wi), w) >> U32.to_nat(sh) : U32)
  +both = U32.or(lo, hi_part(U32.is_eq(sh, 0), wpick9_n(U32.to_nat((wi + 1 : U32)), w), sh))
  (both .&. ((1 << U32.to_nat(c) : U32) - 1 : U32) : U32)

def sd_u(b: Bool, +u: U32, +half: U32) -> SD:
  match b:
    case True{}:
      SD{(u - half : U32), 0}
    case False{}:
      SD{(half - u : U32), 1}

# Signed digit of window j: u_j - 2^(c-1), as magnitude and sign.
def digit9(+w: W9, +j: U32, +c: U32) -> SD:
  +u = bits9(w, (j * c : U32), c)
  +half = (1 << U32.to_nat((c - 1 : U32)) : U32)
  sd_u(U32.is_ge(u, half), u, half)

def fill9(ps: +List<AP>, ks: +List<W9>, +j: U32, +c: U32, a: Array<+List<AP>>) -> Array<+List<AP>>:
  match ps ks:
    case Con{+p, pt} Con{+k, kt}:
      fill9(pt, kt, j, c, put(p, digit9(k, j, c), a))
    case _ _:
      a

def window_sum9(+c: U32, +aps: +List<AP>, +ks: +List<W9>, +j: U32) -> V.Pt:
  +bs = flat(fill9(aps, ks, j, c, empty(U32.to_nat((c - 1 : U32)))), Nil{})
  +summed = rounds(32n, small(bs), bs)
  rs_acc(reduce(List.reverse(&2, +List<AP>, summed), RS{V.identity(), V.identity()}))

def wrange9(+fuel: Nat, one: Bool, +c: U32, +aps: +List<AP>, +ks: +List<W9>, +lo: U32, +cnt: U32) -> V.Pt:
  match fuel one:
    case 1n+f False{}:
      +h = (cnt >> 1n : U32)
      +h2 = (cnt - h : U32)
      a b = wrange9(f, U32.is_lt(h, 2), c, aps, ks, lo, h) wrange9(f, U32.is_lt(h2, 2), c, aps, ks, (lo + h : U32), h2)
      V.add(a, dbl_n(U32.to_nat((h * c : U32)), b))
    case _ _:
      window_sum9(c, aps, ks, lo)

# sum_i [s_i] P_i, carry-free signed c-bit windows, windows in parallel (c in 4..16).
def msm9(+c: U32, +ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  wrange9(9n, False{}, c, normalize(ps), offset_all(ss, hconst(c)), 0, windows9(c))

def msm9_gpu(+c: U32, +ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  wrange9!(9n, False{}, c, normalize(ps), offset_all(ss, hconst(c)), 0, windows9(c))

