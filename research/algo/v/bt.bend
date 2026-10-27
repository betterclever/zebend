# Batch verification of Halo 2 proofs (as halo2's BatchValidator).
#
# Each proof's verifier ends in one IPA check: MSM(other terms ++ G, scalars ++ s) = identity.
# `verify_fin` (orchard_bt.bend) returns those terms instead of evaluating them. A batch of K
# proofs draws independent random weights r_i and checks the single merged MSM
#     sum_i r_i * (others_i) + sum_j (sum_i r_i s_ij) G_j  =  identity,
# so the 2^k-term G part is paid once per batch. A false proof survives only if the random
# combination cancels, with probability about 1/p.
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ../../fast/fp32.bend as Fp
import ../../fast/lib32/vesta.bend as V
import ../lib/msm_ba.bend as BA
import ./vlib.bend as L

type Fin is Data:
  Fin{st: L.St, ops: +List<V.Pt>, oss: +List<Fp.Fp>, gss: +List<Fp.Fp>}

def fin_ok(f: Fin) -> U32:
  Fin{+st, _, _, _} = f
  L.st_ok(st)

def fin_ops(f: Fin) -> +List<V.Pt>:
  Fin{_, +ops, _, _} = f
  ops

def fin_oss(f: Fin) -> +List<Fp.Fp>:
  Fin{_, _, +oss, _} = f
  oss

def fin_gss(f: Fin) -> +List<Fp.Fp>:
  Fin{_, _, _, +gss} = f
  gss

def words(xs: +List<Fp.Fp>) -> +List<Wd.W>:
  match xs:
    case Con{+h, t}:
      Fp.to_words(h) <> words(t)
    case Nil{}:
      Nil{}

def is_id(+p: V.Pt) -> U32:
  Bool.to_u32(V.is_identity(p))

# One proof on its own: the unbatched check.
def single(+f: Fin, +gs: +List<V.Pt>) -> U32:
  +ps = List.append(&2, V.Pt, fin_ops(f), gs)
  +ss = words(List.append(&2, Fp.Fp, fin_oss(f), fin_gss(f)))
  (fin_ok(f) .&. is_id(BA.msm9(9, ps, ss)) : U32)

# acc_j + r * s_j, elementwise.
def axpy(acc: +List<Fp.Fp>, s: +List<Fp.Fp>, +r: Fp.Fp) -> +List<Fp.Fp>:
  match acc s:
    case Con{+a, at} Con{+b, bt}:
      Fp.add(a, Fp.mul(r, b)) <> axpy(at, bt, r)
    case _ _:
      Nil{}

def zeros(n: Nat) -> +List<Fp.Fp>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      Fp.zero() <> zeros(k)

type Acc is Data:
  Acc{ok: U32, ps: +List<V.Pt>, ss: +List<Fp.Fp>, gss: +List<Fp.Fp>}

def merge(fs: +List<Fin>, rs: +List<Fp.Fp>, acc: Acc) -> Acc:
  match fs rs:
    case Con{+f, ft} Con{+r, rt}:
      Acc{+ok, +ps, +ss, +gss} = acc
      +ok2 = (ok .&. fin_ok(f) : U32)
      +ps2 = List.append(&2, V.Pt, fin_ops(f), ps)
      +ss2 = List.append(&2, Fp.Fp, L.scale_list(fin_oss(f), r), ss)
      merge(ft, rt, Acc{ok2, ps2, ss2, axpy(gss, fin_gss(f), r)})
    case _ _:
      acc

def check_acc(+a: Acc, +gs: +List<V.Pt>) -> U32:
  Acc{+ok, +ps, +ss, +gss} = a
  (ok .&. is_id(BA.msm9(9, List.append(&2, V.Pt, ps, gs), words(List.append(&2, Fp.Fp, ss, gss)))) : U32)

# 1 iff every proof's transcript checks pass and the merged MSM is the identity.
def batch(+fs: +List<Fin>, +rs: +List<Fp.Fp>, +gs: +List<V.Pt>) -> U32:
  check_acc(merge(fs, rs, Acc{1, Nil{}, Nil{}, zeros(List.length(&2, V.Pt, gs))}), gs)
