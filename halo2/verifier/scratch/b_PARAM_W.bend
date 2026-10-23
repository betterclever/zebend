import Base
import ../vlib.bend as L
import ../toy_v.bend as T

def main() -> IO(Unit):
  +x = T.PARAM_W()
  do IO<Unit>:
    IO.print("ok")
