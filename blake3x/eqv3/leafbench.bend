# 1e5 chained Equihash leaf compressions (h <- b2_leaf(h, ...)), one thread.
import Base
import ./hashes.bend as H

def chain(n: Nat, h: H.BH, +x: U32) -> H.BH:
  match n:
    case 0n:
      h
    case 1n+k:
      chain(k, H.b2_leaf(h, 1, 2, 3, x), (x + 1 : U32))

def show(h: H.BH) -> String:
  H.BH{a, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} = h
  U32.show(a)

def main() -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    +r : H.BH = chain(100000n, H.eh_h0(), 0)
    IO.print(show(r))
    t1 : Nat <- IO.now()
    IO.print("1e5 b2_leaf: " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
