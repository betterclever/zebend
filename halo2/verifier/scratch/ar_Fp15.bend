import Base
import ../../lib/fp.bend as Fp
import ../../lib/vesta.bend as V
import ../../lib/words.bend as Wd

def g(+a0: Fp.Fp, +a1: Fp.Fp, +a2: Fp.Fp, +a3: Fp.Fp, +a4: Fp.Fp, +a5: Fp.Fp, +a6: Fp.Fp, +a7: Fp.Fp, +a8: Fp.Fp, +a9: Fp.Fp, +a10: Fp.Fp, +a11: Fp.Fp, +a12: Fp.Fp, +a13: Fp.Fp, +a14: Fp.Fp) -> Fp.Fp:
  +z = Fp.inv(Fp.from_u32(7))
  Fp.add(z, Fp.add(a0, Fp.from_u32(1)))

def main() -> IO(Unit):
  +x = g(Fp.from_u32(3), Fp.from_u32(3), Fp.from_u32(3), Fp.from_u32(3), Fp.from_u32(3), Fp.from_u32(3), Fp.from_u32(3), Fp.from_u32(3), Fp.from_u32(3), Fp.from_u32(3), Fp.from_u32(3), Fp.from_u32(3), Fp.from_u32(3), Fp.from_u32(3), Fp.from_u32(3))
  do IO<Unit>:
    IO.print(Wd.hex(Fp.to_words(x)))
