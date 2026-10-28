import Base
import ./model.bend as M
import ./fill.bend as F
import ./digit.bend as D

# The bucket method (research/perf4/lib/msm_ba.bend msm9: carry-free signed c-bit digits,
# buckets, pairwise bucket rounds, running-sum reduction, windows combined by doubling)
# computes the multi-scalar multiplication. Model and refinement: model.bend, README.md.
# Points: AP{p, n} with n standing for -p; window width c = 1 + cm, half = 2^cm buckets.

# ONE WINDOW (fill9 + rounds + reduce): the window's sum is sum_i digit_ij * P_i (signed).
# Hypotheses: every window value is at most 2^c; at most 2^rf points (rounds' fuel).
law window_ok:
  for +half: Nat
  for +rf: Nat
  for +ps: +List<M.AP>
  for +us: +List<+List<Nat>>
  for +j: Nat
  for +hw: M.Win(half, us)
  for +hn: M.Le(F.plen(ps), Nat.pow(2n, rf))
  {M.window_sum(half, rf, ps, us, j) == M.wsum(ps, us, j, half) : Nat}

# THE MSM (msm9 = wrange9 over cnt windows, rounds fuel 32). Its result is
# sum_i (posv_i * P_i + negv_i * N_i), where posv_i / negv_i are the 2^c-weighted sums of
# the positive / negative parts of point i's signed digits.
# Hypotheses: window values at most 2^c, at most 2^32 points, and wrange9's fuel (9) splits
# cnt windows down to single windows (Fuel; true for every window count the code uses, see
# fuel_c4 .. fuel_c16 below).
law msm9_ok:
  for +cm: Nat
  for +ps: +List<M.AP>
  for +us: +List<+List<Nat>>
  for +cnt: Nat
  for +hw: M.Win(Nat.pow(2n, cm), us)
  for +hn: M.Le(F.plen(ps), Nat.pow(2n, 32n))
  for +hf: M.Fuel(9n, False{}, cnt)
  {M.msm9(cm, ps, us, cnt) == D.coef(Nat.pow(2n, 1n+cm), Nat.pow(2n, cm), ps, us, cnt, 0n) : Nat}

# THE DIGITS (digit9 / sd_u, carry-free recoding): for every scalar's windows u (any values),
# posv + H == negv + k', where k' = sum_t B^t u_t is the value whose windows these are and
# H = sum_t B^t half (hconst). The code computes k' = k + H, so posv - negv = k: with
# N_i = -P_i, msm9_ok's result is sum_i k_i * P_i (README.md).
law recode:
  for +B: Nat
  for +half: Nat
  for +u: +List<Nat>
  for +cnt: Nat
  for +lo: Nat
  {Nat.add(D.posv(B, half, u, cnt, lo), D.hv(B, half, cnt)) == Nat.add(D.negv(B, half, u, cnt, lo), D.val(B, u, cnt, lo)) : Nat}

# NON-VACUITY of the hypotheses (they constrain different inputs, so they hold together):
# window values: any number of points with any number of windows, all zero;
law win_sat:
  for +half: Nat
  for +np: Nat
  for +nw: Nat
  M.Win(half, M.zeros(np, nw))

# point count: one point is at most 2^32 (any rf);
law points_sat:
  for +a: M.AP
  for +rf: Nat
  M.Le(F.plen([a]), Nat.pow(2n, rf))

# fuel: wrange9's 9 levels split windows9(c) = (257 + c - 1) / c windows down to single
# windows, for every window width c = 4 .. 16 msm9 accepts.
law fuel_c4:
  M.Fuel(9n, False{}, 65n)

law fuel_c5:
  M.Fuel(9n, False{}, 52n)

law fuel_c6:
  M.Fuel(9n, False{}, 43n)

law fuel_c7:
  M.Fuel(9n, False{}, 37n)

law fuel_c8:
  M.Fuel(9n, False{}, 33n)

law fuel_c9:
  M.Fuel(9n, False{}, 29n)

law fuel_c10:
  M.Fuel(9n, False{}, 26n)

law fuel_c11:
  M.Fuel(9n, False{}, 24n)

law fuel_c12:
  M.Fuel(9n, False{}, 22n)

law fuel_c13:
  M.Fuel(9n, False{}, 20n)

law fuel_c14:
  M.Fuel(9n, False{}, 19n)

law fuel_c15:
  M.Fuel(9n, False{}, 18n)

law fuel_c16:
  M.Fuel(9n, False{}, 17n)
