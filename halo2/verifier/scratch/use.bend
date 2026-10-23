import Base
import ./m.bend as M

def g(p: M.Pair2) -> U32:
  M.Pair2{+a, +b} = p
  (a + b : U32)

def main() -> IO(Unit):
  do IO<Unit>:
    +p : M.Pair2 = M.mk(5)
    IO.print(U32.show(g(p)))
    IO.print(U32.show(M.fst(p)))
