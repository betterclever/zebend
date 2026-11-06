# micro: chains of fq64 mul / sub / sqr
import Base
import ../../../../crypto/field3/fq64.bend as B

def muls(n: Nat, +a: B.Fq, +b: B.Fq) -> B.Fq:
  match n:
    case 1n+k:
      muls(k, B.mul(a, b), a)
    case 0n:
      a

def subs(n: Nat, +a: B.Fq, +b: B.Fq) -> B.Fq:
  match n:
    case 1n+k:
      subs(k, B.sub(a, b), a)
    case 0n:
      a

def sqrs(n: Nat, +a: B.Fq) -> B.Fq:
  match n:
    case 1n+k:
      sqrs(k, B.sqr(a))
    case 0n:
      a

def go(+m: U32) -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    +x : B.Fq = muls(10000000n, B.from_u32((m + 3 : U32)), B.from_u32(7))
    +x0 : U32 = B.eq(x, B.one())
    t1x : Nat <- IO.now()
    +t1 : Nat = t1x
    +y : B.Fq = subs(10000000n, B.from_u32((m + 3 : U32)), B.from_u32(7))
    +y0 : U32 = B.eq(y, B.one())
    t2x : Nat <- IO.now()
    +t2 : Nat = t2x
    +z : B.Fq = sqrs(10000000n, B.from_u32((m + 3 : U32)))
    +z0 : U32 = B.eq(z, B.one())
    t3 : Nat <- IO.now()
    IO.print("10M mul ms " ++ Nat.show(Nat.sub(t1, t0)) ++ " sub ms " ++ Nat.show(Nat.sub(t2, t1)) ++ " sqr ms " ++ Nat.show(Nat.sub(t3, t2)) ++ " " ++ U32.show((x0 + y0 + z0 : U32)))

def main() -> IO(Unit):
  go(1)
