import Base

# The boolean-constraint gadget, the most common gate in PLONKish circuits
# (Orchard's included): a witness b is constrained by  b * (1 - b) = 0.
# Elements of Z/p are canonical Nats below p.

def fmul(+p: Nat, x: Nat, +y: Nat) -> Nat:
  Nat.mod(Nat.mul(x, y), p)

# 1 - b in Z/p, for a canonical b < p.
def one_minus(+p: Nat, b: Nat) -> Nat:
  match b:
    case 0n:
      1n
    case 1n+q:
      match q:
        case 0n:
          0n
        case 1n+r:
          Nat.sub(p, 1n+r)

def bool_gate(+p: Nat, +b: Nat) -> Nat:
  fmul(p, b, one_minus(p, b))

# Z/p has no zero divisors. This holds exactly when p is prime, and it is the
# only property of p the soundness argument uses; it is taken as a hypothesis.
def NoZeroDivisors(+p: Nat) -> Type:
  @x: Nat -> @y: Nat -> {fmul(p, x, y) == 0n : Nat} -> Either<&1, &1, {x == 0n : Nat}, {y == 0n : Nat}>
