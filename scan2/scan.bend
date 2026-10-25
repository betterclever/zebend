# Constant time in the secret ivk (merged from harden/scan_ct): every ivk-dependent table
# lookup reads all 16 entries through masked selects, and the GLV signs are applied by masked
# select of y and -y, so the work per output does not depend on ivk. Marked "CT:".
#
# Ironwood trial decryption, round 2: the gpu-scan filter on field3's 64-bit-limb fields
# with the wallet key prepared once.
#
# Per compact output (epk, first ciphertext word):
#   P = decompress(epk); S = [ivk]P; K = BLAKE2b-256("Zcash_OrchardKDF", repr(S) || epk);
#   hit iff ChaCha20(K, nonce 0, counter 1) word 0 XOR ciphertext word 0 has low byte 0x03.
#
# ivk is the same for every output, so its GLV split and 4-bit digits are computed once
# (`prep`). Each output then runs a fixed Straus ladder: 32 x (4 doublings + 2 table adds)
# over [0..15]P1 and [0..15]P2, where P2's table is P1's mapped through the endomorphism
# phi(x, y, z) = (zeta x, y, z) instead of 15 more point additions. The projective results
# of a whole leaf share one inversion (Montgomery's trick) when encoded.
import Base
import ../halo2/lib/words.bend as Wd
import ../field3/fp64.bend as B
import ../field3/lib64/pallas.bend as V
import ./glv.bend as G
import ./kdf.bend as K

# --- the prepared key -------------------------------------------------------------------

# n1: sign of the first GLV half; flip = n1 xor n2; ds: digit pairs (d1 << 4 | d2), most
# significant first; k: the raw key (only the step-1 benchmark variant uses it).
type Prep is Data:
  Prep{n1: U32, flip: U32, ds: +List<U32>, k: Wd.W}

def digits(+n: Nat, +m1: Wd.W, +m2: Wd.W, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      acc
    case 1n+j:
      digits(j, m1, m2, ((G.digit(j, m1) << 4n) .|. G.digit(j, m2) : U32) <> acc)

def prep_split(s: G.Split, k: Wd.W) -> Prep:
  G.Split{+n1, +m1, +n2, +m2} = s
  Prep{n1, (n1 .^. n2 : U32), List.reverse(&2, U32, digits(32n, m1, m2, Nil{})), k}

def prep(+ivk: Wd.W) -> Prep:
  prep_split(G.split(ivk), ivk)

# --- one output's scalar multiplication --------------------------------------------------

# Table 2 entry i = (-1)^(n1 xor n2) * phi(table 1 entry i): phi commutes with scalar
# multiplication, and P2 = (-1)^n2 phi(P) while P1 = (-1)^n1 P.
# CT: c = 1 selects a, c = 0 selects b, limb by limb through masks (fp64's sel).
def pt_sel(+c: U32, a: V.Pt, b: V.Pt) -> V.Pt:
  V.Pt{+ax, +ay, +az} = a
  V.Pt{+bx, +by, +bz} = b
  V.Pt{B.sel(c, ax, bx), B.sel(c, ay, by), B.sel(c, az, bz)}

# CT: 1 if i == d else 0, for i, d < 16 (i xor d - 1 borrows into bit 31 only when equal).
def eq16(+i: U32, +d: U32) -> U32:
  (((i .^. d : U32) - 1 : U32) >> 31n : U32)

# CT: table entry d, touching every entry (replaces G.get's d-step list walk).
def ct_go(t: +List<V.Pt>, +i: U32, +d: U32, acc: V.Pt) -> V.Pt:
  match t:
    case Nil{}:
      acc
    case Con{h, rest}:
      ct_go(rest, (i + 1 : U32), d, pt_sel(eq16(i, d), h, acc))

def ct_get(+t: +List<V.Pt>, +d: U32) -> V.Pt:
  ct_go(t, 0, d, V.identity())

# CT: (-1)^n P for n in {0, 1}: both y and -y are computed (replaces G.neg_if's branch).
def ct_neg(+n: U32, p: V.Pt) -> V.Pt:
  V.Pt{x, +y, z} = p
  V.Pt{x, B.sel(n, B.neg(y), y), z}

def tab2(+flip: U32, t1: +List<V.Pt>) -> +List<V.Pt>:
  match t1:
    case Con{h, t}:
      ct_neg(flip, G.endo(h)) <> tab2(flip, t)
    case Nil{}:
      Nil{}

def ladder(ds: +List<U32>, +t1: +List<V.Pt>, +t2: +List<V.Pt>, acc: V.Pt) -> V.Pt:
  match ds:
    case Nil{}:
      acc
    case Con{+d, rest}:
      +a1 = V.add(G.dbl4(acc), ct_get(t1, (d >> 4n : U32)))
      ladder(rest, t1, t2, V.add(a1, ct_get(t2, (d .&. 15 : U32))))

def smul(+k: Prep, +p: V.Pt) -> V.Pt:
  Prep{+n1, +flip, +ds, _} = k
  +t1 = G.table(ct_neg(n1, p))
  ladder(ds, t1, tab2(flip, t1), V.identity())

# --- records, flags, tree ----------------------------------------------------------------

type Rec is Data:
  Rec{e: Wd.W, c: U32}

type Recs is Data:
  RNil{}
  RCons{+r: Rec, next: Recs}

type Flags is Data:
  FNil{}
  FCons{+f: U32, next: Flags}

type Tree is Data:
  Leaf{rs: Recs}
  Node{l: Tree, r: Tree}

type RTree is Data:
  RLeaf{fs: Flags}
  RNode{l: RTree, r: RTree}

# Stage 1 of a leaf: decompress and multiply. ok = 0 marks a failed decompression; the
# identity stands in for its point, and its flag is forced to 0 later.
type Mid is Data:
  Mid{ok: U32, e: Wd.W, c: U32, s: V.Pt}

def mid_of(+e: Wd.W, c: U32, +k: Prep, mp: Maybe<&2, V.Pt>) -> Mid:
  match mp:
    case Some{+p}:
      Mid{1, e, c, smul(k, p)}
    case None{}:
      Mid{0, e, c, V.identity()}

def mid(+k: Prep, r: Rec) -> Mid:
  Rec{+e, c} = r
  mid_of(e, c, k, V.decompress(e))

# Every list walk below is tail-recursive (accumulate, then reverse): since Bend 2.0.39
# (commit 5ce1e07f) a GPU lane faults past ~1023 frames of non-tail recursion, which would
# cap the outputs per lane.
def mids_rev(rs: Recs, +k: Prep, acc: +List<Mid>) -> +List<Mid>:
  match rs:
    case RNil{}:
      acc
    case RCons{r, next}:
      mids_rev(next, k, mid(k, r) <> acc)

def mids(rs: Recs, +k: Prep) -> +List<Mid>:
  List.reverse(&2, Mid, mids_rev(rs, k, Nil{}))

# z, with 1 in place of 0 so one identity cannot poison the leaf's batch inversion.
def z_of(m: Mid) -> B.Fp:
  Mid{_, _, _, s} = m
  V.Pt{_, _, +z} = s
  B.sel(Bool.to_u32(B.is_zero(z)), B.one(), z)

def zs_rev(ms: +List<Mid>, acc: +List<B.Fp>) -> +List<B.Fp>:
  match ms:
    case Con{m, t}:
      zs_rev(t, z_of(m) <> acc)
    case Nil{}:
      acc

def zs(ms: +List<Mid>) -> +List<B.Fp>:
  List.reverse(&2, B.Fp, zs_rev(ms, Nil{}))

# Batch inversion (Montgomery's trick) with a tail-recursive prefix pass; the back pass
# is field3's bi_go. Returns the prefix products last-first, as bi_go expects.
def prefix_rev(xs: +List<B.Fp>, +acc: B.Fp, out: +List<B.Fp>) -> +List<B.Fp>:
  match xs:
    case Nil{}:
      out
    case Con{+h, +t}:
      +a = B.mul(acc, h)
      prefix_rev(t, a, a <> out)

def batch_inv(+xs: +List<B.Fp>) -> +List<B.Fp>:
  B.bi_go(xs, prefix_rev(xs, B.one(), Nil{}))

# repr_P from projective (X, Y, Z) and Z^-1; the identity encodes as all zeros.
def enc(+s: V.Pt, +zi: B.Fp) -> Wd.W:
  V.Pt{+x, +y, +z} = s
  V.enc_fin(V.Aff{B.mul(x, zi), B.mul(y, zi)}, B.is_zero(z))

def kdf_w(+s: Wd.W, +p: Wd.W) -> K.U8w:
  Wd.W{s0, s1, s2, s3, s4, s5, s6, s7} = s
  Wd.W{p0, p1, p2, p3, p4, p5, p6, p7} = p
  K.kdf(s0, s1, s2, s3, s4, s5, s6, s7, p0, p1, p2, p3, p4, p5, p6, p7)

def ks_w0(k: K.U8w) -> U32:
  K.U8w{k0, k1, k2, k3, k4, k5, k6, k7} = k
  K.chacha_w0(k0, k1, k2, k3, k4, k5, k6, k7)

def flag(m: Mid, +zi: B.Fp) -> U32:
  Mid{ok, +e, c, +s} = m
  lead = (((c .^. ks_w0(kdf_w(enc(s, zi), e))) .&. 255) : U32)
  (ok .&. Bool.to_u32(U32.is_eq(lead, 3)) : U32)

# Flags come out in reverse leaf order, like gpu-scan's scan_list.
def flags(ms: +List<Mid>, zis: +List<B.Fp>, acc: Flags) -> Flags:
  match ms zis:
    case Con{m, mt} Con{zi, zt}:
      flags(mt, zt, FCons{flag(m, zi), acc})
    case _ _:
      acc

def leaf2(+ms: +List<Mid>) -> Flags:
  flags(ms, batch_inv(zs(ms)), FNil{})

def leaf(rs: Recs, +k: Prep) -> Flags:
  leaf2(mids(rs, k))

def scan(+n: Nat, t: Tree, +k: Prep) -> RTree:
  match n t:
    case _ Leaf{rs}:
      RLeaf{leaf(rs, k)}
    case 1n+j Node{l, r}:
      a b = scan(j, l, k) scan(j, r, k)
      RNode{a, b}
    case _ _:
      RLeaf{FNil{}}
