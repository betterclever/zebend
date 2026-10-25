# Byte strings as lists of U32 values in 0..255, the representation Bend's TCP and
# File effects use (TCP.send_bytes / recv_bytes, File.write_bytes).
import Base

type U64 is Data:
  U64{lo: U32, hi: U32}

def append(xs: +List<U32>, ys: +List<U32>) -> +List<U32>:
  match xs:
    case Nil{}:
      ys
    case Con{h, t}:
      h <> append(t, ys)

def len_go(xs: +List<U32>, +acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{_, t}:
      len_go(t, (acc + 1 : U32))


def length(xs: +List<U32>) -> U32:
  len_go(xs, 0)

def take(xs: +List<U32>, n: Nat) -> +List<U32>:
  match xs n:
    case Nil{} _:
      Nil{}
    case Con{h, t} 0n:
      Nil{}
    case Con{h, t} 1n+p:
      h <> take(t, p)

def drop(xs: +List<U32>, n: Nat) -> +List<U32>:
  match xs n:
    case Nil{} _:
      Nil{}
    case Con{h, t} 0n:
      h <> t
    case Con{_, t} 1n+p:
      drop(t, p)

def take_u(xs: +List<U32>, +n: U32) -> +List<U32>:
  take(xs, U32.to_nat(n))

def drop_u(xs: +List<U32>, +n: U32) -> +List<U32>:
  drop(xs, U32.to_nat(n))

def reverse_go(xs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      reverse_go(t, h <> acc)

def reverse(xs: +List<U32>) -> +List<U32>:
  reverse_go(xs, Nil{})

def is_eq(xs: +List<U32>, ys: +List<U32>) -> Bool:
  match xs ys:
    case Nil{} Nil{}:
      True{}
    case Con{a, s} Con{b, t}:
      Bool.and(U32.is_eq(a, b), is_eq(s, t))
    case _ _:
      False{}

# Little-endian encodings.
def le16(+x: U32) -> +List<U32>:
  [(x .&. 255 : U32), ((x >> 8n) .&. 255 : U32)]

def be16(+x: U32) -> +List<U32>:
  [((x >> 8n) .&. 255 : U32), (x .&. 255 : U32)]

def le32(+x: U32) -> +List<U32>:
  [(x .&. 255 : U32), ((x >> 8n) .&. 255 : U32), ((x >> 16n) .&. 255 : U32), (x >> 24n : U32)]

def le64(x: U64) -> +List<U32>:
  U64{lo, hi} = x
  append(le32(lo), le32(hi))

def get_u8(xs: +List<U32>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{h, _}:
      h

# Reads a little-endian U32 from the first four bytes (missing bytes read as 0).
def get_le32(xs: +List<U32>) -> U32:
  match xs:
    case Con{a, Con{b, Con{c, Con{d, _}}}}:
      (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32)
    case _:
      0

def get_le16(xs: +List<U32>) -> U32:
  match xs:
    case Con{a, Con{b, _}}:
      (a .|. (b << 8n) : U32)
    case _:
      0

def get_le64(+xs: +List<U32>) -> U64:
  U64{get_le32(xs), get_le32(drop(xs, 4n))}

# Bitcoin/Zcash CompactSize (values below 2^32).
def compact_big(mid: Bool, +n: U32) -> +List<U32>:
  match mid:
    case True{}:
      253 <> le16(n)
    case False{}:
      254 <> le32(n)


def compact_sel(small: Bool, +n: U32) -> +List<U32>:
  match small:
    case True{}:
      [n]
    case False{}:
      compact_big(U32.is_lt(n, 65536), n)

def compact(+n: U32) -> +List<U32>:
  compact_sel(U32.is_lt(n, 253), n)

# A decoded CompactSize: the value and how many bytes it occupied.
type Compact is Data:
  Compact{value: U32, width: U32}

# CompactSize exactly as zcash_encoding::CompactSize::read accepts it (merged from
# harden/lib/cs.bend): the bytes must be present, the encoding canonical (fd + u16 needs
# >= 253, fe + u32 needs >= 2^16, ff + u64 always exceeds the cap) and the value
# <= MAX_COMPACT_SIZE = 0x02000000. Failure is Compact{0, 0}: width 0 means "malformed",
# and callers must treat it as a protocol error.
def compact_max() -> U32:
  33554432

# At least n elements, looking at no more than n of them.
def has(xs: +List<U32>, n: Nat) -> Bool:
  match xs n:
    case _ 0n:
      True{}
    case Nil{} 1n+p:
      False{}
    case Con{_, t} 1n+p:
      has(t, p)

def compact_ok(ok: Bool, +v: U32, +w: U32) -> Compact:
  match ok:
    case True{}:
      Compact{v, w}
    case False{}:
      Compact{0, 0}

def read_compact_wide(is16: Bool, +rest: +List<U32>) -> Compact:
  match is16:
    case True{}:
      +v = get_le16(rest)
      compact_ok(has(rest, 2n) && U32.is_le(253, v), v, 3)
    case False{}:
      +v = get_le32(rest)
      compact_ok(has(rest, 4n) && U32.is_le(65536, v) && U32.is_le(v, compact_max()), v, 5)

def read_compact_big(is255: Bool, +b: U32, +rest: +List<U32>) -> Compact:
  match is255:
    case True{}:
      Compact{0, 0}
    case False{}:
      read_compact_wide(U32.is_eq(b, 253), rest)

def read_compact_sel(small: Bool, +b: U32, +rest: +List<U32>) -> Compact:
  match small:
    case True{}:
      Compact{b, 1}
    case False{}:
      read_compact_big(U32.is_eq(b, 255), b, rest)

def read_compact_nonempty(ok: Bool, +xs: +List<U32>) -> Compact:
  match ok:
    case False{}:
      Compact{0, 0}
    case True{}:
      +b = get_u8(xs)
      read_compact_sel(U32.is_lt(b, 253), b, drop(xs, 1n))

def read_compact(+xs: +List<U32>) -> Compact:
  read_compact_nonempty(has(xs, 1n), xs)

# ASCII text <-> bytes.
def of_string(s: String) -> +List<U32>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{c, t}:
      Char.to_u32(c) <> of_string(t)

def to_string(xs: +List<U32>) -> String:
  match xs:
    case Nil{}:
      SNil{}
    case Con{h, t}:
      SCon{Char.from_u32(h), to_string(t)}

# Text up to the first NUL (a P2P command field).
def cut_sel(nul: Bool, +h: U32, rest: +List<U32>) -> +List<U32>:
  match nul:
    case True{}:
      Nil{}
    case False{}:
      h <> rest

# Bytes up to (not including) the first NUL.
def until_nul(xs: +List<U32>) -> +List<U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+h, t}:
      cut_sel(U32.is_eq(h, 0), h, until_nul(t))

def to_cstring(xs: +List<U32>) -> String:
  to_string(until_nul(xs))

def zeros(n: Nat) -> +List<U32>:
  List.replicate(U32, n, 0)

def hex_digit(+x: U32) -> Char:
  Char.from_u32((x + 48 + 39 * ((x + 6) >> 4n) : U32))

def hex(xs: +List<U32>) -> String:
  match xs:
    case Nil{}:
      SNil{}
    case Con{+h, t}:
      SCon{hex_digit((h >> 4n : U32)), SCon{hex_digit((h .&. 15 : U32)), hex(t)}}

# Display order for hashes: reversed bytes, as block explorers print them.
def hex_rev(xs: +List<U32>) -> String:
  hex(reverse(xs))

def hex_val(+c: Char) -> U32:
  +x = Char.to_u32(c)
  ((x .&. 15) + 9 * (x >> 6n) : U32)

def of_hex(s: String) -> +List<U32>:
  match s:
    case SCon{a, SCon{b, t}}:
      ((hex_val(a) << 4n) .|. hex_val(b) : U32) <> of_hex(t)
    case _:
      Nil{}
