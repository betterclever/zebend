import Base
import ../../halo2/lib/words.bend as Wd
import ../../halo2/lib/fp.bend as Fp
import ./wordadd.bend as WA

# Laws about the arithmetic the Pasta field (halo2/lib/fp.bend) is built from.

# The limb layer is lossless: splitting any 256-bit value (8 LE words) into the
# field's 16 limbs of 16 bits (Fp.raw) and reassembling them (Fp.unraw) returns
# the same value, for every input.
law raw_roundtrip:
  for w: Wd.W
  {Fp.unraw(Fp.raw(w)) == w : Wd.W}

# Bend's Word addition (every U32 `+`) is binary addition with carry, at any
# width n: value of the sum + carry-out * 2^n == a + b + carry-in.
law adc_ok:
  for +n: Nat
  for +a: Word(n)
  for +b: Word(n)
  for +c: Bool
  {Nat.add(Word.to_nat(n, Word.adc(n, a, b, False{}, c)), WA.kt(n, WA.wcarry(n, a, b, c))) == Nat.add(Nat.add(Word.to_nat(n, a), Word.to_nat(n, b)), WA.bv(c)) : Nat}

# The same for U32: x + y as computed, plus the dropped carry * 2^32, is the true
# sum; so a U32 `+` whose true sum is below 2^32 is exact.
law u32_add_ok:
  for +x: U32
  for +y: U32
  {Nat.add(U32.to_nat(U32.add(x, y)), WA.kt(32n, WA.u32carry(x, y))) == Nat.add(U32.to_nat(x), U32.to_nat(y)) : Nat}
