# Ed25519 signature verification with Zcash's rules (ZIP 215), as ed25519-zebra 4.2.0
# (`VerificationKey::try_from(A_bytes)?.verify(sig, msg)`, which Zebra uses for Sprout's
# joinSplitSig) implements them:
#
#   - S (sig[32..64], little-endian) must be < l, else reject;
#   - A (pk) and R (sig[0..32]) are decoded like curve25519-dalek 4.1.3's
#     CompressedEdwardsY::decompress: y = low 255 bits taken mod p (non-canonical y >= p
#     accepted), x = the nonnegative root of (y^2-1)/(d y^2+1) negated if bit 255 is set
#     ("negative zero" accepted); reject only when no root exists. Small- and mixed-order
#     points are accepted;
#   - k = SHA-512(R_bytes || A_bytes || M) mod l, over the bytes AS GIVEN;
#   - accept iff [8]([s]B - [k]A - R) is the identity (the cofactored equation).
#
# Variable time (all inputs are public). Bytes are lists of U32 values 0..255.
import Base
import ./fp.bend as F
import ./fl.bend as L
import ./consts.bend as K
import ./sha512.bend as H

# Extended coordinates: x = X/Z, y = Y/Z, T = XY/Z.
type Pt is Data:
  Pt{x: F.Fp, y: F.Fp, z: F.Fp, t: F.Fp}

# Affine "Niels" form of a point: y+x, y-x, 2d*x*y.
type Ni is Data:
  Ni{ypx: F.Fp, ymx: F.Fp, t2d: F.Fp}

def identity() -> Pt:
  Pt{F.zero(), F.one(), F.one(), F.zero()}

# X == 0 and Y == Z
def is_identity(p: Pt) -> Bool:
  Pt{x, +y, +z, _} = p
  Bool.and(F.is_zero(x), F.is_eq(y, z))

# Mixed addition with a Niels point (madd-2008-hwcd-3, a = -1, k = 2d): complete on
# edwards25519 (d is not a square), so torsion points need no special case.
def add_ni(p: Pt, n: Ni) -> Pt:
  Pt{+x1, +y1, +z1, t1} = p
  Ni{ypx, ymx, t2d} = n
  +a = F.mul(F.sub(y1, x1), ymx)
  +b = F.mul(F.add(y1, x1), ypx)
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

def base_ni() -> Ni:
  Ni{K.b_ypx(), K.b_ymx(), K.b_t2d()}

# Niels form of -P for a point with Z = 1 (as decompress returns): (y-x, y+x, -2d*x*y).
def neg_ni_z1(p: Pt) -> Ni:
  Pt{+x, +y, _, t} = p
  Ni{F.sub(y, x), F.add(y, x), F.neg(F.mul(K.d2(), t))}

# ------------------------------------------------------------------ bytes

def drop(xs: +List<U32>, n: Nat) -> +List<U32>:
  match xs n:
    case Nil{} _:
      Nil{}
    case Con{h, t} 0n:
      h <> t
    case Con{_, t} 1n+p:
      drop(t, p)

def take(xs: +List<U32>, n: Nat) -> +List<U32>:
  match xs n:
    case Nil{} _:
      Nil{}
    case Con{h, t} 0n:
      Nil{}
    case Con{h, t} 1n+p:
      h <> take(t, p)

# At least n elements.
def has(xs: +List<U32>, n: Nat) -> Bool:
  match xs n:
    case _ 0n:
      True{}
    case Nil{} 1n+p:
      False{}
    case Con{_, t} 1n+p:
      has(t, p)

def get_le32(xs: +List<U32>) -> U32:
  match xs:
    case Con{a, Con{b, Con{c, Con{d, _}}}}:
      ((a .&. 255) .|. ((b .&. 255) << 8n) .|. ((c .&. 255) << 16n) .|. ((d .&. 255) << 24n) : U32)
    case _:
      0

# Eight little-endian words of the first 32 bytes.
type W8 is Data:
  W8{w0: U32, w1: U32, w2: U32, w3: U32, w4: U32, w5: U32, w6: U32, w7: U32}

def w8(+xs: +List<U32>) -> W8:
  W8{get_le32(xs), get_le32(drop(xs, 4n)), get_le32(drop(xs, 8n)), get_le32(drop(xs, 12n)),
     get_le32(drop(xs, 16n)), get_le32(drop(xs, 20n)), get_le32(drop(xs, 24n)), get_le32(drop(xs, 28n))}

def fp_of(w: W8) -> F.Fp:
  W8{w0, w1, w2, w3, w4, w5, w6, w7} = w
  F.Fp{w0, w1, w2, w3, w4, w5, w6, w7}

def fl_of(w: W8) -> L.Fl:
  W8{w0, w1, w2, w3, w4, w5, w6, w7} = w
  L.Fl{w0, w1, w2, w3, w4, w5, w6, w7}

def w8_of_fl(a: L.Fl) -> W8:
  L.Fl{w0, w1, w2, w3, w4, w5, w6, w7} = a
  W8{w0, w1, w2, w3, w4, w5, w6, w7}

# ------------------------------------------------------------------ decoding

def dec_ok(ok: Bool, +x: F.Fp, +y: F.Fp) -> Maybe<&2, Pt>:
  match ok:
    case True{}:
      Some{Pt{x, y, F.one(), F.mul(x, y)}}
    case False{}:
      None{}

# curve25519-dalek 4.1.3 decompress (step_1 + step_2) with FieldElement::sqrt_ratio_i:
#   r = (u v^3) (u v^7)^((p-5)/8), check = v r^2;
#   valid iff check == u or check == -u; r *= sqrt(-1) if check == -u or check == -u*sqrt(-1);
#   r := |r| (nonnegative = even canonical value); x = -r if the sign bit is set.
def decompress(w: W8) -> Maybe<&2, Pt>:
  W8{w0, w1, w2, w3, w4, w5, w6, +w7} = w
  +sign = (w7 >> 31n : U32)
  +y = F.from_raw(F.Fp{w0, w1, w2, w3, w4, w5, w6, (w7 .&. 2147483647 : U32)})
  +yy = F.sqr(y)
  +u = F.sub(yy, F.one())
  +v = F.add(F.mul(K.d(), yy), F.one())
  +v3 = F.mul(F.sqr(v), v)
  +v7 = F.mul(F.sqr(v3), v)
  +r = F.mul(F.mul(u, v3), F.pow_p58(F.mul(u, v7)))
  +check = F.mul(v, F.sqr(r))
  +nu = F.neg(u)
  +correct = F.eq(check, u)
  +flipped = F.eq(check, nu)
  +flipped_i = F.eq(check, F.mul(nu, K.sqrt_m1()))
  +r1 = F.sel((flipped .|. flipped_i : U32), F.mul(r, K.sqrt_m1()), r)
  +r2 = F.sel(F.low_bit(r1), F.neg(r1), r1)
  +x = F.sel(sign, F.neg(r2), r2)
  dec_ok(U32.is_eq((correct .|. flipped : U32), 1), x, y)

# ------------------------------------------------------------------ scalar multiplication

def add_if(b: Bool, p: Pt, +n: Ni) -> Pt:
  match b:
    case True{}:
      add_ni(p, n)
    case False{}:
      p

# 32 steps of the joint double-and-add: acc := 2 acc + bit(s) B + bit(k) N, MSB first.
def step_w(n: Nat, sw: U32, kw: U32, acc: Pt, +nb: Ni, +na: Ni) -> Pt:
  match n:
    case 0n:
      acc
    case 1n+m:
      +s2 = sw
      +k2 = kw
      +a1 = add_if(U32.is_eq((s2 >> 31n : U32), 1), double(acc), nb)
      +a2 = add_if(U32.is_eq((k2 >> 31n : U32), 1), a1, na)
      step_w(m, (s2 << 1n : U32), (k2 << 1n : U32), a2, nb, na)

# [s]B + [k]N for 256-bit little-endian s, k (here both < l < 2^253: the first 3 steps only
# double the identity).
def dsm(s: W8, k: W8, +na: Ni) -> Pt:
  W8{s0, s1, s2, s3, s4, s5, s6, s7} = s
  W8{k0, k1, k2, k3, k4, k5, k6, k7} = k
  +nb = base_ni()
  a7 = step_w(32n, s7, k7, identity(), nb, na)
  a6 = step_w(32n, s6, k6, a7, nb, na)
  a5 = step_w(32n, s5, k5, a6, nb, na)
  a4 = step_w(32n, s4, k4, a5, nb, na)
  a3 = step_w(32n, s3, k3, a4, nb, na)
  a2 = step_w(32n, s2, k2, a3, nb, na)
  a1 = step_w(32n, s1, k1, a2, nb, na)
  step_w(32n, s0, k0, a1, nb, na)

# ------------------------------------------------------------------ verification

# k = SHA-512(R || A || M) mod l (Scalar::from_hash: the 64-byte digest read little-endian,
# reduced mod l): with lo, hi the two 256-bit halves, k = lo + hi * 2^256, computed in
# Montgomery form as from_raw(lo) + mul(R^3, hi) = (lo + hi R) R, then to_raw.
def challenge(+rb: +List<U32>, +pk: +List<U32>, +msg: +List<U32>) -> W8:
  +h = H.hash(H.append(rb, H.append(pk, msg)))
  +lo = fl_of(w8(h))
  +hi = fl_of(w8(drop(h, 32n)))
  w8_of_fl(L.to_raw(L.add(L.from_raw(lo), L.mul(L.R3(), hi))))

# [8]([s]B - [k]A - R) == identity
def check_eq(+a: Pt, +r: Pt, +s: W8, +k: W8) -> Bool:
  +p = add_ni(dsm(s, k, neg_ni_z1(a)), neg_ni_z1(r))
  is_identity(double(double(double(p))))

def with_r(mr: Maybe<&2, Pt>, +a: Pt, +s: W8, +rb: +List<U32>, +pk: +List<U32>, +msg: +List<U32>) -> Bool:
  match mr:
    case None{}:
      False{}
    case Some{+r}:
      check_eq(a, r, s, challenge(rb, pk, msg))

def with_a(ma: Maybe<&2, Pt>, +s: W8, +rb: +List<U32>, +pk: +List<U32>, +msg: +List<U32>) -> Bool:
  match ma:
    case None{}:
      False{}
    case Some{+a}:
      with_r(decompress(w8(rb)), a, s, rb, pk, msg)

def with_s(ok: Bool, +s: W8, +pk: +List<U32>, +sig: +List<U32>, +msg: +List<U32>) -> Bool:
  match ok:
    case False{}:
      False{}
    case True{}:
      with_a(decompress(w8(pk)), s, take(sig, 32n), take(pk, 32n), msg)

def with_len(ok: Bool, +pk: +List<U32>, +sig: +List<U32>, +msg: +List<U32>) -> Bool:
  match ok:
    case False{}:
      False{}
    case True{}:
      +s = w8(drop(sig, 32n))
      with_s(U32.is_eq(L.lt_p(fl_of(s)), 1), s, pk, sig, msg)

# Ed25519 verification under ZIP 215. pk: 32 bytes; sig: 64 bytes (R || S); msg: any bytes.
# Each byte is one U32 in 0..255. Wrong lengths (pk < 32 or sig < 64 bytes) are rejected;
# extra trailing bytes beyond 32 / 64 are ignored (the caller passes exact fields).
def verify(+pk: +List<U32>, +sig: +List<U32>, +msg: +List<U32>) -> Bool:
  with_len(Bool.and(has(pk, 32n), has(sig, 64n)), pk, sig, msg)
