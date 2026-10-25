# Zebend full node: the Sprout note commitment tree (depth 29), incrementally, in Bend.
# Usage: sprout <in.frontier|-> <leaves.bin> <counts.bin> <out.frontier>
#   in/out.frontier: 29 lines, one per level: "-" or the pending left node (hex, wire order).
#   leaves.bin: note commitments (32 bytes each, as in the JoinSplit), in tree order.
#   counts.bin: one u32 LE per group (the driver uses one group per JoinSplit, 2 leaves each).
# After each group prints "root <group index> <tree size> <hex>". At the end prints
# "size <n>" and "empty_root <hex>".
# MerkleCRH^Sprout(left, right) = SHA256Compress(left || right): the SHA-256 compression
# function on one 64-byte block with the standard IV and no padding (Zcash protocol spec
# 5.4.1.1); the uncommitted leaf is 32 zero bytes (zcashd SHA256Compress / ZCIncrementalMerkleTree).
import Base
import ../../node/block/sha256.bend as S
import ../../node/block/bytes.bend as Y
import ../../node/block/util.bend as U

def depth() -> Nat:
  29n

def crh(+l: +List<U32>, +r: +List<U32>) -> +List<U32>:
  S.digest(S.compress(S.iv(), Y.append(l, r)))

def empties_go(n: Nat, +e: +List<U32>) -> List<&2, +List<U32>>:
  match n:
    case 0n:
      [e]
    case 1n+p:
      e <> empties_go(p, crh(e, e))

def empties() -> List<&2, +List<U32>>:
  empties_go(depth(), Y.zeros(32n))

def nth(+xs: List<&2, +List<U32>>, n: Nat) -> +List<U32>:
  match xs n:
    case Nil{} _:
      Y.zeros(32n)
    case Con{h, _} 0n:
      h
    case Con{_, t} 1n+k:
      nth(t, k)

def push(lv: List<&2, Maybe<&2, +List<U32>>>, carry: +List<U32>) -> List<&2, Maybe<&2, +List<U32>>>:
  match lv:
    case Nil{}:
      Nil{}
    case Con{m, rest}:
      match m:
        case None{}:
          Some{carry} <> rest
        case Some{left}:
          None{} <> push(rest, crh(left, carry))

def nones(n: Nat) -> List<&2, Maybe<&2, +List<U32>>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      None{} <> nones(p)

def fstep(m: Maybe<&2, +List<U32>>, acc: Maybe<&2, +List<U32>>, +l: Nat, +es: List<&2, +List<U32>>) -> Maybe<&2, +List<U32>>:
  match m:
    case Some{left}:
      match acc:
        case Some{a}:
          Some{crh(left, a)}
        case None{}:
          Some{crh(left, nth(es, l))}
    case None{}:
      match acc:
        case Some{a}:
          Some{crh(a, nth(es, l))}
        case None{}:
          None{}

def froot(lv: List<&2, Maybe<&2, +List<U32>>>, +l: Nat, acc: Maybe<&2, +List<U32>>, +es: List<&2, +List<U32>>) -> +List<U32>:
  match lv:
    case Nil{}:
      match acc:
        case Some{a}:
          a
        case None{}:
          nth(es, depth())
    case Con{m, rest}:
      froot(rest, 1n+l, fstep(m, acc, l, es), es)

# ---------------------------------------------------------------- IO

def bytes_of(r: File & Result<&1, &1, U32 & String, +List<U32>>) -> +List<U32>:
  (_, res) = r
  match res:
    case Done{bs}:
      bs
    case Fail{_}:
      Nil{}

def leaves_rev(n: Nat, +bs: +List<U32>, acc: List<&2, +List<U32>>) -> List<&2, +List<U32>>:
  match n:
    case 0n:
      acc
    case 1n+p:
      leaves_rev(p, Y.drop(bs, 32n), Y.take(bs, 32n) <> acc)

def leaves_of(+bs: +List<U32>) -> List<&2, +List<U32>>:
  List.reverse(&2, +List<U32>, leaves_rev(U32.to_nat((Y.length(bs) / 32 : U32)), bs, Nil{}))

def w4(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  U32.or(U32.or(a, U32.shln(b, 8n)), U32.or(U32.shln(c, 16n), U32.shln(d, 24n)))

def words_rev(bs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match bs:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}:
      words_rev(rest, w4(a, b, c, d) <> acc)
    case _:
      acc

def words(+bs: +List<U32>) -> +List<U32>:
  List.reverse(&2, U32, words_rev(bs, Nil{}))

def level_sel(dash: Bool, s: String) -> Maybe<&2, +List<U32>>:
  match dash:
    case True{}:
      None{}
    case False{}:
      Some{Y.of_hex(s)}

def level_of(+s: String) -> Maybe<&2, +List<U32>>:
  level_sel(String.eq(s, "-") || String.eq(s, ""), s)

def levels_of(n: Nat, ls: +List<String>) -> List<&2, Maybe<&2, +List<U32>>>:
  match n ls:
    case 0n _:
      Nil{}
    case 1n+p Con{l, rest}:
      level_of(l) <> levels_of(p, rest)
    case 1n+p Nil{}:
      None{} <> levels_of(p, Nil{})

def show_level(m: Maybe<&2, +List<U32>>) -> String:
  match m:
    case None{}:
      "-"
    case Some{w}:
      U.bhex(w)

def show_frontier(lv: List<&2, Maybe<&2, +List<U32>>>) -> String:
  match lv:
    case Nil{}:
      ""
    case Con{m, rest}:
      show_level(m) ++ "\n" ++ show_frontier(rest)

type St is Data:
  St{+f: +List<Maybe<&2, +List<U32>>>, +leaves: +List<+List<U32>>, +size: Nat}

def push_one(ls: List<&2, +List<U32>>, f: List<&2, Maybe<&2, +List<U32>>>, +size: Nat) -> St:
  match ls:
    case Nil{}:
      St{f, Nil{}, size}
    case Con{w, rest}:
      St{push(f, w), rest, 1n+size}

def push_n(n: Nat, s: St) -> St:
  match n:
    case 0n:
      s
    case 1n+p:
      St{f, ls, +size} = s
      push_n(p, push_one(ls, f, size))

def st_f(s: St) -> List<&2, Maybe<&2, +List<U32>>>:
  St{f, _, _} = s
  f

def st_size(s: St) -> Nat:
  St{_, _, +n} = s
  n

type Out is Type:
  Out{s: St, lines: List<String>}

def groups(cs: +List<U32>, +i: Nat, s: St, +es: List<&2, +List<U32>>, acc: List<String>) -> Out:
  match cs:
    case Nil{}:
      Out{s, acc}
    case Con{+c, rest}:
      +s2 = push_n(U32.to_nat(c), s)
      groups(rest, 1n+i, s2, es,
        ("root " ++ Nat.show(i) ++ " " ++ Nat.show(st_size(s2)) ++ " " ++ U.bhex(froot(st_f(s2), 0n, None{}, es))) <> acc)

def print_all(xs: List<String>) -> IO(Unit):
  match xs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{x, rest}:
      do IO<Unit>:
        IO.print(x)
        print_all(rest)

def close_pair(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, _) = r
  File.close(f)

def finish(o: Out, out_path: String, +es: List<&2, +List<U32>>) -> IO(Unit):
  Out{+s, lines} = o
  do IO<Unit>:
    print_all(List.reverse(&1, String, lines))
    IO.print("size " ++ Nat.show(st_size(s)))
    IO.print("empty_root " ++ U.bhex(nth(es, depth())))
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
        r : File & Result<&1, &1, U32 & String, String> <- File.read(f, 8000)
        text_of(r)

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
  Paths{+fin, lp, cp, fout} = p
  +es = empties()
  do IO<Unit>:
    ft : String <- read_text_if(String.eq(fin, "-"), fin)
    lb : +List<U32> <- read_bin(lp)
    cb : +List<U32> <- read_bin(cp)
    finish(groups(words(cb), 0n, St{levels_of(depth(), String.split(ft, '\n')), leaves_of(lb), 0n}, es, Nil{}), fout, es)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(paths(args))
