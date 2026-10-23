import Base
import ../../lib/fp.bend as Fp
import ../../lib/words.bend as Wd

def main() -> IO(Unit):
  +b = Wd.is_lt(Wd.W{5, 0, 0, 0, 0, 0, 0, 0}, Fp.modulus())
  do IO<Unit>:
    IO.print("x")
