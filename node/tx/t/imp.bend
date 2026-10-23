import Base
import ../../../halo2/lib/pallas.bend as Pa
import ../../../halo2/lib/words.bend as Wd

def main() -> String:
  Wd.hex(Pa.encode(Pa.identity()))
