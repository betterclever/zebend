# Differential test: each patched intrinsic against an unpatched copy of its pure Bend
# definition (same math, different local names so intrinsify leaves the copies alone),
# on edge cases and 2^24 pseudo-random inputs each.
import Base
import ../intrinsics.bend as I

def r_mulhi(+x: U32, +y: U32) -> U32:
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

def r_carry(+x: U32, +y: U32) -> U32:
  +s = (x + y : U32)
  (((x .&. y) .|. ((x .|. y) .&. (s .^. 4294967295))) >> 31n : U32)

def r_borrow(+x: U32, +y: U32) -> U32:
  +d = (x - y : U32)
  ((((x .^. 4294967295) .&. y) .|. (((x .^. y) .^. 4294967295) .&. d)) >> 31n : U32)

def r_addc(+x: U32, +y: U32, +z: U32) -> U32:
  (r_carry(x, y) + r_carry((x + y : U32), z) : U32)

def r_subb(+x: U32, +y: U32, +z: U32) -> U32:
  (r_borrow(x, y) + r_borrow((x - y : U32), z) : U32)

def r_mach(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  +lo = (a * b : U32)
  (r_mulhi(a, b) + r_carry(lo, c) + r_carry((lo + c : U32), d) : U32)

def ne(+u: U32, +v: U32) -> U32:
  +x = (u .^. v : U32)
  ((x .|. (0 - x)) >> 31n : U32)

def bad4(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  (ne(I.mulhi(a, b), r_mulhi(a, b)) + ne(I.mach(a, b, c, d), r_mach(a, b, c, d)) + ne(I.addc(a, b, c), r_addc(a, b, c)) + ne(I.subb(a, b, c), r_subb(a, b, c)) : U32)

def xs(+s: U32) -> U32:
  +a = (s .^. (s << 13n) : U32)
  +b = (a .^. (a >> 17n) : U32)
  (b .^. (b << 5n) : U32)

def rand(n: Nat, +s: U32, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      +a = xs(s)
      +b = xs(a)
      +c = xs(b)
      +d = xs(c)
      rand(p, d, (acc + bad4(a, b, c, d) : U32))

def e3(cs: +List<U32>, +a: U32, +b: U32, acc: U32) -> U32:
  match cs:
    case Nil{}:
      acc
    case Con{+c, t}:
      e3(t, a, b, (acc + bad4(a, b, c, (c .^. b : U32)) : U32))

def e2(bs: +List<U32>, +cs: +List<U32>, +a: U32, acc: U32) -> U32:
  match bs:
    case Nil{}:
      acc
    case Con{+b, t}:
      e2(t, cs, a, e3(cs, a, b, acc))

def e1(as: +List<U32>, +bs: +List<U32>, acc: U32) -> U32:
  match as:
    case Nil{}:
      acc
    case Con{+a, t}:
      e1(t, bs, e2(bs, bs, a, acc))

def main() -> IO(Unit):
  +es : +List<U32> = [0, 1, 2, 65535, 65536, 2147483647, 2147483648, 4294967294, 4294967295, 3735928559]
  do IO<Unit>:
    IO.print("edge-case mismatches (10^3 triples x 4 intrinsics): " ++ U32.show(e1(es, es, 0)))
    IO.print("random mismatches (2^24 inputs x 4 intrinsics): " ++ U32.show(rand(16777216n, 2463534242, 0)))
