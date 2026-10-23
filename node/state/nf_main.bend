# Ingest every mainnet Ironwood nullifier into the Bend nullifier set and count
# double spends; then replay one real nullifier to show it is caught.
import Base
import ../../halo2/lib/words.bend as Wd
import ./nfset.bend as N
import ./checkpoints.bend as CK

def w4(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  U32.or(U32.or(a, U32.shln(b, 8n)), U32.or(U32.shln(c, 16n), U32.shln(d, 24n)))

def words_of(bs: List<&2, U32>, acc: +List<U32>) -> +List<U32>:
  match bs:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}:
      words_of(rest, w4(a, b, c, d) <> acc)
    case _:
      acc

def ws_of(xs: +List<U32>, acc: +List<Wd.W>) -> +List<Wd.W>:
  match xs:
    case Con{a, Con{b, Con{c, Con{d, Con{e, Con{f, Con{g, Con{h, rest}}}}}}}}:
      ws_of(rest, Wd.W{a, b, c, d, e, f, g, h} <> acc)
    case _:
      acc

def nfs_of(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> +List<Wd.W>:
  (_, res) = r
  match res:
    case Done{bs}:
      List.reverse(&2, Wd.W, ws_of(List.reverse(&2, U32, words_of(bs, Nil{})), Nil{}))
    case Fail{_}:
      Nil{}

def bit(+x: U32, k: Nat) -> Bool:
  U32.is_eq(U32.and(U32.shrn(x, k), 1), 1)

def bits_lsb(n: Nat, +x: U32, +k: Nat) -> +List<Bool>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      bit(x, k) <> bits_lsb(p, x, 1n+k)

# Trie key: the low 16 bits of the nullifier (it is a uniformly distributed field element).
def key(w: Wd.W) -> +List<Bool>:
  Wd.W{+a, _, _, _, _, _, _, _} = w
  bits_lsb(16n, a, 0n)

def b2n(b: Bool) -> Nat:
  match b:
    case True{}:
      1n
    case False{}:
      0n

type Ing is Data:
  Ing{t: N.NSet, dups: Nat}

def ingest(xs: +List<Wd.W>, +t: N.NSet, dups: Nat) -> Ing:
  match xs:
    case Nil{}:
      Ing{t, dups}
    case Con{+v, rest}:
      +k = key(v)
      ingest(rest, N.ins(k, t, v), Nat.add(dups, b2n(N.member(t, k, v))))

def first(xs: +List<Wd.W>) -> Wd.W:
  match xs:
    case Nil{}:
      Wd.zero()
    case Con{h, _}:
      h

def yesno(b: Bool) -> String:
  match b:
    case True{}:
      "REJECTED (nullifier already in the set: double spend)"
    case False{}:
      "accepted (BUG: duplicate not detected)"

def report(i: Ing, +replay: Wd.W) -> IO(Unit):
  Ing{+t, dups} = i
  do IO<Unit>:
    IO.print("duplicate nullifiers on mainnet: " ++ Nat.show(dups))
    IO.print("replaying nullifier " ++ Wd.hex(replay) ++ ": " ++ yesno(N.member(t, key(replay), replay)))

def go(path: String) -> IO(Unit):
  +n = CK.leaf_count()
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, (n * 32 : U32))
    +nfs : +List<Wd.W> = nfs_of(r)
    IO.print("ingesting " ++ Nat.show(List.length(&2, Wd.W, nfs)) ++ " Ironwood nullifiers (mainnet blocks 3428143..3528268)")
    t0 : Nat <- IO.now()
    +res : Ing = ingest(nfs, N.empty(), 0n)
    t1 : Nat <- IO.now()
    IO.print("built the nullifier set in " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
    report(res, first(nfs))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(Maybe.default(&1, String, List.get(&1, String, args, 1n), "out/nf.bin"))
