# 1e4 square roots (x += i; count squares), field3 sqrt vs decomp table sqrt, Fq and Fp. One thread.
import Base
import ../../field3/fq64.bend as Fq
import ../../field3/fp64.bend as Fp
import ../fq_sqrt.bend as QS
import ../fp_sqrt.bend as PS

def q_some(m: Maybe<&2, Fq.Fq>) -> U32:
  match m:
    case Some{_}:
      1
    case None{}:
      0

def p_some(m: Maybe<&2, Fp.Fp>) -> U32:
  match m:
    case Some{_}:
      1
    case None{}:
      0

def q_old(n: Nat, +i: U32, +x: Fq.Fq, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      +y = Fq.add(x, Fq.from_u32(i))
      q_old(k, (i + 1 : U32), y, (acc + q_some(Fq.sqrt(y)) : U32))

def q_new(n: Nat, +i: U32, +x: Fq.Fq, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      +y = Fq.add(x, Fq.from_u32(i))
      q_new(k, (i + 1 : U32), y, (acc + q_some(QS.sqrt(y)) : U32))

def p_old(n: Nat, +i: U32, +x: Fp.Fp, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      +y = Fp.add(x, Fp.from_u32(i))
      p_old(k, (i + 1 : U32), y, (acc + p_some(Fp.sqrt(y)) : U32))

def p_new(n: Nat, +i: U32, +x: Fp.Fp, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      +y = Fp.add(x, Fp.from_u32(i))
      p_new(k, (i + 1 : U32), y, (acc + p_some(PS.sqrt(y)) : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    +a : U32 = q_old(10000n, 0, Fq.from_u32(7), 0)
    t1 : Nat <- IO.now()
    IO.print("Fq field3 sqrt 1e4: " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms, squares " ++ U32.show(a))
    t2 : Nat <- IO.now()
    +b : U32 = q_new(10000n, 0, Fq.from_u32(7), 0)
    t3 : Nat <- IO.now()
    IO.print("Fq table sqrt 1e4: " ++ Nat.show(Nat.sub(t3, t2)) ++ " ms, squares " ++ U32.show(b))
    t4 : Nat <- IO.now()
    +c : U32 = p_old(10000n, 0, Fp.from_u32(7), 0)
    t5 : Nat <- IO.now()
    IO.print("Fp field3 sqrt 1e4: " ++ Nat.show(Nat.sub(t5, t4)) ++ " ms, squares " ++ U32.show(c))
    t6 : Nat <- IO.now()
    +d : U32 = p_new(10000n, 0, Fp.from_u32(7), 0)
    t7 : Nat <- IO.now()
    IO.print("Fp table sqrt 1e4: " ++ Nat.show(Nat.sub(t7, t6)) ++ " ms, squares " ++ U32.show(d))
