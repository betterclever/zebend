# Double-spend check for one transaction against the mainnet Ironwood nullifier set.
# Usage: nf_check <mainnet_nf.bin> <tx_nfs.bin>
#   Ingests every mainnet nullifier into node/state's nullifier set (counting duplicates),
#   then, for each of the transaction's nullifiers, reports set membership and its exact
#   number of occurrences in the mainnet list.
import Base
import ../halo2/lib/words.bend as Wd
import ../node/state/nfset.bend as N
import ../node/state/nf_main.bend as M

def count_in(xs: +List<Wd.W>, +v: Wd.W, acc: Nat) -> Nat:
  match xs:
    case Nil{}:
      acc
    case Con{+h, rest}:
      count_in(rest, v, Nat.add(acc, M.b2n(Wd.is_eq(h, v))))

def yn(b: Bool) -> String:
  match b:
    case True{}:
      "yes"
    case False{}:
      "no"

def lines(qs: +List<Wd.W>, +t: N.NSet, +all: +List<Wd.W>) -> List<String>:
  match qs:
    case Nil{}:
      Nil{}
    case Con{+q, rest}:
      ("nf " ++ Wd.hex(q) ++ " member " ++ yn(N.member(t, M.key(q), q)) ++ " occurrences " ++ Nat.show(count_in(all, q, 0n))) <> lines(rest, t, all)

def print_all(xs: List<String>) -> IO(Unit):
  match xs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{l, rest}:
      do IO<Unit>:
        IO.print(l)
        print_all(rest)

def report(i: M.Ing, +all: +List<Wd.W>, +qs: +List<Wd.W>) -> IO(Unit):
  M.Ing{+t, +dups} = i
  do IO<Unit>:
    IO.print("mainnet nullifiers " ++ Nat.show(List.length(&2, Wd.W, all)) ++ " duplicates " ++ Nat.show(dups))
    print_all(lines(qs, t, all))

def finish(+all: +List<Wd.W>, +qs: +List<Wd.W>) -> IO(Unit):
  report(M.ingest(all, N.empty(), 0n), all, qs)

type Paths is Type:
  Paths{all: String, tx: String}

def paths(xs: List<String>) -> Paths:
  match xs:
    case Con{_, Con{a, Con{b, _}}}:
      Paths{a, b}
    case _:
      Paths{"", ""}

def go(p: Paths) -> IO(Unit):
  Paths{ap, tp} = p
  do IO<Unit>:
    f : File <- IO.try(File, File.open(ap, "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 33554432)
    g : File <- IO.try(File, File.open(tp, "r"))
    s : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(g, 4096)
    finish(M.nfs_of(r), M.nfs_of(s))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(paths(args))
