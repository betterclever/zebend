import Base
import ./gadget.bend as G

# Soundness of the boolean gate: over a field (no zero divisors), the only
# canonical witnesses satisfying b * (1 - b) = 0 are 0 and 1. An under-constrained
# version of this gate is the classic circuit bug: it would let a "bit" take
# another value.
law bool_gate_sound:
  for +p: Nat
  for +b: Nat
  for lt: {Nat.is_lt(b, p) == True{} : Bool}
  for nzd: G.NoZeroDivisors(p)
  for h: {G.bool_gate(p, b) == 0n : Nat}
  Either<&1, &1, {b == 0n : Nat}, {b == 1n : Nat}>
