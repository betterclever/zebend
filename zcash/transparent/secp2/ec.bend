# secp256k1 in Bend (speed round 2: GLV + wNAF verification, see the ECDSA section): field helpers, public key decoding (libsecp256k1's ec_pubkey_parse
# rules: compressed 02/03, uncompressed 04, hybrid 06/07), Jacobian point arithmetic and
# ECDSA verification (libsecp256k1's secp256k1_ecdsa_sig_verify on a parsed signature).
#
# Field elements (F.Fe) are fully reduced plain values; scalars (S.Sc) are plain values
# except where a name says "mont" (Montgomery form, R = 2^256).
import Base
import ./fe.bend as F
import ./sc.bend as S
import ./gtab.bend as G
import ./scinv.bend as SI

# ------------------------------------------------------------------ field

def sub(a: F.Fe, b: F.Fe) -> F.Fe:
  F.sub(a, b)

def neg(a: F.Fe) -> F.Fe:
  F.sub(F.zero(), a)

def dbl_f(+a: F.Fe) -> F.Fe:
  F.add(a, a)

def sqr_n(n: Nat, x: F.Fe) -> F.Fe:
  match n:
    case 0n:
      x
    case 1n+p:
      sqr_n(p, F.sqr(x))

type Ch is Data:
  Ch{x2: F.Fe, x3: F.Fe, x22: F.Fe, x223: F.Fe}

# The shared prefix of libsecp256k1's inversion and square-root addition chains:
# xk = x^(2^k - 1).
def chain(+x: F.Fe) -> Ch:
  +x2 = F.mul(F.sqr(x), x)
  +x3 = F.mul(F.sqr(x2), x)
  +x6 = F.mul(sqr_n(3n, x3), x3)
  +x9 = F.mul(sqr_n(3n, x6), x3)
  +x11 = F.mul(sqr_n(2n, x9), x2)
  +x22 = F.mul(sqr_n(11n, x11), x11)
  +x44 = F.mul(sqr_n(22n, x22), x22)
  +x88 = F.mul(sqr_n(44n, x44), x44)
  +x176 = F.mul(sqr_n(88n, x88), x88)
  +x220 = F.mul(sqr_n(44n, x176), x44)
  +x223 = F.mul(sqr_n(3n, x220), x3)
  Ch{x2, x3, x22, x223}

# x^(p-2) = 1/x (0 for x = 0).
def inv_c(c: Ch, +x: F.Fe) -> F.Fe:
  Ch{+x2, _, +x22, +x223} = c
  +t1 = F.mul(sqr_n(23n, x223), x22)
  +t2 = F.mul(sqr_n(5n, t1), x)
  +t3 = F.mul(sqr_n(3n, t2), x2)
  F.mul(sqr_n(2n, t3), x)

def inv(+x: F.Fe) -> F.Fe:
  inv_c(chain(x), x)

# x^((p+1)/4): a square root of x when one exists (p = 3 mod 4).
def sqrt_c(c: Ch) -> F.Fe:
  Ch{+x2, _, +x22, +x223} = c
  +t1 = F.mul(sqr_n(23n, x223), x22)
  +t2 = F.mul(sqr_n(6n, t1), x2)
  sqr_n(2n, t2)

def sqrt_cand(+x: F.Fe) -> F.Fe:
  sqrt_c(chain(x))

def is_odd(+a: F.Fe) -> Bool:
  U32.is_eq((F.low_word(a) .&. 1 : U32), 1)

# y^2 = x^3 + 7
def rhs(+x: F.Fe) -> F.Fe:
  F.add(F.mul(F.sqr(x), x), F.seven())

# ------------------------------------------------------------------ public keys

def blen(xs: +List<U32>, +acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{_, t}:
      blen(t, (acc + 1 : U32))

def tail1(xs: +List<U32>) -> +List<U32>:
  match xs:
    case Con{_, t}:
      t
    case Nil{}:
      Nil{}

def head1(xs: +List<U32>) -> U32:
  match xs:
    case Con{h, _}:
      h
    case Nil{}:
      256

def some_if(ok: Bool, +p: G.Af) -> Maybe<&2, G.Af>:
  match ok:
    case True{}:
      Some{p}
    case False{}:
      None{}

# Compressed: x < p, x^3 + 7 a square, y chosen by parity.
def dec_c_root(+want_odd: Bool, +x: F.Fe, +y: F.Fe) -> Maybe<&2, G.Af>:
  some_if(F.eq(F.sqr(y), rhs(x)), G.Af{x, Bool.pick(F.Fe, Bool.xor(is_odd(y), want_odd), neg(y), y)})

def dec_c_x(ok: Bool, +want_odd: Bool, +x: F.Fe) -> Maybe<&2, G.Af>:
  match ok:
    case True{}:
      dec_c_root(want_odd, x, sqrt_cand(rhs(x)))
    case False{}:
      None{}

def dec_c(+want_odd: Bool, +body: +List<U32>) -> Maybe<&2, G.Af>:
  +x = F.from_be(body)
  dec_c_x(F.is_canonical(x), want_odd, x)

# Uncompressed (04) / hybrid (06, 07): x, y < p, on the curve, and for hybrid keys the
# prefix's parity bit must equal y's.
def dec_u_xy(ok: Bool, +x: F.Fe, +y: F.Fe) -> Maybe<&2, G.Af>:
  match ok:
    case True{}:
      some_if(F.eq(F.sqr(y), rhs(x)), G.Af{x, y})
    case False{}:
      None{}

def dec_u(+prefix: U32, +body: +List<U32>) -> Maybe<&2, G.Af>:
  +x = F.from_be(body)
  +y = F.from_be(F.drop(body, 32n))
  +hybrid_ok = U32.is_eq(prefix, 4) || Bool.not(Bool.xor(U32.is_eq(prefix, 7), is_odd(y)))
  dec_u_xy(F.is_canonical(x) && F.is_canonical(y) && hybrid_ok, x, y)

def dec_33(ok: Bool, +prefix: U32, +body: +List<U32>) -> Maybe<&2, G.Af>:
  match ok:
    case True{}:
      dec_c(U32.is_eq(prefix, 3), body)
    case False{}:
      None{}

def dec_65(ok: Bool, +prefix: U32, +body: +List<U32>) -> Maybe<&2, G.Af>:
  match ok:
    case True{}:
      dec_u(prefix, body)
    case False{}:
      None{}

def dec_len(is33: Bool, +len: U32, +prefix: U32, +body: +List<U32>) -> Maybe<&2, G.Af>:
  match is33:
    case True{}:
      dec_33(U32.is_eq(prefix, 2) || U32.is_eq(prefix, 3), prefix, body)
    case False{}:
      dec_65(U32.is_eq(len, 65) && (U32.is_eq(prefix, 4) || U32.is_eq(prefix, 6) || U32.is_eq(prefix, 7)), prefix, body)

# A serialized public key, as libsecp256k1's secp256k1_ec_pubkey_parse accepts it.
def decode(+bs: +List<U32>) -> Maybe<&2, G.Af>:
  +len = blen(bs, 0)
  dec_len(U32.is_eq(len, 33), len, head1(bs), tail1(bs))

# ------------------------------------------------------------------ points (Jacobian, a = 0)

type Pt is Data:
  Pt{x: F.Fe, y: F.Fe, z: F.Fe}

def inf() -> Pt:
  Pt{F.one(), F.one(), F.zero()}

def is_inf(p: Pt) -> Bool:
  Pt{_, _, z} = p
  F.is_zero(z)

def of_af(a: G.Af) -> Pt:
  G.Af{x, y} = a
  Pt{x, y, F.one()}

# dbl-2009-l. Infinity (z = 0) stays infinity; secp256k1 has no point with y = 0.
def dbl(p: Pt) -> Pt:
  Pt{+x, +y, z} = p
  +a = F.sqr(x)
  +b = F.sqr(y)
  +c = F.sqr(b)
  +d = dbl_f(sub(sub(F.sqr(F.add(x, b)), a), c))
  +e = F.add(dbl_f(a), a)
  +x3 = sub(F.sqr(e), dbl_f(d))
  +c8 = dbl_f(dbl_f(dbl_f(c)))
  Pt{x3, sub(F.mul(e, sub(d, x3)), c8), dbl_f(F.mul(y, z))}

# P + Q from U1, U2, S1, S2 (H = U2 - U1, R = S2 - S1) and the Z factor of the sum.
def add_hr(h0: Bool, +r0: Bool, +p: Pt, +u1: F.Fe, +s1: F.Fe, +h: F.Fe, +r: F.Fe, +zh: F.Fe) -> Pt:
  match h0:
    case True{}:
      Bool.pick(Pt, r0, dbl(p), inf())
    case False{}:
      +h2 = F.sqr(h)
      +h3 = F.mul(h, h2)
      +u1h2 = F.mul(u1, h2)
      +x3 = sub(sub(F.sqr(r), h3), dbl_f(u1h2))
      Pt{x3, sub(F.mul(r, sub(u1h2, x3)), F.mul(s1, h3)), F.mul(zh, h)}

def add_fin(+p: Pt, +u1: F.Fe, +u2: F.Fe, +s1: F.Fe, +s2: F.Fe, +zz: F.Fe) -> Pt:
  +h = sub(u2, u1)
  +r = sub(s2, s1)
  add_hr(F.is_zero(h), F.is_zero(r), p, u1, s1, h, r, zz)

def add_nz(+p: Pt, +q: Pt) -> Pt:
  Pt{+x1, +y1, +z1} = p
  Pt{+x2, +y2, +z2} = q
  +z1z1 = F.sqr(z1)
  +z2z2 = F.sqr(z2)
  add_fin(p, F.mul(x1, z2z2), F.mul(x2, z1z1), F.mul(F.mul(y1, z2), z2z2), F.mul(F.mul(y2, z1), z1z1), F.mul(z1, z2))

def add_q(qi: Bool, +p: Pt, +q: Pt) -> Pt:
  match qi:
    case True{}:
      p
    case False{}:
      add_nz(p, q)

# General Jacobian addition, exact in every case (infinity, P = Q, P = -Q).
def add_p(pi: Bool, +p: Pt, +q: Pt) -> Pt:
  match pi:
    case True{}:
      q
    case False{}:
      add_q(is_inf(q), p, q)

def add(+p: Pt, +q: Pt) -> Pt:
  add_p(is_inf(p), p, q)

# P (Jacobian) + A (affine, never infinity).
def madd_nz(+p: Pt, +a: G.Af) -> Pt:
  Pt{+x1, +y1, +z1} = p
  G.Af{+x2, +y2} = a
  +z1z1 = F.sqr(z1)
  add_fin(p, x1, F.mul(x2, z1z1), y1, F.mul(F.mul(y2, z1), z1z1), z1)

def madd_p(pi: Bool, +p: Pt, +a: G.Af) -> Pt:
  match pi:
    case True{}:
      of_af(a)
    case False{}:
      madd_nz(p, a)

def madd(+p: Pt, +a: G.Af) -> Pt:
  madd_p(is_inf(p), p, a)

# ------------------------------------------------------------------ scalars

# x^(n-2) in Montgomery form (x in Montgomery form): 1/x, by a fixed addition chain.
def sc_inv_mont(+x: S.Sc) -> S.Sc:
  SI.inv_mont(x)

# GLV split (libsecp256k1's secp256k1_scalar_split_lambda): k = k1 + k2 lambda (mod n).
type Split is Data:
  Split{k1: S.Sc, k2: S.Sc}

def split_k2(+k: S.Sc, +k2: S.Sc) -> Split:
  Split{S.add(k, S.n_minus(S.mul(k2, S.lambda_mont()))), k2}

def split(+k: S.Sc) -> Split:
  +c1 = S.mul_shift_384(k, S.glv_g1())
  +c2 = S.mul_shift_384(k, S.glv_g2())
  split_k2(k, S.add(S.mul(c1, S.glv_mb1_mont()), S.mul(c2, S.glv_mb2_mont())))

# A scalar as (|k|, sign): k > (n-1)/2 is taken as -(n - k).
type Mag is Data:
  Mag{v: S.Sc, neg: Bool}

def mag(+k: S.Sc) -> Mag:
  +low = S.is_low(k)
  Mag{Bool.pick(S.Sc, low, k, S.n_minus(k)), Bool.not(low)}

# ------------------------------------------------------------------ wNAF

# A non-zero wNAF digit at bit position pos: value (2 idx + 1), negated if neg.
# kind: 0 G, 1 lambda G, 2 Q, 3 lambda Q (which expansion the digit belongs to).
type Dg is Data:
  Dg{pos: U32, idx: U32, neg: Bool, kind: U32}

# Window parameters: w, 2^(w-1), 2^w.
type Wd is Data:
  Wd{w: U32, half: U32, full: U32}

# w is 5 (Q) or G.wg() = 8 (G); gen_secp2.py asserts WG = 8 matches this.
def wd(+w: U32) -> Wd:
  Wd{w, Bool.pick(U32, U32.is_eq(w, 5), 16, 128), Bool.pick(U32, U32.is_eq(w, 5), 32, 256)}

# One wNAF step at bit i: the next position, carry and digit list.
type Ws is Data:
  Ws{i: U32, carry: U32, acc: +List<Dg>}

def ws_i(s: Ws) -> U32:
  Ws{i, _, _} = s
  i

def ws_carry(s: Ws) -> U32:
  Ws{_, c, _} = s
  c

def ws_acc(s: Ws) -> +List<Dg>:
  Ws{_, _, a} = s
  a

def wn_odd(+wp: Wd, +i: U32, +v: U32, +sneg: Bool, +kind: U32, +acc: +List<Dg>) -> Ws:
  Wd{+w, +half, +full} = wp
  +big = U32.is_ge(v, half)
  +d = Bool.pick(U32, big, (full - v : U32), v)
  Ws{(i + w : U32), Bool.pick(U32, big, 1, 0), Dg{i, (d >> 1n : U32), Bool.xor(big, sneg), kind} <> acc}

def wn_par(even: Bool, +wp: Wd, +i: U32, +win: U32, +carry: U32, +v: U32, +sneg: Bool, +kind: U32, +acc: +List<Dg>) -> Ws:
  match even:
    case True{}:
      Ws{(i + 1 : U32), (((win .&. 1) + carry) >> 1n : U32), acc}
    case False{}:
      wn_odd(wp, i, v, sneg, kind, acc)

def wn_step(+k: S.Sc, +wp: Wd, +i: U32, +carry: U32, +sneg: Bool, +kind: U32, +acc: +List<Dg>) -> Ws:
  Wd{_, _, +full} = wp
  +win = (S.bits32(k, i) .&. (full - 1) : U32)
  +v = (win + carry : U32)
  wn_par(U32.is_zero((v .&. 1 : U32)), wp, i, win, carry, v, sneg, kind, acc)

# Digits of k from bit i up, most significant first (prepended to acc); a digit's sign is
# flipped when sneg. Runs while i < end or a carry is pending.
# fuel bounds the steps (one per bit at most; 300 > 257 positions).
def wn_go(fuel: Nat, go: Bool, +k: S.Sc, +wp: Wd, +end: U32, +sneg: Bool, +kind: U32, +st: Ws) -> +List<Dg>:
  match fuel go:
    case 1n+p True{}:
      +nx = wn_step(k, wp, ws_i(st), ws_carry(st), sneg, kind, ws_acc(st))
      wn_go(p, U32.is_lt(ws_i(nx), end) || U32.is_ne(ws_carry(nx), 0), k, wp, end, sneg, kind, nx)
    case _ _:
      ws_acc(st)

def wnaf(+m: Mag, +w: U32, +kind: U32) -> +List<Dg>:
  Mag{+v, +neg} = m
  +end = (S.top_words(v) << 5n : U32)
  wn_go(300n, U32.is_ne(end, 0), v, wd(w), end, neg, kind, Ws{0, 0, Nil{}})

def dg_pos(d: Dg) -> U32:
  Dg{p, _, _, _} = d
  p

# Does a's head come at or above b's (positions descending)? Nil sorts last.
def hge(+a: +List<Dg>, +b: +List<Dg>) -> Bool:
  match a b:
    case Con{x, _} Con{y, _}:
      U32.is_ge(dg_pos(x), dg_pos(y))
    case Con{_, _} Nil{}:
      True{}
    case _ _:
      False{}

# Merge of two digit lists sorted by descending position; ge = hge(a, b).
def merge(+a: +List<Dg>, +b: +List<Dg>, ge: Bool) -> +List<Dg>:
  match a b ge:
    case Con{x, s} _ True{}:
      x <> merge(s, b, hge(s, b))
    case _ Con{y, t} False{}:
      y <> merge(a, t, hge(a, t))
    case Nil{} _ _:
      b
    case _ Nil{} _:
      a

def merge2(+a: +List<Dg>, +b: +List<Dg>) -> +List<Dg>:
  merge(a, b, hge(a, b))

# ------------------------------------------------------------------ tables

def lam_x(lam: Bool, +x: F.Fe) -> F.Fe:
  match lam:
    case True{}:
      F.mul(x, F.beta())
    case False{}:
      x

def neg_y(ng: Bool, +y: F.Fe) -> F.Fe:
  match ng:
    case True{}:
      neg(y)
    case False{}:
      y

def jneg(+ng: Bool, +p: Pt) -> Pt:
  Pt{+x, +y, +z} = p
  Pt{x, neg_y(ng, y), z}

def jlam(+p: Pt) -> Pt:
  Pt{+x, +y, +z} = p
  Pt{F.mul(x, F.beta()), y, z}

# Q, 3Q, 5Q, ..., (2^(w-1) - 1)Q (Jacobian; exact also if a sum hits infinity).
def odd_go(k: Nat, +q2: Pt, +cur: Pt) -> +List<Pt>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      cur <> odd_go(p, q2, add(cur, q2))

def lam_all(+ps: +List<Pt>) -> +List<Pt>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{p, t}:
      jlam(p) <> lam_all(t)

def nth_pt(xs: +List<Pt>, +k: Nat) -> Pt:
  match xs k:
    case Con{h, _} 0n:
      h
    case Con{_, t} 1n+p:
      nth_pt(t, p)
    case _ _:
      inf()

def g_af2(+lam: Bool, +ng: Bool, +a: G.Af) -> G.Af:
  G.Af{+x, +y} = a
  G.Af{lam_x(lam, x), neg_y(ng, y)}

def g_af(+lam: Bool, +ng: Bool, +i: U32) -> G.Af:
  g_af2(lam, ng, G.g_odd(i))

# ------------------------------------------------------------------ joint wNAF loop

def ap_g(+lam: Bool, +acc: Pt, +ix: U32, +ng: Bool) -> Pt:
  madd(acc, g_af(lam, ng, ix))

def ap_q(+tab: +List<Pt>, +acc: Pt, +ix: U32, +ng: Bool) -> Pt:
  add(acc, jneg(ng, nth_pt(tab, U32.to_nat(ix))))

type Tabs is Data:
  Tabs{q: +List<Pt>, ql: +List<Pt>}

def tab_q(t: Tabs) -> +List<Pt>:
  Tabs{q, _} = t
  q

def tab_ql(t: Tabs) -> +List<Pt>:
  Tabs{_, q} = t
  q

def ap_k(k: U32, +tb: Tabs, +acc: Pt, +ix: U32, +ng: Bool) -> Pt:
  match k:
    case 0: ap_g(False{}, acc, ix, ng)
    case 1: ap_g(True{}, acc, ix, ng)
    case 2: ap_q(tab_q(tb), acc, ix, ng)
    case _: ap_q(tab_ql(tb), acc, ix, ng)

def dbl_n(n: Nat, +p: Pt) -> Pt:
  match n:
    case 0n:
      p
    case 1n+k:
      dbl_n(k, dbl(p))

def ap_dg(+tb: Tabs, +acc: Pt, d: Dg) -> Pt:
  Dg{_, +ix, +ng, +k} = d
  ap_k(k, tb, acc, ix, ng)

# The Strauss loop over the merged digit events (descending positions): acc holds the sum
# scaled to position cur; before an event at position p, acc is doubled cur - p times.
# At the end acc is doubled down to position 0.
def top_of(+ds: +List<Dg>) -> U32:
  match ds:
    case Con{d, _}:
      dg_pos(d)
    case Nil{}:
      0

def evloop(+ds: +List<Dg>, +cur: U32, +acc: Pt, +tb: Tabs) -> Pt:
  match ds:
    case Con{d, t}:
      +p = dg_pos(d)
      evloop(t, p, ap_dg(tb, dbl_n(U32.to_nat((cur - p : U32)), acc), d), tb)
    case Nil{}:
      dbl_n(U32.to_nat(cur), acc)

def wq() -> U32:
  5

# u1 G + u2 Q (u1, u2 plain scalars): both split by GLV, four wNAF expansions merged into
# one event list and one doubling chain (G and lambda G from the constant table, width G.wg(); Q and lambda Q from
# a per-call table of odd multiples, width 5).
def ecmult_s(sa: Split, sb: Split, +q: G.Af) -> Pt:
  Split{+a1, +a2} = sa
  Split{+b1, +b2} = sb
  +ds = merge2(merge2(wnaf(mag(a1), G.wg(), 0), wnaf(mag(a2), G.wg(), 1)), merge2(wnaf(mag(b1), wq(), 2), wnaf(mag(b2), wq(), 3)))
  +qj = of_af(q)
  +tq = odd_go(8n, dbl(qj), qj)
  evloop(ds, top_of(ds), inf(), Tabs{tq, lam_all(tq)})

def ecmult(+u1: S.Sc, +u2: S.Sc, +q: G.Af) -> Pt:
  ecmult_s(split(u1), split(u2), q)

# ------------------------------------------------------------------ ECDSA

def sc_to_fe(a: S.Sc) -> F.Fe:
  S.Sc{a0, a1, a2, a3, a4, a5, a6, a7} = a
  F.Fe{a0, a1, a2, a3, a4, a5, a6, a7}

# r == X / Z^2 mod n, without inverting Z: X == r Z^2, or X == (r + n) Z^2 when r + n < p.
def x_check_n(lt: Bool, +r: S.Sc, +zz: F.Fe, +x: F.Fe) -> Bool:
  match lt:
    case True{}:
      F.eq(F.mul(F.add(sc_to_fe(r), sc_to_fe(S.n_value())), zz), x)
    case False{}:
      False{}

def x_check(+r: S.Sc, p: Pt) -> Bool:
  Pt{+x, _, +z} = p
  +zz = F.sqr(z)
  Bool.not(F.is_zero(z)) && (F.eq(F.mul(sc_to_fe(r), zz), x) || x_check_n(S.is_lt_p_minus_n(r), r, zz, x))

def verify_ok(ok: Bool, +q: G.Af, +r: S.Sc, +s: S.Sc, +z: S.Sc) -> Bool:
  match ok:
    case True{}:
      +w = sc_inv_mont(S.mul(s, S.r2()))
      x_check(r, ecmult(S.mul(z, w), S.mul(r, w), q))
    case False{}:
      False{}

# ECDSA verification of (r, s) over the 32-byte message hash under the public key q.
# r and s are the parsed integers, already replaced by 0 if they were >= n (as
# libsecp256k1's DER parser does); the hash is read big-endian and reduced mod n.
def verify(+q: G.Af, +r: S.Sc, +s: S.Sc, +msg: +List<U32>) -> Bool:
  verify_ok(Bool.not(S.is_zero(r)) && Bool.not(S.is_zero(s)), q, r, s, S.reduce(S.from_be(msg)))
