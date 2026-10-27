#!/usr/bin/env python3
"""Generate lib/fr.bend: GF(r) for r = the BLS12-381 scalar field (= the Jubjub base field),
reusing zcash/halo2/lib/gen_field.py's 16-bit-limb Montgomery generator. Its assumptions hold for r:
r = 1 mod 2^16 (Montgomery constant -1), 2-adicity 32, and 5 is a quadratic non-residue."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "zcash", "halo2", "lib"))
import gen_field as g

R_BLS = 0x73EDA753299D7D483339D80809A1D80553BDA402FFFE5BFEFFFFFFFF00000001
assert R_BLS % 65536 == 1 and ((R_BLS - 1) >> 32) & 1 == 1
assert pow(5, (R_BLS - 1) // 2, R_BLS) == R_BLS - 1
g.P = R_BLS                     # module() labels the modulus by looking it up in {P, Q}
src = g.Field("Fr", R_BLS).module()
src = src.replace("p (pallas::Base = vesta::Scalar)", "r (bls12_381::Scalar = jubjub::Base)")
src = src.replace("import ./words.bend as Wd", "import ../../../zcash/halo2/lib/words.bend as Wd")
open(os.path.join(HERE, "lib/fr.bend"), "w").write(src)
print("wrote lib/fr.bend", len(src.splitlines()), "lines")
