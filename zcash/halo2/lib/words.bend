# 256-bit values as 8 little-endian U32 words: the canonical encoding shared by
# fp.bend, fq.bend, vesta.bend and the verifier (see ../CONTRACT.md).
import Base

type W is Data:
  W{w0: U32, w1: U32, w2: U32, w3: U32, w4: U32, w5: U32, w6: U32, w7: U32}

def zero() -> W:
  W{0, 0, 0, 0, 0, 0, 0, 0}

def is_eq(a: W, b: W) -> Bool:
  W{a0, a1, a2, a3, a4, a5, a6, a7} = a
  W{b0, b1, b2, b3, b4, b5, b6, b7} = b
  +x = ((a0 .^. b0) .|. (a1 .^. b1) .|. (a2 .^. b2) .|. (a3 .^. b3) .|. (a4 .^. b4) .|. (a5 .^. b5) .|. (a6 .^. b6) .|. (a7 .^. b7) : U32)
  U32.is_eq(x, 0)

# a_i < b_i, or a_i == b_i and the lower words already compared less.
def lt_step(+a: U32, +b: U32, lower: Bool) -> Bool:
  Bool.or(U32.is_lt(a, b), Bool.and(U32.is_eq(a, b), lower))

# Unsigned 256-bit a < b.
def is_lt(a: W, b: W) -> Bool:
  W{a0, a1, a2, a3, a4, a5, a6, a7} = a
  W{b0, b1, b2, b3, b4, b5, b6, b7} = b
  l0 = lt_step(a0, b0, False{})
  l1 = lt_step(a1, b1, l0)
  l2 = lt_step(a2, b2, l1)
  l3 = lt_step(a3, b3, l2)
  l4 = lt_step(a4, b4, l3)
  l5 = lt_step(a5, b5, l4)
  l6 = lt_step(a6, b6, l5)
  lt_step(a7, b7, l6)

def low_bit(w: W) -> U32:
  W{a, _, _, _, _, _, _, _} = w
  (a .&. 1 : U32)

def top_bit(w: W) -> U32:
  W{_, _, _, _, _, _, _, h} = w
  (h >> 31n : U32)

def clear_top_bit(w: W) -> W:
  W{a, b, c, d, e, f, g, h} = w
  W{a, b, c, d, e, f, g, (h .&. 2147483647 : U32)}

def set_top_bit(w: W, +b: U32) -> W:
  W{a0, a1, a2, a3, a4, a5, a6, a7} = w
  W{a0, a1, a2, a3, a4, a5, a6, (a7 .|. (b << 31n) : U32)}

# x in 0..15 -> '0'..'9', 'a'..'f' ((x + 6) >> 4 is 1 exactly when x >= 10).
def hex_digit(+x: U32) -> Char:
  Char.from_u32((x + 48 + 39 * ((x + 6) >> 4n) : U32))

def hex_byte(+b: U32) -> String:
  SCon{hex_digit((b >> 4n : U32)), SCon{hex_digit((b .&. 15 : U32)), SNil{}}}

def hex_u32(+x: U32) -> String:
  hex_byte((x .&. 255 : U32)) ++ hex_byte(((x >> 8n) .&. 255 : U32)) ++ hex_byte(((x >> 16n) .&. 255 : U32)) ++ hex_byte((x >> 24n : U32))

def hex_val(+c: Char) -> U32:
  +x = Char.to_u32(c)
  # '0'..'9' -> 0..9, 'a'..'f' / 'A'..'F' -> 10..15
  ((x .&. 15) + 9 * (x >> 6n) : U32)

type HexSt is Data:
  HexSt{+n: U32, +acc: U32, ws: +List<U32>}

# Nibble n of a word (n = 0..7) sits at bit 4 * (n xor 1): bytes are little-endian,
# and inside each byte the high nibble comes first.
def hex_shift(+n: U32) -> U32:
  (4 * (n .^. 1) : U32)

def hex_push(full: Bool, +acc: U32, +n: U32, ws: +List<U32>) -> HexSt:
  match full:
    case True{}:
      HexSt{0, 0, acc <> ws}
    case False{}:
      HexSt{(n + 1 : U32), acc, ws}

def hex_step(+c: Char, st: HexSt) -> HexSt:
  HexSt{+n, +acc, ws} = st
  hex_push(U32.is_eq(n, 7), (acc .|. (hex_val(c) << U32.to_nat(hex_shift(n))) : U32), n, ws)

def hex_go(s: String, st: HexSt) -> HexSt:
  match s:
    case SCon{c, t}:
      hex_go(t, hex_step(c, st))
    case SNil{}:
      st

def hex_ws(st: HexSt) -> +List<U32>:
  HexSt{_, _, ws} = st
  ws

def w_of(ws: +List<U32>) -> Maybe<&2, W>:
  match ws:
    case Con{h, Con{g, Con{f, Con{e, Con{d, Con{c, Con{b, Con{a, Nil{}}}}}}}}}:
      Some{W{a, b, c, d, e, f, g, h}}
    case _:
      None{}

# Inverse of `hex`: 64 hex digits (32 little-endian bytes) -> W; None on a wrong length.
def from_hex(s: String) -> Maybe<&2, W>:
  w_of(hex_ws(hex_go(s, HexSt{0, 0, Nil{}})))

# Lowercase hex of the 32 little-endian bytes (the vectors' text format).
def hex(w: W) -> String:
  W{a, b, c, d, e, f, g, h} = w
  hex_u32(a) ++ hex_u32(b) ++ hex_u32(c) ++ hex_u32(d) ++ hex_u32(e) ++ hex_u32(f) ++ hex_u32(g) ++ hex_u32(h)
