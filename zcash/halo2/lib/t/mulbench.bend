# Field-mul throughput: N chained Fq multiplications on one thread.
import Base
import ../words.bend as Wd
import ../fq.bend as Fq

def chain(n: Nat, x: Fq.Fq, +y: Fq.Fq) -> Fq.Fq:
  match n:
    case 0n:
      x
    case 1n+k:
      chain(k, Fq.mul(x, y), y)

def main() -> IO(Unit):
  +y = Fq.from_u32(3)
  do IO<Unit>:
    t0 : Nat <- IO.now()
    +r : Fq.Fq = chain(1000000n, Fq.from_u32(7), y)
    IO.print(Wd.hex(Fq.to_words(r)))
    t1 : Nat <- IO.now()
    IO.print("1e6 Fq.mul: " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
