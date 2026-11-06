import Base
import ../msm_chunk/model.bend as MC
import ../prims/natlib.bend as L
import ./model.bend as M
import ./comb.bend as CB

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

# --- lib/fixb.bend: the comb tables -------------------------------------------------------
# Points are a P + b (-P) (comb.bend); a window of width c = 1 + d.

# The table of a window, built from [B, 2B, .., 2^d B]: the entry whose index has the bits bs
# (d of them, most significant first) is (1 + value(bs)) B.
law comb_entry:
  for +d: Nat
  for +bs: +List<Bool>
  for +p: CB.SP
  for +hb: {List.length(&2, Bool, bs) == d : Nat}
  {CB.tget(d, CB.window(1n+d, p), bs) == CB.smul(1n+CB.valb(bs), p) : CB.SP}

# fixb.walk over the tables of any bases B_j: acc plus sum_j (signed) m_j B_j, when each
# digit is 0 or its bits are those of m_j - 1.
law comb_walk:
  for +d: Nat
  for +bases: +List<CB.SP>
  for +ds: +List<CB.Dg>
  for +acc: CB.SP
  for +h: CB.DigOk(d, ds)
  {CB.walk(d, CB.windows(1n+d, bases), ds, acc) == CB.padd(acc, CB.wsum(bases, ds)) : CB.SP}

# fixb.wbases: the base of window j is 2^(c j) P.
law comb_bases:
  for +n: Nat
  for +c: Nat
  for +p: CB.SP
  for +j: Nat
  for +hj: L.Le(1n+j, n)
  {CB.nthp(CB.wbases(n, c, p), j) == CB.smul(CB.pow2(Nat.mul(c, j)), p) : CB.SP}

# Together: the comb scalar multiplication is acc + sum_j (signed) m_j 2^(c j) P.
law comb_mul:
  for +d: Nat
  for +n: Nat
  for +p: CB.SP
  for +ds: +List<CB.Dg>
  for +acc: CB.SP
  for +h: CB.DigOk(d, ds)
  for +hl: L.Le(List.length(&2, CB.Dg, ds), n)
  {CB.walk(d, CB.windows(1n+d, CB.wbases(n, 1n+d, p)), ds, acc) == CB.padd(acc, CB.comb_sum(ds, 1n+d, 0n, p)) : CB.SP}

# non-vacuity: c = 2, digits 2 (bits of 1: [1]) and 0, two windows
law comb_sat:
  Sigma<&2, &2, CB.DigOk(1n, [CB.Dg{2n, 1n, [True{}]}, CB.Dg{0n, 0n, Nil{}}]), _ => L.Le(List.length(&2, CB.Dg, [CB.Dg{2n, 1n, [True{}]}, CB.Dg{0n, 0n, Nil{}}]), 2n)>
