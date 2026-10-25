# Zebend full node: the header hash chain, in Bend.
# Usage: hdrchain <headers file> <byte offset> <count> <prev hash, internal-order hex, or ->
#   Reads <count> 1487-byte headers starting at <byte offset>. For each header prints
#   "h <i> <SHA-256d hash, display order>" and checks that its hashPrevBlock field equals the
#   SHA-256d of the header before it (the first one against <prev hash> unless "-").
#   Ends with "links <ok>/<checked>".
# The driver (fullnode/checkpoints.py) compares the printed hashes at Zebra's checkpoint
# heights with the checkpoint list and keeps the hashes as the node's block-hash index.
import Base
import ../../node/block/sha256.bend as S
import ../../node/block/bytes.bend as Y
import ../../node/block/util.bend as U

def bytes_of(r: File & Result<&1, &1, U32 & String, +List<U32>>) -> +List<U32>:
  (_, res) = r
  match res:
    case Done{bs}:
      bs
    case Fail{_}:
      Nil{}

def rev(xs: +List<U32>) -> +List<U32>:
  Y.reverse(xs)

type Acc is Type:
  Acc{ok: Nat, n: Nat, lines: List<String>}

def bump(b: Bool, +k: Nat) -> Nat:
  match b:
    case True{}:
      1n+k
    case False{}:
      k

def link_ok(+has_prev: Bool, +prev: +List<U32>, +hdr: +List<U32>) -> Bool:
  Bool.not(has_prev) || Y.is_eq(Y.take(Y.drop(hdr, 4n), 32n), prev)

def walk(n: Nat, +i: Nat, +xs: +List<U32>, +has_prev: Bool, +prev: +List<U32>, a: Acc) -> Acc:
  match n:
    case 0n:
      a
    case 1n+m:
      Acc{+k, +c, ls} = a
      +hdr = Y.take(xs, 1487n)
      +h = S.hash_d(hdr)
      +ok = link_ok(has_prev, prev, hdr)
      +c2 = bump(has_prev, c)
      walk(m, 1n+i, Y.drop(xs, 1487n), True{}, h,
           Acc{bump(ok && has_prev, k), c2, ("h " ++ Nat.show(i) ++ " " ++ U.bhex(rev(h))) <> ls})

def print_all(xs: List<String>) -> IO(Unit):
  match xs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{x, rest}:
      do IO<Unit>:
        IO.print(x)
        print_all(rest)

def finish(a: Acc) -> IO(Unit):
  Acc{k, c, ls} = a
  do IO<Unit>:
    print_all(List.reverse(&1, String, ls))
    IO.print("links " ++ Nat.show(k) ++ "/" ++ Nat.show(c))

def or_zero(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{v}:
      v
    case None{}:
      0

def num(s: String) -> U32:
  or_zero(U32.read(s))

type Args is Type:
  Args{path: String, off: String, cnt: String, prev: String}

def args_of(xs: List<String>) -> Args:
  match xs:
    case Con{_, Con{p, Con{o, Con{c, Con{v, _}}}}}:
      Args{p, o, c, v}
    case _:
      Args{"", "0", "0", "-"}

def run(a: Args) -> IO(Unit):
  Args{p, os, cs, +ps} = a
  +cnt = num(cs)
  +dash = String.eq(ps, "-")
  do IO<Unit>:
    f : File <- IO.try(File, File.open(p, "r"))
    r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_at(f, num(os), (cnt * 1487 : U32))
    finish(walk(U32.to_nat(cnt), 0n, bytes_of(r), Bool.not(dash), Y.of_hex(ps), Acc{0n, 0n, Nil{}}))

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<String> <- IO.args()
    run(args_of(xs))
