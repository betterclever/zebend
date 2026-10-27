# nf_main NFS N: ingest the first N Sapling nullifiers (36-byte records: u32 height, nf, from
# the oracle's sync) into zcash/state's nullifier set (a binary trie with buckets; its
# insertion law is proven in zcash/state/LAWS.bend), counting nullifiers already present
# (double spends). Then replays the first nullifier, which must be rejected.
# The file is streamed in blocks of 2^16 records.
import Base
import ../../halo2/lib/words.bend as Wd
import ../../state/nfset.bend as N

def w4(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32)

def words_go(bs: List<&2, U32>, acc: +List<U32>) -> +List<U32>:
  match bs:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}:
      words_go(rest, w4(a, b, c, d) <> acc)
    case _:
      List.reverse(&2, U32, acc)

# 9-word records (height, nf): keep nf.
def recs(xs: +List<U32>, acc: +List<Wd.W>) -> +List<Wd.W>:
  match xs:
    case Con{_, Con{a, Con{b, Con{c, Con{d, Con{e, Con{f, Con{g, Con{h, rest}}}}}}}}}:
      recs(rest, Wd.W{a, b, c, d, e, f, g, h} <> acc)
    case _:
      List.reverse(&2, Wd.W, acc)

def bit(+x: U32, k: Nat) -> Bool:
  U32.is_eq(((x >> k) .&. 1 : U32), 1)

def bits_lsb(n: Nat, +x: U32, +k: Nat) -> +List<Bool>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      bit(x, k) <> bits_lsb(p, x, 1n+k)

# Trie key: the low 20 bits of the nullifier (a uniformly distributed hash output).
def key(w: Wd.W) -> +List<Bool>:
  Wd.W{+a, _, _, _, _, _, _, _} = w
  bits_lsb(20n, a, 0n)

def b2n(b: Bool) -> Nat:
  match b:
    case True{}:
      1n
    case False{}:
      0n

type Ing is Data:
  Ing{t: N.NSet, dups: Nat, n: Nat, first: Wd.W}

def ingest(xs: +List<Wd.W>, st: Ing) -> Ing:
  match xs:
    case Nil{}:
      st
    case Con{+v, rest}:
      Ing{+t, +dups, +n, fst} = st
      +k = key(v)
      ingest(rest, Ing{N.ins(k, t, v), Nat.add(dups, b2n(N.member(t, k, v))), 1n+n, fst})

def got(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> File & +List<Wd.W>:
  (fl, res) = r
  match res:
    case Done{bs}:
      (fl, recs(words_go(bs, Nil{}), Nil{}))
    case Fail{_}:
      (fl, Nil{})

def step(fx: File & +List<Wd.W>, st: Ing) -> File & Ing:
  (fl, xs) = fx
  (fl, ingest(xs, st))

def blocks(k: Nat, +i: Nat, +left: Nat, fs: File & Ing) -> IO(File & Ing):
  match k:
    case 0n:
      IO.pure(File & Ing, fs)
    case 1n+p:
      (fl, st) = fs
      +m = Nat.min(left, 65536n)
      do IO<File & Ing>:
        r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(fl, U32.from_nat(Nat.mul(i, Nat.mul(65536n, 36n))), U32.from_nat(Nat.mul(m, 36n)))
        blocks(p, 1n+i, Nat.sub(left, m), step(got(r), st))

def yesno(b: Bool) -> String:
  match b:
    case True{}:
      "REJECTED (already in the set: double spend)"
    case False{}:
      "accepted (BUG: duplicate not detected)"

def first_of(xs: +List<Wd.W>) -> Wd.W:
  match xs:
    case Con{h, _}:
      h
    case Nil{}:
      Wd.zero()

def report(fs: File & Ing, +ms: Nat) -> IO(Unit):
  (fl, st) = fs
  Ing{+t, +dups, +n, +fst} = st
  do IO<Unit>:
    File.close(fl)
    IO.print("ingested " ++ Nat.show(n) ++ " Sapling nullifiers in " ++ Nat.show(ms) ++ " ms; duplicates: " ++ Nat.show(dups))
    IO.print("replaying nullifier " ++ Wd.hex(fst) ++ ": " ++ yesno(N.member(t, key(fst), fst)))

def num(s: String) -> Nat:
  U32.to_nat(Maybe.default(&2, U32, U32.read(s), 0))

def start(f0: File & +List<Wd.W>, +k: Nat, +n: Nat) -> IO(Unit):
  (fl, xs) = f0
  do IO<Unit>:
    t0x : Nat <- IO.now()
    +t0 : Nat = t0x
    res : File & Ing <- blocks(k, 0n, n, (fl, Ing{N.empty(), 0n, 0n, first_of(xs)}))
    t1x : Nat <- IO.now()
    +t1 : Nat = t1x
    report(res, Nat.sub(t1, t0))

def run(path: String, +n: Nat) -> IO(Unit):
  do IO<Unit>:
    fl : File <- IO.try(File, File.open(path, "r"))
    r0 : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(fl, 0, 36)
    start(got(r0), Nat.add(Nat.div(n, 65536n), 1n), n)

def go(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{p, Con{n, _}}}:
      run(p, num(n))
    case _:
      IO.print("usage: nf_main NFS N")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(args)
