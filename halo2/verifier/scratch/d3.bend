import Base
import ../vlib.bend as L
import ../../lib/words.bend as Wd

def main() -> IO(Unit):
  +r = L.rd_scalar(L.st_new({L.Proof{Wd.W{5, 0, 0, 0, 0, 0, 0, 0} <> Nil{}, Nil{}} : L.Proof}))
  do IO<Unit>:
    IO.print(U32.show(L.st_ok(L.sf_st(r))))
