import Base

# A model of research/perf4's chunked and merged MSM (lib/msm_par.bend, v/bt.bend) over the
# commutative monoid (Nat, +): a point is a Nat, k·P is k * P, point addition (V.add, VL.add)
# is +. Each def below copies the control structure of the Bend def named in its comment,
# with these substitutions only: V.Pt -> Nat, Wd.W / Fp.Fp scalars -> Nat, V.add / VL.add ->
# Nat.add, BA.msm9 (one chunk's bucket MSM) -> `msm` (its specification), Fp.add -> Nat.add,
# Fp.mul -> Nat.mul, Fp.to_words -> identity. See README.md for why an identity proven here
# for every Nat-valued point holds in every commutative group.

# The specification: sum_i s_i * P_i over the pairs of the two lists (a shorter list ends it,
# as msm_ba.fill does).
def msm(ps: +List<Nat>, ss: +List<Nat>) -> Nat:
  match ps ss:
    case Con{+p, pt} Con{+s, st}:
      Nat.add(Nat.mul(s, p), msm(pt, st))
    case _ _:
      0n

def take(xs: +List<Nat>, n: Nat) -> +List<Nat>:
  List.take(&2, Nat, xs, n)

def drop(xs: +List<Nat>, n: Nat) -> +List<Nat>:
  List.drop(&2, Nat, xs, n)

def length(xs: +List<Nat>) -> Nat:
  List.length(&2, Nat, xs)

# lib/msm_par.bend mpar (the window width `c` only reaches msm9 and is dropped).
def mpar(+fuel: Nat, +cnt: Nat, +len: Nat, +ps: +List<Nat>, +ss: +List<Nat>) -> Nat:
  match fuel cnt:
    case 1n+f 1n+1n+_:
      +h = Nat.div(cnt, 2n)
      +m = Nat.div(Nat.mul(len, h), cnt)
      Nat.add(mpar(f, h, m, take(ps, m), take(ss, m)), mpar(f, Nat.sub(cnt, h), Nat.sub(len, m), drop(ps, m), drop(ss, m)))
    case _ _:
      msm(ps, ss)

def pick_cnt(+n: Nat) -> Nat:
  Nat.max(1n, Nat.div(n, 2048n))

# lib/msm_par.bend msm_auto
def msm_auto(+ps: +List<Nat>, +ss: +List<Nat>) -> Nat:
  +n = length(ps)
  mpar(32n, pick_cnt(n), n, ps, ss)

# --- v/bt.bend: the merged batch ------------------------------------------------------------

def append(xs: +List<Nat>, ys: +List<Nat>) -> +List<Nat>:
  List.append(&2, Nat, xs, ys)

def flat(xs: +List<+List<Nat>>, +tail: +List<Nat>) -> +List<Nat>:
  match xs:
    case Nil{}:
      tail
    case Con{+h, t}:
      append(h, flat(t, tail))

def ltake(xs: +List<+List<Nat>>, n: Nat) -> +List<+List<Nat>>:
  List.take(&2, +List<Nat>, xs, n)

def ldrop(xs: +List<+List<Nat>>, n: Nat) -> +List<+List<Nat>>:
  List.drop(&2, +List<Nat>, xs, n)

def small_g(+n: Nat) -> Bool:
  Nat.is_lt(n, Nat.add(20n, 1n))

# bt.bend groups: per-proof lists split in halves, each group flattened into one chunked MSM.
def groups(+fuel: Nat, small: Bool, +cnt: Nat, +ps: +List<+List<Nat>>, +ss: +List<+List<Nat>>) -> Nat:
  match fuel small:
    case 1n+f False{}:
      +h = Nat.div(cnt, 2n)
      +h2 = Nat.sub(cnt, h)
      Nat.add(groups(f, small_g(h), h, ltake(ps, h), ltake(ss, h)), groups(f, small_g(h2), h2, ldrop(ps, h), ldrop(ss, h)))
    case _ _:
      msm_auto(flat(ps, Nil{}), flat(ss, Nil{}))

def all_groups(+ps: +List<+List<Nat>>, +ss: +List<+List<Nat>>) -> Nat:
  +k = List.length(&2, +List<Nat>, ps)
  groups(32n, small_g(k), k, ps, ss)

# vlib.bend scale_list / bt.bend scale_words: every scalar times the proof's weight r.
def scale(xs: +List<Nat>, +r: Nat) -> +List<Nat>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      Nat.mul(h, r) <> scale(t, r)

# bt.bend vadd: shared-base scalars added base by base.
def vadd(a: +List<Nat>, b: +List<Nat>) -> +List<Nat>:
  match a b:
    case Con{+x, at} Con{+y, bt}:
      Nat.add(x, y) <> vadd(at, bt)
    case Nil{} _:
      b
    case _ Nil{}:
      a

# One verified proof: its own terms (ops, oss) and its scalars on the shared bases G and the
# fixed commitments (gx = gss ++ fx_dense(fx), aligned with gs ++ fixed).
type Pf is Data:
  Pf{ops: +List<Nat>, oss: +List<Nat>, gx: +List<Nat>}

# The shape of the batch's parallel reduction: any binary tree of weighted proofs.
type Tree is Data:
  Em{}
  Lf{r: Nat, p: Pf}
  Nd{a: Tree, b: Tree}

type Acc is Data:
  Acc{ps: +List<+List<Nat>>, ss: +List<+List<Nat>>, gx: +List<Nat>}

# bt.bend leaf / none / join (ok, n, bad dropped: they do not touch the MSM).
def leaf(+r: Nat, +p: Pf) -> Acc:
  Pf{+ops, +oss, +gx} = p
  Acc{ops <> Nil{}, scale(oss, r) <> Nil{}, scale(gx, r)}

def none() -> Acc:
  Acc{Nil{}, Nil{}, Nil{}}

def lapp(xs: +List<+List<Nat>>, ys: +List<+List<Nat>>) -> +List<+List<Nat>>:
  List.append(&2, +List<Nat>, xs, ys)

def join(+a: Acc, +b: Acc) -> Acc:
  Acc{+pa, +sa, +ga} = a
  Acc{+pb, +sb, +gb} = b
  Acc{lapp(pa, pb), lapp(sa, sb), vadd(ga, gb)}

def acc(t: Tree) -> Acc:
  match t:
    case Em{}:
      none()
    case Lf{+r, +p}:
      leaf(r, p)
    case Nd{a, b}:
      join(acc(a), acc(b))

# bt.bend check: all_groups(ps, ss) + msm_auto(gs ++ fixed, gx). `bases` is gs ++ fixed.
def check_sum(+a: Acc, +bases: +List<Nat>) -> Nat:
  Acc{+ps, +ss, +gx} = a
  Nat.add(all_groups(ps, ss), msm_auto(bases, gx))

def aps(a: Acc) -> +List<+List<Nat>>:
  Acc{+ps, _, _} = a
  ps

def ass(a: Acc) -> +List<+List<Nat>>:
  Acc{_, +ss, _} = a
  ss

def agx(a: Acc) -> +List<Nat>:
  Acc{_, _, +gx} = a
  gx

# The specification of the batch: the r-weighted sum of every proof's own MSM.
def spec(t: Tree, +bases: +List<Nat>) -> Nat:
  match t:
    case Em{}:
      0n
    case Lf{+r, +p}:
      Pf{+ops, +oss, +gx} = p
      Nat.mul(r, Nat.add(msm(ops, oss), msm(bases, gx)))
    case Nd{a, b}:
      Nat.add(spec(a, bases), spec(b, bases))

# Every proof's own terms come in (point, scalar) pairs: the two lists have one length.
def WF(t: Tree) -> Data:
  match t:
    case Em{}:
      Unit
    case Lf{+r, +p}:
      Pf{+ops, +oss, +gx} = p
      {length(ops) == length(oss) : Nat}
    case Nd{a, b}:
      Sigma<&2, &2, WF(a), _ => WF(b)>

# Per-proof lists aligned pairwise.
def Aligned(ps: +List<+List<Nat>>, ss: +List<+List<Nat>>) -> Data:
  match ps ss:
    case Con{+p, pt} Con{+s, st}:
      Sigma<&2, &2, {length(p) == length(s) : Nat}, _ => Aligned(pt, st)>
    case Nil{} Nil{}:
      Unit
    case _ _:
      Empty

# sum over proofs of each proof's MSM
def psum(ps: +List<+List<Nat>>, ss: +List<+List<Nat>>) -> Nat:
  match ps ss:
    case Con{+p, pt} Con{+s, st}:
      Nat.add(msm(p, s), psum(pt, st))
    case _ _:
      0n

# The tree with each proof's scalars replaced by its points (lists of one length).
def diag(t: Tree) -> Tree:
  match t:
    case Em{}:
      Em{}
    case Lf{+r, +p}:
      Pf{+ops, _, +gx} = p
      Lf{r, Pf{ops, ops, gx}}
    case Nd{a, b}:
      Nd{diag(a), diag(b)}
