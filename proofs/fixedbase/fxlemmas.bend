import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L
import ../opt_gates/term.bend as T
import ../msm_chunk/model.bend as MC
import ./model.bend as M

# fx_dense is linear in its terms, and one term s on base j lands as s * fixed[j].

def len(xs: +List<Nat>) -> Nat:
  List.length(&2, Nat, xs)

def D(+fs: +List<Nat>, +i: Nat, +xs: +List<M.FX>) -> +List<Nat>:
  M.fx_dense_go(len(fs), i, xs)

# --- Nat.is_eq ----------------------------------------------------------------------------

def eq_refl(+i: Nat) -> {Nat.is_eq(i, i) == True{} : Bool}:
  match i:
    case 0n:
      {==}
    case 1n+k:
      eq_refl(k)

def neq1(+i: Nat, +e: Nat) -> {Nat.is_eq(i, 1n+Nat.add(e, i)) == False{} : Bool}:
  match i:
    case 0n:
      {==}
    case 1n+k:
      %Equal.sym(Nat, Nat.add(e, 1n+k), 1n+Nat.add(e, k), N.add_succ_r(e, k)) : {Nat.is_eq(k, _) == False{} : Bool}
      neq1(k, e)

def neq2(+j: Nat, +k: Nat) -> {Nat.is_eq(1n+Nat.add(k, j), j) == False{} : Bool}:
  match j:
    case 0n:
      {==}
    case 1n+m:
      %Equal.sym(Nat, Nat.add(k, 1n+m), 1n+Nat.add(k, m), N.add_succ_r(k, m)) : {Nat.is_eq(_, m) == False{} : Bool}
      neq2(m, k)

# --- the accumulator ----------------------------------------------------------------------

def sel_add(b: Bool, +a: Nat, +s: Nat, +f: Nat) -> {Nat.add(M.sel(b, Nat.add(a, s), a), f) == Nat.add(a, Nat.add(M.sel(b, s, 0n), f)) : Nat}:
  match b:
    case True{}:
      N.add_assoc(a, s, f)
    case False{}:
      {==}

def acc(+i: Nat, +r: +List<M.FX>, +a: Nat) -> {M.fx_sum(i, r, a) == Nat.add(a, M.fx_sum(i, r, 0n)) : Nat}:
  match r:
    case Nil{}:
      Equal.sym(Nat, Nat.add(a, 0n), a, N.add_zero_r(a))
    case Con{M.FX{+j, +s}, +t}:
      +c = M.sel(Nat.is_eq(i, j), Nat.add(a, s), a)
      +c0 = M.sel(Nat.is_eq(i, j), s, 0n)
      +f = M.fx_sum(i, t, 0n)
      Equal.trans(Nat, M.fx_sum(i, t, c), Nat.add(c, f), Nat.add(a, M.fx_sum(i, t, c0)), acc(i, t, c),
      Equal.trans(Nat, Nat.add(c, f), Nat.add(a, Nat.add(c0, f)), Nat.add(a, M.fx_sum(i, t, c0)), sel_add(Nat.is_eq(i, j), a, s, f),
      Equal.cong(Nat, Nat, w => Nat.add(a, w), Nat.add(c0, f), M.fx_sum(i, t, c0), Equal.sym(Nat, M.fx_sum(i, t, c0), Nat.add(c0, f), acc(i, t, c0)))))

# --- linearity --------------------------------------------------------------------------------

def lin(+fs: +List<Nat>, +i: Nat, +x: M.FX, +r: +List<M.FX>) -> {MC.msm(fs, D(fs, i, x <> r)) == Nat.add(MC.msm(fs, D(fs, i, [x])), MC.msm(fs, D(fs, i, r))) : Nat}:
  match fs:
    case Nil{}:
      {==}
    case Con{+f, +t}:
      match x:
        case M.FX{+j, +s}:
          +c = M.sel(Nat.is_eq(i, j), s, 0n)
          +fr = M.fx_sum(i, r, 0n)
          +m1 = MC.msm(t, D(t, 1n+i, [M.FX{j, s}]))
          +m2 = MC.msm(t, D(t, 1n+i, r))
          +ea = acc(i, r, c)
          %Equal.sym(Nat, M.fx_sum(i, r, c), Nat.add(c, fr), ea) : {Nat.add(Nat.mul(_, f), MC.msm(t, D(t, 1n+i, M.FX{j, s} <> r))) == Nat.add(Nat.add(Nat.mul(c, f), m1), Nat.add(Nat.mul(fr, f), m2)) : Nat}
          %Equal.sym(Nat, MC.msm(t, D(t, 1n+i, M.FX{j, s} <> r)), Nat.add(m1, m2), lin(t, 1n+i, M.FX{j, s}, r)) : {Nat.add(Nat.mul(Nat.add(c, fr), f), _) == Nat.add(Nat.add(Nat.mul(c, f), m1), Nat.add(Nat.mul(fr, f), m2)) : Nat}
          %Equal.sym(Nat, Nat.mul(Nat.add(c, fr), f), Nat.add(Nat.mul(c, f), Nat.mul(fr, f)), L.mul_add_r(c, fr, f)) : {Nat.add(_, Nat.add(m1, m2)) == Nat.add(Nat.add(Nat.mul(c, f), m1), Nat.add(Nat.mul(fr, f), m2)) : Nat}
          N.swap_mid(Nat.mul(c, f), Nat.mul(fr, f), m1, m2)

# --- one term --------------------------------------------------------------------------------

# a term on base j adds nothing to the entries of the bases after j
def zero1(+fs: +List<Nat>, +j: Nat, +k: Nat, +s: Nat) -> {MC.msm(fs, D(fs, 1n+Nat.add(k, j), [M.FX{j, s}])) == 0n : Nat}:
  match fs:
    case Nil{}:
      {==}
    case Con{+f, +t}:
      %Equal.sym(Bool, Nat.is_eq(1n+Nat.add(k, j), j), False{}, neq2(j, k)) : {Nat.add(Nat.mul(M.sel(_, s, 0n), f), MC.msm(t, D(t, 2n+Nat.add(k, j), [M.FX{j, s}]))) == 0n : Nat}
      zero1(t, j, 1n+k, s)

# a term s on base i + d (counting from base i) is s * fs[d]
def single(+fs: +List<Nat>, +i: Nat, +d: Nat, +s: Nat) -> {MC.msm(fs, D(fs, i, [M.FX{Nat.add(d, i), s}])) == Nat.mul(s, T.nth(fs, d)) : Nat}:
  match fs:
    case Nil{}:
      Equal.sym(Nat, Nat.mul(s, 0n), 0n, L.mul_zero_r(s))
    case Con{+f, +t}:
      match d:
        case 0n:
          %Equal.sym(Bool, Nat.is_eq(i, i), True{}, eq_refl(i)) : {Nat.add(Nat.mul(M.sel(_, s, 0n), f), MC.msm(t, D(t, 1n+i, [M.FX{i, s}]))) == Nat.mul(s, f) : Nat}
          %Equal.sym(Nat, MC.msm(t, D(t, 1n+i, [M.FX{i, s}])), 0n, zero1(t, i, 0n, s)) : {Nat.add(Nat.mul(s, f), _) == Nat.mul(s, f) : Nat}
          N.add_zero_r(Nat.mul(s, f))
        case 1n+e:
          %Equal.sym(Bool, Nat.is_eq(i, 1n+Nat.add(e, i)), False{}, neq1(i, e)) : {Nat.add(Nat.mul(M.sel(_, s, 0n), f), MC.msm(t, D(t, 1n+i, [M.FX{1n+Nat.add(e, i), s}]))) == Nat.mul(s, T.nth(t, e)) : Nat}
          %N.add_succ_r(e, i) : {MC.msm(t, D(t, 1n+i, [M.FX{_, s}])) == Nat.mul(s, T.nth(t, e)) : Nat}
          single(t, 1n+i, e, s)

def zeros(+fs: +List<Nat>, +i: Nat) -> {MC.msm(fs, D(fs, i, Nil{})) == 0n : Nat}:
  match fs:
    case Nil{}:
      {==}
    case Con{+f, +t}:
      zeros(t, 1n+i)

# --- the dense vector's MSM is the sparse sum -------------------------------------------------

def dense_ok(+fs: +List<Nat>, +xs: +List<M.FX>) -> {MC.msm(fs, D(fs, 0n, xs)) == M.sparse(fs, xs) : Nat}:
  match xs:
    case Nil{}:
      zeros(fs, 0n)
    case Con{M.FX{+j, +s}, +r}:
      %Equal.sym(Nat, MC.msm(fs, D(fs, 0n, M.FX{j, s} <> r)), Nat.add(MC.msm(fs, D(fs, 0n, [M.FX{j, s}])), MC.msm(fs, D(fs, 0n, r))), lin(fs, 0n, M.FX{j, s}, r)) : {_ == Nat.add(Nat.mul(s, T.nth(fs, j)), M.sparse(fs, r)) : Nat}
      %Equal.sym(Nat, MC.msm(fs, D(fs, 0n, r)), M.sparse(fs, r), dense_ok(fs, r)) : {Nat.add(MC.msm(fs, D(fs, 0n, [M.FX{j, s}])), _) == Nat.add(Nat.mul(s, T.nth(fs, j)), M.sparse(fs, r)) : Nat}
      %N.add_zero_r(j) : {Nat.add(MC.msm(fs, D(fs, 0n, [M.FX{_, s}])), M.sparse(fs, r)) == Nat.add(Nat.mul(s, T.nth(fs, j)), M.sparse(fs, r)) : Nat}
      Equal.cong(Nat, Nat, w => Nat.add(w, M.sparse(fs, r)), MC.msm(fs, D(fs, 0n, [M.FX{Nat.add(j, 0n), s}])), Nat.mul(s, T.nth(fs, j)), single(fs, 0n, j, s))
