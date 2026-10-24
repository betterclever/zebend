# VARIANT (benchmark only): plain double-and-add, per-output inversion.
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
def tab2(+flip: U32, t1: +List<V.Pt>) -> +List<V.Pt>:
  match t1:
    case Con{h, t}:
      G.neg_if(flip, G.endo(h)) <> tab2(flip, t)
    case Nil{}:
      Nil{}

def ladder(ds: +List<U32>, +t1: +List<V.Pt>, +t2: +List<V.Pt>, acc: V.Pt) -> V.Pt:
  match ds:
    case Nil{}:
      acc
    case Con{+d, rest}:
      +a1 = V.add(G.dbl4(acc), G.get(t1, (d >> 4n : U32)))
      ladder(rest, t1, t2, V.add(a1, G.get(t2, (d .&. 15 : U32))))

def raw(k: Prep) -> Wd.W:
  Prep{_, _, _, +w} = k
  w

def smul(+k: Prep, +p: V.Pt) -> V.Pt:
  V.scalar_mul(p, raw(k))

def smul_glv(+k: Prep, +p: V.Pt) -> V.Pt:
  Prep{+n1, +flip, +ds, _} = k
  +t1 = G.table(G.neg_if(n1, p))
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

def mids(rs: Recs, +k: Prep) -> +List<Mid>:
  match rs:
    case RNil{}:
      Nil{}
    case RCons{r, next}:
      mid(k, r) <> mids(next, k)

# z, with 1 in place of 0 so one identity cannot poison the leaf's batch inversion.
def z_of(m: Mid) -> B.Fp:
  Mid{_, _, _, s} = m
  V.Pt{_, _, +z} = s
  B.sel(Bool.to_u32(B.is_zero(z)), B.one(), z)

def zs(ms: +List<Mid>) -> +List<B.Fp>:
  match ms:
    case Con{m, t}:
      z_of(m) <> zs(t)
    case Nil{}:
      Nil{}

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

def invs(ms: +List<Mid>) -> +List<B.Fp>:
  match ms:
    case Con{m, t}:
      B.inv(z_of(m)) <> invs(t)
    case Nil{}:
      Nil{}

def leaf2(+ms: +List<Mid>) -> Flags:
  flags(ms, invs(ms), FNil{})

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
