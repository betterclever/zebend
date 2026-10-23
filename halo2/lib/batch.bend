# Batch verification support: K final-MSM instances, each scaled by a random r_i,
# evaluated as ONE merged MSM (halo2's BatchVerifier does the same).
#
# Instance i contributes r_i * (sum_j g_ij G_j + sum_k f_ik F_k + sum_l v_il V_il):
#   G_j  the 2^k params generators        -> scalars merge, fixed-base table MSM
#   F_k  bases shared by every proof      -> scalars merge (VK commitments, U, W)
#   V_il this proof's own commitments     -> appended, Pippenger
# Merging is a balanced parallel tree over the instances, so the G-part costs one
# 2^k MSM no matter how many proofs are in the batch.
import Base
import ./words.bend as Wd
import ./fp.bend as S
import ./vesta.bend as V
import ./msm_fast.bend as MF
import ./fixed.bend as FX

type Inst is Data:
  Inst{r: S.Fp, g: +List<S.Fp>, f: +List<S.Fp>, vp: +List<V.Pt>, vs: +List<S.Fp>}

# A merged (partial) MSM.
type Part is Data:
  Part{g: +List<S.Fp>, f: +List<S.Fp>, vp: +List<V.Pt>, vs: +List<S.Fp>}

def scale(+r: S.Fp, xs: +List<S.Fp>) -> +List<S.Fp>:
  match xs:
    case Con{x, t}:
      S.mul(r, x) <> scale(r, t)
    case Nil{}:
      Nil{}

def vadd(xs: +List<S.Fp>, ys: +List<S.Fp>) -> +List<S.Fp>:
  match xs ys:
    case Con{x, xt} Con{y, yt}:
      S.add(x, y) <> vadd(xt, yt)
    case _ _:
      Nil{}

def cat_p(xs: +List<V.Pt>, ys: +List<V.Pt>) -> +List<V.Pt>:
  match xs:
    case Con{x, t}:
      x <> cat_p(t, ys)
    case Nil{}:
      ys

def cat_s(xs: +List<S.Fp>, ys: +List<S.Fp>) -> +List<S.Fp>:
  match xs:
    case Con{x, t}:
      x <> cat_s(t, ys)
    case Nil{}:
      ys

def part_of(i: Inst) -> Part:
  Inst{+r, g, f, vp, vs} = i
  Part{scale(r, g), scale(r, f), vp, scale(r, vs)}

def join(a: Part, b: Part) -> Part:
  Part{ga, fa, pa, sa} = a
  Part{gb, fb, pb, sb} = b
  Part{vadd(ga, gb), vadd(fa, fb), cat_p(pa, pb), cat_s(sa, sb)}

type IT is Data:
  ILeaf{i: Inst}
  INode{l: IT, r: IT}
  IEmpty{}

def merge(+k: Nat, t: IT) -> Part:
  match k t:
    case _ ILeaf{i}:
      part_of(i)
    case 1n+j INode{l, r}:
      a b = merge(j, l) merge(j, r)
      join(a, b)
    case _ _:
      Part{Nil{}, Nil{}, Nil{}, Nil{}}

def take_i(k: Nat, xs: +List<Inst>) -> +List<Inst>:
  match k xs:
    case 1n+j Con{h, t}:
      h <> take_i(j, t)
    case _ _:
      Nil{}

def drop_i(k: Nat, xs: +List<Inst>) -> +List<Inst>:
  match k xs:
    case 1n+j Con{_, t}:
      drop_i(j, t)
    case _ _:
      xs

def itree_one(xs: +List<Inst>) -> IT:
  match xs:
    case Con{h, _}:
      ILeaf{h}
    case Nil{}:
      IEmpty{}

# Balanced tree over n instances (n <= 2^fuel); `one` is n < 2.
def itree(+fuel: Nat, one: Bool, +n: U32, +xs: +List<Inst>) -> IT:
  match fuel one:
    case 1n+f False{}:
      +h = (n >> 1n : U32)
      +h2 = (n - h : U32)
      +hn = U32.to_nat(h)
      INode{itree(f, U32.is_lt(h, 2), h, take_i(hn, xs)), itree(f, U32.is_lt(h2, 2), h2, drop_i(hn, xs))}
    case _ _:
      itree_one(xs)

def words_of(xs: +List<S.Fp>) -> +List<Wd.W>:
  match xs:
    case Con{x, t}:
      S.to_words(x) <> words_of(t)
    case Nil{}:
      Nil{}

def len_s(xs: +List<S.Fp>, +acc: U32) -> U32:
  match xs:
    case Con{_, t}:
      len_s(t, (acc + 1 : U32))
    case Nil{}:
      acc

# Pippenger window for n terms: buckets cost ~2 * 2^c adds per window, terms ~n, so
# grow c with n (one chunk per window: the W >= 26 windows already fill 18 threads).
def pip_c(a: Bool, b: Bool, c: Bool) -> U32:
  match a b c:
    case True{} _ _:
      5
    case False{} True{} _:
      6
    case False{} False{} True{}:
      8
    case _ _ _:
      10

def eval_rest(+n: U32, ps: +List<V.Pt>, ss: +List<Wd.W>) -> V.Pt:
  MF.pip(pip_c(U32.is_lt(n, 256), U32.is_lt(n, 2048), U32.is_lt(n, 16384)), 0n, MF.chunks(0n, n, ps, ss))

# Evaluates a merged part: fixed-base table for G (window c, built with `table`),
# Pippenger for the shared and per-proof bases. `fb` are the shared bases F (same
# order as the f scalars).
def eval(+c: U32, +tb: FX.FT, +ng: U32, +fb: +List<V.Pt>, p: Part) -> V.Pt:
  Part{g, f, vp, vs} = p
  +rest = cat_s(f, vs)
  a b = FX.fixed_msm(c, tb, ng, words_of(g)) eval_rest(len_s(rest, 0), cat_p(fb, vp), words_of(rest))
  V.add(a, b)
