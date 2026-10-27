import Base

# xorshift32 step: 3 shifts + 3 xors
def xs(+x: U32) -> U32:
  +a = (x .^. (x << 13n) : U32)
  +b = (a .^. (a >> 17n) : U32)
  (b .^. (b << 5n) : U32)

# n sequential steps, summing the states (tail recursion -> loop)
def run(n: Nat, +x: U32, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      run(p, xs(x), (acc + x : U32))

# 2^d independent chunks of n steps each, as a balanced parallel tree
def par(+d: Nat, +seed: U32, +n: Nat) -> U32:
  match d:
    case 0n:
      run(n, (seed + 1 : U32), 0)
    case 1n+p:
      a b = par(p, (seed * 2 : U32), n) par(p, (seed * 2 + 1 : U32), n)
      (a + b : U32)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(par!(6n, 0, 4194304n)))
