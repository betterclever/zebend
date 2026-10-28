import Base
import ./model.bend as M

# Chunking and merging preserve the MSM. The model (model.bend) copies the control structure
# of research/perf4's lib/msm_par.bend (mpar, msm_auto) and v/bt.bend (groups, all_groups, the
# accumulator leaf/join, check), with points and scalars as Nats; see README.md for the
# refinement and for why these identities hold in every commutative group.

# Splitting both lists at ANY position m splits the MSM.
law msm_split:
  for +ps: +List<Nat>
  for +ss: +List<Nat>
  for +m: Nat
  {M.msm(ps, ss) == Nat.add(M.msm(M.take(ps, m), M.take(ss, m)), M.msm(M.drop(ps, m), M.drop(ss, m))) : Nat}

# msm_par.mpar (chunked MSM, any fuel, chunk count and length) computes the MSM.
law mpar_ok:
  for +fuel: Nat
  for +cnt: Nat
  for +len: Nat
  for +ps: +List<Nat>
  for +ss: +List<Nat>
  {M.mpar(fuel, cnt, len, ps, ss) == M.msm(ps, ss) : Nat}

law msm_auto_ok:
  for +ps: +List<Nat>
  for +ss: +List<Nat>
  {M.msm_auto(ps, ss) == M.msm(ps, ss) : Nat}

# bt.groups: splitting the list of per-proof term lists into groups, flattening each group
# and running a chunked MSM on it, sums every proof's own MSM. Hypothesis: the per-proof
# point and scalar lists are aligned (same number of proofs, each proof's two lists of one
# length).
law groups_ok:
  for +fuel: Nat
  for small: Bool
  for +cnt: Nat
  for +ps: +List<+List<Nat>>
  for +ss: +List<+List<Nat>>
  for +h: M.Aligned(ps, ss)
  {M.groups(fuel, small, cnt, ps, ss) == M.psum(ps, ss) : Nat}

# Non-vacuity of groups_ok: every list of per-proof point lists, paired with itself (or any
# scalars of the same shape), satisfies the hypothesis.
law aligned_sat:
  for +ps: +List<+List<Nat>>
  M.Aligned(ps, ps)

# Shared-base scalar addition: s1*P + s2*P == (s1+s2)*P, for a whole vector of shared bases.
law shared_base:
  for +bases: +List<Nat>
  for +a: +List<Nat>
  for +b: +List<Nat>
  {M.msm(bases, M.vadd(a, b)) == Nat.add(M.msm(bases, a), M.msm(bases, b)) : Nat}

# THE MERGED BATCH CHECK. For any tree of weighted proofs (any shape of the parallel
# reduction), the value bt.check tests for the identity, all_groups(per-proof terms) +
# msm_auto(gs ++ fixed, summed shared-base scalars), equals sum_k r_k * (own MSM of proof k +
# MSM of proof k's scalars on the shared bases). Hypothesis: each proof's own point and
# scalar lists have one length.
law merge_ok:
  for +t: M.Tree
  for +bases: +List<Nat>
  for +w: M.WF(t)
  {M.check_sum(M.acc(t), bases) == M.spec(t, bases) : Nat}

# Non-vacuity of merge_ok: for every tree, giving each proof as many scalars as points
# (here: its points themselves) satisfies the hypothesis.
law merge_sat:
  for +t: M.Tree
  M.WF(M.diag(t))
