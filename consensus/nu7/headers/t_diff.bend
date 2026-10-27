# Difficulty driver for differential tests: records (u32 height, u32 time, u32 bits) in a file;
# prints "exp <h> <expected nBits hex-decimal>" for every record whose context is full
# (PoWAveragingWindow(h) + 11 predecessors), then pushes the record's given bits.
#   t_diff main|test <file> <bytes>
import Base
import ../../../blake3x/eqv3/diff.bend as D
import ../nu7.bend as N
import ./diff7.bend as D7

def res_bytes(res: Result<&1, &1, U32 & String, +List<U32>>) -> +List<U32>:
  match res:
    case Done{bs}:
      bs
    case Fail{_}:
      Nil{}

def close_with(r: File & Result<&1, &1, U32 & String, +List<U32>>) -> IO(+List<U32>):
  (f, res) = r
  do IO<+List<U32>>:
    File.close(f)
    return res_bytes(res)

def read_all(+path: String, +n: U32) -> IO(+List<U32>):
  do IO<+List<U32>>:
    f : File <- IO.try(File, File.open(path, "r"))
    r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_at(f, 0, n)
    close_with(r)

def words(+bs: +List<U32>) -> +List<U32>:
  match bs:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}:
      (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32) <> words(rest)
    case _:
      Nil{}

def net_sel(t: Bool) -> N.Net:
  match t:
    case True{}:
      N.Test{}
    case False{}:
      N.Main{}

def line_sel(c: Bool, +n: N.Net, +h: U32, +xs: +List<D.TB>, +t: U32) -> String:
  match c:
    case True{}:
      "exp " ++ U32.show(h) ++ " " ++ U32.show(D7.expected7(n, U32.to_nat(h), xs, t)) ++ "\n"
    case False{}:
      ""

def run(+n: N.Net, ws: +List<U32>, w: D.Win) -> String:
  match ws:
    case Con{+h, Con{+t, Con{+b, rest}}}:
      D.Win{+xs} = w
      line_sel(Nat.is_ge(List.length(&2, D.TB, xs), D7.span(n, U32.to_nat(h))), n, h, xs, t)
        ++ run(n, rest, D7.push7(D.Win{xs}, t, b))
    case _:
      ""

def go(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{+net, Con{+path, Con{len, _}}}}:
      do IO<Unit>:
        bs : +List<U32> <- read_all(path, Maybe.default(&2, U32, U32.read(len), 0))
        IO.print(run(net_sel(String.eq(net, "test")), words(bs), D.empty()))
    case _:
      IO.print("usage: t_diff main|test <file> <bytes>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(args)
