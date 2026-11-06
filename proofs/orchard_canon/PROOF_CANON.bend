import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L
import ../orchard/fieldmodel.bend as F
import ../orchard/rowlemmas.bend as R
import ../orchard/natorder.bend as O
import ./CANON.bend as Laws

# Proof of CANON.bend. Bound every partial sum of a + 2^250 b_0 + 2^254 b_1 below p, so that
# no field operation in the decomposition wraps (L.mod_small), then read the field equation
# as an integer one. The only case that needs the canonicity checks is b_1 = 1, where
# a + 2^254 < p needs a < t_P, which the a' check gives: a + 2^130 = t_P + a' with a' < 2^130.

def le_of_eq(+a: Nat, +b: Nat, +e: {a == b : Nat}) -> L.Le(a, b):
  (0n, Equal.trans(Nat, Nat.add(a, 0n), a, b, N.add_zero_r(a), e))

# x <= y + x
def le_add_front(+x: Nat, +y: Nat) -> L.Le(x, Nat.add(y, x)):
  (y, N.add_comm(x, y))

# 2^254 <= p - 1, from p = 2^254 + t_P and t_P >= 1.
def le_t254(+pp: Nat, +t254: Nat, +tP: Nat, +hp: {Nat.add(t254, tP) == 1n+pp : Nat}, +htp1: L.Le(1n, tP)) -> L.Le(t254, pp):
  (+e1, h1) = htp1
  (e1, L.succ_inj(Nat.add(t254, e1), pp,
    Equal.trans(Nat, 1n+Nat.add(t254, e1), Nat.add(t254, 1n+e1), 1n+pp, Equal.sym(Nat, Nat.add(t254, 1n+e1), 1n+Nat.add(t254, e1), N.add_succ_r(t254, e1)),
      Equal.trans(Nat, Nat.add(t254, 1n+e1), Nat.add(t254, tP), 1n+pp, Equal.cong(Nat, Nat, w => Nat.add(t254, w), 1n+e1, tP, h1), hp))))

# y < 16 t250 = t254 <= pp  ==>  y <= pp
def below16(+pp: Nat, +t250: Nat, +t254: Nat, +y: Nat, +h16: {Nat.mul(16n, t250) == t254 : Nat}, +lt: L.Le(t254, pp), +l: L.Le(1n+y, Nat.mul(16n, t250))) -> L.Le(y, pp):
  O.le_trans(y, t254, pp, O.lt_le(y, t254, O.le_trans(1n+y, Nat.mul(16n, t250), t254, l, le_of_eq(Nat.mul(16n, t250), t254, h16))), lt)

# 2 t250 <= 16 t250
def two_le16(+t250: Nat) -> L.Le(Nat.add(t250, t250), Nat.mul(16n, t250)):
  O.le_add_l(t250, t250, Nat.add(t250, Nat.mul(14n, t250)), (Nat.mul(14n, t250), {==}))

# a < t_P, when b_1 = 1 (the a' check): a + 2^130 == t_P + a' with a' < 2^130.
def a_lt_tp(+pp: Nat, +t130: Nat, +t250: Nat, +t254: Nat, +tP: Nat, +h16: {Nat.mul(16n, t250) == t254 : Nat}, +lt: L.Le(t254, pp),
    +htp: L.Le(1n+tP, t130), +h130: L.Le(t130, t250), +a: Nat, +ap: Nat,
    +e1: {F.fadd(1n+pp, a, t130) == F.fadd(1n+pp, tP, ap) : Nat}, +ra: L.Le(1n+a, t250), +rap: L.Le(1n+ap, t130)) -> L.Le(1n+a, tP):
  +s1 = below16(pp, t250, t254, Nat.add(a, t130), h16, lt,
          O.le_trans(1n+Nat.add(a, t130), Nat.add(t250, t250), Nat.mul(16n, t250), O.le_add2(1n+a, t250, t130, t250, ra, h130), two_le16(t250)))
  +s2 = below16(pp, t250, t254, Nat.add(tP, ap), h16, lt,
          O.le_trans(1n+Nat.add(tP, ap), Nat.add(t250, t250), Nat.mul(16n, t250),
            O.le_trans(1n+Nat.add(tP, ap), Nat.add(t130, t130), Nat.add(t250, t250), O.le_add2(1n+tP, t130, ap, t130, htp, O.lt_le(ap, t130, rap)), O.le_add2(t130, t250, t130, t250, h130, h130)),
            two_le16(t250)))
  +eq = Equal.trans(Nat, Nat.add(a, t130), F.fadd(1n+pp, a, t130), Nat.add(tP, ap), Equal.sym(Nat, F.fadd(1n+pp, a, t130), Nat.add(a, t130), L.mod_small(Nat.add(a, t130), pp, s1)),
          Equal.trans(Nat, F.fadd(1n+pp, a, t130), F.fadd(1n+pp, tP, ap), Nat.add(tP, ap), e1, L.mod_small(Nat.add(tP, ap), pp, s2)))
  O.le_cancel_r(1n+a, tP, t130,
    R.le_eq(Nat.add(tP, 1n+ap), 1n+Nat.add(a, t130), Nat.add(tP, t130),
      Equal.trans(Nat, Nat.add(tP, 1n+ap), 1n+Nat.add(tP, ap), 1n+Nat.add(a, t130), N.add_succ_r(tP, ap), Equal.cong(Nat, Nat, w => 1n+w, Nat.add(tP, ap), Nat.add(a, t130), Equal.sym(Nat, Nat.add(a, t130), Nat.add(tP, ap), eq))),
      O.le_add_l(tP, 1n+ap, t130, rap)))

# The whole sum is below p, by cases on b_1.
def b4_one(+pp: Nat, +t254: Nat, +tP: Nat, +hp: {Nat.add(t254, tP) == 1n+pp : Nat}, +a: Nat, +lt: L.Le(1n+a, tP)) -> L.Le(Nat.add(a, t254), pp):
  O.le_pred(Nat.add(a, t254), pp, O.le_trans(1n+Nat.add(a, t254), Nat.add(tP, t254), 1n+pp, O.le_add_r(1n+a, tP, t254, lt),
    le_of_eq(Nat.add(tP, t254), 1n+pp, Equal.trans(Nat, Nat.add(tP, t254), Nat.add(t254, tP), 1n+pp, N.add_comm(tP, t254), hp))))

def b2_zero(+pp: Nat, +t254: Nat, +b1: Nat, +z: {b1 == 0n : Nat}) -> L.Le(Nat.mul(b1, t254), pp):
  %Equal.sym(Nat, b1, 0n, z) : L.Le(Nat.mul(_, t254), pp)
  R.le_0(pp)

def b4_zero(+pp: Nat, +t250: Nat, +t254: Nat, +a: Nat, +b0: Nat, +b1: Nat, +z: {b1 == 0n : Nat}, +b3: L.Le(Nat.add(a, Nat.mul(b0, t250)), pp))
    -> L.Le(Nat.add(Nat.add(a, Nat.mul(b0, t250)), Nat.mul(b1, t254)), pp):
  %Equal.sym(Nat, b1, 0n, z) : L.Le(Nat.add(Nat.add(a, Nat.mul(b0, t250)), Nat.mul(_, t254)), pp)
  %Equal.sym(Nat, Nat.add(Nat.add(a, Nat.mul(b0, t250)), 0n), Nat.add(a, Nat.mul(b0, t250)), N.add_zero_r(Nat.add(a, Nat.mul(b0, t250)))) : L.Le(_, pp)
  b3

def b2_one(+pp: Nat, +t254: Nat, +b1: Nat, +z: {b1 == 1n : Nat}, +lt: L.Le(t254, pp)) -> L.Le(Nat.mul(b1, t254), pp):
  %Equal.sym(Nat, b1, 1n, z) : L.Le(Nat.mul(_, t254), pp)
  %Equal.sym(Nat, Nat.mul(1n, t254), t254, L.mul_one_l(t254)) : L.Le(_, pp)
  lt

def b4_inr(+pp: Nat, +t130: Nat, +t250: Nat, +t254: Nat, +tP: Nat, +hp: {Nat.add(t254, tP) == 1n+pp : Nat}, +h16: {Nat.mul(16n, t250) == t254 : Nat}, +lt: L.Le(t254, pp),
    +htp: L.Le(1n+tP, t130), +h130: L.Le(t130, t250), +a: Nat, +b0: Nat, +b1: Nat, +ap: Nat,
    +e1: {F.fadd(1n+pp, a, t130) == F.fadd(1n+pp, tP, ap) : Nat}, +z0: {b0 == 0n : Nat}, +ra: L.Le(1n+a, t250),
    +rap: L.Le(1n+ap, t130), +z: {b1 == 1n : Nat}) -> L.Le(Nat.add(Nat.add(a, Nat.mul(b0, t250)), Nat.mul(b1, t254)), pp):
  %Equal.sym(Nat, b1, 1n, z) : L.Le(Nat.add(Nat.add(a, Nat.mul(b0, t250)), Nat.mul(_, t254)), pp)
  %Equal.sym(Nat, b0, 0n, z0) : L.Le(Nat.add(Nat.add(a, Nat.mul(_, t250)), Nat.mul(1n, t254)), pp)
  %Equal.sym(Nat, Nat.add(a, 0n), a, N.add_zero_r(a)) : L.Le(Nat.add(_, Nat.mul(1n, t254)), pp)
  %Equal.sym(Nat, Nat.mul(1n, t254), t254, L.mul_one_l(t254)) : L.Le(Nat.add(a, _), pp)
  b4_one(pp, t254, tP, hp, a, a_lt_tp(pp, t130, t250, t254, tP, h16, lt, htp, h130, a, ap, e1, ra, rap))

# The two cases of b_1. Each yields b_1 t254 <= pp and the whole sum <= pp.
def b4(+pp: Nat, +t130: Nat, +t250: Nat, +t254: Nat, +tP: Nat, +hp: {Nat.add(t254, tP) == 1n+pp : Nat}, +h16: {Nat.mul(16n, t250) == t254 : Nat}, +lt: L.Le(t254, pp),
    +htp: L.Le(1n+tP, t130), +h130: L.Le(t130, t250), +a: Nat, +b0: Nat, +b1: Nat, +ap: Nat,
    +e1: {F.fadd(1n+pp, a, t130) == F.fadd(1n+pp, tP, ap) : Nat}, i0: {b1 == 1n : Nat} -> {b0 == 0n : Nat}, +ra: L.Le(1n+a, t250),
    rap: {b1 == 1n : Nat} -> L.Le(1n+ap, t130), +b3: L.Le(Nat.add(a, Nat.mul(b0, t250)), pp),
    bit: Either<&1, &1, {b1 == 0n : Nat}, {b1 == 1n : Nat}>) -> L.Le(Nat.mul(b1, t254), pp) & L.Le(Nat.add(Nat.add(a, Nat.mul(b0, t250)), Nat.mul(b1, t254)), pp):
  match bit:
    case Inl{+z}:
      (b2_zero(pp, t254, b1, z), b4_zero(pp, t250, t254, a, b0, b1, z, b3))
    case Inr{+z}:
      (b2_one(pp, t254, b1, z, lt), b4_inr(pp, t130, t250, t254, tP, hp, h16, lt, htp, h130, a, b0, b1, ap, e1, i0(z), ra, rap(z), z))

def fin(+pp: Nat, +t250: Nat, +t254: Nat, +x: Nat, +a: Nat, +b0: Nat, +b1: Nat,
    +e0: {F.fadd(1n+pp, F.fadd(1n+pp, a, F.fmul(1n+pp, b0, t250)), F.fmul(1n+pp, b1, t254)) == x : Nat},
    +b1x: L.Le(Nat.mul(b0, t250), pp), +b3: L.Le(Nat.add(a, Nat.mul(b0, t250)), pp),
    bb: L.Le(Nat.mul(b1, t254), pp) & L.Le(Nat.add(Nat.add(a, Nat.mul(b0, t250)), Nat.mul(b1, t254)), pp))
    -> {x == Nat.add(Nat.add(a, Nat.mul(b0, t250)), Nat.mul(b1, t254)) : Nat}:
  (+b2, +b4v) = bb
  %L.mod_small(Nat.add(Nat.add(a, Nat.mul(b0, t250)), Nat.mul(b1, t254)), pp, b4v) : {x == _ : Nat}
  %L.mod_small(Nat.mul(b1, t254), pp, b2) : {x == Nat.mod(Nat.add(Nat.add(a, Nat.mul(b0, t250)), _), 1n+pp) : Nat}
  %L.mod_small(Nat.add(a, Nat.mul(b0, t250)), pp, b3) : {x == Nat.mod(Nat.add(_, F.fmul(1n+pp, b1, t254)), 1n+pp) : Nat}
  %L.mod_small(Nat.mul(b0, t250), pp, b1x) : {x == Nat.mod(Nat.add(Nat.mod(Nat.add(a, _), 1n+pp), F.fmul(1n+pp, b1, t254)), 1n+pp) : Nat}
  Equal.sym(Nat, F.fadd(1n+pp, F.fadd(1n+pp, a, F.fmul(1n+pp, b0, t250)), F.fmul(1n+pp, b1, t254)), x, e0)

def Laws.canon_gd(pp, t130, t250, t254, tP, hp, h16, htp, htp1, h130, x, a, b0, b1, ap, e0, e1, i0, bit, ra, rb, rap):
  +lt = le_t254(pp, t254, tP, hp, htp1)
  +b0le = O.le_pred(b0, 15n, rb)
  +lm15 = O.le_mul_r(b0, 15n, t250, b0le)
  +b1x = below16(pp, t250, t254, Nat.mul(b0, t250), h16, lt, O.le_trans(1n+Nat.mul(b0, t250), 1n+Nat.mul(15n, t250), Nat.mul(16n, t250), O.le_add_l(1n, Nat.mul(b0, t250), Nat.mul(15n, t250), lm15), O.le_add_r(1n, t250, Nat.mul(15n, t250), O.le_trans(1n, 1n+tP, t250, (tP, {==}), O.le_trans(1n+tP, t130, t250, htp, h130)))))
  +b3 = below16(pp, t250, t254, Nat.add(a, Nat.mul(b0, t250)), h16, lt, O.le_add2(1n+a, t250, Nat.mul(b0, t250), Nat.mul(15n, t250), ra, lm15))
  fin(pp, t250, t254, x, a, b0, b1, e0, b1x, b3, b4(pp, t130, t250, t254, tP, hp, h16, lt, htp, h130, a, b0, b1, ap, e1, i0, ra, rap, b3, bit))

def Laws.canon_gd_satisfiable():
  ({==}, {==}, (0n, {==}), (0n, {==}), (0n, {==}), {==}, {==},
    z => {==}, Inr{{==}}, (1n, {==}), (15n, {==}), z => (0n, {==}))

def Laws.canon_gd_without_aprime_counterexample():
  ({==}, {==}, (0n, {==}), (0n, {==}), (0n, {==}), {==}, {==},
    z => {==}, Inr{{==}}, (0n, {==}), (15n, {==}), e => L.succ_ne_zero(32n, Equal.sym(Nat, 0n, 33n, e)))
