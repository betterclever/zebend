# zebend follow: the Ironwood nullifier set as 256 bucket files, checked and extended in Bend.
# Usage: nfb <dir> <new.bin> <check|append>
#   <dir>/<k>.bin (k = 0..255): every known nullifier whose first byte is k, 32 bytes each.
#   new.bin: the new nullifiers (32 bytes each).
# Only the buckets that new nullifiers fall in are read. Each one is ingested into
# node/state's nullifier set (nfset.bend, with nf_main's ingest, the code nf_check uses),
# then its new nullifiers are ingested on top, counting
#   misrouted: old entries whose first byte is not the bucket's (a corrupted store),
#   old_dups:  duplicates among the old entries,
#   new_dups:  new nullifiers already in the set or repeated among the new ones.
# Prints "nfb new N buckets T old E misrouted M old_dups D0 new_dups D". In append mode, and
# only if M, D0 and D are all 0, appends each bucket's new nullifiers to its file and prints
# "appended N"; a store is extended only by this program.
import Base
import ../halo2/lib/words.bend as Wd
import ../node/state/nfset.bend as N
import ../node/state/nf_main.bend as M

def bucket_of(w: Wd.W) -> U32:
  Wd.W{+a, _, _, _, _, _, _, _} = w
  U32.and(a, 255)

def keep(k: Bool, +x: Wd.W, rest: +List<Wd.W>) -> +List<Wd.W>:
  match k:
    case True{}:
      x <> rest
    case False{}:
      rest

def in_b(+b: U32, xs: +List<Wd.W>) -> +List<Wd.W>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      keep(U32.is_eq(bucket_of(x), b), x, in_b(b, rest))

def off_n(b: Bool) -> Nat:
  match b:
    case True{}:
      0n
    case False{}:
      1n

def misrouted(+b: U32, xs: +List<Wd.W>, acc: Nat) -> Nat:
  match xs:
    case Nil{}:
      acc
    case Con{+x, rest}:
      misrouted(b, rest, Nat.add(acc, off_n(U32.is_eq(bucket_of(x), b))))

def ing_dups(i: M.Ing) -> Nat:
  M.Ing{_, +d} = i
  d

def ing_set(i: M.Ing) -> N.NSet:
  M.Ing{+t, _} = i
  t

# Little-endian bytes of the nullifiers (the same layout as the files).
def u32_bytes(+w: U32, rest: +List<U32>) -> +List<U32>:
  U32.and(w, 255) <> U32.and(U32.shrn(w, 8n), 255) <> U32.and(U32.shrn(w, 16n), 255) <> U32.shrn(w, 24n) <> rest

def w_bytes(w: Wd.W, rest: +List<U32>) -> +List<U32>:
  Wd.W{+a, +b, +c, +d, +e, +f, +g, +h} = w
  u32_bytes(a, u32_bytes(b, u32_bytes(c, u32_bytes(d, u32_bytes(e, u32_bytes(f, u32_bytes(g, u32_bytes(h, rest))))))))

def bytes_of(xs: +List<Wd.W>) -> +List<U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, rest}:
      w_bytes(x, bytes_of(rest))

type Tot is Type:
  Tot{buckets: Nat, old: Nat, mis: Nat, d0: Nat, d: Nat}

def path(+dir: String, +k: Nat) -> String:
  dir ++ "/" ++ Nat.show(k) ++ ".bin"

def add_bucket(t: Tot, +b: U32, +old: +List<Wd.W>, +nb: +List<Wd.W>) -> Tot:
  Tot{+bs, +o, +m, +d0, +d} = t
  +i0 = M.ingest(old, N.empty(), 0n)
  +i1 = M.ingest(nb, ing_set(i0), 0n)
  Tot{1n+bs, Nat.add(o, List.length(&2, Wd.W, old)), misrouted(b, old, m), Nat.add(d0, ing_dups(i0)), Nat.add(d, ing_dups(i1))}

def read_bucket(+p: String) -> IO(+List<Wd.W>):
  do IO<+List<Wd.W>>:
    f : File <- IO.try(File, File.open(p, "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 33554432)
    return M.nfs_of(r)

def is_nil(xs: +List<Wd.W>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{_, _}:
      False{}

def check_one(skip: Bool, +dir: String, +k: Nat, +nb: +List<Wd.W>, t: Tot) -> IO(Tot):
  match skip:
    case True{}:
      IO.pure(Tot, t)
    case False{}:
      do IO<Tot>:
        old : +List<Wd.W> <- read_bucket(path(dir, k))
        return add_bucket(t, U32.from_nat(k), old, nb)

def check_all(n: Nat, +dir: String, +news: +List<Wd.W>, t: Tot) -> IO(Tot):
  match n:
    case 0n:
      IO.pure(Tot, t)
    case 1n+k:
      +j = k
      +nb = in_b(U32.from_nat(j), news)
      do IO<Tot>:
        t2 : Tot <- check_one(is_nil(nb), dir, j, nb, t)
        check_all(j, dir, news, t2)

def close_pair(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, _) = r
  File.close(f)

def append_one(skip: Bool, +dir: String, +k: Nat, +nb: +List<Wd.W>) -> IO(Unit):
  match skip:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        f : File <- IO.try(File, File.open(path(dir, k), "a"))
        r : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, bytes_of(nb))
        close_pair(r)

def append_all(n: Nat, +dir: String, +news: +List<Wd.W>) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+k:
      +j = k
      +nb = in_b(U32.from_nat(j), news)
      do IO<Unit>:
        append_one(is_nil(nb), dir, j, nb)
        append_all(j, dir, news)

def zero_n(+n: Nat) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+_:
      False{}

def line(+n: Nat, +bs: Nat, +o: Nat, +m: Nat, +d0: Nat, +d: Nat) -> String:
  "nfb new " ++ Nat.show(n) ++ " buckets " ++ Nat.show(bs) ++ " old " ++ Nat.show(o) ++ " misrouted " ++ Nat.show(m) ++ " old_dups " ++ Nat.show(d0) ++ " new_dups " ++ Nat.show(d)

def finish(ok: Bool, +dir: String, +news: +List<Wd.W>) -> IO(Unit):
  match ok:
    case True{}:
      do IO<Unit>:
        append_all(256n, dir, news)
        IO.print("appended " ++ Nat.show(List.length(&2, Wd.W, news)))
    case False{}:
      IO.print("not appended")

def report(+append: Bool, +dir: String, +news: +List<Wd.W>, t: Tot) -> IO(Unit):
  Tot{+bs, +o, +m, +d0, +d} = t
  do IO<Unit>:
    IO.print(line(List.length(&2, Wd.W, news), bs, o, m, d0, d))
    finish(append && zero_n(Nat.add(m, Nat.add(d0, d))), dir, news)

type Args is Type:
  Args{dir: String, new: String, mode: String}

def args_of(xs: List<String>) -> Args:
  match xs:
    case Con{_, Con{a, Con{b, Con{c, _}}}}:
      Args{a, b, c}
    case _:
      Args{"", "", "check"}

def go(a: Args) -> IO(Unit):
  Args{+dir, np, +mode} = a
  do IO<Unit>:
    f : File <- IO.try(File, File.open(np, "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 67108864)
    +news : +List<Wd.W> = M.nfs_of(r)
    t : Tot <- check_all(256n, dir, news, Tot{0n, 0n, 0n, 0n, 0n})
    report(String.eq(mode, "append"), dir, news, t)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(args_of(args))
