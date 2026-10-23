import Base
import ../vlib.bend as L
import ../toy_v.bend as T

def main() -> IO(Unit):
  +x = T.G_ALL()
  do IO<Unit>:
    IO.print("ok")
