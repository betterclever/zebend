import Base
import ../vlib.bend as L
import ../../lib/fp.bend as Fp

def main() -> IO(Unit):
  +st = L.squeeze(L.st_new({L.Proof{Nil{}, Nil{}} : L.Proof}))
  do IO<Unit>:
    L.print_log(L.st_log(L.lgf(L.sf_st(st), "c", L.sf_v(st))))
