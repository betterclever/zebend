# 1e6 chained x = mul(add_nr(x, c), d), one thread.
import Base
import ../../halo2/lib/words.bend as Wd
import ../fq3.bend as Fq

def chain(n: Nat, x: Fq.Fq, +c: Fq.Fq, +d: Fq.Fq) -> Fq.Fq:
  match n:
    case 0n:
      x
    case 1n+k:
      chain(k, Fq.mul(Fq.add_nr(x, c), d), c, d)

def main() -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    +r : Fq.Fq = chain(1000000n, Fq.from_u32(7), Fq.from_u32(5), Fq.from_u32(3))
    IO.print(Wd.hex(Fq.to_words(r)))
    t1 : Nat <- IO.now()
    IO.print("1e6 mul(add_nr): " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
