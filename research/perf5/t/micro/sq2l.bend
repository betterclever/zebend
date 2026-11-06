# micro: 224-squaring chains: one lane at a time vs fq2's interleaved two-lane sqr2 (same values)
import Base
import ../../../../crypto/field3/fq64.bend as B
import ../../lib/fq2.bend as F2

def rep1(n: Nat, +x: B.Fq) -> B.Fq:
  match n:
    case 0n:
      x
    case 1n+k:
      rep1(k, B.add(B.sqr_n(224n, x), B.one()))

def one2(+p: F2.Fq2) -> F2.Fq2:
  F2.Fq2{+a, +b} = p
  F2.Fq2{B.add(a, B.one()), B.add(b, B.one())}

def rep2(n: Nat, +x: F2.Fq2) -> F2.Fq2:
  match n:
    case 0n:
      x
    case 1n+k:
      rep2(k, one2(F2.sqr_n2(224n, x)))

def sq_sep(+p: F2.Fq2) -> F2.Fq2:
  F2.Fq2{+a, +b} = p
  F2.Fq2{B.sqr(a), B.sqr(b)}

def sqn_sep(n: Nat, +x: F2.Fq2) -> F2.Fq2:
  match n:
    case 0n:
      x
    case 1n+k:
      sqn_sep(k, sq_sep(x))

def rep3(n: Nat, +x: F2.Fq2) -> F2.Fq2:
  match n:
    case 0n:
      x
    case 1n+k:
      rep3(k, one2(sqn_sep(224n, x)))

def lanes(+p: F2.Fq2) -> U32:
  F2.Fq2{+a, +b} = p
  (B.eq(a, rep1(500n, B.from_u32(4))) .&. B.eq(b, rep1(500n, B.from_u32(9))) : U32)

def go(+m: U32) -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    +x : B.Fq = rep1(50000n, B.from_u32((m + 3 : U32)))
    +x0 : U32 = B.eq(x, B.one())
    t1x : Nat <- IO.now()
    +t1 : Nat = t1x
    +y0 : U32 = lanes(rep2(25000n, F2.Fq2{B.from_u32((m + 3 : U32)), B.from_u32((m + 4 : U32))}))
    t2x : Nat <- IO.now()
    +t2 : Nat = t2x
    +z0 : U32 = lanes(rep3(25000n, F2.Fq2{B.from_u32((m + 3 : U32)), B.from_u32((m + 4 : U32))}))
    t3 : Nat <- IO.now()
    IO.print("50k chains: one lane ms " ++ Nat.show(Nat.sub(t1, t0)) ++ "  sqr2 ms " ++ Nat.show(Nat.sub(t2, t1)) ++ "  separate calls ms " ++ Nat.show(Nat.sub(t3, t2)) ++ "  lanes exact " ++ U32.show(lanes(rep2(500n, F2.Fq2{B.from_u32(4), B.from_u32(9)}))) ++ " " ++ U32.show((x0 + y0 + z0 : U32)))

def main() -> IO(Unit):
  go(1)
