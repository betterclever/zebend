# Multi-scalar multiplication on Vesta: sum_i [s_i] P_i.
#
# The terms are dealt into a balanced binary tree of 2^depth leaves. Each leaf sums
# its terms sequentially; the tree is folded with parallel calls, so `sum` spreads
# over every CPU thread and `sum!` over the GPU's lanes (Metal / CUDA).
#
#   +t = MSM.tree(depth, points, scalars)    # build once (Data: reusable)
#   r  = MSM.sum!(depth, t)                  # GPU; MSM.sum(depth, t) on CPU threads
#   r  = MSM.msm(depth, points, scalars)     # build + CPU-parallel sum in one call
import Base
import ../../../halo2/lib/words.bend as Wd
import ./vesta.bend as V

type Term is Data:
  Term{p: V.Pt, s: Wd.W}

type Terms is Data:
  TNil{}
  TCons{+t: Term, next: Terms}

type Tree is Data:
  Leaf{ts: Terms}
  Node{l: Tree, r: Tree}

def term_mul(t: Term) -> V.Pt:
  Term{+p, s} = t
  V.scalar_mul(p, s)

def leaf_sum(ts: Terms, acc: V.Pt) -> V.Pt:
  match ts:
    case TNil{}:
      acc
    case TCons{t, next}:
      leaf_sum(next, V.add(acc, term_mul(t)))

# Balanced parallel fold; `k` bounds the depth (termination).
def sum(+k: Nat, t: Tree) -> V.Pt:
  match k t:
    case _ Leaf{ts}:
      leaf_sum(ts, V.identity())
    case 1n+j Node{l, r}:
      a b = sum(j, l) sum(j, r)
      V.add(a, b)
    case _ _:
      V.identity()

# --- building the tree ---------------------------------------------------------

type TL is Data:
  TLNil{}
  TLCons{+t: Tree, next: TL}

type Chunk is Data:
  Chunk{+left: U32, +per: U32, cur: Terms, out: TL}

def chunk_push(full: Bool, x: Term, +per: U32, +left: U32, cur: Terms, out: TL) -> Chunk:
  match full:
    case True{}:
      Chunk{per, per, TNil{}, TLCons{Leaf{TCons{x, cur}}, out}}
    case False{}:
      Chunk{(left - 1 : U32), per, TCons{x, cur}, out}

def chunk_step(x: Term, c: Chunk) -> Chunk:
  Chunk{left, per, cur, out} = c
  chunk_push(U32.is_eq(left, 1), x, per, left, cur, out)

def chunk_close(c: Chunk) -> TL:
  Chunk{_, _, cur, out} = c
  match cur:
    case TNil{}:
      out
    case TCons{h, t}:
      TLCons{Leaf{TCons{h, t}}, out}

def chunks(ps: +List<V.Pt>, ss: +List<Wd.W>, c: Chunk) -> Chunk:
  match ps ss:
    case Con{p, pt} Con{s, st}:
      chunks(pt, st, chunk_step(Term{p, s}, c))
    case _ _:
      c

def tl_rev(xs: TL, acc: TL) -> TL:
  match xs:
    case TLCons{h, t}:
      tl_rev(t, TLCons{h, acc})
    case TLNil{}:
      acc

def pair_up(xs: TL, acc: TL) -> TL:
  match xs:
    case TLCons{a, TLCons{b, rest}}:
      pair_up(rest, TLCons{Node{a, b}, acc})
    case TLCons{a, TLNil{}}:
      TLCons{a, acc}
    case TLNil{}:
      acc

def levels(k: Nat, xs: TL) -> TL:
  match k:
    case 0n:
      xs
    case 1n+j:
      levels(j, tl_rev(pair_up(xs, TLNil{}), TLNil{}))

def tl_head(xs: TL) -> Tree:
  match xs:
    case TLCons{h, _}:
      h
    case TLNil{}:
      Leaf{TNil{}}

def len(xs: +List<V.Pt>, acc: U32) -> U32:
  match xs:
    case Con{_, t}:
      len(t, (acc + 1 : U32))
    case Nil{}:
      acc

# Splits n terms into 2^depth leaves of ceil(n / 2^depth) terms and pairs them up.
def tree(+depth: Nat, +ps: +List<V.Pt>, ss: +List<Wd.W>) -> Tree:
  +n = len(ps, 0)
  +slots = (1 << depth : U32)
  +per = U32.max(1, ((n + slots - 1) / slots : U32))
  tl_head(levels(depth, tl_rev(chunk_close(chunks(ps, ss, Chunk{per, per, TNil{}, TLNil{}})), TLNil{})))

def msm(+depth: Nat, +ps: +List<V.Pt>, ss: +List<Wd.W>) -> V.Pt:
  sum(depth, tree(depth, ps, ss))

def msm_gpu(+depth: Nat, +ps: +List<V.Pt>, ss: +List<Wd.W>) -> V.Pt:
  sum!(depth, tree(depth, ps, ss))
