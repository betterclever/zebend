import Base
import ../prims/natlib.bend as L
import ../opt_gates/term.bend as T
import ../ring/expr.bend as X
import ./model.bend as M
import ./lemmas.bend as B

# Montgomery batch inversion, as the fast Halo 2 verifier runs it (model.bend copies
# crypto/field3/fp64.bend's batch_inv, research/perf4/v/vlib.bend's binvs and
# research/perf4/lib/msm_ba.bend's batch_inv), in Z/p with p = 1 + bp.
#
# Hypotheses, all explicit: l1 (p >= 2) or l2 (p >= 3); every input canonical (hc);
# and either the one inversion the code performs succeeds (bi_inverts: the product times
# its x^(p-2) is 1), or p is prime in the form of Fermat's little theorem (B.Fermat).

# For every p >= 2 and every list xs: if the single inversion inverts the product of the
# inputs, every output is the inverse of its input: B.Inv says the lists have one length
# and x * y == 1 pointwise. No primality is used.
law bi_inverts:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +xs: +List<Nat>
  for +hc: X.Canon(bp, xs)
  for h: {T.fmul(bp, M.prod(bp, xs, 1n), T.finv(bp, M.prod(bp, xs, 1n))) == 1n : Nat}
  B.Inv(bp, xs, M.batch_inv(bp, xs))

# In a prime field (Fermat), batch_inv of nonzero inputs is x |-> x^(p-2) pointwise, i.e. it
# returns exactly what one Fp.inv per element would.
law bi_finv:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +xs: +List<Nat>
  for +hc: X.Canon(bp, xs)
  for +hnz: B.NZs(xs)
  for f: B.Fermat(bp)
  {M.batch_inv(bp, xs) == M.finvs(bp, xs) : +List<Nat>}

# What batch_inv does with a zero input (p >= 3): the product is 0, the inversion returns
# 0^(p-2) = 0, and every output is 0 (B.Zs: same length, all zero). Its callers never pass a
# zero: binvs replaces zeros by 1 first, msm_ba passes z_or_one and den's 1 for non-affine pairs.
law bi_zero:
  for +bp: Nat
  for +l2: L.Le(2n, bp)
  for +xs: +List<Nat>
  for +hc: X.Canon(bp, xs)
  for +hz: B.Has0(xs)
  B.Zs(xs, M.batch_inv(bp, xs))

# vlib.binvs (zeros masked around batch_inv) is x |-> x^(p-2) for every input, 0 |-> 0
# included: exactly how opt_gates reads it (its trusted inversion-batching step).
law binvs_finv:
  for +bp: Nat
  for +l2: L.Le(2n, bp)
  for +xs: +List<Nat>
  for +hc: X.Canon(bp, xs)
  for f: B.Fermat(bp)
  {M.binvs(bp, xs) == M.finvs(bp, xs) : +List<Nat>}

# msm_ba's own batch_inv (prefix / back / top_or_one) computes the same list as fp64's, for
# every input, so the laws above hold for it too.
law ba_is_bi:
  for +bp: Nat
  for +xs: +List<Nat>
  {M.ba_batch_inv(bp, xs) == M.batch_inv(bp, xs) : +List<Nat>}

# --- non-vacuity: every hypothesis above can be met ---------------------------------------

# Fermat holds for p = 5.
law fermat_5:
  B.Fermat(4n)

# p = 5, xs = [2, 3]: p >= 2, canonical, and the one inversion succeeds (2 * 3 = 1 mod 5).
law bi_inverts_sat:
  Sigma<&2, &2, L.Le(1n, 4n), _ => Sigma<&2, &2, X.Canon(4n, [2n, 3n]), _ => {T.fmul(4n, M.prod(4n, [2n, 3n], 1n), T.finv(4n, M.prod(4n, [2n, 3n], 1n))) == 1n : Nat}>>

# p = 5, xs = [2, 3]: canonical and nonzero (with fermat_5, bi_finv's hypotheses).
law bi_finv_sat:
  Sigma<&2, &2, L.Le(1n, 4n), _ => Sigma<&2, &2, X.Canon(4n, [2n, 3n]), _ => B.NZs([2n, 3n])>>

# p = 5, xs = [3, 0]: p >= 3, canonical, with a zero (bi_zero's hypotheses; with fermat_5,
# binvs_finv's).
law bi_zero_sat:
  Sigma<&2, &2, L.Le(2n, 4n), _ => Sigma<&2, &2, X.Canon(4n, [3n, 0n]), _ => B.Has0([3n, 0n])>>
