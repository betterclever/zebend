# Prints, for the first N headers of a file: index, block hash (internal byte order, hex),
# Equihash validity and hash <= target. Compared line by line with the Rust oracle.
#   bend t/pow_test.bend <file> <N>
import Base
import ../pow.bend as P

def nib.go(c: Bool, +x: U32) -> Char:
  match c:
    case True{}:
      Char.from_u32((x + 48 : U32))
    case False{}:
      Char.from_u32((x + 87 : U32))

def nib(+x: U32) -> Char:
  nib.go(U32.is_lt(x, 10), x)

def hex_bytes(bs: +List<U32>) -> String:
  match bs:
    case Con{+b, rest}:
      SCon{nib((b >> 4n : U32)), SCon{nib((b .&. 15 : U32)), hex_bytes(rest)}}
    case Nil{}:
      SNil{}

def h8_hex(h: P.H8) -> String:
  P.H8{a0, a1, a2, a3, a4, a5, a6, a7} = h
  hex_bytes(P.word_bytes(a0, P.word_bytes(a1, P.word_bytes(a2, P.word_bytes(a3, P.word_bytes(a4, P.word_bytes(a5, P.word_bytes(a6, P.word_bytes(a7, Nil{})))))))))

def b(x: Bool) -> String:
  match x:
    case True{}:
      "1"
    case False{}:
      "0"

def line(+i: U32, r: P.HR) -> String:
  P.HR{pow, under, hash, _, _, _} = r
  U32.show(i) ++ " " ++ h8_hex(hash) ++ " pow " ++ b(pow) ++ " target " ++ b(under)

def split(k: Nat, +bs: +List<U32>) -> List<+List<U32>>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      List.take(&2, U32, bs, 1487n) <> split(p, List.drop(&2, U32, bs, 1487n))

def show_all(hs: List<+List<U32>>, +i: U32) -> IO(Unit):
  match hs:
    case Con{h, rest}:
      do IO<Unit>:
        IO.print(line(i, P.check_header(h)))
        show_all(rest, (i + 1 : U32))
    case Nil{}:
      IO.pure(Unit, Unit{})

def bytes_of(r: File & Result<&1, &1, U32 & String, +List<U32>>) -> +List<U32>:
  (_, res) = r
  match res:
    case Done{bs}:
      bs
    case Fail{_}:
      Nil{}

def num(s: String) -> U32:
  Maybe.default(&2, U32, U32.read(s), 0)

def go(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{path, Con{ns, _}}}:
      +n = num(ns)
      do IO<Unit>:
        f : File <- IO.try(File, File.open(path, "r"))
        r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_bytes(f, (n * 1487 : U32))
        show_all(split(U32.to_nat(n), bytes_of(r)), 0)
    case _:
      IO.print("usage: pow_test <file> <N>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(args)
