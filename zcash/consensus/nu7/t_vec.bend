# Prints NU7 quantities for differential testing against the Zebra/Zakura oracles.
#   t_vec heights|fees|nsm main|test <file of u32 LE words>
#   heights: one u32 height per record        -> "h <h> halving <k> subsidy <s> zcg <v> <script> deferred <v> period <p> index <i>"
#   fees:    (height, fee lo, fee hi) records  -> "fee <h> <fees> contribution <c> miner <m>"
#   nsm:     (height, bal lo, bal hi) records  -> "nsm <h> <bal> additional <a> after0 <balance after a block with no fees>"
import Base
import ./nu7.bend as N
import ../../wire/hb.bend as H

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

def net_of(+s: String) -> N.Net:
  net_sel(String.eq(s, "test"))

def line_h(+n: N.Net, +h: U32) -> String:
  +hn = U32.to_nat(h)
  +s = N.subsidy(n, hn)
  "h " ++ U32.show(h) ++ " halving " ++ Nat.show(N.halving(n, hn)) ++ " subsidy " ++ Nat.show(s)
    ++ " zcg " ++ Nat.show(N.fs_zcg(n, hn, s)) ++ " " ++ N.zcg_script(n, hn)
    ++ " deferred " ++ Nat.show(N.fs_deferred(n, hn, s)) ++ " period " ++ Nat.show(N.period(n, hn))
    ++ " index " ++ Nat.show(N.zcg_index(n, hn))

def heights(+n: N.Net, ws: +List<U32>) -> String:
  match ws:
    case Con{+h, rest}:
      line_h(n, h) ++ "\n" ++ heights(n, rest)
    case Nil{}:
      ""

def fees(+n: N.Net, ws: +List<U32>) -> String:
  match ws:
    case Con{+h, Con{lo, Con{hi, rest}}}:
      +f : H.U64 = H.U64{lo, hi}
      "fee " ++ U32.show(h) ++ " " ++ N.udec(f) ++ " contribution " ++ N.udec(N.contribution(n, h, f))
        ++ " miner " ++ N.udec(N.miner_fees(n, h, f)) ++ "\n" ++ fees(n, rest)
    case _:
      ""

def nsm(+n: N.Net, ws: +List<U32>) -> String:
  match ws:
    case Con{+h, Con{lo, Con{hi, rest}}}:
      +b : H.U64 = H.U64{lo, hi}
      "nsm " ++ U32.show(h) ++ " " ++ N.udec(b) ++ " additional " ++ N.udec(N.additional(n, h, b))
        ++ " after0 " ++ N.udec(N.nsm_after(n, h, b, N.z64())) ++ "\n" ++ nsm(n, rest)
    case _:
      ""

def run2(g: Bool, +n: N.Net, ws: +List<U32>) -> String:
  match g:
    case True{}:
      nsm(n, ws)
    case False{}:
      heights(n, ws)

def run_sel(f: Bool, g: Bool, +n: N.Net, ws: +List<U32>) -> String:
  match f:
    case True{}:
      fees(n, ws)
    case False{}:
      run2(g, n, ws)

def run(+mode: String, +n: N.Net, ws: +List<U32>) -> String:
  run_sel(String.eq(mode, "fees"), String.eq(mode, "nsm"), n, ws)

def go(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{+mode, Con{net, Con{+path, Con{len, _}}}}}:
      do IO<Unit>:
        bs : +List<U32> <- read_all(path, Maybe.default(&2, U32, U32.read(len), 0))
        IO.print(run(mode, net_of(net), words(bs)))
    case _:
      IO.print("usage: t_vec heights|fees|nsm main|test <file> <bytes>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(args)
