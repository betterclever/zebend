# RedJubjub (Sapling spend-auth and binding signatures) in Bend, single and batched.
#
# A signature (R̄, s) on msg under vk, with base B (G = SpendAuthSig base for spend-auth,
# R = value-commitment randomness base for binding), is valid iff s < r_J, R̄ and vk decode
# (ZIP 216: jubjub::AffinePoint::from_bytes), and
#   [8] (R + [c] vk - [s] B) = 0,   c = BLAKE2b-512("Zcash_RedJubjubH", R̄ || vk || msg) mod r_J.
# For binding signatures, vk = bvk = sum cv_spend - sum cv_output - [valueBalance] V,
# computed here from the cvs (each must decode) and the i64 valueBalance.
#
# Batch (reddsa's batch equation, cofactored): accept iff
#   [8] ( sum z_i R_i + sum (z_i c_i) vk_i - (sum_SA z_i s_i) G - (sum_B z_i s_i) R ) = 0
# with 128-bit weights z_i derived from the whole batch (Fiat-Shamir, as research/sigbatch/):
#   leaf_i = BLAKE2b-256(kind pers, R̄ || vk || msg || s), seed = Merkle root of the leaves,
#   z_i = low 128 bits of BLAKE2b-256("ZebendJJBatchZ__", seed || le32(i)).
# [8] maps everything into the prime-order subgroup (order r_J > 2^251), so an invalid
# signature passes with probability <= 2^-128 per oracle query (see README.md).
# Items that fail to decode, or have s >= r_J, are rejected without entering the batch;
# a failing batch is bisected down to the failing signatures.
import Base
import ../../halo2/lib/words.bend as Wd
import ../jubjub/fr.bend as F
import ../jubjub/fs.bend as S
import ../jubjub/jubjub.bend as J
import ../jubjub/consts.bend as K
import ../../tx/blake2b.bend as H
import ./msm_jj.bend as M

# ------------------------------------------------------------------ input items

# kind: 0 spend-auth (vk = rk), 1 binding (vk from cvs and valueBalance lo/hi), 2 binding
# with the vk given explicitly (test vectors);
# ncv = n_spend_cv | n_output_cv << 16.
type It is Data:
  It{kind: U32, ncv: U32, lo: U32, hi: U32, r: Wd.W, s: Wd.W, msg: Wd.W, vk: Wd.W, cvs: +List<Wd.W>}

def words(ws: +List<U32>) -> +List<Wd.W>:
  match ws:
    case Con{a, Con{b, Con{c, Con{d, Con{e, Con{f, Con{g, Con{h, rest}}}}}}}}:
      Wd.W{a, b, c, d, e, f, g, h} <> words(rest)
    case _:
      Nil{}

def pack_go(bs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match bs:
    case Con{+a, Con{+b, Con{+c, Con{+d, rest}}}}:
      pack_go(rest, (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32) <> acc)
    case _:
      List.reverse(&2, U32, acc)

def ncv_total(+n: U32) -> Nat:
  U32.to_nat(((n .&. 65535) + (n >> 16n) : U32))

def parse_go(fuel: Nat, ws: +List<U32>, acc: +List<It>) -> +List<It>:
  match fuel ws:
    case 1n+fu Con{k, Con{+n, Con{lo, Con{hi, Con{r0, Con{r1, Con{r2, Con{r3, Con{r4, Con{r5, Con{r6, Con{r7, Con{s0, Con{s1, Con{s2, Con{s3, Con{s4, Con{s5, Con{s6, Con{s7, Con{m0, Con{m1, Con{m2, Con{m3, Con{m4, Con{m5, Con{m6, Con{m7, Con{v0, Con{v1, Con{v2, Con{v3, Con{v4, Con{v5, Con{v6, Con{v7, +t}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}:
      +nw = (ncv_total(n) * 8n : Nat)
      parse_go(fu, List.drop(&2, U32, t, nw), It{k, n, lo, hi, Wd.W{r0, r1, r2, r3, r4, r5, r6, r7}, Wd.W{s0, s1, s2, s3, s4, s5, s6, s7}, Wd.W{m0, m1, m2, m3, m4, m5, m6, m7}, Wd.W{v0, v1, v2, v3, v4, v5, v6, v7}, words(List.take(&2, U32, t, nw))} <> acc)
    case _ _:
      List.reverse(&2, It, acc)

def parse_hdr(ws: +List<U32>) -> +List<It>:
  match ws:
    case Con{n, t}:
      parse_go(U32.to_nat(n), t, Nil{})
    case Nil{}:
      Nil{}

# A chunk file: u32 n_items, then the items (zcash/sapling/oracle README.md).
def parse(bs: +List<U32>) -> +List<It>:
  parse_hdr(pack_go(bs, Nil{}))

# ------------------------------------------------------------------ bytes, hashes

def bytes_of(w: Wd.W) -> +List<U32>:
  Wd.W{a, b, c, d, e, f, g, h} = w
  H.b2_w4(a, H.b2_w4(b, H.b2_w4(c, H.b2_w4(d, H.b2_w4(e, H.b2_w4(f, H.b2_w4(g, H.b2_w4(h, Nil{}))))))))

def first_w(xs: +List<Wd.W>) -> Wd.W:
  match xs:
    case Con{w, _}:
      w
    case Nil{}:
      Wd.zero()

def w_of(bs: +List<U32>) -> Wd.W:
  first_w(words(pack_go(List.take(&2, U32, bs, 32n), Nil{})))

def cat(a: +List<U32>, b: +List<U32>) -> +List<U32>:
  List.append(&2, U32, a, b)

def pers_h() -> H.P4:
  H.P4{1935762266, 1699897192, 1651853924, 1214412138}

def pers_leaf_sa() -> H.P4:
  H.P4{1700947290, 1246389358, 1282695490, 1095982950}

def pers_leaf_bd() -> H.P4:
  H.P4{1700947290, 1246389358, 1282695490, 1682071398}

def pers_node() -> H.P4:
  H.P4{1700947290, 1246389358, 1316249922, 1600480367}

def pers_z() -> H.P4:
  H.P4{1700947290, 1246389358, 1668571458, 1600084584}

def leaf_pers_b(sa: Bool) -> H.P4:
  match sa:
    case True{}:
      pers_leaf_sa()
    case False{}:
      pers_leaf_bd()

def leaf_pers(+kind: U32) -> H.P4:
  leaf_pers_b(U32.is_eq(kind, 0))

# c = BLAKE2b-512("Zcash_RedJubjubH", R̄ || vk || msg) mod r_J
def challenge(+pre: +List<U32>) -> S.Fs:
  +h = H.hash64(pers_h(), pre)
  S.from_wide(w_of(h), w_of(List.drop(&2, U32, h, 32n)))

# ------------------------------------------------------------------ bvk

def vpt() -> J.Pt:
  J.from_aff(K.v_cv())

# [valueBalance] V for an i64 (lo, hi) in two's complement.
def vb_mul_s(neg: Bool, +v: J.Pt, +lo: U32, +hi: U32) -> J.Pt:
  match neg:
    case False{}:
      J.mul64(v, lo, hi)
    case True{}:
      +nlo = (U32.not(lo) + 1 : U32)
      +nhi = (U32.not(hi) + Bool.to_u32(U32.is_zero(lo)) : U32)
      J.neg(J.mul64(v, nlo, nhi))

def vb_mul(+v: J.Pt, +lo: U32, +hi: U32) -> J.Pt:
  vb_mul_s(U32.is_ge(hi, 2147483648), v, lo, hi)

type CS is Data:
  CS{ok: Bool, p: J.Pt}

def cv_step(st: CS, m: Maybe<&2, J.Pt>, neg: Bool) -> CS:
  CS{ok, acc} = st
  match m:
    case Some{p}:
      match neg:
        case True{}:
          CS{ok, J.sub(acc, p)}
        case False{}:
          CS{ok, J.add(acc, p)}
    case None{}:
      CS{False{}, acc}

# Spends' cvs (the first nsp) are added, outputs' cvs subtracted.
def cv_go(cvs: +List<Wd.W>, +nsp: Nat, st: CS) -> CS:
  match cvs nsp:
    case Nil{} _:
      st
    case Con{w, t} 0n:
      cv_go(t, 0n, cv_step(st, J.decompress(w), True{}))
    case Con{w, t} 1n+k:
      cv_go(t, k, cv_step(st, J.decompress(w), False{}))

def cv_fin(st: CS) -> Maybe<&2, J.Pt>:
  CS{ok, p} = st
  match ok:
    case True{}:
      Some{p}
    case False{}:
      None{}

def bvk_of(m: Maybe<&2, J.Pt>, +v: J.Pt, +lo: U32, +hi: U32) -> Maybe<&2, J.Pt>:
  match m:
    case Some{sum}:
      Some{J.sub(sum, vb_mul(v, lo, hi))}
    case None{}:
      None{}

# bvk = sum cv_spend - sum cv_output - [valueBalance] V
def bvk(cvs: +List<Wd.W>, +ncv: U32, +v: J.Pt, +lo: U32, +hi: U32) -> Maybe<&2, J.Pt>:
  bvk_of(cv_fin(cv_go(cvs, U32.to_nat((ncv .&. 65535 : U32)), CS{True{}, J.identity()})), v, lo, hi)

# The verification key as a Niels point and its 32-byte encoding.
type VK is Data:
  NoVK{}
  VK{n: J.Ni, w: Wd.W}

def vk_sa(m: Maybe<&2, J.Pt>, w: Wd.W) -> VK:
  match m:
    case Some{p}:
      VK{J.ni_of_z1(p), w}
    case None{}:
      NoVK{}

def vk_bd(m: Maybe<&2, J.Pt>) -> VK:
  match m:
    case Some{p}:
      +a = J.to_aff(p)
      VK{J.ni_of_aff(a), J.enc_aff(a)}
    case None{}:
      NoVK{}

# kind 1 derives bvk from the cvs; kinds 0 (spend-auth) and 2 (binding with an explicit vk,
# for test vectors) decode the vk field.
def vk_sel(derive: Bool, +vkw: Wd.W, +it_cvs: +List<Wd.W>, +ncv: U32, +v: J.Pt, +lo: U32, +hi: U32) -> VK:
  match derive:
    case False{}:
      vk_sa(J.decompress(vkw), vkw)
    case True{}:
      vk_bd(bvk(it_cvs, ncv, v, lo, hi))

# ------------------------------------------------------------------ preparation

type Pr is Data:
  Bad{}
  Pr{kind: U32, r: J.Ni, vk: J.Ni, s: S.Fs, c: S.Fs, leaf: +List<U32>}

def pr_fin(+kind: U32, mr: Maybe<&2, J.Pt>, vk: VK, +rw: Wd.W, +sw: Wd.W, +msg: Wd.W) -> Pr:
  match mr vk:
    case Some{r} VK{n, +vkw}:
      +pre = cat(bytes_of(rw), cat(bytes_of(vkw), bytes_of(msg)))
      Pr{kind, J.ni_of_z1(r), n, S.from_words(sw), challenge(pre), H.hash32(leaf_pers(kind), cat(pre, bytes_of(sw)))}
    case _ _:
      Bad{}

def pr_s(canon: Bool, +it: It, +v: J.Pt) -> Pr:
  match canon:
    case False{}:
      Bad{}
    case True{}:
      It{+kind, +ncv, +lo, +hi, +r, +s, +msg, +vk, cvs} = it
      pr_fin(kind, J.decompress(r), vk_sel(U32.is_eq(kind, 1), vk, cvs, ncv, v, lo, hi), r, s, msg)

def prep(+it: It, +v: J.Pt) -> Pr:
  It{_, _, _, _, _, +s, _, _, _} = it
  pr_s(Wd.is_lt(s, S.modulus()), it, v)

# ------------------------------------------------------------------ single verification

def base_of(sa: Bool) -> J.Pt:
  match sa:
    case True{}:
      J.from_aff(K.g_spendauth())
    case False{}:
      J.from_aff(K.r_cv())

# [8] (R + [c] vk - [s] B) == identity, for a prepared signature (Niels points are affine).
def ni_pt(n: J.Ni) -> J.Pt:
  J.add_ni(J.identity(), n)

def verify_pr(p: Pr) -> Bool:
  match p:
    case Bad{}:
      False{}
    case Pr{kind, r, vk, s, c, _}:
      +e = J.sub(J.add(ni_pt(r), J.scalar_mul(ni_pt(vk), S.to_words(c))), J.scalar_mul(base_of(U32.is_eq(kind, 0)), S.to_words(s)))
      J.is_identity(J.mul_by_cofactor(e))

def verify1(+it: It) -> Bool:
  verify_pr(prep(it, vpt()))

# ------------------------------------------------------------------ batch

type Ix is Data:
  Ix{i: U32, p: Pr}

type Pp is Data:
  Pp{good: +List<Ix>, bad: +List<U32>}

def pp_one(+i: U32, p: Pr) -> Pp:
  match p:
    case Bad{}:
      Pp{Nil{}, i <> Nil{}}
    case Pr{kind, r, vk, s, c, leaf}:
      Pp{Ix{i, Pr{kind, r, vk, s, c, leaf}} <> Nil{}, Nil{}}

def pp_cat(a: Pp, b: Pp) -> Pp:
  Pp{ga, ba} = a
  Pp{gb, bb} = b
  Pp{List.append(&2, Ix, ga, gb), List.append(&2, U32, ba, bb)}

def prep_all(+fuel: Nat, +cnt: Nat, +i0: U32, +xs: +List<It>, +v: J.Pt) -> Pp:
  match fuel cnt xs:
    case _ 0n _:
      Pp{Nil{}, Nil{}}
    case _ 1n Con{+x, _}:
      pp_one(i0, prep(x, v))
    case 1n+f _ _:
      +h = Nat.div(cnt, 2n)
      a b = prep_all(f, h, i0, List.take(&2, It, xs, h), v) prep_all(f, Nat.sub(cnt, h), (i0 + U32.from_nat(h) : U32), List.drop(&2, It, xs, h), v)
      pp_cat(a, b)
    case _ _ _:
      Pp{Nil{}, Nil{}}

def pr_leaf(p: Pr) -> +List<U32>:
  match p:
    case Pr{_, _, _, _, _, leaf}:
      leaf
    case Bad{}:
      Nil{}

def ix_leaf(x: Ix) -> +List<U32>:
  Ix{_, p} = x
  pr_leaf(p)

def root(+fuel: Nat, +cnt: Nat, +xs: +List<Ix>) -> +List<U32>:
  match fuel cnt xs:
    case _ 1n Con{+x, _}:
      ix_leaf(x)
    case 1n+f _ _:
      +h = Nat.div(cnt, 2n)
      a b = root(f, h, List.take(&2, Ix, xs, h)) root(f, Nat.sub(cnt, h), List.drop(&2, Ix, xs, h))
      H.hash32(pers_node(), cat(a, b))
    case _ _ _:
      H.hash32(pers_node(), Nil{})

def lo128(w: Wd.W) -> Wd.W:
  Wd.W{a, b, c, d, _, _, _, _} = w
  Wd.W{a, b, c, d, 0, 0, 0, 0}

def zw(+seed: +List<U32>, +j: U32) -> Wd.W:
  lo128(w_of(H.hash32(pers_z(), cat(seed, H.b2_w4(j, Nil{})))))

# MSM terms: Niels points, scalar words, and sum z s per base.
type T is Data:
  T{ps: +List<J.Ni>, ss: +List<Wd.W>, sa: S.Fs, sb: S.Fs}

def t_sel(sa: Bool, ps: +List<J.Ni>, ss: +List<Wd.W>, +zs: S.Fs) -> T:
  match sa:
    case True{}:
      T{ps, ss, zs, S.zero()}
    case False{}:
      T{ps, ss, S.zero(), zs}

def t_pr(+z: Wd.W, p: Pr) -> T:
  match p:
    case Pr{kind, r, vk, s, c, _}:
      +zf = S.from_words(z)
      t_sel(U32.is_eq(kind, 0), r <> vk <> Nil{}, z <> S.to_words(S.mul(zf, c)) <> Nil{}, S.mul(zf, s))
    case Bad{}:
      T{Nil{}, Nil{}, S.zero(), S.zero()}

def t_one(+z: Wd.W, x: Ix) -> T:
  Ix{_, p} = x
  t_pr(z, p)

def t_cat(a: T, b: T) -> T:
  T{pa, sa, a1, a2} = a
  T{pb, sb, b1, b2} = b
  T{List.append(&2, J.Ni, pa, pb), List.append(&2, Wd.W, sa, sb), S.add(a1, b1), S.add(a2, b2)}

def terms(+fuel: Nat, +cnt: Nat, +j0: U32, +xs: +List<Ix>, +seed: +List<U32>) -> T:
  match fuel cnt xs:
    case _ 1n Con{+x, _}:
      t_one(zw(seed, j0), x)
    case 1n+f _ _:
      +h = Nat.div(cnt, 2n)
      a b = terms(f, h, j0, List.take(&2, Ix, xs, h), seed) terms(f, Nat.sub(cnt, h), (j0 + U32.from_nat(h) : U32), List.drop(&2, Ix, xs, h), seed)
      t_cat(a, b)
    case _ _ _:
      T{Nil{}, Nil{}, S.zero(), S.zero()}

def eq_fin(+c: U32, t: T) -> Bool:
  T{ps, ss, sa, sb} = t
  +ps2 = List.append(&2, J.Ni, ps, J.ni_of_aff(K.g_spendauth()) <> J.ni_of_aff(K.r_cv()) <> Nil{})
  +ss2 = List.append(&2, Wd.W, ss, S.to_words(S.neg(sa)) <> S.to_words(S.neg(sb)) <> Nil{})
  J.is_identity(J.mul_by_cofactor(M.msm(c, ps2, ss2)))

def batch_ok(+c: U32, +cnt: Nat, +xs: +List<Ix>) -> Bool:
  +seed = root(16n, cnt, xs)
  eq_fin(c, terms(16n, cnt, 0, xs, seed))

def ix_i(x: Ix) -> U32:
  Ix{+i, _} = x
  i

def find(+fuel: Nat, ok: Bool, +c: U32, +cnt: Nat, +xs: +List<Ix>) -> +List<U32>:
  match fuel ok cnt xs:
    case _ True{} _ _:
      Nil{}
    case _ False{} 1n Con{+x, _}:
      ix_i(x) <> Nil{}
    case 1n+f False{} _ _:
      +h = Nat.div(cnt, 2n)
      +h2 = Nat.sub(cnt, h)
      +xa = List.take(&2, Ix, xs, h)
      +xb = List.drop(&2, Ix, xs, h)
      a b = find(f, batch_ok(c, h, xa), c, h, xa) find(f, batch_ok(c, h2, xb), c, h2, xb)
      List.append(&2, U32, a, b)
    case _ _ _ _:
      Nil{}

def verify_pp(+c: U32, pp: Pp) -> +List<U32>:
  Pp{+good, bad} = pp
  +n = List.length(&2, Ix, good)
  List.append(&2, U32, bad, find(32n, batch_ok(c, n, good), c, n, good))

def prepare(+xs: +List<It>) -> Pp:
  +v = vpt()
  prep_all(16n, List.length(&2, It, xs), 0, xs, v)

def pp_ngood(pp: Pp) -> Nat:
  Pp{+good, _} = pp
  List.length(&2, Ix, good)

# Per-signature verdicts (no batching): one bit per item, in order.
def single_all(+fuel: Nat, +cnt: Nat, +xs: +List<It>) -> +List<Bool>:
  match fuel cnt xs:
    case _ 0n _:
      Nil{}
    case _ 1n Con{+x, _}:
      verify1(x) <> Nil{}
    case 1n+f _ _:
      +h = Nat.div(cnt, 2n)
      a b = single_all(f, h, List.take(&2, It, xs, h)) single_all(f, Nat.sub(cnt, h), List.drop(&2, It, xs, h))
      List.append(&2, Bool, a, b)
    case _ _ _:
      Nil{}
