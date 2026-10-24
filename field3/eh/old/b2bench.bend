# 1e5 chained BLAKE2b compressions (h <- F(h, m, t, 0)), one thread.
import Base
import ./hashes.bend as H

def msg() -> H.BM:
  H.BM{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32}

def chain(n: Nat, h: H.BH, +m: H.BM, +t: U32) -> H.BH:
  match n:
    case 0n:
      h
    case 1n+k:
      chain(k, H.b2_compress(h, m, t, 0), m, (t + 128 : U32))

def show(h: H.BH) -> String:
  H.BH{a, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} = h
  U32.show(a)

def main() -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    +r : H.BH = chain(100000n, H.eh_h0(), msg(), 128)
    IO.print(show(r))
    t1 : Nat <- IO.now()
    IO.print("1e5 b2_compress: " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
