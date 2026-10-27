# Arithmetic helpers that intrinsify.py turns into single hardware instructions.
# Their meaning is the pure Bend definition below; the C patch only changes speed.
import Base

# High 32 bits of the 64-bit product a * b, via four 16x16-bit partial products.
# intrinsify.py matches this exact body (keep the variable names).
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

# High 32 bits of a * b + c + d (the sum always fits 64 bits). Low half is (a * b + c + d : U32).
def mach(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  +qlo = (a * b : U32)
  +qhi = mulhi(a, b)
  +qs1 = (qlo + c : U32)
  +qc1 = (((qlo .&. c) .|. ((qlo .|. c) .&. (qs1 .^. 4294967295))) >> 31n : U32)
  +qs2 = (qs1 + d : U32)
  +qc2 = (((qs1 .&. d) .|. ((qs1 .|. d) .&. (qs2 .^. 4294967295))) >> 31n : U32)
  (qhi + qc1 + qc2 : U32)

# Carry out of x + y + z (0, 1 or 2). Low half is (x + y + z : U32).
def addc(+x: U32, +y: U32, +z: U32) -> U32:
  +ws1 = (x + y : U32)
  +wc1 = (((x .&. y) .|. ((x .|. y) .&. (ws1 .^. 4294967295))) >> 31n : U32)
  +ws2 = (ws1 + z : U32)
  +wc2 = (((ws1 .&. z) .|. ((ws1 .|. z) .&. (ws2 .^. 4294967295))) >> 31n : U32)
  (wc1 + wc2 : U32)

# Borrows out of x - y - z (0, 1 or 2). Low half is (x - y - z : U32).
def subb(+x: U32, +y: U32, +z: U32) -> U32:
  +ud1 = (x - y : U32)
  +ub1 = ((((x .^. 4294967295) .&. y) .|. (((x .^. y) .^. 4294967295) .&. ud1)) >> 31n : U32)
  +ud2 = (ud1 - z : U32)
  +ub2 = ((((ud1 .^. 4294967295) .&. z) .|. (((ud1 .^. z) .^. 4294967295) .&. ud2)) >> 31n : U32)
  (ub1 + ub2 : U32)
