# 1000 chained Vesta variable-base scalar multiplications, one thread (32-bit field limbs).
import Base
import ../../../../zcash/halo2/lib/words.bend as Wd
import ../lib32/vesta.bend as V

def xs(+s: U32) -> U32:
  +a = (s .^. (s << 13n) : U32)
  +b = (a .^. (a >> 17n) : U32)
  (b .^. (b << 5n) : U32)

type St is Data:
  St{p: V.Pt, s: U32}

def step(st: St) -> St:
  St{+p, +s} = st
  +s1 = xs(s)
  +s2 = xs(s1)
  +s3 = xs(s2)
  +s4 = xs(s3)
  +s5 = xs(s4)
  +s6 = xs(s5)
  +s7 = xs(s6)
  +s8 = xs(s7)
  St{V.scalar_mul(p, Wd.W{s1, s2, s3, s4, s5, s6, s7, (s8 .&. 1073741823 : U32)}), s8}

def loop(n: Nat, st: St) -> St:
  match n:
    case 0n:
      st
    case 1n+k:
      loop(k, step(st))

def pt(st: St) -> V.Pt:
  St{p, _} = st
  p

def unwrap(m: Maybe<&2, V.Pt>) -> V.Pt:
  match m:
    case Some{p}:
      p
    case None{}:
      V.identity()

# The Vesta generator (-1, 2) in compressed form.
def gen() -> V.Pt:
  unwrap(V.decompress(Wd.W{0, 2353457953, 160737501, 575052028, 0, 0, 0, 1073741824}))

def main() -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    +r : Wd.W = V.encode(pt(loop(1000n, St{gen(), 2463534242})))
    IO.print(Wd.hex(r))
    t1 : Nat <- IO.now()
    IO.print("1000 scalar mults: " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
