# EXPERIMENT (research/flatio): SHA-256d of every transaction in a file made by mk_txs.py
# (count ‖ (len ‖ tx padded to 4)*), R times; prints the XOR of each digest's first word.
#   mode "l": File.read_bytes + the live list SHA-256 (each tx taken as its own list, as the
#             legacy sighash serializes one)
#   mode "a": File.read_words + sha256_arr.bend at the tx's word offset (no copy)
import Base
import ../../zcash/block/bytes.bend as By
import ../../zcash/transparent/sighash2/sha256.bend as S
import ./sha256_arr.bend as A

def digit(c: Char) -> U32:
  (Char.to_u32(c) - 48 : U32)

def num_go(s: String, +acc: U32) -> U32:
  match s:
    case SNil{}:
      acc
    case SCon{c, t}:
      num_go(t, (acc * 10 + digit(c) : U32))

def w0(+h: +List<U32>) -> U32:
  match h:
    case Con{a, Con{b, Con{c, Con{d, _}}}}:
      ((a << 24n) .|. (b << 16n) .|. (c << 8n) .|. d : U32)
    case _:
      0

def pad4(+n: U32) -> U32:
  ((n + 3) .&. 4294967292 : U32)

# list mode: n transactions from xs
def txs_l(n: Nat, +xs: +List<U32>, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      +len = By.get_le32(xs)
      +rest = By.drop(xs, 4n)
      +h = S.hash_d(By.take_u(rest, len))
      txs_l(p, By.drop_u(rest, pad4(len)), (acc .^. w0(h) : U32))

def rep_l(n: Nat, +xs: +List<U32>, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      rep_l(p, xs, txs_l(U32.to_nat(By.get_le32(xs)), By.drop(xs, 4n), acc))

# array mode: the array, the word offset of the next transaction, the checksum
type St is Type:
  St{a: Array<U32>, o: U32, acc: U32}

def s8a(st: S.S8) -> U32:
  S.S8{a, _, _, _, _, _, _, _} = st
  a

def step.k2(r: Array<U32> & S.S8, +o: U32, +len: U32, +acc: U32) -> St:
  (a, st) = r
  St{a, (o + 1 + (pad4(len) >> 2n) : U32), (acc .^. s8a(st) : U32)}

def step.k1(r: Array<U32> & U32, +o: U32, +acc: U32) -> St:
  (a, +len) = r
  step.k2(A.hash_d_at(a, (o + 1 : U32), len), o, len, acc)

def step(st: St) -> St:
  St{a, +o, +acc} = st
  step.k1(a[o], o, acc)

def txs_a(n: Nat, st: St) -> St:
  match n:
    case 0n:
      st
    case 1n+p:
      txs_a(p, step(st))

def rep_a.go(r: Array<U32> & U32, +acc: U32) -> St:
  (a, +cnt) = r
  txs_a(U32.to_nat(cnt), St{a, 1, acc})

def rep_a(n: Nat, st: St) -> U32:
  match n:
    case 0n:
      St{a, o, acc} = st
      acc
    case 1n+p:
      St{a, o, +acc} = st
      rep_a(p, rep_a.go(a[0], acc))

def run_a(an: Array<U32> & U32, +n: Nat) -> U32:
  (a, len) = an
  rep_a(n, St{a, 0, 0})

law got_l:
  for m: File & Result<&1, &1, U32 & String, List<&2, U32>>
  for +n: Nat
  IO(Unit)

def got_l(m, n):
  (f, r) = m
  do IO<Unit>:
    xs : List<&2, U32> <- IO.pass(List<&2, U32>, r)
    IO.print(U32.show(rep_l(n, xs, 0)))
    File.close(f)

law got_a:
  for m: File & Result<&1, &1, U32 & String, Array<U32> & U32>
  for +n: Nat
  IO(Unit)

def got_a(m, n):
  (f, r) = m
  do IO<Unit>:
    an : Array<U32> & U32 <- IO.pass(Array<U32> & U32, r)
    IO.print(U32.show(run_a(an, n)))
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
      IO.print("usage: tx_bench FILE l|a REPS")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
