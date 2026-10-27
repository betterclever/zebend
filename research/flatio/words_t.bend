# words_t FILE: byte sum through words.byte, and word 0 big-endian (check vs python)
import Base
import ./words.bend as W

# r: the array and byte i; n more bytes after it
def sum(n: Nat, r: Array<U32> & U32, +i: U32, +acc: U32) -> U32:
  match n:
    case 0n:
      (a, b) = r
      (acc + b : U32)
    case 1n+p:
      (a, +b) = r
      +j = U32.inc(i)
      sum(p, W.byte(a, j), j, (acc + b : U32))

def show(an: Array<U32> & U32) -> String:
  (a, +n) = an
  U32.show(n) ++ " " ++ U32.show(sum(U32.to_nat((n - 1 : U32)), W.byte(a, 0), 0, 0))

def run(a: List<String>) -> IO(Unit):
  match a:
    case [_, path]:
      IO.bind(Array<U32> & U32, Unit, W.load(path), an => IO.print(show(an)))
    case _:
      IO.print("usage: words_t FILE")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
