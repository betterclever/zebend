# Differential test: the patched mulhi (one hardware multiply) against an unpatched
# copy of the same pure definition, on edge cases and 2^24 pseudo-random pairs.
import Base
import ../intrinsics.bend as I

def ref(+x: U32, +y: U32) -> U32:
  +xl = (x .&. 65535 : U32)
  +xh = (x >> 16n : U32)
  +yl = (y .&. 65535 : U32)
  +yh = (y >> 16n : U32)
  +p0 = (xl * yl : U32)
  +p1 = (xl * yh : U32)
  +p2 = (xh * yl : U32)
  +p3 = (xh * yh : U32)
  +md = ((p0 >> 16n) + (p1 .&. 65535) + (p2 .&. 65535) : U32)
  (p3 + (p1 >> 16n) + (p2 >> 16n) + (md >> 16n) : U32)

# 1 if the two definitions disagree on (x, y), else 0 (branch-free).
def bad(+x: U32, +y: U32) -> U32:
  +v = (I.mulhi(x, y) .^. ref(x, y) : U32)
  ((v .|. (0 - v)) >> 31n : U32)

def row(ys: +List<U32>, +x: U32, acc: U32) -> U32:
  match ys:
    case Nil{}:
      acc
    case Con{+y, t}:
      row(t, x, (acc + bad(x, y) : U32))

def edges(xs: +List<U32>, +ys: +List<U32>, acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{+x, t}:
      edges(t, ys, (acc + row(ys, x, 0) : U32))


# xorshift pairs
def rand(n: Nat, +s: U32, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      +a = (s .^. (s << 13n) : U32)
      +b = (a .^. (a >> 17n) : U32)
      +c = (b .^. (b << 5n) : U32)
      +d = (c .^. (c << 13n) : U32)
      +e = (d .^. (d >> 17n) : U32)
      +f = (e .^. (e << 5n) : U32)
      rand(p, f, (acc + bad(c, f) : U32))

def main() -> IO(Unit):
  +es : +List<U32> = [0, 1, 2, 65535, 65536, 65537, 2147483647, 2147483648, 4294967294, 4294967295, 3735928559, 305419896]
  do IO<Unit>:
    IO.print("edge-case mismatches: " ++ U32.show(edges(es, es, 0)))
    IO.print("random-pair mismatches (2^24 pairs): " ++ U32.show(rand(16777216n, 2463534242, 0)))
