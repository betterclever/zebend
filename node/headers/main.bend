# Verifies a file of raw mainnet headers: per-header PoW (Equihash + target) runs as a
# balanced parallel tree (`verify!` on the Metal GPU; `+RTS --gpu off` for CPU threads),
# then a sequential fold checks prev-hash linkage and the difficulty adjustment.
#
#   ./verify <headers.bin> <count> <batch> <depth>
import Base
import ./pow.bend as P
import ./diff.bend as D

# ---------------------------------------------------------------------------
# Batches -> balanced tree -> parallel verification
# ---------------------------------------------------------------------------

type T is Data:
  Leaf{hs: List<+List<U32>>}
  Node{l: T, r: T}

type RT is Data:
  RLeaf{rs: List<P.HR>}
  RNode{l: RT, r: RT}

def check_all(hs: List<+List<U32>>) -> List<P.HR>:
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
def flatten(t: RT, acc: List<P.HR>) -> List<P.HR>:
  match t:
    case RLeaf{rs}:
      List.append(&2, P.HR, rs, acc)
    case RNode{l, r}:
      flatten(l, flatten(r, acc))

def split(k: Nat, +bs: +List<U32>) -> List<+List<U32>>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      List.take(&2, U32, bs, 1487n) <> split(p, List.drop(&2, U32, bs, 1487n))

def leaves(k: Nat, +per: Nat, hs: List<+List<U32>>) -> List<T>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      +h2 = hs
      Leaf{List.take(&2, +List<U32>, h2, per)} <> leaves(p, per, List.drop(&2, +List<U32>, h2, per))

def pair_up(xs: List<T>) -> List<T>:
  match xs:
    case Con{a, Con{b, rest}}:
      Node{a, b} <> pair_up(rest)
    case Con{a, Nil{}}:
      [a]
    case Nil{}:
      Nil{}

def levels(k: Nat, xs: List<T>) -> List<T>:
  match k:
    case 0n:
      xs
    case 1n+p:
      levels(p, pair_up(xs))

def root(xs: List<T>) -> T:
  match xs:
    case Con{t, _}:
      t
    case Nil{}:
      Leaf{Nil{}}

# ---------------------------------------------------------------------------
# Sequential fold: counts, linkage, difficulty
# ---------------------------------------------------------------------------

type St is Data:
  St{n: U32, pow: U32, tgt: U32, link: U32, diff: U32, diffn: U32, last: P.H8, have: Bool, win: D.Win}

def inc(b: Bool, +x: U32) -> U32:
  match b:
    case True{}:
      (x + 1 : U32)
    case False{}:
      x

def step(st: St, r: P.HR) -> St:
  St{n, pow, tgt, link, diff, diffn, last, +have, win} = st
  P.HR{p, u, +hash, prev, +time, +bits} = r
  +dc = D.check(win, bits)
  St{(n + 1 : U32), inc(p, pow), inc(u, tgt), inc(have && P.h8_eq(prev, last), link), inc(D.ok(dc), diff), inc(D.applies(dc), diffn), hash, True{}, D.push(win, time, bits)}

def fold(rs: List<P.HR>, st: St) -> St:
  match rs:
    case Con{r, rest}:
      fold(rest, step(st, r))
    case Nil{}:
      st

def bytes_of(r: File & Result<&1, &1, U32 & String, +List<U32>>) -> File & +List<U32>:
  (f, res) = r
  match res:
    case Done{bs}:
      (f, bs)
    case Fail{_}:
      (f, Nil{})

def run!(+d: Nat, t: T) -> RT:
  verify!(d, t)

# Verifies `nb` batches of `per_batch` headers each, starting at batch `i`.
def batches(nb: Nat, f: File, +i: U32, +per_batch: U32, +d: Nat, st: St, +ms: Nat) -> IO(St & Nat):
  match nb:
    case 0n:
      do IO<St & Nat>:
        File.close(f)
        return (st, ms)
    case 1n+p:
      do IO<St & Nat>:
        r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_at(f, (i * per_batch * 1487 : U32), (per_batch * 1487 : U32))
        fb : File & +List<U32> = bytes_of(r)
        (f2, bs) = fb
        +n = U32.to_nat(per_batch)
        +per_leaf = U32.to_nat(U32.max(1, (per_batch >> d : U32)))
        tree : T = root(levels(d, leaves(Nat.pow(2n, d), per_leaf, split(n, bs))))
        t0 : Nat <- IO.now()
        res : RT = verify!(d, tree)
        +rs : List<P.HR> = flatten(res, Nil{})
        t1 : Nat <- IO.now()
        IO.print("batch " ++ U32.show(i) ++ ": " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
        batches(p, f2, (i + 1 : U32), per_batch, d, fold(rs, st), Nat.add(ms, Nat.sub(t1, t0)))

def num(s: String) -> U32:
  Maybe.default(&2, U32, U32.read(s), 0)

def report(x: St & Nat) -> String:
  (st, ms) = x
  St{n, pow, tgt, link, diff, diffn, _, _, _} = st
  "headers " ++ U32.show(n) ++ "\n" ++
  "equihash valid " ++ U32.show(pow) ++ "/" ++ U32.show(n) ++ "\n" ++
  "hash <= target " ++ U32.show(tgt) ++ "/" ++ U32.show(n) ++ "\n" ++
  "prev-hash links " ++ U32.show(link) ++ "/" ++ U32.show((n - 1 : U32)) ++ "\n" ++
  "difficulty (nBits == expected) " ++ U32.show(diff) ++ "/" ++ U32.show(diffn) ++ "\n" ++
  "verify time " ++ Nat.show(ms) ++ " ms"

def go(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{path, Con{cs, Con{bs, Con{ds, _}}}}}:
      +count = num(cs)
      +per_batch = num(bs)
      +d = U32.to_nat(num(ds))
      do IO<Unit>:
        f : File <- IO.try(File, File.open(path, "r"))
        res : St & Nat <- batches(U32.to_nat((count / per_batch : U32)), f, 0, per_batch, d, St{0, 0, 0, 0, 0, 0, P.H8{0, 0, 0, 0, 0, 0, 0, 0}, False{}, D.empty()}, 0n)
        IO.print(report(res))
    case _:
      IO.print("usage: verify <headers.bin> <count> <batch> <depth>")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(args)
