# Differential test of pts.bend: pt_ok (no square root) against pt_ok_ref (node/wire's
# decoders) on every point.
#   t_pts win <window.bin>   every curve point of every block of a blockdelta window
#   t_pts rnd <file>         records of 33 bytes: kind (0 JN, 1 JA, 2 PI, 3 PN) | 32 bytes
# Prints: points <n> ref_ok <a> new_ok <b> mismatches <m>, then "mm <i>" for the first ones.
import Base
import ./parse.bend as P
import ./pts.bend as T
import ../wire/blk.bend as KB
import ../../../node/wire/hb.bend as H
import ../../../halo2/lib/words.bend as Wd

type Cnt is Data:
  Cnt{n: U32, a: U32, b: U32, m: U32, mm: String}

def b32(b: Bool) -> U32:
  match b:
    case True{}:
      1
    case False{}:
      0

def sm_sel(few: Bool, +i: U32, +s: String) -> String:
  match few:
    case True{}:
      s ++ "mm " ++ U32.show(i) ++ "\n"
    case False{}:
      s

def mm_sel(diff: Bool, +i: U32, +m: U32, +s: String) -> String:
  match diff:
    case True{}:
      sm_sel(U32.is_lt(m, 20), i, s)
    case False{}:
      s

def one(+k: T.Kd, +w: Wd.W, c: Cnt) -> Cnt:
  Cnt{+n, +a, +b, +m, +mm} = c
  +r = T.pt_ok_ref(k, w)
  +x = T.pt_ok(k, w)
  +diff = Bool.not(U32.is_eq(b32(r), b32(x)))
  Cnt{(n + 1 : U32), (a + b32(r) : U32), (b + b32(x) : U32), (m + b32(diff) : U32), mm_sel(diff, n, m, mm)}

def all(ps: +List<T.Pt>, c: Cnt) -> Cnt:
  match ps:
    case Nil{}:
      c
    case Con{p, t}:
      T.Pt{_, +k, +w} = p
      all(t, one(k, w, c))

def show(c: Cnt) -> String:
  Cnt{+n, +a, +b, +m, +mm} = c
  "points " ++ U32.show(n) ++ " ref_ok " ++ U32.show(a) ++ " new_ok " ++ U32.show(b) ++ " mismatches " ++ U32.show(m) ++ "\n" ++ mm

# ---- window mode

def txs(n: Nat, +c: P.C, acc: +List<T.Pt>) -> +List<T.Pt>:
  match n:
    case 0n:
      acc
    case 1n+m:
      +t = P.tx(c)
      txs(m, P.skip(c, P.tx_size(t)), T.tx(0, c, acc))

def blk_pts(m: Maybe<&2, U32>, +blk: +List<U32>) -> +List<T.Pt>:
  match m:
    case None{}:
      Nil{}
    case Some{_}:
      +c = P.skip(P.start(blk), 1487)
      +n = P.cs(c)
      txs(U32.to_nat(P.cs_v(n)), P.cs_c(n), Nil{})

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

def blk_in(+blk: +List<U32>, c: Cnt) -> Cnt:
  all(blk_pts(KB.parse_capped(blk), blk), c)

type Hd is Data:
  Stop{}
  Rec{blen: U32, off: U32}

def hd_sel(full: Bool, +bs: +List<U32>, +off: U32) -> Hd:
  match full:
    case False{}:
      Stop{}
    case True{}:
      Rec{H.le32(H.drop(bs, 1491)), off}

def head_of(+bs: +List<U32>, +off: U32) -> Hd:
  hd_sel(U32.is_eq(H.length(bs), 1495), bs, off)

def wloop(fuel: Nat, st: Hd, +path: String, c: Cnt) -> IO(Cnt):
  match fuel st:
    case 0n _:
      IO.pure(Cnt, c)
    case 1n+p Stop{}:
      IO.pure(Cnt, c)
    case 1n+p Rec{+blen, +off}:
      +next = (off + 1495 + blen : U32)
      do IO<Cnt>:
        blk : +List<U32> <- read_at(path, (off + 1495 : U32), blen)
        c2 : Cnt = blk_in(blk, c)
        nh : +List<U32> <- read_at(path, next, 1495)
        wloop(p, head_of(nh, next), path, c2)

# ---- random mode

def kind2(t: Bool) -> T.Kd:
  match t:
    case True{}:
      T.PI{}
    case False{}:
      T.PN{}

def kind1(o: Bool, +x: U32) -> T.Kd:
  match o:
    case True{}:
      T.JA{}
    case False{}:
      kind2(U32.is_eq(x, 2))

def kind_sel(z: Bool, +x: U32) -> T.Kd:
  match z:
    case True{}:
      T.JN{}
    case False{}:
      kind1(U32.is_eq(x, 1), x)

def kind(+x: U32) -> T.Kd:
  kind_sel(U32.is_eq(x, 0), x)

def recs(n: Nat, +xs: +List<U32>, c: Cnt) -> Cnt:
  match n:
    case 0n:
      c
    case 1n+p:
      recs(p, H.drop(xs, 33), one(kind(H.at(xs, 0)), H.w32(H.drop(xs, 1)), c))

def rnd_all(+bs: +List<U32>) -> Cnt:
  recs(U32.to_nat((H.length(bs) / 33 : U32)), bs, Cnt{0, 0, 0, 0, ""})

def run(w: Bool, +path: String) -> IO(Unit):
  match w:
    case True{}:
      do IO<Unit>:
        h0 : +List<U32> <- read_at(path, 0, 1495)
        cw : Cnt <- wloop(1000000n, head_of(h0, 0), path, Cnt{0, 0, 0, 0, ""})
        IO.print(show(cw))
    case False{}:
      do IO<Unit>:
        all_b : +List<U32> <- read_at(path, 0, 100000000)
        IO.print(show(rnd_all(all_b)))

def go(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{mode, Con{path, _}}}:
      run(String.eq(mode, "win"), path)
    case _:
      IO.print("usage: t_pts win|rnd <file>")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<String> <- IO.args()
    go(xs)
