# micro: 224-squaring chains, Nat-recursive sqr_n vs blocks of 8 inlined squarings
import Base
import ../../../../crypto/field3/fq64.bend as B

def msq(+x: B.Fq) -> B.Fq:
  B.mul(x, x)

def sqr8(+x: B.Fq) -> B.Fq:
  msq(x)

def sqr8_n(n: Nat, +x: B.Fq) -> B.Fq:
  match n:
    case 0n:
      x
    case 1n+k:
      sqr8_n(k, sqr8(x))

def rep_a(n: Nat, +x: B.Fq) -> B.Fq:
  match n:
    case 0n:
      x
    case 1n+k:
      rep_a(k, B.add(B.sqr_n(224n, x), B.one()))

def rep_b(n: Nat, +x: B.Fq) -> B.Fq:
  match n:
    case 0n:
      x
    case 1n+k:
      rep_b(k, B.add(sqr8_n(224n, x), B.one()))

def go(+m: U32) -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    +x : B.Fq = rep_a(50000n, B.from_u32((m + 3 : U32)))
    t1x : Nat <- IO.now()
    +t1 : Nat = t1x
    +y : B.Fq = rep_b(50000n, B.from_u32((m + 3 : U32)))
    t2 : Nat <- IO.now()
    IO.print("50k x 224 sqr: nat-rec ms " ++ Nat.show(Nat.sub(t1, t0)) ++ "  mul(x,x) ms " ++ Nat.show(Nat.sub(t2, t1)) ++ " same " ++ U32.show(B.eq(x, y)))

def main() -> IO(Unit):
  go(1)
