# EXPERIMENT (research/flatio): SHA-256d of a file, R times, through
#   mode "l": File.read_bytes (one List cell per byte) + the live list SHA-256 (sighash2/sha256.bend)
#   mode "a": File.read_words (flat Array<U32>)        + sha256_arr.bend
# Usage: hash_bench FILE MODE R   (prints the last digest, hex)
import Base
import ../../zcash/transparent/util.bend as U
import ../../zcash/transparent/sighash2/sha256.bend as S
import ./sha256_arr.bend as A

def last(xs: List<String>, d: String) -> String:
  match xs:
    case Con{x, t}:
      last(t, x)
    case Nil{}:
      d

def nth(xs: List<String>, n: Nat) -> String:
  match xs n:
    case Con{x, t} 0n:
      x
    case Con{x, t} 1n+p:
      nth(t, p)
    case Nil{} _:
      ""

def digit(c: Char) -> U32:
  (Char.to_u32(c) - 48 : U32)

def num_go(s: String, +acc: U32) -> U32:
  match s:
    case SNil{}:
      acc
    case SCon{c, t}:
      num_go(t, (acc * 10 + digit(c) : U32))

def s8_hex(st: S.S8) -> String:
  U.hex(S.digest(st))

# list mode
def rep_l(n: Nat, +xs: +List<U32>, +h: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      h
    case 1n+p:
      rep_l(p, xs, S.hash_d(xs))

# array mode
def rep_a(n: Nat, r: Array<U32> & S.S8, +len: U32) -> S.S8:
  match n:
    case 0n:
      (a, st) = r
      st
    case 1n+p:
      (a, st) = r
      rep_a(p, A.hash_d(a, len), len)

law got_l:
  for m: File & Result<&1, &1, U32 & String, List<&2, U32>>
  for +n: Nat
  IO(Unit)

def got_l(m, n):
  (f, r) = m
  do IO<Unit>:
    xs : List<&2, U32> <- IO.pass(List<&2, U32>, r)
    IO.print(U.hex(rep_l(n, xs, Nil{})))
    File.close(f)

def run_a(an: Array<U32> & U32, +n: Nat) -> String:
  (a, +len) = an
  s8_hex(rep_a(n, (a, S.iv()), len))

law got_a:
  for m: File & Result<&1, &1, U32 & String, Array<U32> & U32>
  for +n: Nat
  IO(Unit)

def got_a(m, n):
  (f, r) = m
  do IO<Unit>:
    an : Array<U32> & U32 <- IO.pass(Array<U32> & U32, r)
    IO.print(run_a(an, n))
    File.close(f)

law sized:
  for p: File & Result<&1, &1, U32 & String, U32>
  for arr: Bool
  for +n: Nat
  IO(Unit)

def sized(p, arr, n):
  (f, r) = p
  match arr:
    case True{}:
      do IO<Unit>:
        sz : U32 <- IO.pass(U32, r)
        m : File & Result<&1, &1, U32 & String, Array<U32> & U32> <- File.read_words(f, sz)
        got_a(m, n)
    case False{}:
      do IO<Unit>:
        sz : U32 <- IO.pass(U32, r)
        m : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, sz)
        got_l(m, n)

def run(a: List<String>) -> IO(Unit):
  match a:
    case [_, path, mode, reps]:
      do IO<Unit>:
        f : File <- IO.try(File, File.open(path, "r"))
        p : File & Result<&1, &1, U32 & String, U32> <- File.size(f)
        sized(p, String.eq(mode, "a"), U32.to_nat(num_go(reps, 0)))
    case _:
      IO.print("usage: hash_bench FILE l|a REPS")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
