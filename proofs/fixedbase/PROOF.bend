import Base
import ../msm_chunk/model.bend as MC
import ../msm_chunk/lemmas.bend as MCL
import ./model.bend as M
import ./fxlemmas.bend as F
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
