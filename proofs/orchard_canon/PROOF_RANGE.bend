import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L
import ../orchard/fieldmodel.bend as F
import ../orchard/evals.bend as E
import ../orchard/rowlemmas.bend as R
import ../orchard/natorder.bend as O
import ./RANGE.bend as Laws

# Proofs of RANGE.bend. The induction runs from the end of the running sum: if z_{i+1} < r^m
# and the word w = z_i - z_{i+1} r is < r, then z_{i+1} r + w < r^(m+1) <= p, so neither the
# product nor the sum wraps mod p, and z_i equals the integer z_{i+1} r + w < r^(m+1).

# 1 <= r from a word below r.
def r_pos(+w: Nat, +r: Nat, +hw: L.Le(1n+w, r)) -> L.Le(1n, r):
  O.le_trans(1n, 1n+w, r, (w, {==}), hw)

# r^m <= r^m r, for r >= 1.
def pw_le(+q: Nat, +r: Nat, +lr: L.Le(1n, r)) -> L.Le(q, Nat.mul(q, r)):
  %L.mul_one_r(q) : L.Le(_, Nat.mul(q, r))
  O.le_mul_l(q, 1n, r, lr)

def step_bound_a(+z1: Nat, +w: Nat, +r: Nat, +hw: L.Le(1n+w, r)) -> L.Le(1n+Nat.add(Nat.mul(z1, r), w), Nat.mul(1n+z1, r)):
  %N.add_succ_r(Nat.mul(z1, r), w) : L.Le(_, Nat.mul(1n+z1, r))
  %N.add_comm(Nat.mul(z1, r), r) : L.Le(Nat.add(Nat.mul(z1, r), 1n+w), _)
  O.le_add_l(Nat.mul(z1, r), 1n+w, r, hw)

# z1 < q and w < r  ==>  z1 r + w < q r
def step_bound(+z1: Nat, +w: Nat, +r: Nat, +q: Nat, +hw: L.Le(1n+w, r), +ih: L.Le(1n+z1, q)) -> L.Le(1n+Nat.add(Nat.mul(z1, r), w), Nat.mul(q, r)):
  O.le_trans(1n+Nat.add(Nat.mul(z1, r), w), Nat.mul(1n+z1, r), Nat.mul(q, r),
    step_bound_a(z1, w, r, hw), O.le_mul_r(1n+z1, q, r, ih))

# The field step is the integer step: z == z1 r + w, given the integer bound.
def z_int(+pp: Nat, +r: Nat, +z: Nat, +z1: Nat, +lz: L.Le(z, pp), +lsum: L.Le(Nat.add(Nat.mul(z1, r), Laws.word(pp, r, z, z1)), pp))
    -> {z == Nat.add(Nat.mul(z1, r), Laws.word(pp, r, z, z1)) : Nat}:
  +w = Laws.word(pp, r, z, z1)
  +lmul = O.le_trans(Nat.mul(z1, r), Nat.add(Nat.mul(z1, r), w), pp, (w, {==}), lsum)
  +e1 = F.neg_eq(pp, z, F.fmul(1n+pp, z1, r), w, lz, E.le_fmul(pp, z1, r), {==})
  %L.mod_small(Nat.add(Nat.mul(z1, r), w), pp, lsum) : {z == _ : Nat}
  %L.mod_small(Nat.mul(z1, r), pp, lmul) : {z == Nat.mod(Nat.add(_, w), 1n+pp) : Nat}
  e1

def go(+pp: Nat, +r: Nat, zs: List<&2, Nat>, +z: Nat, +lz: L.Le(z, pp), h: Laws.Steps(pp, r, zs, z), +hz: {Laws.last(zs, z) == 0n : Nat},
    +hp: L.Le(Laws.pw(r, Laws.len(zs)), 1n+pp)) -> L.Le(1n+z, Laws.pw(r, Laws.len(zs))):
  match zs:
    case Nil{}:
      %Equal.sym(Nat, z, 0n, hz) : L.Le(1n+_, 1n)
      (0n, {==})
    case Con{+z1, +t}:
      (+hw, rest1) = h
      (+lz1, rest) = rest1
      +q = Laws.pw(r, Laws.len(t))
      +w = Laws.word(pp, r, z, z1)
      +lr = r_pos(w, r, hw)
      +ih = go(pp, r, t, z1, lz1, rest, hz, O.le_trans(q, Nat.mul(q, r), 1n+pp, pw_le(q, r, lr), hp))
      +b = step_bound(z1, w, r, q, hw, ih)
      +lsum = O.le_pred(Nat.add(Nat.mul(z1, r), w), pp, O.le_trans(1n+Nat.add(Nat.mul(z1, r), w), Nat.mul(q, r), 1n+pp, b, hp))
      %Equal.sym(Nat, z, Nat.add(Nat.mul(z1, r), w), z_int(pp, r, z, z1, lz, lsum)) : L.Le(1n+_, Nat.mul(q, r))
      b

def Laws.running_sum_range(pp, r, z0, lz0, zs, h, hz, hp):
  go(pp, r, zs, z0, lz0, h, hz, hp)

# word(0, 0) == 0
def word_00(+pp: Nat, +r: Nat) -> {Laws.word(pp, r, 0n, 0n) == 0n : Nat}:
  %Equal.sym(Nat, F.fsub(1n+pp, 0n, 0n), 0n, E.fsub_0_0(pp)) : {F.fadd(1n+pp, 0n, _) == 0n : Nat}
  {==}

def zero_steps(+pp: Nat, +r: Nat, +lr: L.Le(1n, r), n: Nat) -> Laws.Steps(pp, r, Laws.zeros(n), 0n):
  match n:
    case 0n:
      Unit{}
    case 1n+m:
      (%Equal.sym(Nat, Laws.word(pp, r, 0n, 0n), 0n, word_00(pp, r)) : L.Le(1n+_, r)
       lr, (R.le_0(pp), zero_steps(pp, r, lr, m)))

def zero_last(n: Nat) -> {Laws.last(Laws.zeros(n), 0n) == 0n : Nat}:
  match n:
    case 0n:
      {==}
    case 1n+m:
      zero_last(m)

def Laws.running_sum_zero_satisfiable(pp, r, lr, n):
  (R.le_0(pp), zero_steps(pp, r, lr, n), zero_last(n))

def Laws.running_sum_range_satisfiable():
  ((5n, {==}), ((0n, {==}), ((9n, {==}), ((1n, {==}), ((10n, {==}), Unit{})))), {==}, (2n, {==}))

def Laws.running_sum_nonstrict_counterexample():
  ((0n, {==}), ((1n, {==}), ((7n, {==}), Unit{})), (8n, {==}), l => R.gt_absurd(3n, 7n, l))
