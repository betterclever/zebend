# Shared types for the issuance checker.
import Base

type Out is Data:
  Out{value: Nat, script: String}

type Block is Data:
  Block{height: Nat, outs: +List<Out>}

def big(+hi: U32, +lo: U32) -> Nat:
  Nat.add(Nat.mul(U32.to_nat(hi), Nat.mul(65536n, 65536n)), U32.to_nat(lo))
