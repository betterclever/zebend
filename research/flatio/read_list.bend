# read a file through File.read_bytes (one List cell per byte) and sum its bytes
import Base

def sum(xs: List<&2, U32>, acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{x, t}:
      sum(t, U32.add(acc, x))

law got:
  for m: File & Result<&1, &1, U32 & String, List<&2, U32>>
  IO(Unit)

def got(m):
  (f, r) = m
  do IO<Unit>:
    xs : List<&2, U32> <- IO.pass(List<&2, U32>, r)
    IO.print(U32.show(sum(xs, 0)))
    File.close(f)

law sized:
  for p: File & Result<&1, &1, U32 & String, U32>
  IO(Unit)

def sized(p):
  (f, r) = p
  do IO<Unit>:
    n : U32 <- IO.pass(U32, r)
    m : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, n)
    got(m)

def last(xs: List<String>, d: String) -> String:
  match xs:
    case Con{x, t}:
      last(t, x)
    case Nil{}:
      d

def main() -> IO(Unit):
  do IO<Unit>:
    a : List<String> <- IO.args()
    f : File <- IO.try(File, File.open(last(a, ""), "r"))
    p : File & Result<&1, &1, U32 & String, U32> <- File.size(f)
    sized(p)
