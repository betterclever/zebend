import Base
import ../../lib/fp.bend as Fp
import ../../lib/vesta.bend as V
import ../../lib/words.bend as Wd

def g(+a0: V.Pt, +a1: V.Pt, +a2: V.Pt, +a3: V.Pt, +a4: V.Pt) -> Fp.Fp:
  +z = Fp.inv(Fp.from_u32(7))
  Fp.add(z, Fp.from_u32(1))

def main() -> IO(Unit):
  +x = g(V.identity(), V.identity(), V.identity(), V.identity(), V.identity())
  do IO<Unit>:
    IO.print(Wd.hex(Fp.to_words(x)))
