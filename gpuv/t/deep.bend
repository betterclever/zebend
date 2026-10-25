# GPU lane stack probe: every lane builds a list of length L with NON-tail recursion
# (mk(n) = n <> mk(n-1)) and sums it. Usage: ./deep <L> <depth>
import Base

def mk(+n: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      U32.from_nat(k) <> mk(k)

def sum(xs: +List<U32>, acc: U32) -> U32:
  match xs:
    case Con{h, t}:
      sum(t, (acc + h : U32))
    case Nil{}:
      acc

def lanes(+d: Nat, +l: Nat) -> U32:
  match d:
    case 0n:
      sum(mk(l), 0)
    case 1n+j:
      a b = lanes(j, l) lanes(j, l)
      (a + b : U32)

def num(s: String) -> U32:
  Maybe.default(&2, U32, U32.read(s), 0)

def go(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{l, Con{d, _}}}:
      IO.print(U32.show(lanes!(U32.to_nat(num(d)), U32.to_nat(num(l)))))
    case _:
      IO.print("usage: deep L depth")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(args)
