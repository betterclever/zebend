import Base

# The fork's U32 arithmetic and its widening primitives, against Nat arithmetic.
# K = 65536 * 65536 = 2^32, written as the fork writes it.
#
# Laws 1-3 are about U32.mul / U32.add / U32.from_nat themselves.
# Laws 4-6 are about the defining expressions of the fork's widening primitives:
# by definition (bend-fork bend2/base.bend, branch u64-rot)
#   U32.mul_hi(a, b)       = U32.from_nat(Nat.div(a*b, K))
#   U32.add_hi(a, b)       = U32.from_nat(Nat.div(a+b, K))
#   U32.mac_hi(a, b, c, d) = U32.from_nat(Nat.div(a*b+c+d, K))
# and each law shows that this high word together with the 32-bit low word
# (U32.mul, U32.add, (a*b + c + d : U32)) is exactly the double-width result:
# nothing is lost, the high word never wraps. The laws spell the definitions out
# instead of naming U32.mul_hi etc., because the checker cannot unfold those names:
# comparing an unfolded body with a copy of it expands the closed term
# Nat.mul(65536n, 65536n) to 2^32 in unary (see proofs/README.md).
#
# A = U32.to_nat(a), etc.

# 1. U32.mul is the product mod 2^32 (Bend's shift-and-add Word.mul, proven for every width).
law u32_mul_lo:
  for +a: U32
  for +b: U32
  {U32.to_nat(U32.mul(a, b)) == Nat.mod(Nat.mul(U32.to_nat(a), U32.to_nat(b)), Nat.mul(65536n, 65536n)) : Nat}

# 2. U32.add is the sum mod 2^32.
law u32_add_lo:
  for +a: U32
  for +b: U32
  {U32.to_nat(U32.add(a, b)) == Nat.mod(Nat.add(U32.to_nat(a), U32.to_nat(b)), Nat.mul(65536n, 65536n)) : Nat}

# 3. U32.from_nat reduces mod 2^32.
law u32_from_nat:
  for +y: Nat
  {U32.to_nat(U32.from_nat(y)) == Nat.mod(y, Nat.mul(65536n, 65536n)) : Nat}

# 4. mul_hi: a * b == U32.mul(a, b) + mul_hi(a, b) * 2^32.
law mul_hi_split:
  for +a: U32
  for +b: U32
  {Nat.add(U32.to_nat(U32.mul(a, b)), Nat.mul(U32.to_nat(U32.from_nat(Nat.div(Nat.mul(U32.to_nat(a), U32.to_nat(b)), Nat.mul(65536n, 65536n)))), Nat.mul(65536n, 65536n))) == Nat.mul(U32.to_nat(a), U32.to_nat(b)) : Nat}

# 5. add_hi: a + b == U32.add(a, b) + add_hi(a, b) * 2^32.
law add_hi_split:
  for +a: U32
  for +b: U32
  {Nat.add(U32.to_nat(U32.add(a, b)), Nat.mul(U32.to_nat(U32.from_nat(Nat.div(Nat.add(U32.to_nat(a), U32.to_nat(b)), Nat.mul(65536n, 65536n)))), Nat.mul(65536n, 65536n))) == Nat.add(U32.to_nat(a), U32.to_nat(b)) : Nat}

# 6. mac_hi: a * b + c + d == (a * b + c + d : U32) + mac_hi(a, b, c, d) * 2^32.
law mac_hi_split:
  for +a: U32
  for +b: U32
  for +c: U32
  for +d: U32
  {Nat.add(U32.to_nat(U32.add(U32.add(U32.mul(a, b), c), d)), Nat.mul(U32.to_nat(U32.from_nat(Nat.div(Nat.add(Nat.add(Nat.mul(U32.to_nat(a), U32.to_nat(b)), U32.to_nat(c)), U32.to_nat(d)), Nat.mul(65536n, 65536n)))), Nat.mul(65536n, 65536n))) == Nat.add(Nat.add(Nat.mul(U32.to_nat(a), U32.to_nat(b)), U32.to_nat(c)), U32.to_nat(d)) : Nat}

# 7. lane64: the two 32-bit lanes of a 64-bit value are its low and high words.
# U32.lane64(k, x) = U32.from_nat(Nat.div(Nat.mod(x, 2^64), 2^(32 * U32.to_nat(k)))) by
# definition; U32.add64(k, ...) is lane64(k, a + b) and U32.rotr64(k, ...) is lane64(k, r)
# for the rotation formula r, so for every x this says the lanes the fork returns
# recombine to x mod 2^64: lane 0 + lane 1 * 2^32 == x mod 2^64.
law lane64_split:
  for +x: Nat
  {Nat.add(U32.to_nat(U32.from_nat(Nat.div(Nat.mod(x, Nat.pow(2n, 64n)), Nat.pow(2n, Nat.mul(32n, U32.to_nat(0)))))), Nat.mul(U32.to_nat(U32.from_nat(Nat.div(Nat.mod(x, Nat.pow(2n, 64n)), Nat.pow(2n, Nat.mul(32n, U32.to_nat(1)))))), Nat.mul(65536n, 65536n))) == Nat.mod(x, Nat.pow(2n, 64n)) : Nat}
