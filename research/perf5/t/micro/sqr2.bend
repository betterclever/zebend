# micro: one 224-squaring chain vs two independent chains interleaved in one function
import Base
import ../../../../crypto/field3/fq64.bend as B

type P2 is Data:
  P2{x: B.Fq, y: B.Fq}

def sq2_n(n: Nat, +x: B.Fq, +y: B.Fq) -> P2:
  match n:
    case 0n:
      P2{x, y}
    case 1n+k:
      sq2_n(k, B.sqr(x), B.sqr(y))

def rep1(n: Nat, +x: B.Fq) -> B.Fq:
  match n:
    case 0n:
      x
    case 1n+k:
      rep1(k, B.add(B.sqr_n(224n, x), B.one()))

def rep2(n: Nat, p: P2) -> B.Fq:
  match n p:
    case 0n P2{+a, +b}:
      B.add(a, b)
    case 1n+k P2{+a, +b}:
      rep2(k, sq2_n(224n, B.add(a, B.one()), B.add(b, B.one())))

def go(+m: U32) -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    +x : B.Fq = rep1(50000n, B.from_u32((m + 3 : U32)))
    t1x : Nat <- IO.now()
    +t1 : Nat = t1x
    +y : B.Fq = rep2(25000n, P2{B.from_u32((m + 3 : U32)), B.from_u32((m + 4 : U32))})
    t2 : Nat <- IO.now()
    IO.print("50k chains: one at a time ms " ++ Nat.show(Nat.sub(t1, t0)) ++ "  two interleaved ms " ++ Nat.show(Nat.sub(t2, t1)) ++ " " ++ U32.show(B.eq(x, y)))

def main() -> IO(Unit):
  go(1)
