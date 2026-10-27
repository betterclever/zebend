# The same helpers as ../../intrinsics.bend, now pure Bend with no C post-processing:
# mulhi is Bend's own U32.mul_hi primitive (one widening multiply in every backend),
# and carries are unsigned compares (a sum wrapped iff it is below an addend).
import Base

def mulhi(+a: U32, +b: U32) -> U32:
  U32.mul_hi(a, b)

# High 32 bits of a * b + c + d (the sum always fits 64 bits). Low half is (a * b + c + d : U32).
def mach(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  +qs1 = ((a * b : U32) + c : U32)
  +qs2 = (qs1 + d : U32)
  (U32.mul_hi(a, b) + Bool.to_u32(U32.is_lt(qs1, c)) + Bool.to_u32(U32.is_lt(qs2, d)) : U32)

# Carry out of x + y + z (0, 1 or 2). Low half is (x + y + z : U32).
def addc(+x: U32, +y: U32, +z: U32) -> U32:
  +ws1 = (x + y : U32)
  +ws2 = (ws1 + z : U32)
  (Bool.to_u32(U32.is_lt(ws1, x)) + Bool.to_u32(U32.is_lt(ws2, z)) : U32)

# Borrows out of x - y - z (0, 1 or 2). Low half is (x - y - z : U32).
def subb(+x: U32, +y: U32, +z: U32) -> U32:
  +ud1 = (x - y : U32)
  (Bool.to_u32(U32.is_lt(x, y)) + Bool.to_u32(U32.is_lt(ud1, z)) : U32)
