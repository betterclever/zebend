import Base

def pow2(n: Nat) -> Nat:
  match n:
    case 0n:
      1n
    case 1n+p:
      Nat.double(pow2(p))

law t:
  {65536n == pow2(16n) : Nat}

def t():
  {==}
