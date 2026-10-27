# Fixed-base MSM for bases that never change (the IPA generators G of the params).
#
# Precompute once, per base G_i, the window powers T_ij = [2^(j c)] G_i for j < W.
# Then sum_i [s_i] G_i = sum_(i, j) [d_ij] T_ij with d_ij the j-th c-bit digit of s_i:
# a single bucket pass over n * W points, with no doublings and no per-window
# reductions. Chunks of bases run in parallel (`fixed_msm` on CPU threads,
# `fixed_msm_gpu` on the GPU).
#
#   +tb = FX.table(c, cdepth, n, bases)      # once per process (parallel)
#   r   = FX.fixed_msm(c, tb, n, scalars)    # per MSM
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ./vesta.bend as V
import ./msm_fast.bend as MF

type FT is Data:
  FLeaf{rows: +List<+List<V.Pt>>}
  FNode{l: FT, r: FT}

# [2^(j c)] P for j < w, as a list (lowest window first).
def row(+w: Nat, +c: Nat, p: V.Pt) -> +List<V.Pt>:
  match w:
    case 0n:
      Nil{}
    case 1n+k:
      +q = p
      q <> row(k, c, MF.dbl_n(c, q))

def rows(+w: Nat, +c: Nat, ps: +List<V.Pt>) -> +List<+List<V.Pt>>:
  match ps:
    case Con{p, t}:
      row(w, c, p) <> rows(w, c, t)
    case Nil{}:
      Nil{}

def build(+k: Nat, +w: Nat, +c: Nat, +d: Nat, +n: U32, +ps: +List<V.Pt>) -> FT:
  match d:
    case 0n:
      FLeaf{rows(w, c, ps)}
    case 1n+j:
      +h = (n >> 1n : U32)
      +hn = U32.to_nat(h)
      l r = build(k, w, c, j, h, MF.take_p(hn, ps)) build(k, w, c, j, (n - h : U32), MF.drop_p(hn, ps))
      FNode{l, r}

def table(+c: U32, +cdepth: Nat, +n: U32, +ps: +List<V.Pt>) -> FT:
  build(cdepth, U32.to_nat(MF.windows(c)), U32.to_nat(c), cdepth, n, ps)

# Drops every (T_ij, d_ij) of one base into the buckets.
def put_row(r: +List<V.Pt>, +s: Wd.W, +j: U32, +c: U32, a: Array<V.Pt>) -> Array<V.Pt>:
  match r:
    case Con{t, rest}:
      +dg = MF.digit(s, MF.win_of(j, c))
      put_row(rest, s, (j + 1 : U32), c, MF.put_if(U32.is_eq(dg, 0), a, dg, t))
    case Nil{}:
      a

def fill(rs: +List<+List<V.Pt>>, ss: +List<Wd.W>, +c: U32, a: Array<V.Pt>) -> Array<V.Pt>:
  match rs ss:
    case Con{r, rt} Con{s, st}:
      fill(rt, st, c, put_row(r, s, 0, c, a))
    case _ _:
      a

def leaf(+c: U32, rs: +List<+List<V.Pt>>, ss: +List<Wd.W>) -> V.Pt:
  MF.rs_acc(MF.reduce(fill(rs, ss, c, MF.buckets(U32.to_nat(c))), MF.RS{V.identity(), V.identity()}))

# Walks the table tree, splitting the scalars the same way it was built.
def go(+k: Nat, +c: U32, +tb: FT, +n: U32, +ss: +List<Wd.W>) -> V.Pt:
  match k tb:
    case _ FLeaf{rs}:
      leaf(c, rs, ss)
    case 1n+j FNode{l, r}:
      +h = (n >> 1n : U32)
      +hn = U32.to_nat(h)
      a b = go(j, c, l, h, MF.take_s(hn, ss)) go(j, c, r, (n - h : U32), MF.drop_s(hn, ss))
      V.add(a, b)
    case _ _:
      V.identity()

def fixed_msm(+c: U32, +tb: FT, +n: U32, +ss: +List<Wd.W>) -> V.Pt:
  go(16n, c, tb, n, ss)

def fixed_msm_gpu(+c: U32, +tb: FT, +n: U32, +ss: +List<Wd.W>) -> V.Pt:
  go!(16n, c, tb, n, ss)
