import Base
import ../vlib.bend as L
import ../../lib/words.bend as Wd

def main() -> IO(Unit):
  +r = L.rd_scalars(L.st_new({L.Proof{Wd.W{5, 0, 0, 0, 0, 0, 0, 0} <> Nil{}, Nil{}} : L.Proof}), 1n)
  do IO<Unit>:
    IO.print(U32.show(L.st_ok(L.sl_st(r))))
