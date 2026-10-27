# blake3x/eqv3/main.bend (follow's `equihash`) with a height- and network-aware difficulty
# check: ZIP 218 (NU7: 25 s spacing, averaging window 102) and Testnet minimum difficulty.
# Per-header PoW (Equihash + target) runs as a balanced parallel tree (`verify!` on the Metal
# GPU; `+RTS --gpu off` for CPU threads), then a sequential fold checks prev-hash linkage and
# the difficulty of every header that has PoWAveragingWindow(h) + 11 predecessors in the file.
#
#   ./equihash7 <headers.bin> <count> <batch> <depth> <height of the first header> [main|test]
import Base
import ../../../blake3x/eqv3/pow.bend as P
import ../../../blake3x/eqv3/diff.bend as D
import ../nu7.bend as N
import ./diff7.bend as D7

# ---------------------------------------------------------------------------
# Batches -> balanced tree -> parallel verification
# ---------------------------------------------------------------------------

type T is Data:
  Leaf{hs: +List<+List<U32>>}
  Node{l: T, r: T}

type RT is Data:
  RLeaf{rs: +List<P.HR>}
  RNode{l: RT, r: RT}

def check_all(hs: +List<+List<U32>>) -> +List<P.HR>:
  match hs:
    case Con{h, rest}:
      P.check_header(h) <> check_all(rest)
    case Nil{}:
      Nil{}

def verify(+k: Nat, t: T) -> RT:
  match k t:
    case _ Leaf{hs}:
      RLeaf{check_all(hs)}
    case 1n+j Node{l, r}:
      a b = verify(j, l) verify(j, r)
      RNode{a, b}
    case _ _:
      RLeaf{Nil{}}

# Results in header order.
def flatten(t: RT, acc: +List<P.HR>) -> +List<P.HR>:
  match t:
    case RLeaf{rs}:
      List.append(&2, P.HR, rs, acc)
    case RNode{l, r}:
      flatten(l, flatten(r, acc))

def split(k: Nat, +bs: +List<U32>) -> +List<+List<U32>>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      List.take(&2, U32, bs, 1487n) <> split(p, List.drop(&2, U32, bs, 1487n))

def leaf_size(c: Bool, +base: Nat) -> Nat:
  match c:
    case True{}:
      1n+base
    case False{}:
      base

# 2^d leaves; the first `extra` get base + 1 headers, the rest base (no header dropped).
def leaves(k: Nat, +base: Nat, +extra: Nat, hs: +List<+List<U32>>) -> +List<T>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      +h2 = hs
      +sz = leaf_size(Nat.is_lt(0n, extra), base)
      Leaf{List.take(&2, +List<U32>, h2, sz)} <> leaves(p, base, Nat.sub(extra, 1n), List.drop(&2, +List<U32>, h2, sz))

def pair_up(xs: +List<T>) -> +List<T>:
  match xs:
    case Con{a, Con{b, rest}}:
      Node{a, b} <> pair_up(rest)
    case Con{a, Nil{}}:
      [a]
    case Nil{}:
      Nil{}

def levels(k: Nat, xs: +List<T>) -> +List<T>:
  match k:
    case 0n:
      xs
    case 1n+p:
      levels(p, pair_up(xs))

def root(xs: +List<T>) -> T:
  match xs:
    case Con{t, _}:
      t
    case Nil{}:
      Leaf{Nil{}}

# ---------------------------------------------------------------------------
# Sequential fold: counts, linkage, difficulty
# ---------------------------------------------------------------------------

type St is Data:
  St{n: U32, pow: U32, tgt: U32, link: U32, diff: U32, diffn: U32, last: P.H8, have: Bool, win: D.Win, h: U32, net: N.Net, bad: String}

def inc(b: Bool, +x: U32) -> U32:
  match b:
    case True{}:
      (x + 1 : U32)
    case False{}:
      x

def note_sel(c: Bool, +h: U32, +bits: U32, bad: String) -> String:
  match c:
    case True{}:
      bad ++ "difficulty mismatch at " ++ U32.show(h) ++ " nBits " ++ U32.show(bits) ++ "\n"
    case False{}:
      bad

def note(+applies: Bool, +ok: Bool, +h: U32, +bits: U32, bad: String) -> String:
  note_sel(applies && Bool.not(ok), h, bits, bad)

def step(st: St, r: P.HR) -> St:
  St{n, pow, tgt, link, diff, diffn, last, +have, +win, +h, +net, bad} = st
  P.HR{p, u, +hash, prev, +time, +bits} = r
  +dc = D7.check7(net, U32.to_nat(h), win, time, bits)
  St{(n + 1 : U32), inc(p, pow), inc(u, tgt), inc(have && P.h8_eq(prev, last), link), inc(D.ok(dc), diff), inc(D.applies(dc), diffn), hash, True{}, D7.push7(win, time, bits), (h + 1 : U32), net,
     note(D.applies(dc), D.ok(dc), h, bits, bad)}

def fold(rs: +List<P.HR>, st: St) -> St:
  match rs:
    case Con{r, rest}:
      fold(rest, step(st, r))
    case Nil{}:
      st

def bytes_res(res: Result<&1, &1, U32 & String, +List<U32>>) -> +List<U32>:
  match res:
    case Done{bs}:
      bs
    case Fail{_}:
      Nil{}

def close_bytes(r: File & Result<&1, &1, U32 & String, +List<U32>>) -> IO(+List<U32>):
  (f, res) = r
  do IO<+List<U32>>:
    File.close(f)
    return bytes_res(res)

# Verifies `nb` batches of `per_batch` headers each, starting at batch `i`.
def batches(nb: Nat, +path: String, +i: U32, +per_batch: U32, +d: Nat, st: St, +ms: Nat) -> IO(St & Nat):
  match nb:
    case 0n:
      IO.pure(St & Nat, (st, ms))
    case 1n+p:
      +n = U32.to_nat(per_batch)
      +lanes = Nat.pow(2n, d)
      do IO<St & Nat>:
        f : File <- IO.try(File, File.open(path, "r"))
        r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_at(f, (i * per_batch * 1487 : U32), (per_batch * 1487 : U32))
        bs : +List<U32> <- close_bytes(r)
        tree : T = root(levels(d, leaves(lanes, Nat.div(n, lanes), Nat.mod(n, lanes), split(n, bs))))
        t0 : Nat <- IO.now()
        res : RT = verify!(d, tree)
        rs : +List<P.HR> = flatten(res, Nil{})
        +st2 : St = fold(rs, st)
        t1 : Nat <- IO.now()
        +dt : Nat = Nat.sub(t1, t0)
        IO.print("batch " ++ U32.show(i) ++ ": " ++ Nat.show(dt) ++ " ms")
        batches(p, path, (i + 1 : U32), per_batch, d, st2, Nat.add(ms, dt))

def num(s: String) -> U32:
  Maybe.default(&2, U32, U32.read(s), 0)

def report(x: St & Nat) -> String:
  (st, ms) = x
  St{+n, pow, tgt, link, diff, +diffn, _, _, _, _, _, bad} = st
  bad ++ "headers " ++ U32.show(n) ++ "\n" ++
  "equihash valid " ++ U32.show(pow) ++ "/" ++ U32.show(n) ++ "\n" ++
  "hash <= target " ++ U32.show(tgt) ++ "/" ++ U32.show(n) ++ "\n" ++
  "prev-hash links " ++ U32.show(link) ++ "/" ++ U32.show((n - 1 : U32)) ++ "\n" ++
  "difficulty (nBits == expected) " ++ U32.show(diff) ++ "/" ++ U32.show(diffn) ++ "\n" ++
  "verify time " ++ Nat.show(ms) ++ " ms"

def net_sel(t: Bool) -> N.Net:
  match t:
    case True{}:
      N.Test{}
    case False{}:
      N.Main{}

def net_of(xs: List<String>) -> N.Net:
  match xs:
    case Con{+s, _}:
      net_sel(String.eq(s, "test"))
    case Nil{}:
      N.Main{}

def go(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{+path, Con{cs, Con{bs, Con{ds, Con{hs, rest}}}}}}:
      +count = num(cs)
      +per_batch = num(bs)
      +d = U32.to_nat(num(ds))
      do IO<Unit>:
        res : St & Nat <- batches(U32.to_nat((count / per_batch : U32)), path, 0, per_batch, d, St{0, 0, 0, 0, 0, 0, P.H8{0, 0, 0, 0, 0, 0, 0, 0}, False{}, D.empty(), num(hs), net_of(rest), ""}, 0n)
        IO.print(report(res))
    case _:
      IO.print("usage: equihash7 <headers.bin> <count> <batch> <depth> <first height> [main|test]")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(args)
