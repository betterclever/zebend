import Base
import ../vlib.bend as L
import ./cut2.bend as T

def main() -> IO(Unit):
  +st = T.verify({L.Proof{Nil{}, Nil{}} : L.Proof})
  do IO<Unit>:
    IO.print(U32.show(L.st_ok(st)))
