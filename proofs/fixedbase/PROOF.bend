import Base
import ../msm_chunk/model.bend as MC
import ../msm_chunk/lemmas.bend as MCL
import ./model.bend as M
import ./fxlemmas.bend as F
import ./comb.bend as CB
import ./comblemmas3.bend as K3
import ./comblemmas4.bend as K4
import ./LAWS.bend as Laws

def Laws.fx_dense_sparse(fs, xs):
  F.dense_ok(fs, xs)

def Laws.fx_dense_46(fs, xs, h):
  %h : {MC.msm(fs, M.fx_dense_go(_, 0n, xs)) == M.sparse(fs, xs) : Nat}
  F.dense_ok(fs, xs)

def Laws.fx_merged(gs, gss, fs, xs, h):
  Equal.trans(Nat, MC.msm(List.append(&2, Nat, gs, fs), List.append(&2, Nat, gss, M.fx_dense_go(List.length(&2, Nat, fs), 0n, xs))), Nat.add(MC.msm(gs, gss), MC.msm(fs, M.fx_dense_go(List.length(&2, Nat, fs), 0n, xs))), Nat.add(MC.msm(gs, gss), M.sparse(fs, xs)), MCL.msm_append(gs, gss, fs, M.fx_dense_go(List.length(&2, Nat, fs), 0n, xs), h), Equal.cong(Nat, Nat, w => Nat.add(MC.msm(gs, gss), w), MC.msm(fs, M.fx_dense_go(List.length(&2, Nat, fs), 0n, xs)), M.sparse(fs, xs), F.dense_ok(fs, xs)))

def Laws.fx_46_sat():
  {==}

def Laws.comb_entry(d, bs, p, hb):
  K3.table_entry(d, bs, p, hb)

def Laws.comb_walk(d, bases, ds, acc, h):
  K3.walk_ok(d, bases, ds, acc, h)

def Laws.comb_bases(n, c, p, j, hj):
  K3.wbases_pow(n, c, p, j, hj)

def Laws.comb_mul(d, n, p, ds, acc, h, hl):
  Equal.trans(CB.SP, CB.walk(d, CB.windows(1n+d, CB.wbases(n, 1n+d, p)), ds, acc), CB.padd(acc, CB.wsum(CB.wbases(n, 1n+d, p), ds)), CB.padd(acc, CB.comb_sum(ds, 1n+d, 0n, p)), K3.walk_ok(d, CB.wbases(n, 1n+d, p), ds, acc, h), Equal.cong(CB.SP, CB.SP, z => CB.padd(acc, z), CB.wsum(CB.wbases(n, 1n+d, p), ds), CB.comb_sum(ds, 1n+d, 0n, p), K4.ws_cs0(ds, n, 1n+d, p, hl)))

def Laws.comb_sat():
  (((Inr{({==}, {==})}, ((Inl{{==}}, Unit{})))), (0n, {==}))
