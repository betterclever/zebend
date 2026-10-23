import Base
import ../../lib/fp.bend as Fp
import ../../lib/words.bend as Wd

def main() -> IO(Unit):
  +x = Fp.from_words(Wd.W{5, 0, 0, 0, 0, 0, 0, 0})
  do IO<Unit>:
    IO.print(Wd.hex(Fp.to_words(x)))
