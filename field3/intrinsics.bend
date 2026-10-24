# Carry helpers for the generated fields. With the U32.add_hi / U32.mac_hi primitives
# (local Bend fork, branch u32-prims) every carry is one instruction; the
# compare-based forms of fast/pure remain only for the --no-prims build.
import Base

def mulhi(+a: U32, +b: U32) -> U32:
  U32.mul_hi(a, b)

# High 32 bits of a * b + c + d. Low half is (a * b + c + d : U32).
def mach(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  U32.mac_hi(a, b, c, d)

# Carry out of x + y + z (0, 1 or 2). Low half is (x + y + z : U32).
def addc(+x: U32, +y: U32, +z: U32) -> U32:
  (U32.add_hi(x, y) + U32.add_hi((x + y : U32), z) : U32)

# Borrows out of x - y - z (0, 1 or 2). Low half is (x - y - z : U32).
def subb(+x: U32, +y: U32, +z: U32) -> U32:
  +ud1 = (x - y : U32)
  (Bool.to_u32(U32.is_lt(x, y)) + Bool.to_u32(U32.is_lt(ud1, z)) : U32)
