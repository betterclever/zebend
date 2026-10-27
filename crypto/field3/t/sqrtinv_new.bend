# 1e4 square roots (x += i; count squares) and 1e4 chained inversions (x = inv(x) + i), one thread.
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ../fq3.bend as Fq

def is_some(m: Maybe<&2, Fq.Fq>) -> U32:
  match m:
    case Some{_}:
      1
    case None{}:
      0

def sq(n: Nat, +i: U32, +x: Fq.Fq, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      +y = Fq.add(x, Fq.from_u32(i))
      sq(k, (i + 1 : U32), y, (acc + is_some(Fq.sqrt(y)) : U32))

def iv(n: Nat, +i: U32, x: Fq.Fq) -> Fq.Fq:
  match n:
    case 0n:
      x
    case 1n+k:
      iv(k, (i + 1 : U32), Fq.add(Fq.inv(x), Fq.from_u32(i)))

def main() -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    +h : U32 = sq(10000n, 0, Fq.from_u32(7), 0)
    IO.print("squares " ++ U32.show(h))
    t1 : Nat <- IO.now()
    IO.print("1e4 Fq.sqrt: " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
    t1b : Nat <- IO.now()
    +r : Fq.Fq = iv(10000n, 1, Fq.from_u32(7))
    IO.print(Wd.hex(Fq.to_words(r)))
    t2 : Nat <- IO.now()
    IO.print("1e4 Fq.inv: " ++ Nat.show(Nat.sub(t2, t1b)) ++ " ms")
