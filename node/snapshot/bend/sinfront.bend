# Zebend snapshot: the Orchard / Ironwood note commitment tree frontier, block by block.
# A copy of node/follow/frontier.bend (Sinsemilla, depth 32; the same push/froot as zcash/state,
# whose frontier = full-tree law is proven in proofs/state), with ONE change: a root line is
# printed after every block, also one that appends 0 leaves, so that a counts file holding a
# single 0 gives the root of the input frontier (the snapshot consumer's root check).
# Usage: sinfront <in.frontier|-> <leaves.bin> <counts.bin> <out.frontier>
#   prints "root <block index> <size> <hex>" per block, then "size <n>", "empty_root <hex>".
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ../../../research/fast/state32/sinsemilla.bend as S

def bytes_of(r: File & Result<&1, &1, U32 & String, +List<U32>>) -> +List<U32>:
  (_, res) = r
  match res:
    case Done{bs}:
      bs
    case Fail{_}:
      Nil{}

def w4(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  U32.or(U32.or(a, U32.shln(b, 8n)), U32.or(U32.shln(c, 16n), U32.shln(d, 24n)))

# little-endian bytes -> u32 words, in order
def words_rev(bs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match bs:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}:
      words_rev(rest, w4(a, b, c, d) <> acc)
    case _:
      acc

def words(+bs: +List<U32>) -> +List<U32>:
  List.reverse(&2, U32, words_rev(bs, Nil{}))

def ws_rev(xs: +List<U32>, acc: +List<Wd.W>) -> +List<Wd.W>:
  match xs:
    case Con{a, Con{b, Con{c, Con{d, Con{e, Con{f, Con{g, Con{h, rest}}}}}}}}:
      ws_rev(rest, Wd.W{a, b, c, d, e, f, g, h} <> acc)
    case _:
      acc

def leaves_of(+bs: +List<U32>) -> +List<Wd.W>:
  List.reverse(&2, Wd.W, ws_rev(words(bs), Nil{}))

def level_of(s: String) -> Maybe<&2, Wd.W>:
  Wd.from_hex(s)

def levels_of(ls: +List<String>) -> +List<Maybe<&2, Wd.W>>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{l, rest}:
      level_of(l) <> levels_of(rest)

def take32(n: Nat, +xs: +List<Maybe<&2, Wd.W>>) -> +List<Maybe<&2, Wd.W>>:
  match n xs:
    case 0n _:
      Nil{}
    case 1n+p Con{+x, rest}:
      x <> take32(p, rest)
    case 1n+p Nil{}:
      None{} <> take32(p, Nil{})

def frontier_of(s: String) -> +List<Maybe<&2, Wd.W>>:
  take32(32n, levels_of(String.split(s, '\n')))

def show_level(m: Maybe<&2, Wd.W>) -> String:
  match m:
    case None{}:
      "-"
    case Some{w}:
      Wd.hex(w)

def show_frontier(lv: +List<Maybe<&2, Wd.W>>) -> String:
  match lv:
    case Nil{}:
      ""
    case Con{+m, rest}:
      show_level(m) ++ "\n" ++ show_frontier(rest)

type St is Data:
  St{+f: +List<Maybe<&2, Wd.W>>, +leaves: +List<Wd.W>, +size: Nat}

def push_one(ls: +List<Wd.W>, +f: +List<Maybe<&2, Wd.W>>, +size: Nat, +g: S.Gens) -> St:
  match ls:
    case Nil{}:
      St{f, Nil{}, size}
    case Con{+w, rest}:
      St{S.push(f, 0n, w, g), rest, 1n+size}

def push_n(n: Nat, s: St, +g: S.Gens) -> St:
  match n:
    case 0n:
      s
    case 1n+p:
      St{+f, +ls, +size} = s
      push_n(p, push_one(ls, f, size, g), g)

def st_f(s: St) -> +List<Maybe<&2, Wd.W>>:
  St{+f, _, _} = s
  f

def st_size(s: St) -> Nat:
  St{_, _, +n} = s
  n

def root_into(any: Bool, +i: Nat, +s: St, +g: S.Gens, +es: +List<Wd.W>, acc: List<String>) -> List<String>:
  match any:
    case True{}:
      ("root " ++ Nat.show(i) ++ " " ++ Nat.show(st_size(s)) ++ " " ++ Wd.hex(S.froot(st_f(s), 0n, None{}, g, es))) <> acc
    case False{}:
      acc

def is_pos(+n: Nat) -> Bool:
  match n:
    case 0n:
      False{}
    case 1n+_:
      True{}

type Out is Type:
  Out{s: St, lines: List<String>}

def blocks(cs: +List<U32>, +i: Nat, s: St, +g: S.Gens, +es: +List<Wd.W>, acc: List<String>) -> Out:
  match cs:
    case Nil{}:
      Out{s, acc}
    case Con{+c, rest}:
      +n = U32.to_nat(c)
      +s2 = push_n(n, s, g)
      blocks(rest, 1n+i, s2, g, es, root_into(True{}, i, s2, g, es, acc))

def print_all(xs: List<String>) -> IO(Unit):
  match xs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{x, rest}:
      do IO<Unit>:
        IO.print(x)
        print_all(rest)

# Root of the empty tree: also a valid anchor (the tree's state before its first note).
def empty_root() -> Wd.W:
  +g = S.gens()
  S.froot(S.frontier_new(), 0n, None{}, g, S.empties(g))

def close_pair(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, _) = r
  File.close(f)

def finish(o: Out, out_path: String) -> IO(Unit):
  Out{+s, lines} = o
  do IO<Unit>:
    print_all(List.reverse(&1, String, lines))
    IO.print("size " ++ Nat.show(st_size(s)))
    IO.print("empty_root " ++ Wd.hex(empty_root()))
    w : File <- IO.try(File, File.open(out_path, "w"))
    wr : File & Result<&1, &1, U32 & String, Unit> <- File.write(w, show_frontier(st_f(s)))
    close_pair(wr)

def text_of(r: File & Result<&1, &1, U32 & String, String>) -> IO(String):
  (f, res) = r
  match res:
    case Done{s}:
      do IO<String>:
        File.close(f)
        return s
    case Fail{_}:
      do IO<String>:
        File.close(f)
        return ""

def read_text_if(dash: Bool, p: String) -> IO(String):
  match dash:
    case True{}:
      IO.pure(String, "")
    case False{}:
      do IO<String>:
        f : File <- IO.try(File, File.open(p, "r"))
        r : File & Result<&1, &1, U32 & String, String> <- File.read(f, 4000)
        text_of(r)

def read_text(+p: String) -> IO(String):
  read_text_if(String.eq(p, "-"), p)

def read_bin(p: String) -> IO(+List<U32>):
  do IO<+List<U32>>:
    f : File <- IO.try(File, File.open(p, "r"))
    r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_bytes(f, 200000000)
    return bytes_of(r)

type Paths is Type:
  Paths{fin: String, leaves: String, counts: String, fout: String}

def paths(xs: List<String>) -> Paths:
  match xs:
    case Con{_, Con{a, Con{b, Con{c, Con{d, _}}}}}:
      Paths{a, b, c, d}
    case _:
      Paths{"-", "", "", ""}

def go(p: Paths) -> IO(Unit):
  Paths{fin, lp, cp, fout} = p
  +g = S.gens()
  +es = S.empties(g)
  do IO<Unit>:
    ft : String <- read_text(fin)
    lb : +List<U32> <- read_bin(lp)
    cb : +List<U32> <- read_bin(cp)
    +f0 : +List<Maybe<&2, Wd.W>> = frontier_of(ft)
    finish(blocks(words(cb), 0n, St{f0, leaves_of(lb), 0n}, g, es, Nil{}), fout)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(paths(args))
