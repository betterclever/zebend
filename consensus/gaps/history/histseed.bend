# histseed: build / extend the ZIP 221 history tree from precomputed per-block leaf records,
# checking every header field it can.
# Usage: histseed <state.in | -> <leaves.bin> <state.out> [main|test]
#   leaves.bin: 184-byte records, in height order:
#     u32 height | block hash 32 (internal order) | u32 nTime | u32 nBits |
#     header field 32 (bytes 68..100 of the header: hashLightClientRoot / hashBlockCommitments) |
#     Sapling root 32 | Orchard root 32 | Ironwood root 32 (final roots after the block, LE repr) |
#     u32 Sapling tx count | u32 Orchard tx count | u32 Ironwood tx count
# Prints one line per block (see hist.bend check): Heartwood/Canopy blocks are checked
# (field == history root); NU5+ blocks print the history root only ("UNCHECKED no-authroot"),
# since hashBlockCommitments also needs the block's hashAuthDataRoot (use `history` for that).
import Base
import ./hist.bend as X
import ../../../node/wire/hb.bend as H

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

def read_at(+path: String, +off: U32, +n: U32) -> IO(+List<U32>):
  do IO<+List<U32>>:
    f : File <- IO.try(File, File.open(path, "r"))
    r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_at(f, off, n)
    close_with(r)

def u32o(+xs: +List<U32>, +o: U32) -> U32:
  H.le32(H.drop(xs, o))

def b32o(+xs: +List<U32>, +o: U32) -> +List<U32>:
  H.take(H.drop(xs, o), 32)

def one(+s: X.St, +r: +List<U32>) -> X.R:
  X.step(s, u32o(r, 0), b32o(r, 44), X.zeros(32n), False{}, b32o(r, 4), u32o(r, 36), u32o(r, 40),
    b32o(r, 76), b32o(r, 108), b32o(r, 140), u32o(r, 172), u32o(r, 176), u32o(r, 180))

type Acc is Data:
  Acc{st: X.St, out: String}

def acc_st(a: Acc) -> X.St:
  Acc{+s, _} = a
  s

def acc_out(a: Acc) -> String:
  Acc{_, +o} = a
  o

def recs(fuel: Nat, +xs: +List<U32>, +s: X.St) -> Acc:
  match fuel:
    case 0n:
      Acc{s, ""}
    case 1n+k:
      +r = one(s, H.take(xs, 184))
      +rest = recs(k, H.drop(xs, 184), X.r_st(r))
      Acc{acc_st(rest), X.r_line(r) ++ "\n" ++ acc_out(rest)}

def chunk() -> U32:
  368000

def close_pair(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, _) = r
  File.close(f)

def write_state(+p: String, +bs: +List<U32>) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(p, "w"))
    r : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, bs)
    close_pair(r)

def net_of(s: String) -> U32:
  X.b2u(String.eq(s, "test"))

def state_in(dash: Bool, +p: String, +net: U32) -> IO(X.St):
  match dash:
    case True{}:
      IO.pure(X.St, X.state_of(net, Nil{}))
    case False{}:
      do IO<X.St>:
        +hd : +List<U32> <- read_at(p, 0, 20)
        +xs : +List<U32> <- read_at(p, 0, (20 + H.le32(H.drop(hd, 16)) * 300 : U32))
        return X.state_of(net, xs)

def loop(fuel: Nat, cont: Bool, +path: String, +off: U32, +s: X.St, +outp: String) -> IO(Unit):
  match fuel cont:
    case 1n+p True{}:
      do IO<Unit>:
        +xs : +List<U32> <- read_at(path, off, chunk())
        +a : Acc = recs(U32.to_nat((H.length(xs) / 184 : U32)), xs, s)
        IO.write(acc_out(a))
        loop(p, U32.is_eq(H.length(xs), chunk()), path, (off + chunk() : U32), acc_st(a), outp)
    case _ _:
      write_state(outp, X.state_bytes(s))

def run(+sin: String, +lv: String, +sout: String, +net: U32) -> IO(Unit):
  do IO<Unit>:
    s : X.St <- state_in(String.eq(sin, "-"), sin, net)
    loop(100000n, True{}, lv, 0, s, sout)

def go(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{a, Con{b, Con{c, Con{d, _}}}}}:
      run(a, b, c, net_of(d))
    case Con{_, Con{a, Con{b, Con{c, _}}}}:
      run(a, b, c, 0)
    case _:
      IO.print("usage: histseed <state.in|-> <leaves.bin> <state.out> [main|test]")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<String> <- IO.args()
    go(xs)
