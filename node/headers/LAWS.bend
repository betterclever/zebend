# Laws about Zcash's difficulty adjustment, stated over the exact functions the
# verifier (main.bend) executes. Open claims here; proven in PROOF.bend.
import Base
import ./diff.bend as D

# Whatever the block timestamps say, the bounded actual timespan is at least
# MinActualTimespan (1071 s = 84% of 1275 s): difficulty can drop by at most
# what that allows per block (PoWMaxAdjustUp = 16%).
law timespan_ge_min:
  for neg: Bool
  for +mag: Nat
  exs k: Nat
  {Nat.add(D.MIN_TS(), k) == D.timespan(neg, mag) : Nat}

# ... and at most MaxActualTimespan (1683 s = 132% of 1275 s): difficulty can rise
# by at most what that allows per block (PoWMaxAdjustDown = 32%).
law timespan_le_max:
  for neg: Bool
  for +mag: Nat
  exs k: Nat
  {Nat.add(D.timespan(neg, mag), k) == D.MAX_TS() : Nat}

# Blocks arriving exactly on schedule (75 s apart) leave the timespan unchanged,
# so the target is only re-averaged, never scaled.
law on_schedule:
  {D.timespan(False{}, D.AWT()) == D.AWT() : Nat}

# The clamp itself: for every input, MIN <= clamp(x) <= MAX.
law clamp_ge_min:
  for +x: Nat
  exs k: Nat
  {Nat.add(D.MIN_TS(), k) == D.clamp(x) : Nat}

law clamp_le_max:
  for +x: Nat
  exs k: Nat
  {Nat.add(D.clamp(x), k) == D.MAX_TS() : Nat}

# Inside the bounds the clamp is the identity: real timespans pass through untouched.
law clamp_id:
  for +x: Nat
  for lo: {Nat.is_lt(x, D.MIN_TS()) == False{} : Bool}
  for hi: {Nat.is_lt(D.MAX_TS(), x) == False{} : Bool}
  {D.clamp(x) == x : Nat}
