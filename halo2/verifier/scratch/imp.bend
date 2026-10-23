import Base
import ../../lib/fp.bend as Fp
import ../../lib/words.bend as Wd

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(Wd.hex(Fp.to_words(Fp.add(Fp.from_u32(2), Fp.from_u32(3)))))
