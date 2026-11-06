# micro: cost of allocating (and filling) a 2^16-element Array<V.Aff> (1M words)
import Base
import ../../../../crypto/field3/fq64.bend as B
import ../../../../crypto/field3/lib64/vesta.bend as V

def one(r: Array<V.Aff> & V.Aff) -> U32:
  (a, +p) = r
  V.Aff{+x, _} = p
  B.eq(x, B.zero())

def rep(n: Nat, +acc: U32) -> U32:
  match n:
    case 1n+k:
      a = [V.Aff{B.zero(), B.zero()} : V.Aff^16n]
      rep(k, (acc + one(Array.get(V.Aff, a, (acc .&. 1023 : U32))) : U32))
    case 0n:
      acc

def go(+m: U32) -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    +x : U32 = rep(100n, m)
    t1 : Nat <- IO.now()
    IO.print("100 allocs of 2^16 x 16 words: ms " ++ Nat.show(Nat.sub(t1, t0)) ++ " " ++ U32.show(x))

def main() -> IO(Unit):
  go(1)
