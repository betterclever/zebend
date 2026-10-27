import Base
import ../../zcash/halo2/lib/words.bend as Wd
import ../../zcash/halo2/lib/fp.bend as Fp
import ./limbs.bend as Lb
import ./wordadd.bend as WA
import ./LAWS.bend as Laws

def Laws.raw_roundtrip(w):
  Lb.raw_roundtrip(w)

def Laws.adc_ok(n, a, b, c):
  WA.adc_ok(n, a, b, c)

def Laws.u32_add_ok(x, y):
  WA.u32_add_ok(x, y)
