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
import ../lib/msm_sb.bend as SB
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

# Stable merge sort of the fixed-base terms by base index (lists of ~46 terms; fuel bounds).
# lt: the head of b sorts before the head of a.
def fx_lt(+a: +List<L.FX>, +b: +List<L.FX>) -> Bool:
  match a b:
    case Con{L.FX{+i, _}, _} Con{L.FX{+j, _}, _}:
      U32.is_lt(j, i)
    case _ _:
      False{}

def fx_merge(fuel: Nat, lt: Bool, +a: +List<L.FX>, +b: +List<L.FX>) -> +List<L.FX>:
  match fuel lt a b:
    case _ _ Nil{} _:
      b
    case _ _ _ Nil{}:
      a
    case 1n+f True{} _ Con{+y, bt}:
      y <> fx_merge(f, fx_lt(a, bt), a, bt)
    case 1n+f False{} Con{+x, at} _:
      x <> fx_merge(f, fx_lt(at, b), at, b)
    case _ _ _ _:
      List.append(&2, L.FX, a, b)

def fx_sort(+fuel: Nat, +cnt: Nat, +xs: +List<L.FX>) -> +List<L.FX>:
  match fuel cnt:
    case _ 0n:
      xs
    case _ 1n:
      xs
    case 1n+f _:
      +h = Nat.div(cnt, 2n)
      +a = fx_sort(f, h, List.take(&2, L.FX, xs, h))
      +b = fx_sort(f, Nat.sub(cnt, h), List.drop(&2, L.FX, xs, h))
      fx_merge(256n, fx_lt(a, b), a, b)
    case 0n _:
      xs

# the head term is on base i
def fx_eqh(+i: U32, +xs: +List<L.FX>) -> Bool:
  match xs:
    case Con{L.FX{+j, _}, _}:
      U32.is_eq(i, j)
    case Nil{}:
      False{}

# dense scalars of bases i .. 45 from the sorted terms, each times w (go: i < 46; eq: the head
# term is on base i): the terms of base i summed from zero in list order, as the per-base scans
# did; terms on an index >= 46 are ignored.
def fx_fill(fuel: Nat, go: Bool, eq: Bool, +i: U32, +xs: +List<L.FX>, +acc: Fp.Fp, +w: Fp.Fp) -> +List<Fp.Fp>:
  match fuel go eq xs:
    case 1n+f True{} True{} Con{L.FX{_, +s}, t}:
      fx_fill(f, True{}, fx_eqh(i, t), i, t, Fp.add(acc, s), w)
    case 1n+f True{} _ _:
      Fp.mul(acc, w) <> fx_fill(f, U32.is_lt((i + 1 : U32), 46), fx_eqh((i + 1 : U32), xs), (i + 1 : U32), xs, Fp.zero(), w)
    case _ _ _ _:
      Nil{}

# the fixed-base scalars as a dense vector, base 0 first, each times w
def fx_dense_w(+xs: +List<L.FX>, +w: Fp.Fp) -> +List<Fp.Fp>:
  +n = List.length(&2, L.FX, xs)
  +ys = fx_sort(16n, n, xs)
  fx_fill(Nat.add(n, 64n), True{}, fx_eqh(0, ys), 0, ys, Fp.zero(), w)

# the fixed-base scalars as a dense vector, base 0 first
def fx_dense(+xs: +List<L.FX>) -> +List<Fp.Fp>:
  fx_dense_w(xs, Fp.one())

# --- the IPA G scalars ----------------------------------------------------------------
# The generated batch verifier (opt_gates.py) leaves the G scalars as a recipe,
# [init, v, u_k, ..., u_1] (the u_j last-first, as compute_s takes them), for
# sub_head(compute_s(us, init), v); g_expand builds them, times a weight r, in front of tail.
def s_recipe(+us_rev: +List<Fp.Fp>, +init: Fp.Fp, +v: Fp.Fp) -> +List<Fp.Fp>:
  init <> v <> us_rev

def g_expand(+rc: +List<Fp.Fp>, +r: Fp.Fp, +tail: +List<Fp.Fp>) -> +List<Fp.Fp>:
  match rc:
    case Con{+init, Con{+v, us}}:
      L.sub_head(L.s_build(List.reverse(&2, Fp.Fp, us), Fp.mul(init, r), tail), Fp.mul(v, r))
    case _:
      tail

# --- one proof on its own: the unbatched check -----------------------------------------

def single(+f: Fin, +gs: +List<V.Pt>, +fixed: +List<V.Pt>) -> U32:
  +ps = List.append(&2, V.Pt, fin_ops(f), List.append(&2, V.Pt, gs, fixed))
  +ss = words(List.append(&2, Fp.Fp, fin_oss(f), g_expand(fin_gss(f), Fp.one(), fx_dense(fin_fx(f)))))
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

# A verified proof, weighted by r: the 2,048 G scalars r * s_i are built directly (r folded
# into compute_s's init and into v), in front of the 46 fixed-base scalars, so no list is
# appended or scaled. (init * r) * prod u = (init * prod u) * r and init*r - v*r = (init - v)*r
# in the field, and every Fp result is canonical, so each scalar is the same as
# scale_list(sub_head(compute_s(us, init), v) ++ fixed, r).
def leaf(+f: Fin, +r: Fp.Fp, +bad: U32) -> Acc:
  +gx = g_expand(fin_gss(f), r, L.scale_list(fx_dense(fin_fx(f)), r))
  Acc{fin_ok(f), 1n, bad, fin_ops(f) <> Nil{}, scale_words(fin_oss(f), r) <> Nil{}, gx}

def none() -> Acc:
  Acc{1, 0n, 0, Nil{}, Nil{}, Nil{}}

def join(+a: Acc, +b: Acc) -> Acc:
  Acc{+oa, +na, +ba, +pa, +sa, +ga} = a
  Acc{+ob, +nb, +bb, +pb, +sb, +gb} = b
  Acc{(oa .&. ob : U32), Nat.add(na, nb), (ba + bb : U32), List.append(&2, +List<V.Pt>, pa, pb), List.append(&2, +List<Wd.W>, sa, sb), vadd(ga, gb)}

# --- the tree accumulator (perf5-gate) ---------------------------------------------------
# Inside the parallel tree the 2,048 G scalars travel in blocks of four (one heap cell per four
# scalars, so a quarter of the allocations, frees and list steps in the leaves' s-vectors and
# in the vector adds at every join); the 46 fixed-base scalars stay a plain list. The root
# turns the result into an Acc with the same gx, element for element (to_acc).
type GB is Data:
  GB4{a: Fp.Fp, b: Fp.Fp, c: Fp.Fp, d: Fp.Fp, n: GB}
  GBN{}

# s_build in blocks: the last two challenges (the two lowest index bits) make one block
# [c, c*u_b, c*u_a, (c*u_a)*u_b] for us = [.., u_a, u_b]; above them, as s_build.
def s_build4(+us: +List<Fp.Fp>, +c: Fp.Fp, +tail: GB) -> GB:
  match us:
    case Con{+ua, Con{+ub, Nil{}}}:
      +ca = Fp.mul(c, ua)
      GB4{c, Fp.mul(c, ub), ca, Fp.mul(ca, ub), tail}
    case Con{+u, +rest}:
      s_build4(rest, c, s_build4(rest, Fp.mul(c, u), tail))
    case Nil{}:
      tail

def gb_sub_head(+g: GB, +v: Fp.Fp) -> GB:
  match g:
    case GB4{+a, +b, +c, +d, t}:
      GB4{Fp.sub(a, v), b, c, d, t}
    case GBN{}:
      GBN{}

# the weighted G scalars of one proof (the recipe of s_recipe), r * (sub_head(compute_s, v))
def g_expand4(+rc: +List<Fp.Fp>, +r: Fp.Fp) -> GB:
  match rc:
    case Con{+init, Con{+v, us}}:
      gb_sub_head(s_build4(List.reverse(&2, Fp.Fp, us), Fp.mul(init, r), GBN{}), Fp.mul(v, r))
    case _:
      GBN{}

def vadd4(a: GB, b: GB) -> GB:
  match a b:
    case GB4{+a0, +a1, +a2, +a3, at} GB4{+b0, +b1, +b2, +b3, bt}:
      GB4{Fp.add(a0, b0), Fp.add(a1, b1), Fp.add(a2, b2), Fp.add(a3, b3), vadd4(at, bt)}
    case GBN{} _:
      b
    case _ GBN{}:
      a

def gb_list(g: GB, +tail: +List<Fp.Fp>) -> +List<Fp.Fp>:
  match g:
    case GB4{+a, +b, +c, +d, t}:
      a <> b <> c <> d <> gb_list(t, tail)
    case GBN{}:
      tail

type TA is Data:
  TA{ok: U32, n: Nat, bad: U32, ps: +List<+List<V.Pt>>, ss: +List<+List<Wd.W>>, g: GB, fx: +List<Fp.Fp>}

# A verified proof, weighted by r (the same scalars as leaf's gx).
def leaf_t(+f: Fin, +r: Fp.Fp, +bad: U32) -> TA:
  TA{fin_ok(f), 1n, bad, fin_ops(f) <> Nil{}, scale_words(fin_oss(f), r) <> Nil{}, g_expand4(fin_gss(f), r), fx_dense_w(fin_fx(f), r)}

# Two proofs' weighted G scalars summed while they are built (the bottom joins of the tree):
# the same products as two s_build4 runs and the same sums as vadd4 on their results, without
# building either vector. us_a, us_b: the two proofs' challenges, top-first (same length).
def s_build4_2(+us_a: +List<Fp.Fp>, +ca: Fp.Fp, +us_b: +List<Fp.Fp>, +cb: Fp.Fp, +tail: GB) -> GB:
  match us_a us_b:
    case Con{+ua, Con{+ub, Nil{}}} Con{+va, Con{+vb, Nil{}}}:
      +caa = Fp.mul(ca, ua)
      +cba = Fp.mul(cb, va)
      GB4{Fp.add(ca, cb), Fp.add(Fp.mul(ca, ub), Fp.mul(cb, vb)), Fp.add(caa, cba), Fp.add(Fp.mul(caa, ub), Fp.mul(cba, vb)), tail}
    case Con{+u, +ra} Con{+v, +rb}:
      s_build4_2(ra, ca, rb, cb, s_build4_2(ra, Fp.mul(ca, u), rb, Fp.mul(cb, v), tail))
    case _ _:
      tail

def rc_init(+rc: +List<Fp.Fp>) -> Fp.Fp:
  match rc:
    case Con{+init, _}:
      init
    case Nil{}:
      Fp.zero()

def rc_v(+rc: +List<Fp.Fp>) -> Fp.Fp:
  match rc:
    case Con{_, Con{+v, _}}:
      v
    case _:
      Fp.zero()

def rc_us(+rc: +List<Fp.Fp>) -> +List<Fp.Fp>:
  match rc:
    case Con{_, Con{_, us}}:
      List.reverse(&2, Fp.Fp, us)
    case _:
      Nil{}

def same_len(+a: +List<Fp.Fp>, +b: +List<Fp.Fp>) -> Bool:
  Nat.is_eq(List.length(&2, Fp.Fp, a), List.length(&2, Fp.Fp, b))

# r_a * (s_a with v_a off its head) + r_b * (s_b with v_b off its head), as vadd4 of the two
# g_expand4 results; falls back to exactly that when the challenge counts differ.
def g_expand4_2(same: Bool, +rca: +List<Fp.Fp>, +ra: Fp.Fp, +rcb: +List<Fp.Fp>, +rb: Fp.Fp) -> GB:
  match same:
    case True{}:
      gb_sub_head(gb_sub_head(s_build4_2(rc_us(rca), Fp.mul(rc_init(rca), ra), rc_us(rcb), Fp.mul(rc_init(rcb), rb), GBN{}), Fp.mul(rc_v(rca), ra)), Fp.mul(rc_v(rcb), rb))
    case False{}:
      vadd4(g_expand4(rca, ra), g_expand4(rcb, rb))

# One verified proof, weighted, with everything a leaf needs (built in parallel, then paired).
type JF is Data:
  JF{f: Fin, r: Fp.Fp, bad: U32}

# join_t(leaf_t(a), leaf_t(b)), with the two G vectors summed while they are built
def leaf2_t(+a: JF, +b: JF) -> TA:
  JF{+fa, +ra, +bada} = a
  JF{+fb, +rb, +badb} = b
  +ga = fin_gss(fa)
  +gb = fin_gss(fb)
  +g = g_expand4_2(same_len(ga, gb), ga, ra, gb, rb)
  TA{(fin_ok(fa) .&. fin_ok(fb) : U32), 2n, (bada + badb : U32), fin_ops(fa) <> fin_ops(fb) <> Nil{}, scale_words(fin_oss(fa), ra) <> scale_words(fin_oss(fb), rb) <> Nil{}, g, vadd(fx_dense_w(fin_fx(fa), ra), fx_dense_w(fin_fx(fb), rb))}

def none_t() -> TA:
  TA{1, 0n, 0, Nil{}, Nil{}, GBN{}, Nil{}}

def join_t(+a: TA, +b: TA) -> TA:
  TA{+oa, +na, +ba, +pa, +sa, +ga, +fa} = a
  TA{+ob, +nb, +bb, +pb, +sb, +gb, +fb} = b
  TA{(oa .&. ob : U32), Nat.add(na, nb), (ba + bb : U32), List.append(&2, +List<V.Pt>, pa, pb), List.append(&2, +List<Wd.W>, sa, sb), vadd4(ga, gb), vadd(fa, fb)}

# the Acc of join/leaf: gx = the G scalars followed by the fixed-base scalars
def to_acc(+t: TA) -> Acc:
  TA{+ok, +n, +bad, +ps, +ss, +g, +fx} = t
  Acc{ok, n, bad, ps, ss, gb_list(g, fx)}

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
# perf5-msm: the MSM is msm_sb (sorted flat buckets), whose per-term cost falls with n, so groups
# are 400 proofs (~50k terms, c = 13) instead of 20: K = 1,024 at 1 thread final 0.78 / 0.70 /
# 0.62 ms per bundle for 200 / 400 / 800, at 18 threads 0.078 / 0.089 / 0.123; K = 10,048 at 18
# threads 0.066 / 0.053 / 0.057.
def grp() -> Nat:
  400n

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
      SB.msm_auto(flat_p(ps, Nil{}), flat_w(ss, Nil{}))

def all_groups(+ps: +List<+List<V.Pt>>, +ss: +List<+List<Wd.W>>) -> V.Pt:
  +k = List.length(&2, +List<V.Pt>, ps)
  groups(32n, small_g(k), k, ps, ss)

# 1 iff every proof's transcript checks pass and the merged MSM is the identity.
def check(+a: Acc, +gs: +List<V.Pt>, +fixed: +List<V.Pt>) -> U32:
  Acc{+ok, _, _, +ps, +ss, +gx} = a
  x y = all_groups(ps, ss) SB.msm_auto(List.append(&2, V.Pt, gs, fixed), words(gx))
  (ok .&. is_id(VL.add(x, y)) : U32)

# --- with the fixed-base table of G ------------------------------------------------------

def gtab_c() -> U32:
  9

def gtab_tasks() -> Nat:
  16n

def ngs(+gs: +List<V.Pt>) -> Nat:
  List.length(&2, V.Pt, gs)

def msm_rest(+fixed: +List<V.Pt>, +fw: +List<Wd.W>, +ps: +List<+List<V.Pt>>, +ss: +List<+List<Wd.W>>) -> V.Pt:
  x y = SB.msm_auto(fixed, fw) all_groups(ps, ss)
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
