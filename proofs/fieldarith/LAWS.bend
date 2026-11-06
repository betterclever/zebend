import Base
import ../../zcash/halo2/lib/fp.bend as Fp
import ../prims/natlib.bend as L
import ../prims/words.bend as Ws
import ../field/wordadd.bend as W
import ./bits.bend as Bt
import ./defs.bend as D

# Laws about the Pasta field arithmetic of zcash/halo2/lib/fp.bend (imported, not
# copied): elements are 16 limbs of 16 bits held in U32s. D.val(K, f) is the limbs'
# value in base K; D.Canon(f) says every limb is below 2^16 and the value is below the
# modulus. The modulus is written as the code holds it (the limbs Fp.add subtracts);
# gen_add.py checks that these limbs spell Pallas' p,
# 0x40000000000000000000000000000000224698fc094cf91b992d30ed00000001.

# --- 1. masking and shifting, on values (for every U32 x and every k) ----------

# The low k bits of x are x mod 2^k (Bt.lowmask(32n, k) is the word with the low k bits set).
law u32_mask_mod:
  for +x: U32
  for +k: Nat
  {U32.to_nat(U32.and(x, U32{Bt.lowmask(32n, k)})) == Nat.mod(U32.to_nat(x), W.pow2(k)) : Nat}

# x >> k (U32.shrn) is x div 2^k.
law u32_shr_div:
  for +x: U32
  for +k: Nat
  {U32.to_nat(U32.shrn(x, k)) == Nat.div(U32.to_nat(x), W.pow2(k)) : Nat}

# The 16-bit instance the field code uses: x .&. 65535 and x >> 16n.
law mask16_mod:
  for +x: U32
  {U32.to_nat(U32.and(x, 65535)) == Nat.mod(U32.to_nat(x), 65536n) : Nat}

law shr16_div:
  for +x: U32
  {U32.to_nat(U32.shrn(x, 16n)) == Nat.div(U32.to_nat(x), 65536n) : Nat}

# --- 2. U32 addition and subtraction that do not wrap are exact ----------------

law add_exact:
  for +a: U32
  for +b: U32
  for +l: L.Le(Nat.add(U32.to_nat(a), U32.to_nat(b)), Ws.mask(32n))
  {U32.to_nat(U32.add(a, b)) == Nat.add(U32.to_nat(a), U32.to_nat(b)) : Nat}

# Non-vacuity: the hypothesis holds (for a = b = 0).
law add_exact_sat:
  L.Le(Nat.add(U32.to_nat(0), U32.to_nat(0)), Ws.mask(32n))

law sub_exact:
  for +a: U32
  for +b: U32
  for +l: L.Le(U32.to_nat(b), U32.to_nat(a))
  {Nat.add(U32.to_nat(U32.sub(a, b)), U32.to_nat(b)) == U32.to_nat(a) : Nat}

# Non-vacuity: the hypothesis holds for a = b = x, every x.
law sub_exact_sat:
  for +x: U32
  L.Le(U32.to_nat(x), U32.to_nat(x))

# --- 3. Fp.add is addition mod p ---------------------------------------------------

# For canonical a and b, the limbs Fp.add returns hold (a + b) mod p.
law add_ok:
  for +a: Fp.Fp
  for +b: Fp.Fp
  for +ca: D.Canon(a)
  for +cb: D.Canon(b)
  {D.val(65536n, Fp.add(a, b)) == Nat.mod(Nat.add(D.val(65536n, a), D.val(65536n, b)), D.val(65536n, Fp.Fp{1, 0, 12525, 39213, 63771, 2380, 39164, 8774, 0, 0, 0, 0, 0, 0, 0, 16384})) : Nat}

# ... and that value is below p.
law add_lt:
  for +a: Fp.Fp
  for +b: Fp.Fp
  for +ca: D.Canon(a)
  for +cb: D.Canon(b)
  L.Le(1n+D.val(65536n, Fp.add(a, b)), D.val(65536n, Fp.Fp{1, 0, 12525, 39213, 63771, 2380, 39164, 8774, 0, 0, 0, 0, 0, 0, 0, 16384}))

# --- 4. Fp.sub is subtraction mod p ----------------------------------------------

# For canonical a and b, the limbs Fp.sub returns hold (a + (p - b)) mod p.
law sub_ok:
  for +a: Fp.Fp
  for +b: Fp.Fp
  for +ca: D.Canon(a)
  for +cb: D.Canon(b)
  {D.val(65536n, Fp.sub(a, b)) == Nat.mod(Nat.add(D.val(65536n, a), Nat.sub(D.val(65536n, Fp.Fp{1, 0, 12525, 39213, 63771, 2380, 39164, 8774, 0, 0, 0, 0, 0, 0, 0, 16384}), D.val(65536n, b))), D.val(65536n, Fp.Fp{1, 0, 12525, 39213, 63771, 2380, 39164, 8774, 0, 0, 0, 0, 0, 0, 0, 16384})) : Nat}

# ... and that value is below p.
law sub_lt:
  for +a: Fp.Fp
  for +b: Fp.Fp
  for +ca: D.Canon(a)
  for +cb: D.Canon(b)
  L.Le(1n+D.val(65536n, Fp.sub(a, b)), D.val(65536n, Fp.Fp{1, 0, 12525, 39213, 63771, 2380, 39164, 8774, 0, 0, 0, 0, 0, 0, 0, 16384}))

# Non-vacuity of add_ok, add_lt, sub_ok, sub_lt: zero is canonical.
law canon_zero:
  D.Canon(Fp.Fp{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0})
