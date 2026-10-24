import Base

def mulhi(+a: U32, +b: U32) -> U32:
  +al = (a .&. 65535 : U32)
  +ah = (a >> 16n : U32)
  +bl = (b .&. 65535 : U32)
  +bh = (b >> 16n : U32)
  +ll = (al * bl : U32)
  +lh = (al * bh : U32)
  +hl = (ah * bl : U32)
  +hh = (ah * bh : U32)
  +mid = ((ll >> 16n) + (lh .&. 65535) + (hl .&. 65535) : U32)
  (hh + (lh >> 16n) + (hl >> 16n) + (mid >> 16n) : U32)

def loop(n: Nat, +x: U32, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      loop(p, (x * 2654435761 + 1 : U32), (acc + mulhi(x, (x .^. 2246822519 : U32)) : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    IO.print(U32.show(loop(100000000n, 12345, 0)))
    t1 : Nat <- IO.now()
    IO.print("ms " ++ Nat.show(Nat.sub(t1, t0)))
