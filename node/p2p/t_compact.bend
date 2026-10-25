import Base
import ./bytes.bend as B

def show(c: B.Compact) -> String:
  B.Compact{v, w} = c
  U32.show(v) ++ "/" ++ U32.show(w)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(show(B.read_compact([5])) ++ " " ++ show(B.read_compact([252])) ++ " " ++ show(B.read_compact([253, 253, 0]))
      ++ " " ++ show(B.read_compact([253, 5, 0])) ++ " " ++ show(B.read_compact([253, 64, 5])) ++ " " ++ show(B.read_compact([254, 0, 0, 1, 0]))
      ++ " " ++ show(B.read_compact([254, 255, 255, 0, 0])) ++ " " ++ show(B.read_compact([254, 1, 0, 0, 2])) ++ " " ++ show(B.read_compact([254, 0, 0, 0, 2]))
      ++ " " ++ show(B.read_compact([255, 0, 0, 0, 0, 1, 0, 0, 0])) ++ " " ++ show(B.read_compact([253, 64])) ++ " " ++ show(B.read_compact([])))
