# File reading, byte packing and hex printing shared by the test and verifier mains.
import Base
import ./fq.bend as F

def got(f: File, res: Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(List<&2, U32>):
  match res:
    case Done{bytes}:
      do IO<List<&2, U32>>:
        File.close(f)
        return bytes
    case Fail{e}:
      do IO<List<&2, U32>>:
        File.close(f)
        return Nil{}

def got_pair(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(List<&2, U32>):
  (f, res) = r
  got(f, res)

# Whole file as a list of bytes (empty on any error); at most 256 MB.
def read_all(path: String) -> IO(List<&2, U32>):
  do IO<List<&2, U32>>:
    f : File <- IO.try(File, File.open(path, "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 268435456)
    got_pair(r)

# Little-endian bytes -> U32 words.
def pack4(bs: +List<U32>) -> +List<U32>:
  match bs:
    case Con{+a, Con{+b, Con{+c, Con{+d, rest}}}}:
      (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32) <> pack4(rest)
    case _:
      Nil{}

# Big-endian bytes -> U32 words (each word big-endian), same order.
def pack4be(bs: +List<U32>) -> +List<U32>:
  match bs:
    case Con{+a, Con{+b, Con{+c, Con{+d, rest}}}}:
      ((a << 24n) .|. (b << 16n) .|. (c << 8n) .|. d : U32) <> pack4be(rest)
    case _:
      Nil{}

def w_at(i: Nat, ws: +List<U32>) -> U32:
  match i ws:
    case 0n Con{+h, _}:
      h
    case 1n+k Con{_, t}:
      w_at(k, t)
    case _ Nil{}:
      0

# 12 little-endian words -> raw Fq (missing words read as 0).
def raw_fq(+ws: +List<U32>) -> F.Fq:
  F.Fq{w_at(0n, ws), w_at(1n, ws), w_at(2n, ws), w_at(3n, ws), w_at(4n, ws), w_at(5n, ws), w_at(6n, ws), w_at(7n, ws), w_at(8n, ws), w_at(9n, ws), w_at(10n, ws), w_at(11n, ws)}

# 12 big-endian words (most significant first) -> raw Fq.
def raw_fq_be(+ws: +List<U32>) -> F.Fq:
  F.Fq{w_at(11n, ws), w_at(10n, ws), w_at(9n, ws), w_at(8n, ws), w_at(7n, ws), w_at(6n, ws), w_at(5n, ws), w_at(4n, ws), w_at(3n, ws), w_at(2n, ws), w_at(1n, ws), w_at(0n, ws)}

def hex_digit(+x: U32) -> Char:
  Char.from_u32((x + 48 + 39 * ((x + 6) >> 4n) : U32))

# A U32 as 8 hex digits, most significant first.
def hex8(+x: U32) -> String:
  SCon{hex_digit((x >> 28n : U32)), SCon{hex_digit(((x >> 24n) .&. 15 : U32)), SCon{hex_digit(((x >> 20n) .&. 15 : U32)), SCon{hex_digit(((x >> 16n) .&. 15 : U32)), SCon{hex_digit(((x >> 12n) .&. 15 : U32)), SCon{hex_digit(((x >> 8n) .&. 15 : U32)), SCon{hex_digit(((x >> 4n) .&. 15 : U32)), SCon{hex_digit((x .&. 15 : U32)), SNil{}}}}}}}}}

# Raw Fq words as 96 hex digits, big-endian (the oracle's format).
def hex_raw(a: F.Fq) -> String:
  F.Fq{+a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +a8, +a9, +a10, +a11} = a
  hex8(a11) ++ hex8(a10) ++ hex8(a9) ++ hex8(a8) ++ hex8(a7) ++ hex8(a6) ++ hex8(a5) ++ hex8(a4) ++ hex8(a3) ++ hex8(a2) ++ hex8(a1) ++ hex8(a0)

# A Montgomery element's canonical value as hex.
def hex_fq(a: F.Fq) -> String:
  hex_raw(F.to_raw(a))

# Little-endian words -> consecutive raw Fq values (12 words each; a short tail is dropped).
def fqs(ws: +List<U32>) -> +List<F.Fq>:
  match ws:
    case Con{+a0, Con{+a1, Con{+a2, Con{+a3, Con{+a4, Con{+a5, Con{+a6, Con{+a7, Con{+a8, Con{+a9, Con{+a10, Con{+a11, rest}}}}}}}}}}}}:
      F.Fq{a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11} <> fqs(rest)
    case _:
      Nil{}
