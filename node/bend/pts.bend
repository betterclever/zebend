# node/fast: the curve points zcash/wire's validator decodes, collected per block and
# checked in one batch (a balanced parallel tree: `check!` runs it on the Metal GPU).
#
# fast/wire/txv.bend is zcash/wire/txv.bend with jpoint/ppoint deferred (they only consume 32
# bytes). This module lists the same 32-byte fields, at the same positions, for a block that
# fast/wire accepted, and decodes them exactly as zcash/wire does:
#   Sapling v4 spend (384 B):  cv @0 jpoint(nso)   rk @96 jpoint            (txv spend4)
#   Sapling v4 output (948 B): cv @0 jpoint(nso)                            (txv out4)
#   Sapling v5 spend (96 B):   cv @0 jpoint(nso)   rk @64 jpoint            (txv spend5)
#   Sapling v5 output (756 B): cv @0 jpoint(nso)                            (txv out5)
#   Orchard/Ironwood action (820 B): cv @0 ppoint(allow identity), rk @64 ppoint(no identity),
#                                    epk @128 ppoint(no identity)           (txv action)
# txv reads v4 Sapling only for an overwintered v4 tx (group checked by the validator), v5/v6
# bundles only for overwintered v5/v6; a non-overwintered tx is read as Sprout (no points).
# Sprout JoinSplits have no decoded points. The layouts are parse.bend's (fuzzed against
# zcash_primitives through txv.bend).
import Base
import ./parse.bend as P
import ../../zcash/wire/hb.bend as H
import ../../zcash/wire/jj.bend as J
import ../../zcash/halo2/lib/pallas.bend as Pa
import ../../zcash/halo2/lib/words.bend as Wd
import ../../zcash/wire/fr.bend as F
import ../../zcash/halo2/lib/fp.bend as B

# JN: Jubjub, not small order (cv); JA: Jubjub, any (rk); PI: Pallas, identity allowed (cv);
# PN: Pallas, not the identity (rk, epk).
type Kd is Data:
  JN{}
  JA{}
  PI{}
  PN{}

# b: the block's index in the batch; w: the 32 bytes as 8 LE words.
type Pt is Data:
  Pt{b: U32, k: Kd, w: Wd.W}

# ---------------------------------------------------------------- decoding (as txv.bend)

# The reference: zcash/wire's decoders, as txv.bend calls them (kept for the differential test,
# t_pts.bend).
def j_ok(+nso: Bool, m: Maybe<&2, J.Jp>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{p}:
      Bool.not(nso) || Bool.not(J.is_small_order(p))

def p_ok(+allow_id: Bool, m: Maybe<&2, Pa.Pt>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{p}:
      allow_id || Bool.not(Pa.is_identity(p))

def pt_ok_ref(k: Kd, +w: Wd.W) -> Bool:
  match k:
    case JN{}:
      j_ok(True{}, J.decode(w))
    case JA{}:
      j_ok(False{}, J.decode(w))
    case PI{}:
      p_ok(True{}, Pa.decompress(w))
    case PN{}:
      p_ok(False{}, Pa.decompress(w))

# The same predicates without computing the point (no inversion, no square root): only
# whether it exists. Both fields have m - 1 = 2^32 t (t odd), so Euler's criterion
# x^((m-1)/2) is pow_c3(x)^2 * x (= x^t, as in the Tonelli-Shanks start of sqrt_cand)
# squared 31 times. sqrt(x) is Some exactly when x is 0 or a square (sqrt_cand is a root
# of every square; the result is checked by squaring).
def fr_euler1(+x: F.Fr) -> Bool:
  +z0 = F.pow_c3(x)
  F.is_eq(F.sqr_n(31n, F.mul(F.sqr(z0), x)), F.one())

def fp_euler1(+x: B.Fp) -> Bool:
  +z0 = B.pow_c3(x)
  B.is_eq(B.sqr_n(31n, B.mul(B.sqr(z0), x)), B.one())

def j_fin(xz: Bool, +nso: Bool, +small: Bool, +sign: U32, +num: F.Fr, +den: F.Fr) -> Bool:
  match xz:
    case True{}:
      U32.is_eq(sign, 0) && Bool.not(nso && small)
    case False{}:
      fr_euler1(F.mul(num, den)) && Bool.not(nso && small)

# Jubjub (jj.bend decode): v canonical; u^2 = x = (v^2 - 1) / (1 + d v^2) (1/0 read as 0)
# must be a square; u = 0 with sign 1 is rejected (ZIP 216). For den != 0, x and num * den
# differ by the square den^-2, so they are squares together, and x = 0 iff num = 0.
# Small order (jj.bend is_small_order on (+-u, v)): u v = 0 or u^2 + v^2 = 0, i.e. x = 0, or
# v = 0, or x + v^2 = 0 (for den != 0: num + v^2 den = 0; for den = 0, x = 0).
def j_v(+nso: Bool, +v: F.Fr, +sign: U32) -> Bool:
  +v2 = F.sqr(v)
  +num = F.sub(v2, F.one())
  +den = F.add(F.one(), F.mul(J.d(), v2))
  +den0 = F.is_zero(den)
  +xz = den0 || F.is_zero(num)
  +small = xz || F.is_zero(v) || F.is_zero(F.add(num, F.mul(v2, den)))
  j_fin(xz, nso, small, sign, num, den)

def j_canon(ok: Bool, +nso: Bool, +vw: Wd.W, +sign: U32) -> Bool:
  match ok:
    case False{}:
      False{}
    case True{}:
      j_v(nso, F.from_words(vw), sign)

def j_check(+nso: Bool, +w: Wd.W) -> Bool:
  +vw = Wd.clear_top_bit(w)
  j_canon(Wd.is_lt(vw, F.modulus()), nso, vw, Wd.top_bit(w))

def p_rhs(z: Bool, +rhs: B.Fp) -> Bool:
  match z:
    case True{}:
      True{}
    case False{}:
      fp_euler1(rhs)

# Pallas (pallas.bend decompress): x canonical; x = 0 with sign 0 is the identity; x = 0 with
# sign 1 needs sqrt(5) (none: 5 is a non-residue); otherwise y^2 = x^3 + 5 must be 0 or a
# square. Every point but the identity has z = 1.
def p_x(x0: Bool, +allow_id: Bool, +x: B.Fp, +sign: U32) -> Bool:
  match x0:
    case True{}:
      allow_id && U32.is_eq(sign, 0)
    case False{}:
      +rhs = B.add(B.mul(B.sqr(x), x), B.from_u32(5))
      p_rhs(B.is_zero(rhs), rhs)

def p_canon(ok: Bool, +allow_id: Bool, +xw: Wd.W, +sign: U32) -> Bool:
  match ok:
    case False{}:
      False{}
    case True{}:
      +x = B.from_words(xw)
      p_x(B.is_zero(x), allow_id, x, sign)

def p_check(+allow_id: Bool, +w: Wd.W) -> Bool:
  +xw = Wd.clear_top_bit(w)
  p_canon(Wd.is_lt(xw, B.modulus()), allow_id, xw, Wd.top_bit(w))

def pt_ok(k: Kd, +w: Wd.W) -> Bool:
  match k:
    case JN{}:
      j_check(True{}, w)
    case JA{}:
      j_check(False{}, w)
    case PI{}:
      p_check(True{}, w)
    case PN{}:
      p_check(False{}, w)

# ---------------------------------------------------------------- collecting

def pt_at(+b: U32, k: Kd, +c: P.C, +off: U32) -> Pt:
  Pt{b, k, H.w32(P.c_xs(P.skip(c, off)))}

def cat(xs: +List<Pt>, ys: +List<Pt>) -> +List<Pt>:
  List.append(&2, Pt, xs, ys)

def sp4(n: Nat, +b: U32, +c: P.C, acc: +List<Pt>) -> +List<Pt>:
  match n:
    case 0n:
      acc
    case 1n+m:
      sp4(m, b, P.skip(c, 384), pt_at(b, JA{}, c, 96) <> pt_at(b, JN{}, c, 0) <> acc)

def op4(n: Nat, +b: U32, +c: P.C, acc: +List<Pt>) -> +List<Pt>:
  match n:
    case 0n:
      acc
    case 1n+m:
      op4(m, b, P.skip(c, 948), pt_at(b, JN{}, c, 0) <> acc)

def sp5(n: Nat, +b: U32, +c: P.C, acc: +List<Pt>) -> +List<Pt>:
  match n:
    case 0n:
      acc
    case 1n+m:
      sp5(m, b, P.skip(c, 96), pt_at(b, JA{}, c, 64) <> pt_at(b, JN{}, c, 0) <> acc)

def op5(n: Nat, +b: U32, +c: P.C, acc: +List<Pt>) -> +List<Pt>:
  match n:
    case 0n:
      acc
    case 1n+m:
      op5(m, b, P.skip(c, 756), pt_at(b, JN{}, c, 0) <> acc)

def acts(n: Nat, +b: U32, +c: P.C, acc: +List<Pt>) -> +List<Pt>:
  match n:
    case 0n:
      acc
    case 1n+m:
      acts(m, b, P.skip(c, 820), pt_at(b, PN{}, c, 128) <> pt_at(b, PN{}, c, 64) <> pt_at(b, PI{}, c, 0) <> acc)

# v4: after the transparent part: lock 4, expiry 4, valueBalance 8, spends, outputs.
def tx4(+b: U32, +c0: P.C, acc: +List<Pt>) -> +List<Pt>:
  +tp = P.transparent(P.skip(c0, 8))
  +sc = P.skip(P.tp_c(tp), 16)
  +ns = P.cs(sc)
  +nsv = P.cs_v(ns)
  +no = P.cs(P.skip(P.cs_c(ns), (nsv * 384 : U32)))
  op4(U32.to_nat(P.cs_v(no)), b, P.cs_c(no), sp4(U32.to_nat(nsv), b, P.cs_c(ns), acc))

def bun(+b: U32, +c: P.C, acc: +List<Pt>) -> +List<Pt>:
  +na = P.cs(c)
  acts(U32.to_nat(P.cs_v(na)), b, P.cs_c(na), acc)

def iron_sel(v6: Bool, +b: U32, +c: P.C, acc: +List<Pt>) -> +List<Pt>:
  match v6:
    case True{}:
      bun(b, c, acc)
    case False{}:
      acc

# v5/v6: header fragment (20 bytes incl. version and group), transparent, Sapling v5,
# Orchard, [Ironwood].
def tx56(+v6: Bool, +b: U32, +c0: P.C, acc: +List<Pt>) -> +List<Pt>:
  +tp = P.transparent(P.skip(c0, 20))
  +sc = P.tp_c(tp)
  +ns = P.cs(sc)
  +nsv = P.cs_v(ns)
  +no = P.cs(P.skip(P.cs_c(ns), (nsv * 96 : U32)))
  +a1 = op5(U32.to_nat(P.cs_v(no)), b, P.cs_c(no), sp5(U32.to_nat(nsv), b, P.cs_c(ns), acc))
  +sap = P.sapling5(sc)
  +orch = P.bundle(P.sap_c(sap))
  iron_sel(v6, b, P.bun_c(orch), bun(b, P.sap_c(sap), a1))

def by_v4(v4: Bool, +b: U32, +c: P.C, acc: +List<Pt>) -> +List<Pt>:
  match v4:
    case True{}:
      tx4(b, c, acc)
    case False{}:
      acc

def by_v56(v56: Bool, +v: U32, +b: U32, +c: P.C, acc: +List<Pt>) -> +List<Pt>:
  match v56:
    case True{}:
      tx56(U32.is_eq(v, 6), b, c, acc)
    case False{}:
      by_v4(U32.is_eq(v, 4), b, c, acc)

def by_ver_ow(+v: U32, +b: U32, +c: P.C, acc: +List<Pt>) -> +List<Pt>:
  by_v56(U32.is_ge(v, 5), v, b, c, acc)

def tx_ow(ow: Bool, +v: U32, +b: U32, +c: P.C, acc: +List<Pt>) -> +List<Pt>:
  match ow:
    case True{}:
      by_ver_ow(v, b, c, acc)
    case False{}:
      acc

# The points of one transaction starting at c (prepended to acc).
def tx(+b: U32, +c: P.C, acc: +List<Pt>) -> +List<Pt>:
  +h = P.u32(c)
  tx_ow(U32.is_eq((h >> 31n : U32), 1), (h .&. 2147483647 : U32), b, c, acc)
