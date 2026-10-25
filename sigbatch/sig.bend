# Batched RedPallas verification (reddsa's batch algorithm, prime-order Pallas).
#
# Every signature i, with base B_i (G_SPENDAUTH or R_CV), is valid iff
#   E_i = R_i + [c_i] vk_i - [s_i] B_i = 0,  c_i = BLAKE2b-512("Zcash_RedPallasH", R̄ || vk || msg) mod q.
# A batch is accepted iff sum_i [z_i] E_i = 0, i.e. one multiscalar multiplication
#   sum_i [z_i] R_i + sum_i [z_i c_i] vk_i + [-sum_SA z_i s_i] G_SPENDAUTH + [-sum_B z_i s_i] R_CV = 0,
# with 128-bit weights z_i derived from the whole batch (see README.md):
#   leaf_i = BLAKE2b-256(kind pers, R̄ || vk || msg || s), seed = Merkle root of the leaves,
#   z_i = low 128 bits of BLAKE2b-256("ZebendSigBatchZ_", seed || le32(i)).
# Items whose R, vk or cv do not decompress, or whose s is not canonical, are rejected
# without entering the batch (reddsa rejects them while parsing). A rejected batch is split
# in halves until every failing signature is isolated.
import Base
import ../halo2/lib/words.bend as Wd
import ../field3/fq64.bend as S
import ../field3/lib64/pallas.bend as P
import ../node/tx/blake2b.bend as H
import ../node/tx/consts.bend as K
import ./msm_pallas.bend as BA
import ./msm_fast_pallas.bend as MF

# ------------------------------------------------------------------ input items

# kind: 0 spend-auth (vk = rk), 1 binding (vk derived from cvs and valueBalance lo/hi).
type It is Data:
  It{kind: U32, lo: U32, hi: U32, r: Wd.W, s: Wd.W, msg: Wd.W, vk: Wd.W, cvs: +List<Wd.W>}

# Words -> 256-bit values, 8 at a time.
def words(ws: +List<U32>) -> +List<Wd.W>:
  match ws:
    case Con{a, Con{b, Con{c, Con{d, Con{e, Con{f, Con{g, Con{h, rest}}}}}}}}:
      Wd.W{a, b, c, d, e, f, g, h} <> words(rest)
    case _:
      Nil{}

# Little-endian bytes -> U32 words (tail-recursive: chunk files are ~1.5 MB).
def pack_go(bs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match bs:
    case Con{+a, Con{+b, Con{+c, Con{+d, rest}}}}:
      pack_go(rest, (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32) <> acc)
    case _:
      List.reverse(&2, U32, acc)

# Item header (4 words), R, s, msg, vk (8 words each), then ncv cvs (8 words each).
def parse_go(fuel: Nat, ws: +List<U32>, acc: +List<It>) -> +List<It>:
  match fuel ws:
    case 1n+fu Con{k, Con{+n, Con{lo, Con{hi, Con{r0, Con{r1, Con{r2, Con{r3, Con{r4, Con{r5, Con{r6, Con{r7, Con{s0, Con{s1, Con{s2, Con{s3, Con{s4, Con{s5, Con{s6, Con{s7, Con{m0, Con{m1, Con{m2, Con{m3, Con{m4, Con{m5, Con{m6, Con{m7, Con{v0, Con{v1, Con{v2, Con{v3, Con{v4, Con{v5, Con{v6, Con{v7, +t}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}:
      +nw = (U32.to_nat(n) * 8n : Nat)
      parse_go(fu, List.drop(&2, U32, t, nw), It{k, lo, hi, Wd.W{r0, r1, r2, r3, r4, r5, r6, r7}, Wd.W{s0, s1, s2, s3, s4, s5, s6, s7}, Wd.W{m0, m1, m2, m3, m4, m5, m6, m7}, Wd.W{v0, v1, v2, v3, v4, v5, v6, v7}, words(List.take(&2, U32, t, nw))} <> acc)
    case _ _:
      List.reverse(&2, It, acc)

def parse_hdr(ws: +List<U32>) -> +List<It>:
  match ws:
    case Con{n, t}:
      parse_go(U32.to_nat(n), t, Nil{})
    case Nil{}:
      Nil{}

# A chunk file: u32 n_items, then the items.
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

# The first 32 bytes of a byte list as little-endian words.
def w_of(bs: +List<U32>) -> Wd.W:
  first_w(words(pack_go(List.take(&2, U32, bs, 32n), Nil{})))

def cat(a: +List<U32>, b: +List<U32>) -> +List<U32>:
  List.append(&2, U32, a, b)

def pers_leaf_sa() -> H.P4:
  H.P4{1700947290, 1767072878, 1952531047, 1095984716}

def pers_leaf_bd() -> H.P4:
  H.P4{1700947290, 1767072878, 1952531047, 1682073164}

def pers_node() -> H.P4:
  H.P4{1700947290, 1767072878, 1952531047, 1701080910}

def pers_z() -> H.P4:
  H.P4{1700947290, 1767072878, 1952531047, 1599760483}

def leaf_pers_b(sa: Bool) -> H.P4:
  match sa:
    case True{}:
      pers_leaf_sa()
    case False{}:
      pers_leaf_bd()

def leaf_pers(+kind: U32) -> H.P4:
  leaf_pers_b(U32.is_eq(kind, 0))

# ------------------------------------------------------------------ per-item preparation

# A prepared signature: kind, R, vk (points), s, c (scalars), leaf (32 bytes).
type Pr is Data:
  Bad{}
  Pr{kind: U32, r: P.Pt, vk: P.Pt, s: S.Fq, c: S.Fq, leaf: +List<U32>}

# [m] q for a 64-bit m = lo + 2^32 hi.
def mul64(+q: P.Pt, +lo: U32, +hi: U32) -> P.Pt:
  P.mul_w(32n, lo, P.mul_w(32n, hi, P.identity(), q), q)

def vpt() -> P.Pt:
  Maybe.default(&2, P.Pt, P.decompress(K.V_CV()), P.identity())

# [valueBalance] V for an i64 (lo, hi) in two's complement.
def vb_mul_s(neg: Bool, +v: P.Pt, +lo: U32, +hi: U32) -> P.Pt:
  match neg:
    case False{}:
      mul64(v, lo, hi)
    case True{}:
      +nlo = (U32.not(lo) + 1 : U32)
      +nhi = (U32.not(hi) + Bool.to_u32(U32.is_zero(lo)) : U32)
      P.neg(mul64(v, nlo, nhi))

def vb_mul(+v: P.Pt, +lo: U32, +hi: U32) -> P.Pt:
  vb_mul_s(U32.is_ge(hi, 2147483648), v, lo, hi)

# Running Σ cv; ok turns false if a cv does not decompress.
type CS is Data:
  CS{ok: Bool, p: P.Pt}

def cv_step(st: CS, m: Maybe<&2, P.Pt>) -> CS:
  CS{ok, acc} = st
  match m:
    case Some{p}:
      CS{ok, P.add(acc, p)}
    case None{}:
      CS{False{}, acc}

def cv_fin(st: CS) -> Maybe<&2, P.Pt>:
  CS{ok, p} = st
  match ok:
    case True{}:
      Some{p}
    case False{}:
      None{}

def cv_go(cvs: +List<Wd.W>, st: CS) -> CS:
  match cvs:
    case Nil{}:
      st
    case Con{w, t}:
      cv_go(t, cv_step(st, P.decompress(w)))

# Σ cv (None if any cv does not decompress).
def cv_sum(cvs: +List<Wd.W>) -> Maybe<&2, P.Pt>:
  cv_fin(cv_go(cvs, CS{True{}, P.identity()}))

def bvk_of(m: Maybe<&2, P.Pt>, +v: P.Pt, +lo: U32, +hi: U32) -> Maybe<&2, P.Pt>:
  match m:
    case Some{sum}:
      Some{P.sub(sum, vb_mul(v, lo, hi))}
    case None{}:
      None{}

# The verification key as a point and as its 32-byte encoding.
type VK is Data:
  NoVK{}
  VK{p: P.Pt, w: Wd.W}

def vk_sa(m: Maybe<&2, P.Pt>, w: Wd.W) -> VK:
  match m:
    case Some{p}:
      VK{p, w}
    case None{}:
      NoVK{}

def vk_bd(m: Maybe<&2, P.Pt>) -> VK:
  match m:
    case Some{+p}:
      VK{p, P.encode(p)}
    case None{}:
      NoVK{}

def vk_sel(sa: Bool, +vkw: Wd.W, +cvs: +List<Wd.W>, +v: P.Pt, +lo: U32, +hi: U32) -> VK:
  match sa:
    case True{}:
      vk_sa(P.decompress(vkw), vkw)
    case False{}:
      vk_bd(bvk_of(cv_sum(cvs), v, lo, hi))

def vk_of(+kind: U32, +vkw: Wd.W, +cvs: +List<Wd.W>, +v: P.Pt, +lo: U32, +hi: U32) -> VK:
  vk_sel(U32.is_eq(kind, 0), vkw, cvs, v, lo, hi)

def challenge(+h: +List<U32>) -> S.Fq:
  S.from_wide(w_of(h), w_of(List.drop(&2, U32, h, 32n)))

def pr_fin(+kind: U32, mr: Maybe<&2, P.Pt>, vk: VK, +rw: Wd.W, +sw: Wd.W, +msg: Wd.W) -> Pr:
  match mr vk:
    case Some{r} VK{p, +vkw}:
      +pre = cat(bytes_of(rw), cat(bytes_of(vkw), bytes_of(msg)))
      +c = challenge(H.hash64(H.P.Zcash_RedPallasH(), pre))
      Pr{kind, r, p, S.from_words(sw), c, H.hash32(leaf_pers(kind), cat(pre, bytes_of(sw)))}
    case _ _:
      Bad{}

def pr_s(canon: Bool, +it: It, +v: P.Pt) -> Pr:
  match canon:
    case False{}:
      Bad{}
    case True{}:
      It{+kind, +lo, +hi, +r, +s, +msg, +vk, cvs} = it
      pr_fin(kind, P.decompress(r), vk_of(kind, vk, cvs, v, lo, hi), r, s, msg)

def prep(+it: It, +v: P.Pt) -> Pr:
  It{_, _, _, _, +s, _, _, _} = it
  pr_s(Wd.is_lt(s, S.modulus()), it, v)

# ------------------------------------------------------------------ batch equation

# An index plus a prepared (good) signature.
type Ix is Data:
  Ix{i: U32, p: Pr}

# Prepare cnt items (indices from i0) as a balanced fork-join; split into good and bad.
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

def prep_all(+fuel: Nat, +cnt: Nat, +i0: U32, +xs: +List<It>, +v: P.Pt) -> Pp:
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

# Merkle root of the leaves (balanced, in parallel).
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

# MSM terms of a batch: points, scalar words, and Σ z s per base.
type T is Data:
  T{ps: +List<P.Pt>, ss: +List<Wd.W>, sa: S.Fq, sb: S.Fq}

def t_sel(sa: Bool, ps: +List<P.Pt>, ss: +List<Wd.W>, +zs: S.Fq) -> T:
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
  T{List.append(&2, P.Pt, pa, pb), List.append(&2, Wd.W, sa, sb), S.add(a1, b1), S.add(a2, b2)}

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

def base_sa() -> P.Pt:
  Maybe.default(&2, P.Pt, P.decompress(K.G_SPENDAUTH()), P.identity())

def base_bd() -> P.Pt:
  Maybe.default(&2, P.Pt, P.decompress(K.R_CV()), P.identity())

def eq_fin(+c: U32, t: T) -> Bool:
  T{ps, ss, sa, sb} = t
  +ps2 = List.append(&2, P.Pt, ps, base_sa() <> base_bd() <> Nil{})
  +ss2 = List.append(&2, Wd.W, ss, S.to_words(S.neg(sa)) <> S.to_words(S.neg(sb)) <> Nil{})
  P.is_identity(BA.msm9(c, ps2, ss2))

# The batch equation over cnt good signatures.
def batch_ok(+c: U32, +cnt: Nat, +xs: +List<Ix>) -> Bool:
  +seed = root(16n, cnt, xs)
  eq_fin(c, terms(16n, cnt, 0, xs, seed))

def ix_i(x: Ix) -> U32:
  Ix{+i, _} = x
  i

# Indices of the failing signatures, given ok = batch_ok(c, cnt, xs): accept, or bisect.
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

def verify(+c: U32, +xs: +List<It>) -> +List<U32>:
  +v = vpt()
  verify_pp(c, prep_all(16n, List.length(&2, It, xs), 0, xs, v))

# The two phases of verify, for timing: preparation, then the batch equation(s).
def prepare(+xs: +List<It>) -> Pp:
  +v = vpt()
  prep_all(16n, List.length(&2, It, xs), 0, xs, v)

def pp_ngood(pp: Pp) -> Nat:
  Pp{+good, _} = pp
  List.length(&2, Ix, good)

# ------------------------------------------------------------------ GPU preparation

# Preparation as a tree of leaves (one leaf per GPU lane), each walked tail-recursively:
# since Bend 2.0.39 a Metal lane faults past ~1,023 frames of non-tail recursion (scan2/README.md).
type Ii is Data:
  Ii{i: U32, it: It}

type IT is Data:
  ILeaf{xs: +List<Ii>}
  INode{l: IT, r: IT}

type PT is Data:
  PLeaf{p: Pp}
  PNode{l: PT, r: PT}

def index_go(xs: +List<It>, +i: U32, acc: +List<Ii>) -> +List<Ii>:
  match xs:
    case Nil{}:
      List.reverse(&2, Ii, acc)
    case Con{x, t}:
      index_go(t, (i + 1 : U32), Ii{i, x} <> acc)

# A tree of depth `fuel` over cnt indexed items; leaves hold at most lsz items.
def itree(+fuel: Nat, small: Bool, +lsz: Nat, +cnt: Nat, +xs: +List<Ii>) -> IT:
  match fuel small:
    case 1n+f False{}:
      +h = Nat.div(cnt, 2n)
      +h2 = Nat.sub(cnt, h)
      a b = itree(f, Nat.is_lt(h, (lsz + 1n : Nat)), lsz, h, List.take(&2, Ii, xs, h)) itree(f, Nat.is_lt(h2, (lsz + 1n : Nat)), lsz, h2, List.drop(&2, Ii, xs, h))
      INode{a, b}
    case _ _:
      ILeaf{xs}

def pp_push(st: Pp, +i: U32, p: Pr) -> Pp:
  Pp{good, bad} = st
  match p:
    case Bad{}:
      Pp{good, i <> bad}
    case Pr{kind, r, vk, s, c, leaf}:
      Pp{Ix{i, Pr{kind, r, vk, s, c, leaf}} <> good, bad}

def leaf_add(st: Pp, x: Ii, +v: P.Pt) -> Pp:
  Ii{+i, +it} = x
  pp_push(st, i, prep(it, v))

def pp_rev(st: Pp) -> Pp:
  Pp{good, bad} = st
  Pp{List.reverse(&2, Ix, good), List.reverse(&2, U32, bad)}

def leaf_go(xs: +List<Ii>, +v: P.Pt, st: Pp) -> Pp:
  match xs:
    case Nil{}:
      pp_rev(st)
    case Con{x, t}:
      leaf_go(t, v, leaf_add(st, x, v))

def prep_tree(+n: Nat, t: IT, +v: P.Pt) -> PT:
  match n t:
    case _ ILeaf{xs}:
      PLeaf{leaf_go(xs, v, Pp{Nil{}, Nil{}})}
    case 1n+j INode{l, r}:
      a b = prep_tree(j, l, v) prep_tree(j, r, v)
      PNode{a, b}
    case _ _:
      PLeaf{Pp{Nil{}, Nil{}}}

def pt_flat(t: PT) -> Pp:
  match t:
    case PLeaf{p}:
      p
    case PNode{l, r}:
      pp_cat(pt_flat(l), pt_flat(r))

def prep_gpu_run(+v: P.Pt, t: IT) -> PT:
  prep_tree!(32n, t, v)

# prepare on the GPU, in three steps (timed separately): build the tree on the CPU, run it
# with prep_tree! (one leaf of at most lsz items per lane), flatten it on the CPU.
def gpu_tree(+lsz: Nat, +xs: +List<It>) -> IT:
  +n = List.length(&2, It, xs)
  itree(32n, Nat.is_lt(n, (lsz + 1n : Nat)), lsz, n, index_go(xs, 0, Nil{}))

def gpu_run(t: IT) -> PT:
  prep_gpu_run(vpt(), t)

def it_leaves(t: IT) -> Nat:
  match t:
    case ILeaf{_}:
      1n
    case INode{l, r}:
      (it_leaves(l) + it_leaves(r) : Nat)

def pt_leaves(t: PT) -> Nat:
  match t:
    case PLeaf{_}:
      1n
    case PNode{l, r}:
      (pt_leaves(l) + pt_leaves(r) : Nat)

# ------------------------------------------------------------------ GPU MSM variant

# batch_ok / find / verify_pp with the MSM on the GPU (msm_fast's Pippenger: c-bit
# windows, 2^d chunks of terms per window, one GPU task per (window, chunk)).
def eq_fin_g(+c: U32, +d: Nat, t: T) -> Bool:
  T{ps, ss, sa, sb} = t
  +ps2 = List.append(&2, P.Pt, ps, base_sa() <> base_bd() <> Nil{})
  +ss2 = List.append(&2, Wd.W, ss, S.to_words(S.neg(sa)) <> S.to_words(S.neg(sb)) <> Nil{})
  P.is_identity(MF.pip_gpu(c, d, MF.chunks(d, U32.from_nat(List.length(&2, P.Pt, ps2)), ps2, ss2)))

def batch_ok_g(+c: U32, +d: Nat, +cnt: Nat, +xs: +List<Ix>) -> Bool:
  +seed = root(16n, cnt, xs)
  eq_fin_g(c, d, terms(16n, cnt, 0, xs, seed))

def find_g(+fuel: Nat, ok: Bool, +c: U32, +d: Nat, +cnt: Nat, +xs: +List<Ix>) -> +List<U32>:
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
      a = find_g(f, batch_ok_g(c, d, h, xa), c, d, h, xa)
      b = find_g(f, batch_ok_g(c, d, h2, xb), c, d, h2, xb)
      List.append(&2, U32, a, b)
    case _ _ _ _:
      Nil{}

def verify_pp_g(+c: U32, +d: Nat, pp: Pp) -> +List<U32>:
  Pp{+good, bad} = pp
  +n = List.length(&2, Ix, good)
  List.append(&2, U32, bad, find_g(32n, batch_ok_g(c, d, n, good), c, d, n, good))

# m = 0: the MSM on CPU threads; m > 0: on the GPU with 2^m chunks per window.
def verify_m(+m: Nat, +c: U32, pp: Pp) -> +List<U32>:
  match m:
    case 0n:
      verify_pp(c, pp)
    case _:
      verify_pp_g(c, m, pp)

# ------------------------------------------------------------------ determinism digest

# Fingerprint of a preparation (untimed): the leaf Merkle root, Σ (R_i + vk_i) and Σ c_i,
# so GPU and CPU runs can be compared bit for bit.
type Dg is Data:
  Dg{p: P.Pt, c: S.Fq}

def dg_pr(acc: P.Pt, cs: S.Fq, p: Pr) -> Dg:
  match p:
    case Pr{_, r, vk, _, c, _}:
      Dg{P.add(P.add(acc, r), vk), S.add(cs, c)}
    case Bad{}:
      Dg{acc, cs}

def dg_add(st: Dg, x: Ix) -> Dg:
  Dg{acc, cs} = st
  Ix{_, p} = x
  dg_pr(acc, cs, p)

def dg_go(xs: +List<Ix>, st: Dg) -> Dg:
  match xs:
    case Nil{}:
      st
    case Con{x, t}:
      dg_go(t, dg_add(st, x))

def dg_show(st: Dg) -> String:
  Dg{p, c} = st
  Wd.hex(P.encode(p)) ++ " " ++ Wd.hex(S.to_words(c))

def digest(pp: Pp) -> String:
  Pp{+good, _} = pp
  Wd.hex(w_of(root(16n, List.length(&2, Ix, good), good))) ++ " " ++ dg_show(dg_go(good, Dg{P.identity(), S.zero()}))
