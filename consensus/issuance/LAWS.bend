# Laws about Zcash's issuance schedule, stated about the functions the coinbase checker runs
# (issuance.bend). Le(a, b) is "a <= b", witnessed by the gap (proofs/prims/natlib.bend).
import Base
import ../../proofs/prims/natlib.bend as L
import ./issuance.bend as I

# One more halving is the previous subsidy halved: S(k+1, m) == floor(S(k, m) / 2).
law halve_succ:
  for +k: Nat
  for +m: Nat
  {I.halve(1n+k, m) == Nat.div(I.halve(k, m), 2n) : Nat}

# The subsidy never increases from one halving era to the next: S(k+1, m) <= S(k, m).
law halve_step_le:
  for +k: Nat
  for +m: Nat
  L.Le(I.halve(1n+k, m), I.halve(k, m))

# No era's subsidy exceeds the starting subsidy: S(k, m) <= m.
law halve_le:
  for +k: Nat
  for +m: Nat
  L.Le(I.halve(k, m), m)

# Geometric bound: the sum of the subsidies of any number of eras is at most twice the
# first: total(K, m) <= 2m, for every K and m.
law total_le:
  for +K: Nat
  for +m: Nat
  L.Le(I.total(K, m), Nat.add(m, m))

# Supply cap, era-weighted: with n blocks per halving era, the issuance of any number of
# eras is at most n * 2m. For Zcash's post-Blossom schedule (n = 1,680,000 blocks,
# m = 625,000,000 zat) the bound is 2.1e15 zat = 21,000,000 ZEC.
law cap:
  for +n: Nat
  for +K: Nat
  for +m: Nat
  L.Le(Nat.mul(n, I.total(K, m)), Nat.mul(n, Nat.add(m, m)))
