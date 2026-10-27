# secp256k1 in Bend: field helpers, public key decoding (libsecp256k1's ec_pubkey_parse
# rules: compressed 02/03, uncompressed 04, hybrid 06/07), Jacobian point arithmetic and
# ECDSA verification (libsecp256k1's secp256k1_ecdsa_sig_verify on a parsed signature).
#
# Field elements (F.Fe) are fully reduced plain values; scalars (S.Sc) are plain values
# except where a name says "mont" (Montgomery form, R = 2^256).
import Base
import ./fe.bend as F
import ./sc.bend as S
import ./gtab.bend as G

# ------------------------------------------------------------------ field

def sub(a: F.Fe, b: F.Fe) -> F.Fe:
  F.add(a, F.p_minus(b))

def neg(a: F.Fe) -> F.Fe:
  F.add(F.zero(), F.p_minus(a))

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

def wnib(+w: U32, acc: +List<U32>) -> +List<U32>:
  (w >> 28n : U32) <> ((w >> 24n) .&. 15 : U32) <> ((w >> 20n) .&. 15 : U32) <> ((w >> 16n) .&. 15 : U32)
    <> ((w >> 12n) .&. 15 : U32) <> ((w >> 8n) .&. 15 : U32) <> ((w >> 4n) .&. 15 : U32) <> (w .&. 15 : U32) <> acc

# The 64 base-16 digits of a scalar, most significant first.
def nibbles(a: S.Sc) -> +List<U32>:
  S.Sc{a0, a1, a2, a3, a4, a5, a6, a7} = a
  wnib(a7, wnib(a6, wnib(a5, wnib(a4, wnib(a3, wnib(a2, wnib(a1, wnib(a0, Nil{}))))))))

def nth_sc(xs: +List<S.Sc>, +k: Nat) -> S.Sc:
  match xs k:
    case Con{h, _} 0n:
      h
    case Con{_, t} 1n+p:
      nth_sc(t, p)
    case _ _:
      S.zero()

def sc_pows(k: Nat, +x: S.Sc, +cur: S.Sc) -> +List<S.Sc>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      cur <> sc_pows(p, x, S.mul(cur, x))

def sc_sqr4(+x: S.Sc) -> S.Sc:
  +a = S.mul(x, x)
  +b = S.mul(a, a)
  +c = S.mul(b, b)
  S.mul(c, c)

def sc_pow_go(ds: +List<U32>, +tab: +List<S.Sc>, +acc: S.Sc) -> S.Sc:
  match ds:
    case Nil{}:
      acc
    case Con{d, t}:
      sc_pow_go(t, tab, S.mul(sc_sqr4(acc), nth_sc(tab, U32.to_nat(d))))

# x^(n-2) in Montgomery form (x in Montgomery form): 1/x, by 4-bit fixed windows.
def sc_inv_mont(+x: S.Sc) -> S.Sc:
  sc_pow_go(nibbles(S.n_minus_2()), sc_pows(16n, x, S.mont_one()), S.mont_one())

# ------------------------------------------------------------------ ECDSA

def nth_af(xs: +List<G.Af>, +k: Nat) -> G.Af:
  match xs k:
    case Con{h, _} 0n:
      h
    case Con{_, t} 1n+p:
      nth_af(t, p)
    case _ _:
      G.Af{F.zero(), F.zero()}

def nth_pt(xs: +List<Pt>, +k: Nat) -> Pt:
  match xs k:
    case Con{h, _} 0n:
      h
    case Con{_, t} 1n+p:
      nth_pt(t, p)
    case _ _:
      inf()

def q_table(k: Nat, +q: G.Af, +cur: Pt) -> +List<Pt>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      cur <> q_table(p, q, madd(cur, q))

def step_g(z: Bool, +acc: Pt, +gt: +List<G.Af>, +d: U32) -> Pt:
  match z:
    case True{}:
      acc
    case False{}:
      madd(acc, nth_af(gt, U32.to_nat((d - 1 : U32))))

def step_q(z: Bool, +acc: Pt, +qt: +List<Pt>, +d: U32) -> Pt:
  match z:
    case True{}:
      acc
    case False{}:
      add(acc, nth_pt(qt, U32.to_nat((d - 1 : U32))))

# u1 G + u2 Q by joint 4-bit windows (Strauss-Shamir), digits most significant first.
def shamir(d1: +List<U32>, d2: +List<U32>, +gt: +List<G.Af>, +qt: +List<Pt>, +acc: Pt) -> Pt:
  match d1 d2:
    case Con{+a, t1} Con{+b, t2}:
      +acc4 = dbl(dbl(dbl(dbl(acc))))
      +accq = step_q(U32.is_zero(b), acc4, qt, b)
      shamir(t1, t2, gt, qt, step_g(U32.is_zero(a), accq, gt, a))
    case _ _:
      acc

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
      +u1 = S.mul(z, w)
      +u2 = S.mul(r, w)
      x_check(r, shamir(nibbles(u1), nibbles(u2), G.g_table(), q_table(15n, q, of_af(q)), inf()))
    case False{}:
      False{}

# ECDSA verification of (r, s) over the 32-byte message hash under the public key q.
# r and s are the parsed integers, already replaced by 0 if they were >= n (as
# libsecp256k1's DER parser does); the hash is read big-endian and reduced mod n.
def verify(+q: G.Af, +r: S.Sc, +s: S.Sc, +msg: +List<U32>) -> Bool:
  verify_ok(Bool.not(S.is_zero(r)) && Bool.not(S.is_zero(s)), q, r, s, S.reduce(S.from_be(msg)))
