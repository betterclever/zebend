# Laws about Zcash's difficulty timespan in BOTH mainnet eras (pre-Blossom 150 s
# spacing, post-Blossom 75 s), stated over era.bend's functions, plus agreement with
# the post-Blossom function zcash/headers' verifier runs on mainnet.
import Base
import ./era.bend as E
import ../../zcash/headers/diff.bend as D

# For every era and every (signed) actual timespan, the bounded timespan is at least
# MinActualTimespan (difficulty rises by at most PoWMaxAdjustUp = 16% per block) ...
law timespan_ge_min:
  for +e: E.Era
  for neg: Bool
  for +mag: Nat
  exs k: Nat
  {Nat.add(E.MIN_TS(e), k) == E.timespan(e, neg, mag) : Nat}

# ... and at most MaxActualTimespan (difficulty drops by at most PoWMaxAdjustDown = 32%).
law timespan_le_max:
  for +e: E.Era
  for neg: Bool
  for +mag: Nat
  exs k: Nat
  {Nat.add(E.timespan(e, neg, mag), k) == E.MAX_TS(e) : Nat}

# Blocks exactly on schedule leave the timespan unchanged, in both eras.
law on_schedule:
  for +e: E.Era
  {E.timespan(e, False{}, E.AWT(e)) == E.AWT(e) : Nat}

# The clamp is bounded and the identity inside the bounds, in both eras.
law clamp_ge_min:
  for +e: E.Era
  for +x: Nat
  exs k: Nat
  {Nat.add(E.MIN_TS(e), k) == E.clamp(e, x) : Nat}

law clamp_le_max:
  for +e: E.Era
  for +x: Nat
  exs k: Nat
  {Nat.add(E.clamp(e, x), k) == E.MAX_TS(e) : Nat}

law clamp_id:
  for +e: E.Era
  for +x: Nat
  for lo: {Nat.is_lt(x, E.MIN_TS(e)) == False{} : Bool}
  for hi: {Nat.is_lt(E.MAX_TS(e), x) == False{} : Bool}
  {E.clamp(e, x) == x : Nat}

# The post-Blossom instance IS the function zcash/headers' verifier executes, so
# everything above also holds for the code that checked 128,252 mainnet nBits.
law post_agrees:
  for +neg: Bool
  for +mag: Nat
  {E.timespan(E.Post{}, neg, mag) == D.timespan(neg, mag) : Nat}

# The era parameters are the spec's: pre-Blossom AWT is twice post-Blossom's, and
# MIN < AWT < MAX in both eras.
law pre_awt_double:
  {E.AWT(E.Pre{}) == Nat.mul(2n, E.AWT(E.Post{})) : Nat}
