import Base
import ./intrinsics.bend as I

def mac(+a: U32, +b: U32, +c: U32, +d: U32) -> U32 & U32:
  +mlo = (a * b : U32)
  +mhi = I.mulhi(a, b)
  +ms1 = (mlo + c : U32)
  +mc1 = ((mlo .&. c) .|. ((mlo .|. c) .&. (ms1 .^. 4294967295)) >> 31n : U32)
  +ms2 = (ms1 + d : U32)
  +mc2 = ((ms1 .&. d) .|. ((ms1 .|. d) .&. (ms2 .^. 4294967295)) >> 31n : U32)
  (ms2, (mhi + mc1 + mc2 : U32))

def fst(p: U32 & U32) -> U32:
  (a, _) = p
  a

def loop(n: Nat, +x: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      loop(p, (x * 2654435761 + 1 : U32), (acc + fst(mac(x, (x .^. 7 : U32), acc, 3)) : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(loop(1000n, 12345, 0)))
