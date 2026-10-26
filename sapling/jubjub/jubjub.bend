# Jubjub: -u^2 + v^2 = 1 + d u^2 v^2 over Fr (BLS12-381's scalar field), a = -1.
# Extended twisted Edwards coordinates (Hisil-Wong-Carter-Dawson 2008): u = X/Z, v = Y/Z,
# T = XY/Z. Addition "add-2008-hwcd-3" is complete here (a = -1 is a square, d is not).
# Precomputed affine points are kept in "Niels" form (v+u, v-u, 2d*u*v): 7M per mixed add.
# Encoding (protocol spec 5.4.9.4): 32 LE bytes of v with u's low bit in bit 255.
import Base
import ../../halo2/lib/words.bend as Wd
import ./fr.bend as F
import ./consts.bend as K
import ./fr_sqrt.bend as FQ

type Pt is Data:
  Pt{x: F.Fr, y: F.Fr, z: F.Fr, t: F.Fr}

type Ni is Data:
  Ni{vpu: F.Fr, vmu: F.Fr, t2d: F.Fr}

def identity() -> Pt:
  Pt{F.zero(), F.one(), F.one(), F.zero()}

# X == 0 and Y == Z
def is_identity(p: Pt) -> Bool:
  Pt{x, +y, +z, _} = p
  Bool.and(F.is_zero(x), F.is_eq(y, z))

def from_aff(a: K.Aff) -> Pt:
  K.Aff{+u, +v} = a
  Pt{u, v, F.one(), F.mul(u, v)}

def ni_of_aff(a: K.Aff) -> Ni:
  K.Aff{+u, +v} = a
  Ni{F.add(v, u), F.sub(v, u), F.mul(K.d2(), F.mul(u, v))}

def ni_neg(n: Ni) -> Ni:
  Ni{a, b, c} = n
  Ni{b, a, F.neg(c)}

# Complete unified addition (add-2008-hwcd-3, a = -1, k = 2d).
def add(p: Pt, q: Pt) -> Pt:
  Pt{+x1, +y1, z1, t1} = p
  Pt{+x2, +y2, z2, t2} = q
  +a = F.mul(F.sub(y1, x1), F.sub(y2, x2))
  +b = F.mul(F.add(y1, x1), F.add(y2, x2))
  +c = F.mul(F.mul(t1, K.d2()), t2)
  +zz = F.mul(z1, z2)
  +dd = F.add(zz, zz)
  +e = F.sub(b, a)
  +f = F.sub(dd, c)
  +g = F.add(dd, c)
  +h = F.add(b, a)
  Pt{F.mul(e, f), F.mul(g, h), F.mul(f, g), F.mul(e, h)}

# Mixed addition with a Niels point (madd-2008-hwcd-3): 7M.
def add_ni(p: Pt, n: Ni) -> Pt:
  Pt{+x1, +y1, +z1, t1} = p
  Ni{vpu, vmu, t2d} = n
  +a = F.mul(F.sub(y1, x1), vmu)
  +b = F.mul(F.add(y1, x1), vpu)
  +c = F.mul(t1, t2d)
  +dd = F.add(z1, z1)
  +e = F.sub(b, a)
  +f = F.sub(dd, c)
  +g = F.add(dd, c)
  +h = F.add(b, a)
  Pt{F.mul(e, f), F.mul(g, h), F.mul(f, g), F.mul(e, h)}

# Doubling (dbl-2008-hwcd, a = -1): 4M + 4S.
def double(p: Pt) -> Pt:
  Pt{+x1, +y1, z1, _} = p
  +a = F.sqr(x1)
  +b = F.sqr(y1)
  +zz = F.sqr(z1)
  +c = F.add(zz, zz)
  +d = F.neg(a)
  +e = F.sub(F.sub(F.sqr(F.add(x1, y1)), a), b)
  +g = F.add(d, b)
  +f = F.sub(g, c)
  +h = F.sub(d, b)
  Pt{F.mul(e, f), F.mul(g, h), F.mul(f, g), F.mul(e, h)}

def neg(p: Pt) -> Pt:
  Pt{x, y, z, t} = p
  Pt{F.neg(x), y, z, F.neg(t)}

def sub(p: Pt, q: Pt) -> Pt:
  add(p, neg(q))

# [8] p
def mul_by_cofactor(p: Pt) -> Pt:
  double(double(double(p)))

# Projective equality: X1 Z2 == X2 Z1 and Y1 Z2 == Y2 Z1.
def is_eq(p: Pt, q: Pt) -> Bool:
  Pt{x1, y1, +z1, _} = p
  Pt{x2, y2, +z2, _} = q
  Bool.and(F.is_eq(F.mul(x1, z2), F.mul(x2, z1)), F.is_eq(F.mul(y1, z2), F.mul(y2, z1)))

# [8] p == identity (p is one of the 8 small-order points).
def is_small_order(p: Pt) -> Bool:
  is_identity(mul_by_cofactor(p))

def to_aff(p: Pt) -> K.Aff:
  Pt{x, y, z, _} = p
  +zi = F.inv(z)
  K.Aff{F.mul(x, zi), F.mul(y, zi)}

def aff_u(a: K.Aff) -> F.Fr:
  K.Aff{u, _} = a
  u

def enc_aff(a: K.Aff) -> Wd.W:
  K.Aff{u, v} = a
  Wd.set_top_bit(F.to_words(v), F.low_bit(u))

# 32-byte encoding.
def encode(p: Pt) -> Wd.W:
  enc_aff(to_aff(p))

# u-coordinate as canonical words (Extract_J for the Pedersen-hash Merkle tree).
def u_of(p: Pt) -> Wd.W:
  F.to_words(aff_u(to_aff(p)))

# ------------------------------------------------------------------ decoding

def dec_fin(+u: F.Fr, +v: F.Fr, +sign: U32) -> Maybe<&2, Pt>:
  +u2 = F.sel((F.low_bit(u) .^. sign : U32), F.neg(u), u)
  Some{Pt{u2, v, F.one(), F.mul(u2, v)}}

def dec_z(bad: Bool, +u: F.Fr, +v: F.Fr, +sign: U32) -> Maybe<&2, Pt>:
  match bad:
    case True{}:
      None{}
    case False{}:
      dec_fin(u, v, sign)

# ZIP 216: u = 0 with the sign bit set is rejected.
def dec_u(mu: Maybe<&2, F.Fr>, +v: F.Fr, +sign: U32) -> Maybe<&2, Pt>:
  match mu:
    case None{}:
      None{}
    case Some{+u}:
      dec_z(Bool.and(F.is_zero(u), U32.is_eq(sign, 1)), u, v, sign)

# u^2 = (v^2 - 1) / (d v^2 + 1)
def dec_v(+v: F.Fr, +sign: U32, +canon: Bool) -> Maybe<&2, Pt>:
  match canon:
    case False{}:
      None{}
    case True{}:
      +vv = F.sqr(v)
      +den = F.add(F.mul(K.d(), vv), F.one())
      dec_u(FQ.sqrt(F.mul(F.sub(vv, F.one()), F.inv(den))), v, sign)

# abst_J with ZIP 216 (jubjub::AffinePoint::from_bytes): rejects v >= r, non-points, and
# the non-canonical encodings of the two points with u = 0.
def decompress(+w: Wd.W) -> Maybe<&2, Pt>:
  +vw = Wd.clear_top_bit(w)
  dec_v(F.from_words(vw), Wd.top_bit(w), Wd.is_lt(vw, F.modulus()))

# ------------------------------------------------------------------ scalar multiplication

def add_if(b: Bool, p: Pt, +q: Pt) -> Pt:
  match b:
    case True{}:
      add(p, q)
    case False{}:
      p

# acc * 2^32 + w * q, scanning w from its top bit.
def mul_w(n: Nat, w: U32, acc: Pt, +q: Pt) -> Pt:
  match n:
    case 0n:
      acc
    case 1n+k:
      +w2 = w
      mul_w(k, (w2 << 1n : U32), add_if(U32.is_eq((w2 >> 31n : U32), 1), double(acc), q), q)

# [s] p for a 256-bit little-endian scalar (any 256-bit integer).
def scalar_mul(+p: Pt, s: Wd.W) -> Pt:
  Wd.W{w0, w1, w2, w3, w4, w5, w6, w7} = s
  a7 = mul_w(32n, w7, identity(), p)
  a6 = mul_w(32n, w6, a7, p)
  a5 = mul_w(32n, w5, a6, p)
  a4 = mul_w(32n, w4, a5, p)
  a3 = mul_w(32n, w3, a4, p)
  a2 = mul_w(32n, w2, a3, p)
  a1 = mul_w(32n, w1, a2, p)
  mul_w(32n, w0, a1, p)

# [m] q for a 64-bit m = lo + 2^32 hi.
def mul64(+q: Pt, +lo: U32, +hi: U32) -> Pt:
  mul_w(32n, lo, mul_w(32n, hi, identity(), q), q)

# Niels form of a point with Z = 1 (as decompress returns): (v+u, v-u, 2d*T).
def ni_of_z1(p: Pt) -> Ni:
  Pt{+x, +y, _, t} = p
  Ni{F.add(y, x), F.sub(y, x), F.mul(K.d2(), t)}

# Niels form of any point (one inversion).
def ni_of(p: Pt) -> Ni:
  ni_of_aff(to_aff(p))
