import Base
import ./bytes.bend as B
import ./msg.bend as M

def main() -> IO(Unit):
  IO.print(B.hex(M.frame("version", M.version_payload(170190, 1761264000, 12345, "34.80.219.125", 0))))
