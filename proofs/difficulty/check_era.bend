# Checks every header's nBits against the era-aware difficulty rule.
# Input: 12-byte records (height, time, nBits; u32 little-endian), consecutive heights.
# Prints per-era counts and the first mismatching heights.
import Base
import ./era.bend as E
import ./differa.bend as X
import ../../node/headers/diff.bend as D

def le32(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32)

type R is Data:
  R{h: U32, t: U32, b: U32}

def recs(bs: +List<U32>) -> +List<R>:
  match bs:
    case Con{a0, Con{a1, Con{a2, Con{a3, Con{b0, Con{b1, Con{b2, Con{b3, Con{c0, Con{c1, Con{c2, Con{c3, rest}}}}}}}}}}}}:
      R{le32(a0, a1, a2, a3), le32(b0, b1, b2, b3), le32(c0, c1, c2, c3)} <> recs(rest)
    case _:
      Nil{}

type St is Data:
  St{pre_ok: U32, pre_n: U32, post_ok: U32, post_n: U32, bad: +List<U32>, win: D.Win}

def inc(c: Bool, +x: U32) -> U32:
  match c:
    case True{}:
      (x + 1 : U32)
    case False{}:
      x

def note_bad(c: Bool, +h: U32, bad: +List<U32>) -> +List<U32>:
  match c:
    case True{}:
      List.take(&2, U32, h <> bad, 8n)
    case False{}:
      bad

def is_pre(e: E.Era) -> Bool:
  match e:
    case E.Pre{}:
      True{}
    case E.Post{}:
      False{}

def yes3(+h: U32, +t: U32, +b: U32, +po: U32, +pn: U32, +qo: U32, +qn: U32, bad: +List<U32>, +xs: +List<D.TB>, +e: E.Era) -> St:
  +ok = U32.is_eq(X.expected(e, xs), b)
  +pre = is_pre(e)
  St{inc(pre && ok, po), inc(pre, pn), inc(Bool.not(pre) && ok, qo), inc(Bool.not(pre), qn), note_bad(Bool.not(ok), h, bad), D.push(D.Win{xs}, t, b)}

def yes2(+h: U32, +t: U32, +b: U32, +po: U32, +pn: U32, +qo: U32, +qn: U32, bad: +List<U32>, win: D.Win) -> St:
  D.Win{+xs} = win
  yes3(h, t, b, po, pn, qo, qn, bad, xs, E.era_of(h))

def step.yes(+r: R, s: St) -> St:
  R{+h, +t, +b} = r
  St{+po, +pn, +qo, +qn, bad, win} = s
  yes2(h, t, b, po, pn, qo, qn, bad, win)

def step.no(+r: R, s: St) -> St:
  R{_, +t, +b} = r
  St{po, pn, qo, qn, bad, win} = s
  St{po, pn, qo, qn, bad, D.push(win, t, b)}

def step.full(full: Bool, +r: R, s: St) -> St:
  match full:
    case True{}:
      step.yes(r, s)
    case False{}:
      step.no(r, s)

def win_len(w: D.Win) -> Nat:
  D.Win{+xs} = w
  List.length(&2, D.TB, xs)

def step2(+r: R, +po: U32, +pn: U32, +qo: U32, +qn: U32, bad: +List<U32>, +win: D.Win) -> St:
  step.full(Nat.is_eq(win_len(win), 28n), r, St{po, pn, qo, qn, bad, win})

def step(+r: R, s: St) -> St:
  St{+po, +pn, +qo, +qn, bad, +win} = s
  step2(r, po, pn, qo, qn, bad, win)

def run(rs: +List<R>, s: St) -> St:
  match rs:
    case Con{+r, rest}:
      run(rest, step(r, s))
    case Nil{}:
      s

def show_list(xs: +List<U32>) -> String:
  match xs:
    case Con{+x, rest}:
      U32.show(x) ++ " " ++ show_list(rest)
    case Nil{}:
      ""

def report(s: St) -> IO(Unit):
  St{po, pn, qo, qn, bad, _} = s
  do IO<Unit>:
    IO.print("pre-Blossom nBits == expected " ++ U32.show(po) ++ "/" ++ U32.show(pn))
    IO.print("post-Blossom nBits == expected " ++ U32.show(qo) ++ "/" ++ U32.show(qn))
    IO.print("first mismatches (newest first): " ++ show_list(bad))

def got(f: File, res: Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(List<&2, U32>):
  match res:
    case Done{bytes}:
      do IO<List<&2, U32>>:
        File.close(f)
        return bytes
    case Fail{e}:
      do IO<List<&2, U32>>:
        File.close(f)
        return Nil{}

def got_pair(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(List<&2, U32>):
  (f, res) = r
  got(f, res)

def read_all(path: String) -> IO(List<&2, U32>):
  do IO<List<&2, U32>>:
    f : File <- IO.try(File, File.open(path, "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 67108864)
    got_pair(r)

def go(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{p, _}}:
      do IO<Unit>:
        bs : List<&2, U32> <- read_all(p)
        report(run(recs(bs), St{0, 0, 0, 0, Nil{}, D.empty()}))
    case _:
      IO.print("usage: check_era <records.bin>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(args)
