# Batch verification of Halo 2 proofs (as halo2's BatchVerifier).
#
# Each proof's verifier ends in one IPA check: MSM(other terms ++ G ++ fixed, scalars) = identity.
# `verify` (orchard_bt.bend) returns those terms instead of evaluating them. A batch of K
# proofs draws independent random weights r_i and checks the single merged MSM
#     sum_i r_i * (others_i) + sum_j (sum_i r_i s_ij) G_j + sum_f (sum_i r_i t_if) F_f  =  identity,
# so the 2^k-term G part and the 46 fixed bases F (VK fixed and permutation commitments, W, U)
# are paid once per batch. A false proof survives only if the random combination cancels,
# with probability about 1/p.
#
# perf4: every per-proof step (parse, verify, weighting, scalar encoding) runs inside the
# parallel tree; the tree's nodes merge results (list-of-lists concatenation, vector adds),
# so nothing proportional to K x 2^k runs serially.
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ../../../crypto/field3/fp64.bend as Fp
import ../../../crypto/field3/lib64/vesta.bend as V
import ../lib/msm_ba.bend as BA
import ../lib/msm_par.bend as MP
import ../lib/vesta_lz.bend as VL
import ./vlib.bend as L
import ./pio.bend as P
import ../lib/gtab.bend as GT

type Fin is Data:
  Fin{st: L.St, ops: +List<V.Pt>, oss: +List<Fp.Fp>, gss: +List<Fp.Fp>, fx: +List<L.FX>}

def fin_ok(f: Fin) -> U32:
  Fin{+st, _, _, _, _} = f
  L.st_ok(st)

def fin_ops(f: Fin) -> +List<V.Pt>:
  Fin{_, +ops, _, _, _} = f
  ops

def fin_oss(f: Fin) -> +List<Fp.Fp>:
  Fin{_, _, +oss, _, _} = f
  oss

def fin_gss(f: Fin) -> +List<Fp.Fp>:
  Fin{_, _, _, +gss, _} = f
  gss

def fin_fx(f: Fin) -> +List<L.FX>:
  Fin{_, _, _, _, +fx} = f
  fx

def words(xs: +List<Fp.Fp>) -> +List<Wd.W>:
  match xs:
    case Con{+h, t}:
      Fp.to_words(h) <> words(t)
    case Nil{}:
      Nil{}

def is_id(+p: V.Pt) -> U32:
  Bool.to_u32(V.is_identity(p))

# --- fixed-base scalars --------------------------------------------------------------

def nfixed() -> Nat:
  46n

# sum of the scalars of every term on fixed base i
def fx_sum(+i: U32, xs: +List<L.FX>, +acc: Fp.Fp) -> Fp.Fp:
  match xs:
    case Nil{}:
      acc
    case Con{L.FX{+j, +s}, t}:
      fx_sum(i, t, Fp.sel(Bool.to_u32(U32.is_eq(i, j)), Fp.add(acc, s), acc))

def fx_dense_go(n: Nat, +i: U32, +xs: +List<L.FX>) -> +List<Fp.Fp>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      fx_sum(i, xs, Fp.zero()) <> fx_dense_go(k, (i + 1 : U32), xs)

# the fixed-base scalars as a dense vector, base 0 first
def fx_dense(+xs: +List<L.FX>) -> +List<Fp.Fp>:
  fx_dense_go(nfixed(), 0, xs)

# --- one proof on its own: the unbatched check -----------------------------------------

def single(+f: Fin, +gs: +List<V.Pt>, +fixed: +List<V.Pt>) -> U32:
  +ps = List.append(&2, V.Pt, fin_ops(f), List.append(&2, V.Pt, gs, fixed))
  +ss = words(List.append(&2, Fp.Fp, fin_oss(f), List.append(&2, Fp.Fp, fin_gss(f), fx_dense(fin_fx(f)))))
  (fin_ok(f) .&. is_id(BA.msm9(9, ps, ss)) : U32)

# --- the batch accumulator ----------------------------------------------------------------
# ok: AND of every proof's transcript checks; n: proofs that produced a result; bad: unreadable
# bundles; ps/ss: per-proof terms, as a list of per-proof lists (flattened once at the end);
# gx: weighted G scalars followed by the weighted fixed-base scalars, summed over proofs.

type Acc is Data:
  Acc{ok: U32, n: Nat, bad: U32, ps: +List<+List<V.Pt>>, ss: +List<+List<Wd.W>>, gx: +List<Fp.Fp>}

def vadd(a: +List<Fp.Fp>, b: +List<Fp.Fp>) -> +List<Fp.Fp>:
  match a b:
    case Con{+x, at} Con{+y, bt}:
      Fp.add(x, y) <> vadd(at, bt)
    case Nil{} _:
      b
    case _ Nil{}:
      a

def scale_words(xs: +List<Fp.Fp>, +r: Fp.Fp) -> +List<Wd.W>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      Fp.to_words(Fp.mul(h, r)) <> scale_words(t, r)

# A verified proof, weighted by r.
def leaf(+f: Fin, +r: Fp.Fp, +bad: U32) -> Acc:
  +gx = L.scale_list(List.append(&2, Fp.Fp, fin_gss(f), fx_dense(fin_fx(f))), r)
  Acc{fin_ok(f), 1n, bad, fin_ops(f) <> Nil{}, scale_words(fin_oss(f), r) <> Nil{}, gx}

def none() -> Acc:
  Acc{1, 0n, 0, Nil{}, Nil{}, Nil{}}

def join(+a: Acc, +b: Acc) -> Acc:
  Acc{+oa, +na, +ba, +pa, +sa, +ga} = a
  Acc{+ob, +nb, +bb, +pb, +sb, +gb} = b
  Acc{(oa .&. ob : U32), Nat.add(na, nb), (ba + bb : U32), List.append(&2, +List<V.Pt>, pa, pb), List.append(&2, +List<Wd.W>, sa, sb), vadd(ga, gb)}

def acc_n(a: Acc) -> Nat:
  Acc{_, +n, _, _, _, _} = a
  n

def acc_bad(a: Acc) -> U32:
  Acc{_, _, +bad, _, _, _} = a
  bad

def flat_p(xs: +List<+List<V.Pt>>, +tail: +List<V.Pt>) -> +List<V.Pt>:
  match xs:
    case Nil{}:
      tail
    case Con{+h, t}:
      List.append(&2, V.Pt, h, flat_p(t, tail))

def flat_w(xs: +List<+List<Wd.W>>, +tail: +List<Wd.W>) -> +List<Wd.W>:
  match xs:
    case Nil{}:
      tail
    case Con{+h, t}:
      List.append(&2, Wd.W, h, flat_w(t, tail))

# The merged MSM's per-proof terms, by groups of about `grp()` proofs: the parallel tree splits
# the list of per-proof lists (K cells, not n), and each group flattens its own terms and runs
# a chunked MSM on them. Flattening all n ~ 100 K terms into one list and splitting it again was
# a serial O(n log n) list copy before any MSM task started.
def grp() -> Nat:
  20n

def small_g(+n: Nat) -> Bool:
  Nat.is_lt(n, Nat.add(grp(), 1n))

def groups(+fuel: Nat, small: Bool, +cnt: Nat, +ps: +List<+List<V.Pt>>, +ss: +List<+List<Wd.W>>) -> V.Pt:
  match fuel small:
    case 1n+f False{}:
      +h = Nat.div(cnt, 2n)
      +h2 = Nat.sub(cnt, h)
      x y = groups(f, small_g(h), h, List.take(&2, +List<V.Pt>, ps, h), List.take(&2, +List<Wd.W>, ss, h)) groups(f, small_g(h2), h2, List.drop(&2, +List<V.Pt>, ps, h), List.drop(&2, +List<Wd.W>, ss, h))
      VL.add(x, y)
    case _ _:
      MP.msm_auto(flat_p(ps, Nil{}), flat_w(ss, Nil{}))

def all_groups(+ps: +List<+List<V.Pt>>, +ss: +List<+List<Wd.W>>) -> V.Pt:
  +k = List.length(&2, +List<V.Pt>, ps)
  groups(32n, small_g(k), k, ps, ss)

# 1 iff every proof's transcript checks pass and the merged MSM is the identity.
def check(+a: Acc, +gs: +List<V.Pt>, +fixed: +List<V.Pt>) -> U32:
  Acc{+ok, _, _, +ps, +ss, +gx} = a
  x y = all_groups(ps, ss) MP.msm_auto(List.append(&2, V.Pt, gs, fixed), words(gx))
  (ok .&. is_id(VL.add(x, y)) : U32)

# --- with the fixed-base table of G ------------------------------------------------------

def gtab_c() -> U32:
  9

def gtab_tasks() -> Nat:
  16n

def ngs(+gs: +List<V.Pt>) -> Nat:
  List.length(&2, V.Pt, gs)

def msm_rest(+fixed: +List<V.Pt>, +fw: +List<Wd.W>, +ps: +List<+List<V.Pt>>, +ss: +List<+List<Wd.W>>) -> V.Pt:
  x y = MP.msm_auto(fixed, fw) all_groups(ps, ss)
  VL.add(x, y)

# the merged check with sum_j g_j G_j from the table (in parallel with the rest)
def check_tab(+a: Acc, +gs: +List<V.Pt>, +fixed: +List<V.Pt>, t: Array<U32>) -> U32:
  Acc{+ok, _, _, +ps, +ss, +gx} = a
  +n = ngs(gs)
  +gw = words(List.take(&2, Fp.Fp, gx, n))
  +fw = words(List.drop(&2, Fp.Fp, gx, n))
  x y = GT.msm(t, gtab_c(), gw, gtab_tasks()) msm_rest(fixed, fw, ps, ss)
  (ok .&. is_id(VL.add(x, y)) : U32)

def check_sel(valid: Bool, +a: Acc, +gs: +List<V.Pt>, +fixed: +List<V.Pt>, t: Array<U32>) -> U32:
  match valid:
    case True{}:
      (check_tab(a, gs, fixed, t) .|. 2 : U32)
    case False{}:
      check(a, gs, fixed)

def check_v(p: Array<U32> & Array<U32>, +a: Acc, +gs: +List<V.Pt>, +fixed: +List<V.Pt>, +rs: +List<U32>) -> U32:
  (t1, t2) = p
  check_sel(U32.is_eq(GT.check(t1, gtab_c(), gs, rs), 1), a, gs, fixed, t2)

# check, using the table when there is one and it matches params (rs: random positions to
# spot-check). Bit 0: the verdict; bit 1: the table was used.
def check_opt(+a: Acc, +gs: +List<V.Pt>, +fixed: +List<V.Pt>, ot: P.OT, +rs: +List<U32>) -> U32:
  match ot:
    case P.ONone{}:
      check(a, gs, fixed)
    case P.OSome{t, _}:
      check_v(Array.fork(U32, t), a, gs, fixed, rs)

def tab_ok_k(p: Array<U32> & Array<U32>, +gs: +List<V.Pt>, +rs: +List<U32>) -> U32:
  (t1, t2) = p
  GT.check(t1, gtab_c(), gs, rs)
