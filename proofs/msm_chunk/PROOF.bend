import Base
import ./model.bend as M
import ./lemmas.bend as X
import ./LAWS.bend as Laws

def Laws.msm_split(ps, ss, m):
  X.msm_split(ps, ss, m)

def Laws.mpar_ok(fuel, cnt, len, ps, ss):
  X.mpar_ok(fuel, cnt, len, ps, ss)

def Laws.msm_auto_ok(ps, ss):
  X.msm_auto_ok(ps, ss)

def Laws.groups_ok(fuel, small, cnt, ps, ss, h):
  X.groups_ok(fuel, small, cnt, ps, ss, h)

def Laws.aligned_sat(ps):
  match ps:
    case Nil{}:
      Unit{}
    case Con{+p, +pt}:
      ({==}, Laws.aligned_sat(pt))

def Laws.shared_base(bases, a, b):
  X.msm_vadd(bases, a, b)

def Laws.merge_ok(t, bases, w):
  +ps = M.aps(M.acc(t))
  +ss = M.ass(M.acc(t))
  +gx = M.agx(M.acc(t))
  +k = List.length(&2, +List<Nat>, ps)
  Equal.trans(Nat, M.check_sum(M.acc(t), bases), Nat.add(M.all_groups(ps, ss), M.msm_auto(bases, gx)), M.spec(t, bases), X.check_parts(M.acc(t), bases), Equal.trans(Nat, Nat.add(M.all_groups(ps, ss), M.msm_auto(bases, gx)), Nat.add(X.own(t), X.fixs(t, bases)), M.spec(t, bases), X.cadd(M.all_groups(ps, ss), X.own(t), M.msm_auto(bases, gx), X.fixs(t, bases), Equal.trans(Nat, M.groups(32n, M.small_g(k), k, ps, ss), M.psum(ps, ss), X.own(t), X.groups_ok(32n, M.small_g(k), k, ps, ss, X.acc_aligned(t, w)), X.acc_own(t, w)), Equal.trans(Nat, M.msm_auto(bases, gx), M.msm(bases, gx), X.fixs(t, bases), X.msm_auto_ok(bases, gx), X.acc_fix(t, bases))), Equal.sym(Nat, M.spec(t, bases), Nat.add(X.own(t), X.fixs(t, bases)), X.spec_split(t, bases))))

def Laws.merge_sat(t):
  match t:
    case M.Em{}:
      Unit{}
    case M.Lf{+r, +p}:
      match p:
        case M.Pf{+ops, +oss, +gx}:
          {==}
    case M.Nd{+a, +b}:
      (Laws.merge_sat(a), Laws.merge_sat(b))
