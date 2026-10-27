# Laws about NU7's consensus changes, stated about the functions in nu7.bend and era7.bend
# that the node runs (rules.bend, follow's equihash7), except where marked "(spec)": those are
# about the Nat form of a formula whose 64-bit implementation is differential-tested instead.
# Le(a, b) is "a <= b", witnessed by the gap (proofs/prims/natlib.bend).
import Base
import ../../proofs/prims/natlib.bend as L
import ../issuance/issuance.bend as I
import ./nu7.bend as N
import ./era7.bend as E

# ---------------------------------------------------------------- ZIP 218: issuance schedule

# The halving index does not jump at NU7 activation: the NU7 case of Halving() (every era
# scaled into 25 s blocks, divided by PostNU7HalvingInterval = 3 * PostBlossomHalvingInterval)
# at the activation height equals the post-Blossom case there. For every slow-start shift s,
# Blossom height b, activation height a and halving interval iv >= 1.
law halving_continuous:
  for +s: Nat
  for +b: Nat
  for +a: Nat
  for +ivp: Nat
  {N.halving_nu7(s, b, a, a, 1n+ivp) == N.halving_post(s, b, a, 1n+ivp) : Nat}

# Issuance per unit of time is preserved at the 75 s -> 25 s transition, up to rounding: for
# every halving era k and starting subsidy m, three NU7 blocks issue at most one post-Blossom
# block's subsidy ...
law per_time_le:
  for +k: Nat
  for +m: Nat
  L.Le(Nat.mul(3n, N.sub7(k, m)), I.halve(k, m))

# ... and at most 2 zatoshi less.
law per_time_ge:
  for +k: Nat
  for +m: Nat
  L.Le(I.halve(k, m), Nat.add(Nat.mul(3n, N.sub7(k, m)), 2n))

# The halving era containing the activation issues no more than without NU7: x blocks at the
# post-Blossom subsidy s, then the remaining y blocks' worth of time as 3y NU7 blocks at
# floor(s / 3), issue at most (x + y) s. For every x, y, s.
law transition_era_le:
  for +x: Nat
  for +y: Nat
  for +s: Nat
  L.Le(Nat.add(Nat.mul(x, s), Nat.mul(Nat.mul(3n, y), Nat.div(s, 3n))), Nat.mul(Nat.add(x, y), s))

# Supply cap under NU7: K halving eras of 3n NU7 blocks each (starting subsidy floor(m/3) per
# block, halving per era) issue at most n * 2m, the bound the 75 s schedule has (issuance's
# `cap`: 21,000,000 ZEC for n = 1,680,000, m = 625,000,000).
law cap_nu7:
  for +n: Nat
  for +K: Nat
  for +m: Nat
  L.Le(Nat.mul(Nat.mul(3n, n), N.total7(K, m)), Nat.mul(n, Nat.add(m, m)))

# ---------------------------------------------------------------- ZIP 235 / 237: NSM

# (spec) ZIP 235's split form 6 q + floor(6 r / 10) is exactly floor(6 fees / 10).
law contribution_exact:
  for +f: Nat
  {N.nsm_contribution_n(f) == Nat.div(Nat.mul(6n, f), 10n) : Nat}

# (spec) The contribution never exceeds the fees ...
law contribution_le:
  for +f: Nat
  L.Le(N.nsm_contribution_n(f), f)

# (spec) ... so the fee split conserves value: contribution + MinerFees == fees.
law fee_split_conserves:
  for +f: Nat
  {Nat.add(N.nsm_contribution_n(f), N.miner_fees_n(f)) == f : Nat}

# (spec) Reissuance never exceeds the balance it is drawn from: ceiling(c * bal / d) <= bal for
# c <= d (ZIP 237: c = 1375, d = 10^10), so the NSM value balance cannot go negative through
# AdditionalBlockSubsidy (the ZIP's "MUST reject if negative" cannot trigger from it).
law reissue_le:
  for +c: Nat
  for +dp: Nat
  for +bal: Nat
  for l: L.Le(c, 1n+dp)
  L.Le(N.reissue_n(c, dp, bal), bal)

# (spec) Value conservation of the NSM: per block, issued supply + NSM balance grows by
# exactly the scheduled subsidy s, whatever is reissued (a <= balance) or removed (c <= issued
# supply + s + a).
law nsm_conserves:
  for +i: Nat
  for +v: Nat
  for +s: Nat
  for +a: Nat
  for +c: Nat
  for la: L.Le(a, v)
  for lc: L.Le(c, Nat.add(Nat.add(i, s), a))
  {Nat.add(N.issued_next(i, s, a, c), N.nsm_next(v, a, c)) == Nat.add(Nat.add(i, v), s) : Nat}

# ---------------------------------------------------------------- ZIP 218: difficulty

# In every era (pre-Blossom, post-Blossom, NU7) and for every actual timespan, the bounded
# timespan stays within [MinActualTimespan, MaxActualTimespan]: at most 16% harder or 32%
# easier per block, also across the NU7 transition.
law timespan_ge_min:
  for +e: E.Era
  for neg: Bool
  for +mag: Nat
  exs k: Nat
  {Nat.add(E.MIN_TS(e), k) == E.timespan(e, neg, mag) : Nat}

law timespan_le_max:
  for +e: E.Era
  for neg: Bool
  for +mag: Nat
  exs k: Nat
  {Nat.add(E.timespan(e, neg, mag), k) == E.MAX_TS(e) : Nat}

# Blocks exactly on schedule (W blocks at the era's spacing) leave the timespan unchanged.
law on_schedule:
  for +e: E.Era
  {E.timespan(e, False{}, Nat.mul(E.WINDOW(e), E.SPACING(e))) == E.AWT(e) : Nat}

# ZIP 218's averaging window keeps the launch wall-clock window: 102 x 25 s == 17 x 150 s.
law nu7_window_wallclock:
  {Nat.mul(E.WINDOW(E.Nu7{}), E.SPACING(E.Nu7{})) == Nat.mul(E.WINDOW(E.Pre{}), E.SPACING(E.Pre{})) : Nat}

# Hence the NU7 timespan function is the pre-Blossom one, for every actual timespan.
law nu7_timespan_is_pre:
  for +neg: Bool
  for +mag: Nat
  {E.timespan(E.Nu7{}, neg, mag) == E.timespan(E.Pre{}, neg, mag) : Nat}
