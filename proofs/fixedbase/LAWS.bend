import Base
import ../msm_chunk/model.bend as MC
import ./model.bend as M

# Fixed-base scalars in the fast Halo 2 verifier, over msm_chunk's (Nat, +) model of the
# group (model.bend, comb.bend).

# --- bt.fx_dense: the sparse-to-dense step ------------------------------------------------

# For every list of fixed bases fs and every list of terms FX{i, s}: the MSM of fs against
# the dense vector fx_dense builds (one summed scalar per base) is the sum of the terms,
# s * fs[i] each (terms with i past the last base contribute nothing).
law fx_dense_sparse:
  for +fs: +List<Nat>
  for +xs: +List<M.FX>
  {MC.msm(fs, M.fx_dense_go(List.length(&2, Nat, fs), 0n, xs)) == M.sparse(fs, xs) : Nat}

# The same for bt.fx_dense itself (46 fixed bases).
law fx_dense_46:
  for +fs: +List<Nat>
  for +xs: +List<M.FX>
  for h: {List.length(&2, Nat, fs) == 46n : Nat}
  {MC.msm(fs, M.fx_dense(xs)) == M.sparse(fs, xs) : Nat}

# Merged with the G scalars as bt.leaf builds gx = gss ++ fx_dense(fx), against the bases
# gs ++ fixed: the G part and the fixed terms, separately.
law fx_merged:
  for +gs: +List<Nat>
  for +gss: +List<Nat>
  for +fs: +List<Nat>
  for +xs: +List<M.FX>
  for h: {List.length(&2, Nat, gs) == List.length(&2, Nat, gss) : Nat}
  {MC.msm(List.append(&2, Nat, gs, fs), List.append(&2, Nat, gss, M.fx_dense_go(List.length(&2, Nat, fs), 0n, xs))) == Nat.add(MC.msm(gs, gss), M.sparse(fs, xs)) : Nat}

# non-vacuity: 46 bases exist
law fx_46_sat:
  {List.length(&2, Nat, M.zeros(46n)) == 46n : Nat}
