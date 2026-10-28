import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L
import ./acu.bend as A
import ./model.bend as M
import ./red.bend as R
import ./fill.bend as F

# The carry-free signed digits (msm_ba.digit9 / sd_u) and what the windows add up to.

# positive and negative part of a digit
def dpos_b(b: Bool, +u: Nat, +half: Nat) -> Nat:
  match b:
    case True{}:
      Nat.sub(u, half)
    case False{}:
      0n

def dneg_b(b: Bool, +u: Nat, +half: Nat) -> Nat:
  match b:
    case True{}:
      0n
    case False{}:
      Nat.sub(half, u)

def dpos(+u: Nat, +half: Nat) -> Nat:
  dpos_b(Nat.is_ge(u, half), u, half)

def dneg(+u: Nat, +half: Nat) -> Nat:
  dneg_b(Nat.is_ge(u, half), u, half)

def sdval_b(b: Bool, +u: Nat, +half: Nat, +p: Nat, +n: Nat) -> {M.sdval(M.sd_u(b, u, half), M.AP{p, n}) == Nat.add(Nat.mul(dpos_b(b, u, half), p), Nat.mul(dneg_b(b, u, half), n)) : Nat}:
  match b:
    case True{}:
      Equal.sym(Nat, Nat.add(Nat.mul(Nat.sub(u, half), p), 0n), Nat.mul(Nat.sub(u, half), p), N.add_zero_r(Nat.mul(Nat.sub(u, half), p)))
    case False{}:
      {==}

def ge_T(+u: Nat, +h: Nat, e: {Nat.is_ge(u, h) == True{} : Bool}) -> M.Le(h, u):
  match u:
    case 0n:
      match h:
        case 0n:
          (0n, {==})
        case 1n+k:
          Empty.absurd(M.Le(1n+k, 0n), R.bool_ne(e))
    case 1n+v:
      match h:
        case 0n:
          (1n+v, {==})
        case 1n+k:
          R.le_succ(k, v, ge_T(v, k, e))

def ge_F(+u: Nat, +h: Nat, e: {Nat.is_ge(u, h) == False{} : Bool}) -> M.Le(u, h):
  match u:
    case 0n:
      (h, {==})
    case 1n+v:
      match h:
        case 0n:
          Empty.absurd(M.Le(1n+v, 0n), R.bool_ne(Equal.sym(Bool, True{}, False{}, e)))
        case 1n+k:
          R.le_succ(v, k, ge_F(v, k, e))

def digit_b(b: Bool, +u: Nat, +half: Nat, e: {Nat.is_ge(u, half) == b : Bool}) -> {Nat.add(dpos_b(b, u, half), half) == Nat.add(dneg_b(b, u, half), u) : Nat}:
  match b:
    case True{}:
      Equal.trans(Nat, Nat.add(Nat.sub(u, half), half), Nat.add(half, Nat.sub(u, half)), u, N.add_comm(Nat.sub(u, half), half), L.sub_add(u, half, ge_T(u, half, e)))
    case False{}:
      Equal.sym(Nat, Nat.add(Nat.sub(half, u), u), half, Equal.trans(Nat, Nat.add(Nat.sub(half, u), u), Nat.add(u, Nat.sub(half, u)), half, N.add_comm(Nat.sub(half, u), u), L.sub_add(half, u, ge_F(u, half, e))))

# --- per scalar: B-weighted sums over the windows ----------------------------------------------

def posv(+B: Nat, +half: Nat, +u: +List<Nat>, cnt: Nat, +lo: Nat) -> Nat:
  match cnt:
    case 0n:
      0n
    case 1n+t:
      Nat.add(dpos(M.nth(u, lo), half), Nat.mul(B, posv(B, half, u, t, 1n+lo)))

def negv(+B: Nat, +half: Nat, +u: +List<Nat>, cnt: Nat, +lo: Nat) -> Nat:
  match cnt:
    case 0n:
      0n
    case 1n+t:
      Nat.add(dneg(M.nth(u, lo), half), Nat.mul(B, negv(B, half, u, t, 1n+lo)))

# k' = sum_t B^t u_t (the scalar plus H, whose windows the code extracts)
def val(+B: Nat, +u: +List<Nat>, cnt: Nat, +lo: Nat) -> Nat:
  match cnt:
    case 0n:
      0n
    case 1n+t:
      Nat.add(M.nth(u, lo), Nat.mul(B, val(B, u, t, 1n+lo)))

# H = sum_t B^t half
def hv(+B: Nat, +half: Nat, cnt: Nat) -> Nat:
  match cnt:
    case 0n:
      0n
    case 1n+t:
      Nat.add(half, Nat.mul(B, hv(B, half, t)))

def recode(+B: Nat, +half: Nat, +u: +List<Nat>, +cnt: Nat, +lo: Nat) -> {Nat.add(posv(B, half, u, cnt, lo), hv(B, half, cnt)) == Nat.add(negv(B, half, u, cnt, lo), val(B, u, cnt, lo)) : Nat}:
  match cnt:
    case 0n:
      {==}
    case 1n+t:
      +x = M.nth(u, lo)
      +p0 = dpos(x, half)
      +n0 = dneg(x, half)
      +P = posv(B, half, u, t, 1n+lo)
      +H = hv(B, half, t)
      +Q = negv(B, half, u, t, 1n+lo)
      +V = val(B, u, t, 1n+lo)
      +e0 = digit_b(Nat.is_ge(x, half), x, half, {==})
      +e1 = Equal.trans(Nat, Nat.add(Nat.mul(B, P), Nat.mul(B, H)), Nat.mul(B, Nat.add(P, H)), Nat.add(Nat.mul(B, Q), Nat.mul(B, V)), Equal.sym(Nat, Nat.mul(B, Nat.add(P, H)), Nat.add(Nat.mul(B, P), Nat.mul(B, H)), L.mul_add_l(B, P, H)), Equal.trans(Nat, Nat.mul(B, Nat.add(P, H)), Nat.mul(B, Nat.add(Q, V)), Nat.add(Nat.mul(B, Q), Nat.mul(B, V)), Equal.cong(Nat, Nat, w => Nat.mul(B, w), Nat.add(P, H), Nat.add(Q, V), recode(B, half, u, t, 1n+lo)), L.mul_add_l(B, Q, V)))
      Equal.trans(Nat, Nat.add(Nat.add(p0, Nat.mul(B, P)), Nat.add(half, Nat.mul(B, H))), Nat.add(Nat.add(p0, half), Nat.add(Nat.mul(B, P), Nat.mul(B, H))), Nat.add(Nat.add(n0, Nat.mul(B, Q)), Nat.add(x, Nat.mul(B, V))), N.swap_mid(p0, Nat.mul(B, P), half, Nat.mul(B, H)), Equal.trans(Nat, Nat.add(Nat.add(p0, half), Nat.add(Nat.mul(B, P), Nat.mul(B, H))), Nat.add(Nat.add(n0, x), Nat.add(Nat.mul(B, Q), Nat.mul(B, V))), Nat.add(Nat.add(n0, Nat.mul(B, Q)), Nat.add(x, Nat.mul(B, V))), R.cadd(Nat.add(p0, half), Nat.add(n0, x), Nat.add(Nat.mul(B, P), Nat.mul(B, H)), Nat.add(Nat.mul(B, Q), Nat.mul(B, V)), e0, e1), N.swap_mid(n0, x, Nat.mul(B, Q), Nat.mul(B, V))))

# --- the windows' sum, regrouped per point: sum_i posv_i * P_i + negv_i * N_i ---------------

def coef(+B: Nat, +half: Nat, ps: +List<M.AP>, us: +List<+List<Nat>>, +cnt: Nat, +lo: Nat) -> Nat:
  match ps us:
    case Con{M.AP{+p, +n}, pt} Con{+u, ut}:
      Nat.add(Nat.add(Nat.mul(posv(B, half, u, cnt, lo), p), Nat.mul(negv(B, half, u, cnt, lo), n)), coef(B, half, pt, ut, cnt, lo))
    case _ _:
      0n

def coef_step(+B: Nat, +half: Nat, +ps: +List<M.AP>, +us: +List<+List<Nat>>, +t: Nat, +lo: Nat) -> {Nat.add(M.wsum(ps, us, lo, half), Nat.mul(B, coef(B, half, ps, us, t, 1n+lo))) == coef(B, half, ps, us, 1n+t, lo) : Nat}:
  match ps:
    case Nil{}:
      L.mul_zero_r(B)
    case Con{+a, +pt}:
      match a:
        case M.AP{+p, +n}:
          match us:
            case Nil{}:
              L.mul_zero_r(B)
            case Con{+u, +ut}:
              +x = M.nth(u, lo)
              +p0 = dpos(x, half)
              +n0 = dneg(x, half)
              +P = posv(B, half, u, t, 1n+lo)
              +Q = negv(B, half, u, t, 1n+lo)
              +C = coef(B, half, pt, ut, t, 1n+lo)
              +W = M.wsum(pt, ut, lo, half)
              +sv = sdval_b(Nat.is_ge(x, half), x, half, p, n)
              +rest = coef_step(B, half, pt, ut, t, lo)
              +k1 = Nat.mul(p0, p)
              +k2 = Nat.mul(n0, n)
              +k3 = Nat.mul(B, Nat.mul(P, p))
              +k4 = Nat.mul(B, Nat.mul(Q, n))
              +k5 = Nat.mul(B, C)
              +lhs1 = Equal.trans(Nat, Nat.mul(B, Nat.add(Nat.add(Nat.mul(P, p), Nat.mul(Q, n)), C)), Nat.add(Nat.mul(B, Nat.add(Nat.mul(P, p), Nat.mul(Q, n))), k5), Nat.add(Nat.add(k3, k4), k5), L.mul_add_l(B, Nat.add(Nat.mul(P, p), Nat.mul(Q, n)), C), Equal.cong(Nat, Nat, w => Nat.add(w, k5), Nat.mul(B, Nat.add(Nat.mul(P, p), Nat.mul(Q, n))), Nat.add(k3, k4), L.mul_add_l(B, Nat.mul(P, p), Nat.mul(Q, n))))
              +m1 = Equal.trans(Nat, Nat.mul(Nat.add(p0, Nat.mul(B, P)), p), Nat.add(k1, Nat.mul(Nat.mul(B, P), p)), Nat.add(k1, k3), L.mul_add_r(p0, Nat.mul(B, P), p), Equal.cong(Nat, Nat, w => Nat.add(k1, w), Nat.mul(Nat.mul(B, P), p), k3, L.mul_assoc(B, P, p)))
              +m2 = Equal.trans(Nat, Nat.mul(Nat.add(n0, Nat.mul(B, Q)), n), Nat.add(k2, Nat.mul(Nat.mul(B, Q), n)), Nat.add(k2, k4), L.mul_add_r(n0, Nat.mul(B, Q), n), Equal.cong(Nat, Nat, w => Nat.add(k2, w), Nat.mul(Nat.mul(B, Q), n), k4, L.mul_assoc(B, Q, n)))
              +tail = rest
              Equal.trans(Nat, Nat.add(Nat.add(M.sdval(M.digit(x, half), M.AP{p, n}), W), Nat.mul(B, Nat.add(Nat.add(Nat.mul(P, p), Nat.mul(Q, n)), C))), Nat.add(Nat.add(Nat.add(k1, k2), W), Nat.add(Nat.add(k3, k4), k5)), Nat.add(Nat.add(Nat.mul(Nat.add(p0, Nat.mul(B, P)), p), Nat.mul(Nat.add(n0, Nat.mul(B, Q)), n)), coef(B, half, pt, ut, 1n+t, lo)), R.cadd(Nat.add(M.sdval(M.digit(x, half), M.AP{p, n}), W), Nat.add(Nat.add(k1, k2), W), Nat.mul(B, Nat.add(Nat.add(Nat.mul(P, p), Nat.mul(Q, n)), C)), Nat.add(Nat.add(k3, k4), k5), Equal.cong(Nat, Nat, w => Nat.add(w, W), M.sdval(M.digit(x, half), M.AP{p, n}), Nat.add(k1, k2), sv), lhs1), Equal.trans(Nat, Nat.add(Nat.add(Nat.add(k1, k2), W), Nat.add(Nat.add(k3, k4), k5)), Nat.add(Nat.add(Nat.add(k1, k3), Nat.add(k2, k4)), Nat.add(W, k5)), Nat.add(Nat.add(Nat.mul(Nat.add(p0, Nat.mul(B, P)), p), Nat.mul(Nat.add(n0, Nat.mul(B, Q)), n)), coef(B, half, pt, ut, 1n+t, lo)), A.acu({[k1, k2, k3, k4, k5, W] : +List<Nat>}, A.P{A.P{A.P{A.V{0n}, A.V{1n}}, A.V{5n}}, A.P{A.P{A.V{2n}, A.V{3n}}, A.V{4n}}}, A.P{A.P{A.P{A.V{0n}, A.V{2n}}, A.P{A.V{1n}, A.V{3n}}}, A.P{A.V{5n}, A.V{4n}}}, {==}), R.cadd(Nat.add(Nat.add(k1, k3), Nat.add(k2, k4)), Nat.add(Nat.mul(Nat.add(p0, Nat.mul(B, P)), p), Nat.mul(Nat.add(n0, Nat.mul(B, Q)), n)), Nat.add(W, k5), coef(B, half, pt, ut, 1n+t, lo), R.cadd(Nat.add(k1, k3), Nat.mul(Nat.add(p0, Nat.mul(B, P)), p), Nat.add(k2, k4), Nat.mul(Nat.add(n0, Nat.mul(B, Q)), n), Equal.sym(Nat, Nat.mul(Nat.add(p0, Nat.mul(B, P)), p), Nat.add(k1, k3), m1), Equal.sym(Nat, Nat.mul(Nat.add(n0, Nat.mul(B, Q)), n), Nat.add(k2, k4), m2)), tail)))

def coef_zero(+B: Nat, +half: Nat, +ps: +List<M.AP>, +us: +List<+List<Nat>>, +lo: Nat) -> {0n == coef(B, half, ps, us, 0n, lo) : Nat}:
  match ps:
    case Nil{}:
      {==}
    case Con{+a, +pt}:
      match a:
        case M.AP{+p, +n}:
          match us:
            case Nil{}:
              {==}
            case Con{+u, +ut}:
              coef_zero(B, half, pt, ut, lo)

def spec_coef(+c: Nat, +half: Nat, +ps: +List<M.AP>, +us: +List<+List<Nat>>, +cnt: Nat, +lo: Nat) -> {M.spec(c, half, ps, us, cnt, lo) == coef(Nat.pow(2n, c), half, ps, us, cnt, lo) : Nat}:
  match cnt:
    case 0n:
      coef_zero(Nat.pow(2n, c), half, ps, us, lo)
    case 1n+t:
      Equal.trans(Nat, Nat.add(M.wsum(ps, us, lo, half), Nat.mul(Nat.pow(2n, c), M.spec(c, half, ps, us, t, 1n+lo))), Nat.add(M.wsum(ps, us, lo, half), Nat.mul(Nat.pow(2n, c), coef(Nat.pow(2n, c), half, ps, us, t, 1n+lo))), coef(Nat.pow(2n, c), half, ps, us, 1n+t, lo), Equal.cong(Nat, Nat, w => Nat.add(M.wsum(ps, us, lo, half), Nat.mul(Nat.pow(2n, c), w)), M.spec(c, half, ps, us, t, 1n+lo), coef(Nat.pow(2n, c), half, ps, us, t, 1n+lo), spec_coef(c, half, ps, us, t, 1n+lo)), coef_step(Nat.pow(2n, c), half, ps, us, t, lo))

