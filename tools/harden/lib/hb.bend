# Byte-list helpers for the hardened parsers. Bytes are U32 values 0..255.
# Every reader takes the remaining input as a cursor S{bytes, remaining length} and
# answers None on short input, so a parser can never read past the end.
import Base
import ../../../zcash/halo2/lib/words.bend as Wd

type S is Data:
  S{xs: +List<U32>, n: U32}

def len_go(xs: +List<U32>, +acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{_, t}:
      len_go(t, (acc + 1 : U32))

def length(xs: +List<U32>) -> U32:
  len_go(xs, 0)

def start(+xs: +List<U32>) -> S:
  S{xs, length(xs)}

def rem(s: S) -> U32:
  S{_, +n} = s
  n

def bytes_of(s: S) -> +List<U32>:
  S{+xs, _} = s
  xs

def is_done(s: S) -> Bool:
  S{_, +n} = s
  U32.is_eq(n, 0)

def drop_go(xs: +List<U32>, +k: U32, stop: Bool) -> +List<U32>:
  match xs stop:
    case Nil{} _:
      Nil{}
    case Con{h, t} True{}:
      h <> t
    case Con{_, t} False{}:
      drop_go(t, (k - 1 : U32), U32.is_eq((k - 1 : U32), 0))

def drop(xs: +List<U32>, +k: U32) -> +List<U32>:
  drop_go(xs, k, U32.is_eq(k, 0))

def take_go(xs: +List<U32>, +k: U32, stop: Bool) -> +List<U32>:
  match xs stop:
    case Nil{} _:
      Nil{}
    case Con{_, _} True{}:
      Nil{}
    case Con{h, t} False{}:
      h <> take_go(t, (k - 1 : U32), U32.is_eq((k - 1 : U32), 0))

def take(xs: +List<U32>, +k: U32) -> +List<U32>:
  take_go(xs, k, U32.is_eq(k, 0))

def skip_ok(ok: Bool, s: S, +k: U32) -> Maybe<&2, S>:
  match ok:
    case False{}:
      None{}
    case True{}:
      S{+xs, +n} = s
      Some{S{drop(xs, k), (n - k : U32)}}

# Consume k bytes (None if fewer remain).
def skip(+s: S, +k: U32) -> Maybe<&2, S>:
  skip_ok(U32.is_le(k, rem(s)), s, k)

def b0(xs: +List<U32>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{h, _}:
      h

def at(+xs: +List<U32>, +i: U32) -> U32:
  b0(drop(xs, i))

def le16(+xs: +List<U32>) -> U32:
  (at(xs, 0) .|. (at(xs, 1) << 8n) : U32)

def le32(+xs: +List<U32>) -> U32:
  (at(xs, 0) .|. (at(xs, 1) << 8n) .|. (at(xs, 2) << 16n) .|. (at(xs, 3) << 24n) : U32)

type V is Data:
  V{v: U32, s: S}

def val(r: V) -> U32:
  V{+v, _} = r
  v

def st(r: V) -> S:
  V{_, +s} = r
  s

# A fixed-width little-endian field of k <= 4 bytes.
def rd_ok(ok: Bool, s: S, +k: U32) -> Maybe<&2, V>:
  match ok:
    case False{}:
      None{}
    case True{}:
      S{+xs, +n} = s
      Some{V{le32(take(xs, k)), S{drop(xs, k), (n - k : U32)}}}

def rd(+s: S, +k: U32) -> Maybe<&2, V>:
  rd_ok(U32.is_le(k, rem(s)), s, k)

def u8(+s: S) -> Maybe<&2, V>:
  rd(s, 1)

def u32le(+s: S) -> Maybe<&2, V>:
  rd(s, 4)

# The next 32 bytes as 8 little-endian words (call only after checking 32 bytes remain).
def w32(+xs: +List<U32>) -> Wd.W:
  Wd.W{le32(xs), le32(drop(xs, 4)), le32(drop(xs, 8)), le32(drop(xs, 12)),
       le32(drop(xs, 16)), le32(drop(xs, 20)), le32(drop(xs, 24)), le32(drop(xs, 28))}

type W is Data:
  Wv{w: Wd.W, s: S}

def wv_w(r: W) -> Wd.W:
  Wv{+w, _} = r
  w

def wv_s(r: W) -> S:
  Wv{_, +s} = r
  s

def word_ok(ok: Bool, s: S) -> Maybe<&2, W>:
  match ok:
    case False{}:
      None{}
    case True{}:
      S{+xs, +n} = s
      Some{Wv{w32(xs), S{drop(xs, 32), (n - 32 : U32)}}}

# Read a 32-byte encoding.
def word(+s: S) -> Maybe<&2, W>:
  word_ok(U32.is_le(32, rem(s)), s)

# Two 32-bit halves of a little-endian 64-bit integer.
type U64 is Data:
  U64{lo: U32, hi: U32}

type V64 is Data:
  V64{v: U64, s: S}

def v64_v(r: V64) -> U64:
  V64{+v, _} = r
  v

def v64_s(r: V64) -> S:
  V64{_, +s} = r
  s

def rd64_ok(ok: Bool, s: S) -> Maybe<&2, V64>:
  match ok:
    case False{}:
      None{}
    case True{}:
      S{+xs, +n} = s
      Some{V64{U64{le32(xs), le32(drop(xs, 4))}, S{drop(xs, 8), (n - 8 : U32)}}}

def rd64(+s: S) -> Maybe<&2, V64>:
  rd64_ok(U32.is_le(8, rem(s)), s)

def u64_le(a: U64, b: U64) -> Bool:
  U64{+al, +ah} = a
  U64{+bl, +bh} = b
  U32.is_lt(ah, bh) || (U32.is_eq(ah, bh) && U32.is_le(al, bl))

def u64_ge(a: U64, b: U64) -> Bool:
  u64_le(b, a)

# MAX_MONEY = 21,000,000 * 10^8 zatoshis.
def max_money() -> U64:
  U64{1510424576, 489968}

# 2^64 - MAX_MONEY: the smallest u64 whose i64 reading is >= -MAX_MONEY.
def neg_max_money() -> U64:
  U64{2784542720, 4294478351}

# Zatoshis / vpub: 0 <= v <= MAX_MONEY.
def amount_nonneg(+v: U64) -> Bool:
  u64_le(v, max_money())

# ZatBalance: -MAX_MONEY <= v <= MAX_MONEY as a signed 64-bit integer.
def amount_balance(+v: U64) -> Bool:
  u64_le(v, max_money()) || u64_ge(v, neg_max_money())

def guard(ok: Bool, s: S) -> Maybe<&2, S>:
  match ok:
    case True{}:
      Some{s}
    case False{}:
      None{}

def amount_check(nonneg: Bool, r: V64) -> Maybe<&2, S>:
  match nonneg:
    case True{}:
      V64{+v, +s} = r
      guard(amount_nonneg(v), s)
    case False{}:
      V64{+v, +s} = r
      guard(amount_balance(v), s)

# Read an 8-byte amount and range-check it (nonneg: Zatoshis; otherwise ZatBalance).
def amount(+nonneg: Bool, +s: S) -> Maybe<&2, S>:
  do Maybe<&2, S>:
    r : V64 <- rd64(s)
    s2 : S <- amount_check(nonneg, r)
    return s2
