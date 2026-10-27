# read a file through File.read_words (flat Array<U32>) and sum its bytes
import Base

def bsum(+w: U32) -> U32:
  U32.add(U32.add(U32.and(w, 255), U32.and(U32.shrn(w, 8n), 255)),
    U32.add(U32.and(U32.shrn(w, 16n), 255), U32.shrn(w, 24n)))

def sum(n: Nat, r: Array<U32> & U32, +i: U32, acc: U32) -> U32:
  match n:
    case 0n:
      (a, w) = r
      U32.add(acc, bsum(w))
    case 1n+p:
      (a, w) = r
      +j = U32.inc(i)
      sum(p, a[j], j, U32.add(acc, bsum(w)))

def sum_all(an: Array<U32> & U32) -> U32:
  (a, +n) = an
  sum(U32.to_nat(U32.sub(U32.shrn(U32.add(n, 3), 2n), 1)), a[0], 0, 0)

law got:
  for m: File & Result<&1, &1, U32 & String, Array<U32> & U32>
  IO(Unit)

def got(m):
  (f, r) = m
  do IO<Unit>:
    an : Array<U32> & U32 <- IO.pass(Array<U32> & U32, r)
    IO.print(U32.show(sum_all(an)))
    File.close(f)

law sized:
  for p: File & Result<&1, &1, U32 & String, U32>
  IO(Unit)

def sized(p):
  (f, r) = p
  do IO<Unit>:
    n : U32 <- IO.pass(U32, r)
    m : File & Result<&1, &1, U32 & String, Array<U32> & U32> <- File.read_words(f, n)
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
