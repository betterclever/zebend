# Zcash block header proof-of-work, in Bend.
#
# A header is its 1487 serialized bytes (one U32 per byte):
#   version(4) prev(32) merkle(32) commitments(32) time(4) bits(4) nonce(32)
#   compactsize(1344) = fd 40 05, solution(1344)
# Checked here, per header and independently (so it parallelizes):
#   - block hash = SHA-256d(header)
#   - hash <= target(nBits)
#   - Equihash(n = 200, k = 9) solution validity (protocol spec § 7.7.1)
import Base
import ./hashes.bend as H

# ---------------------------------------------------------------------------
# Words and bytes
# ---------------------------------------------------------------------------

# 256-bit value as 8 little-endian U32 words (a0 least significant).
type H8 is Data:
  H8{a0: U32, a1: U32, a2: U32, a3: U32, a4: U32, a5: U32, a6: U32, a7: U32}

def rev(xs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match xs:
    case Con{h, t}:
      rev(t, h <> acc)
    case Nil{}:
      acc

# Groups bytes into little-endian words; drops a trailing partial word. Result is reversed.
def le_words(bs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match bs:
    case Con{b0, Con{b1, Con{b2, Con{b3, rest}}}}:
      le_words(rest, (b0 .|. (b1 << 8n) .|. (b2 << 16n) .|. (b3 << 24n) : U32) <> acc)
    case _:
      acc

# Groups bytes into big-endian words; drops a trailing partial word. Result is reversed.
def be_words(bs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match bs:
    case Con{b0, Con{b1, Con{b2, Con{b3, rest}}}}:
      be_words(rest, ((b0 << 24n) .|. (b1 << 16n) .|. (b2 << 8n) .|. b3 : U32) <> acc)
    case _:
      acc

def bswap(+x: U32) -> U32:
  ((x >> 24n) .|. ((x >> 8n) .&. 65280) .|. ((x << 8n) .&. 16711680) .|. (x << 24n) : U32)

# Bytes of a word, least significant first, prepended to acc.
def word_bytes(+w: U32, acc: +List<U32>) -> +List<U32>:
  (w .&. 255 : U32) <> ((w >> 8n) .&. 255 : U32) <> ((w >> 16n) .&. 255 : U32) <> (w >> 24n : U32) <> acc

def shr_safe.go(c: Bool, +x: U32, +n: U32) -> U32:
  match c:
    case True{}:
      U32.shrn(x, U32.to_nat(n))
    case False{}:
      0

# x >> n, with 0 for n >= 32.
def shr_safe(+x: U32, +n: U32) -> U32:
  shr_safe.go(U32.is_lt(n, 32), x, n)

def shl_safe.go(c: Bool, +x: U32, +n: U32) -> U32:
  match c:
    case True{}:
      U32.shln(x, U32.to_nat(n))
    case False{}:
      0

# x << n, with 0 for n >= 32.
def shl_safe(+x: U32, +n: U32) -> U32:
  shl_safe.go(U32.is_lt(n, 32), x, n)

def mask(+n: U32) -> U32:
  (shl_safe(1, n) - 1 : U32)

# ---------------------------------------------------------------------------
# SHA-256d block hash
# ---------------------------------------------------------------------------

# 1487 bytes ++ 0x80 ++ 40 zero bytes ++ the 64-bit big-endian bit length (11896 = 0x2E78).
def sha_pad(bs: +List<U32>) -> +List<U32>:
  List.append(&2, U32, bs, 128 <> List.append(&2, U32, List.replicate(U32, 40n, 0), [0, 0, 0, 0, 0, 0, 46, 120]))

def sha2_block(h: H.SH) -> H.SW:
  H.SH{a, b, c, d, e, f, g, i} = h
  H.SW{a, b, c, d, e, f, g, i, 2147483648, 0, 0, 0, 0, 0, 0, 256}

def sh_to_h8(h: H.SH) -> H8:
  H.SH{+a, +b, +c, +d, +e, +f, +g, +i} = h
  H8{bswap(a), bswap(b), bswap(c), bswap(d), bswap(e), bswap(f), bswap(g), bswap(i)}

# SHA-256d of the header, as a little-endian 256-bit number (internal byte order).
def block_hash(+bs: +List<U32>) -> H8:
  +h1 = H.sha_blocks(rev(be_words(sha_pad(bs), Nil{}), Nil{}), H.sha_iv())
  sh_to_h8(H.sha_compress(H.sha_iv(), sha2_block(h1)))

# ---------------------------------------------------------------------------
# Compact target
# ---------------------------------------------------------------------------

def place.go(c: Bool, +m: U32, +k: U32, +base: U32) -> U32:
  match c:
    case True{}:
      shr_safe(m, (base - k : U32))
    case False{}:
      shl_safe(m, (k - base : U32))

# The 32-bit word at bit offset `base` of m << k.
def place(+m: U32, +k: U32, +base: U32) -> U32:
  place.go(U32.is_le(k, base), m, k, base)

# target = mantissa * 256^(exponent - 3); mainnet exponents are always >= 3.
def target(+bits: U32) -> H8:
  +m = (bits .&. 8388607 : U32)
  +k = (((bits >> 24n) - 3 : U32) * 8 : U32)
  H8{place(m, k, 0), place(m, k, 32), place(m, k, 64), place(m, k, 96), place(m, k, 128), place(m, k, 160), place(m, k, 192), place(m, k, 224)}

def h8_desc(h: H8) -> +List<U32>:
  H8{a0, a1, a2, a3, a4, a5, a6, a7} = h
  [a7, a6, a5, a4, a3, a2, a1, a0]

def le_desc.go(c: Cmp, rest: Bool) -> Bool:
  match c:
    case LT{}:
      True{}
    case GT{}:
      False{}
    case EQ{}:
      rest

# a <= b for two most-significant-first word lists of equal length.
def le_desc(a: +List<U32>, b: +List<U32>) -> Bool:
  match a:
    case Con{x, xs}:
      match b:
        case Con{y, ys}:
          le_desc.go(U32.cmp(x, y), le_desc(xs, ys))
        case Nil{}:
          True{}
    case Nil{}:
      True{}

def h8_le(a: H8, b: H8) -> Bool:
  le_desc(h8_desc(a), h8_desc(b))

def h8_eq(a: H8, b: H8) -> Bool:
  H8{a0, a1, a2, a3, a4, a5, a6, a7} = a
  H8{b0, b1, b2, b3, b4, b5, b6, b7} = b
  U32.is_eq(a0, b0) && U32.is_eq(a1, b1) && U32.is_eq(a2, b2) && U32.is_eq(a3, b3) && U32.is_eq(a4, b4) && U32.is_eq(a5, b5) && U32.is_eq(a6, b6) && U32.is_eq(a7, b7)

# Head of a word list (0 if empty).
def w(xs: +List<U32>) -> U32:
  match xs:
    case Con{h, _}:
      h
    case Nil{}:
      0

# ---------------------------------------------------------------------------
# Equihash (n = 200, k = 9): generated by blake3x/gen_eq.py (no byte lists)
# ---------------------------------------------------------------------------

# Ten 20-bit chunks of one leaf hash.
type L10 is Data:
  L10{c0: U32, c1: U32, c2: U32, c3: U32, c4: U32, c5: U32, c6: U32, c7: U32, c8: U32, c9: U32}

# A subtree: still valid, its first index, and the XOR of its leaves' chunks.
type Nd is Data:
  Nd{ok: Bool, first: U32, c0: U32, c1: U32, c2: U32, c3: U32, c4: U32, c5: U32, c6: U32, c7: U32, c8: U32, c9: U32}

def leaf0(d: H.BH) -> L10:
  H.BH{+h0l, +h0h, +h1l, +h1h, +h2l, +h2h, +h3l, +h3h, +h4l, +h4h, +h5l, +h5h, +h6l, +h6h, +h7l, +h7h} = d
  +b0 = (h0l .&. 255 : U32)
  +b1 = ((h0l >> 8n) .&. 255 : U32)
  +b2 = ((h0l >> 16n) .&. 255 : U32)
  +b3 = ((h0l >> 24n) .&. 255 : U32)
  +b4 = (h0h .&. 255 : U32)
  +b5 = ((h0h >> 8n) .&. 255 : U32)
  +b6 = ((h0h >> 16n) .&. 255 : U32)
  +b7 = ((h0h >> 24n) .&. 255 : U32)
  +b8 = (h1l .&. 255 : U32)
  +b9 = ((h1l >> 8n) .&. 255 : U32)
  +b10 = ((h1l >> 16n) .&. 255 : U32)
  +b11 = ((h1l >> 24n) .&. 255 : U32)
  +b12 = (h1h .&. 255 : U32)
  +b13 = ((h1h >> 8n) .&. 255 : U32)
  +b14 = ((h1h >> 16n) .&. 255 : U32)
  +b15 = ((h1h >> 24n) .&. 255 : U32)
  +b16 = (h2l .&. 255 : U32)
  +b17 = ((h2l >> 8n) .&. 255 : U32)
  +b18 = ((h2l >> 16n) .&. 255 : U32)
  +b19 = ((h2l >> 24n) .&. 255 : U32)
  +b20 = (h2h .&. 255 : U32)
  +b21 = ((h2h >> 8n) .&. 255 : U32)
  +b22 = ((h2h >> 16n) .&. 255 : U32)
  +b23 = ((h2h >> 24n) .&. 255 : U32)
  +b24 = (h3l .&. 255 : U32)
  L10{((b0 << 12n) .|. (b1 << 4n) .|. (b2 >> 4n) : U32), (((b2 .&. 15) << 16n) .|. (b3 << 8n) .|. b4 : U32), ((b5 << 12n) .|. (b6 << 4n) .|. (b7 >> 4n) : U32), (((b7 .&. 15) << 16n) .|. (b8 << 8n) .|. b9 : U32), ((b10 << 12n) .|. (b11 << 4n) .|. (b12 >> 4n) : U32), (((b12 .&. 15) << 16n) .|. (b13 << 8n) .|. b14 : U32), ((b15 << 12n) .|. (b16 << 4n) .|. (b17 >> 4n) : U32), (((b17 .&. 15) << 16n) .|. (b18 << 8n) .|. b19 : U32), ((b20 << 12n) .|. (b21 << 4n) .|. (b22 >> 4n) : U32), (((b22 .&. 15) << 16n) .|. (b23 << 8n) .|. b24 : U32)}

def leaf1(d: H.BH) -> L10:
  H.BH{+h0l, +h0h, +h1l, +h1h, +h2l, +h2h, +h3l, +h3h, +h4l, +h4h, +h5l, +h5h, +h6l, +h6h, +h7l, +h7h} = d
  +b0 = ((h3l >> 8n) .&. 255 : U32)
  +b1 = ((h3l >> 16n) .&. 255 : U32)
  +b2 = ((h3l >> 24n) .&. 255 : U32)
  +b3 = (h3h .&. 255 : U32)
  +b4 = ((h3h >> 8n) .&. 255 : U32)
  +b5 = ((h3h >> 16n) .&. 255 : U32)
  +b6 = ((h3h >> 24n) .&. 255 : U32)
  +b7 = (h4l .&. 255 : U32)
  +b8 = ((h4l >> 8n) .&. 255 : U32)
  +b9 = ((h4l >> 16n) .&. 255 : U32)
  +b10 = ((h4l >> 24n) .&. 255 : U32)
  +b11 = (h4h .&. 255 : U32)
  +b12 = ((h4h >> 8n) .&. 255 : U32)
  +b13 = ((h4h >> 16n) .&. 255 : U32)
  +b14 = ((h4h >> 24n) .&. 255 : U32)
  +b15 = (h5l .&. 255 : U32)
  +b16 = ((h5l >> 8n) .&. 255 : U32)
  +b17 = ((h5l >> 16n) .&. 255 : U32)
  +b18 = ((h5l >> 24n) .&. 255 : U32)
  +b19 = (h5h .&. 255 : U32)
  +b20 = ((h5h >> 8n) .&. 255 : U32)
  +b21 = ((h5h >> 16n) .&. 255 : U32)
  +b22 = ((h5h >> 24n) .&. 255 : U32)
  +b23 = (h6l .&. 255 : U32)
  +b24 = ((h6l >> 8n) .&. 255 : U32)
  L10{((b0 << 12n) .|. (b1 << 4n) .|. (b2 >> 4n) : U32), (((b2 .&. 15) << 16n) .|. (b3 << 8n) .|. b4 : U32), ((b5 << 12n) .|. (b6 << 4n) .|. (b7 >> 4n) : U32), (((b7 .&. 15) << 16n) .|. (b8 << 8n) .|. b9 : U32), ((b10 << 12n) .|. (b11 << 4n) .|. (b12 >> 4n) : U32), (((b12 .&. 15) << 16n) .|. (b13 << 8n) .|. b14 : U32), ((b15 << 12n) .|. (b16 << 4n) .|. (b17 >> 4n) : U32), (((b17 .&. 15) << 16n) .|. (b18 << 8n) .|. b19 : U32), ((b20 << 12n) .|. (b21 << 4n) .|. (b22 >> 4n) : U32), (((b22 .&. 15) << 16n) .|. (b23 << 8n) .|. b24 : U32)}

def leaf_of(odd: Bool, d: H.BH) -> L10:
  match odd:
    case True{}:
      leaf1(d)
    case False{}:
      leaf0(d)

def nd_of(+x: U32, l: L10) -> Nd:
  L10{c0, c1, c2, c3, c4, c5, c6, c7, c8, c9} = l
  Nd{True{}, x, c0, c1, c2, c3, c4, c5, c6, c7, c8, c9}

# Context shared by the 512 leaf hashes of one header: the BLAKE2b state after
# the first 128 header bytes, and header bytes 128..139 (words 32..34).
type EC is Data:
  EC{mid: H.BH, w32: U32, w33: U32, w34: U32}

def ec_of(+ws: +List<U32>) -> EC:
  EC{H.b2_compress(H.eh_h0(), H.bm_of(ws), 128, 0), w(List.drop(&2, U32, ws, 32n)), w(List.drop(&2, U32, ws, 33n)), w(List.drop(&2, U32, ws, 34n))}

# BLAKE2b(I || LE32(x / 2)); the half selected by x mod 2 gives the leaf's chunks.
def leaf(+c: EC, +x: U32) -> Nd:
  EC{mid, w32, w33, w34} = c
  +d = H.b2_leaf(mid, w32, w33, w34, (x >> 1n : U32))
  nd_of(x, leaf_of(U32.is_eq((x .&. 1 : U32), 1), d))

def leaves(xs: +List<U32>, +c: EC) -> List<Nd>:
  match xs:
    case Con{+x, rest}:
      leaf(c, x) <> leaves(rest, c)
    case Nil{}:
      Nil{}

# Level-0 merge: chunk 0 of the XOR must be 0 and left.first < right.first.
def merge0(l: Nd, r: Nd) -> Nd:
  Nd{ok1, +f1, +a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +a8, +a9} = l
  Nd{ok2, f2, +b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7, +b8, +b9} = r
  Nd{ok1 && ok2 && U32.is_eq((a0 .^. b0 : U32), 0) && U32.is_lt(f1, f2), f1, (a0 .^. b0 : U32), (a1 .^. b1 : U32), (a2 .^. b2 : U32), (a3 .^. b3 : U32), (a4 .^. b4 : U32), (a5 .^. b5 : U32), (a6 .^. b6 : U32), (a7 .^. b7 : U32), (a8 .^. b8 : U32), (a9 .^. b9 : U32)}

def pairs0(xs: List<Nd>) -> List<Nd>:
  match xs:
    case Con{a, Con{b, rest}}:
      merge0(a, b) <> pairs0(rest)
    case _:
      Nil{}

# Level-1 merge: chunk 1 of the XOR must be 0 and left.first < right.first.
def merge1(l: Nd, r: Nd) -> Nd:
  Nd{ok1, +f1, +a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +a8, +a9} = l
  Nd{ok2, f2, +b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7, +b8, +b9} = r
  Nd{ok1 && ok2 && U32.is_eq((a1 .^. b1 : U32), 0) && U32.is_lt(f1, f2), f1, (a0 .^. b0 : U32), (a1 .^. b1 : U32), (a2 .^. b2 : U32), (a3 .^. b3 : U32), (a4 .^. b4 : U32), (a5 .^. b5 : U32), (a6 .^. b6 : U32), (a7 .^. b7 : U32), (a8 .^. b8 : U32), (a9 .^. b9 : U32)}

def pairs1(xs: List<Nd>) -> List<Nd>:
  match xs:
    case Con{a, Con{b, rest}}:
      merge1(a, b) <> pairs1(rest)
    case _:
      Nil{}

# Level-2 merge: chunk 2 of the XOR must be 0 and left.first < right.first.
def merge2(l: Nd, r: Nd) -> Nd:
  Nd{ok1, +f1, +a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +a8, +a9} = l
  Nd{ok2, f2, +b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7, +b8, +b9} = r
  Nd{ok1 && ok2 && U32.is_eq((a2 .^. b2 : U32), 0) && U32.is_lt(f1, f2), f1, (a0 .^. b0 : U32), (a1 .^. b1 : U32), (a2 .^. b2 : U32), (a3 .^. b3 : U32), (a4 .^. b4 : U32), (a5 .^. b5 : U32), (a6 .^. b6 : U32), (a7 .^. b7 : U32), (a8 .^. b8 : U32), (a9 .^. b9 : U32)}

def pairs2(xs: List<Nd>) -> List<Nd>:
  match xs:
    case Con{a, Con{b, rest}}:
      merge2(a, b) <> pairs2(rest)
    case _:
      Nil{}

# Level-3 merge: chunk 3 of the XOR must be 0 and left.first < right.first.
def merge3(l: Nd, r: Nd) -> Nd:
  Nd{ok1, +f1, +a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +a8, +a9} = l
  Nd{ok2, f2, +b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7, +b8, +b9} = r
  Nd{ok1 && ok2 && U32.is_eq((a3 .^. b3 : U32), 0) && U32.is_lt(f1, f2), f1, (a0 .^. b0 : U32), (a1 .^. b1 : U32), (a2 .^. b2 : U32), (a3 .^. b3 : U32), (a4 .^. b4 : U32), (a5 .^. b5 : U32), (a6 .^. b6 : U32), (a7 .^. b7 : U32), (a8 .^. b8 : U32), (a9 .^. b9 : U32)}

def pairs3(xs: List<Nd>) -> List<Nd>:
  match xs:
    case Con{a, Con{b, rest}}:
      merge3(a, b) <> pairs3(rest)
    case _:
      Nil{}

# Level-4 merge: chunk 4 of the XOR must be 0 and left.first < right.first.
def merge4(l: Nd, r: Nd) -> Nd:
  Nd{ok1, +f1, +a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +a8, +a9} = l
  Nd{ok2, f2, +b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7, +b8, +b9} = r
  Nd{ok1 && ok2 && U32.is_eq((a4 .^. b4 : U32), 0) && U32.is_lt(f1, f2), f1, (a0 .^. b0 : U32), (a1 .^. b1 : U32), (a2 .^. b2 : U32), (a3 .^. b3 : U32), (a4 .^. b4 : U32), (a5 .^. b5 : U32), (a6 .^. b6 : U32), (a7 .^. b7 : U32), (a8 .^. b8 : U32), (a9 .^. b9 : U32)}

def pairs4(xs: List<Nd>) -> List<Nd>:
  match xs:
    case Con{a, Con{b, rest}}:
      merge4(a, b) <> pairs4(rest)
    case _:
      Nil{}

# Level-5 merge: chunk 5 of the XOR must be 0 and left.first < right.first.
def merge5(l: Nd, r: Nd) -> Nd:
  Nd{ok1, +f1, +a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +a8, +a9} = l
  Nd{ok2, f2, +b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7, +b8, +b9} = r
  Nd{ok1 && ok2 && U32.is_eq((a5 .^. b5 : U32), 0) && U32.is_lt(f1, f2), f1, (a0 .^. b0 : U32), (a1 .^. b1 : U32), (a2 .^. b2 : U32), (a3 .^. b3 : U32), (a4 .^. b4 : U32), (a5 .^. b5 : U32), (a6 .^. b6 : U32), (a7 .^. b7 : U32), (a8 .^. b8 : U32), (a9 .^. b9 : U32)}

def pairs5(xs: List<Nd>) -> List<Nd>:
  match xs:
    case Con{a, Con{b, rest}}:
      merge5(a, b) <> pairs5(rest)
    case _:
      Nil{}

# Level-6 merge: chunk 6 of the XOR must be 0 and left.first < right.first.
def merge6(l: Nd, r: Nd) -> Nd:
  Nd{ok1, +f1, +a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +a8, +a9} = l
  Nd{ok2, f2, +b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7, +b8, +b9} = r
  Nd{ok1 && ok2 && U32.is_eq((a6 .^. b6 : U32), 0) && U32.is_lt(f1, f2), f1, (a0 .^. b0 : U32), (a1 .^. b1 : U32), (a2 .^. b2 : U32), (a3 .^. b3 : U32), (a4 .^. b4 : U32), (a5 .^. b5 : U32), (a6 .^. b6 : U32), (a7 .^. b7 : U32), (a8 .^. b8 : U32), (a9 .^. b9 : U32)}

def pairs6(xs: List<Nd>) -> List<Nd>:
  match xs:
    case Con{a, Con{b, rest}}:
      merge6(a, b) <> pairs6(rest)
    case _:
      Nil{}

# Level-7 merge: chunk 7 of the XOR must be 0 and left.first < right.first.
def merge7(l: Nd, r: Nd) -> Nd:
  Nd{ok1, +f1, +a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +a8, +a9} = l
  Nd{ok2, f2, +b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7, +b8, +b9} = r
  Nd{ok1 && ok2 && U32.is_eq((a7 .^. b7 : U32), 0) && U32.is_lt(f1, f2), f1, (a0 .^. b0 : U32), (a1 .^. b1 : U32), (a2 .^. b2 : U32), (a3 .^. b3 : U32), (a4 .^. b4 : U32), (a5 .^. b5 : U32), (a6 .^. b6 : U32), (a7 .^. b7 : U32), (a8 .^. b8 : U32), (a9 .^. b9 : U32)}

def pairs7(xs: List<Nd>) -> List<Nd>:
  match xs:
    case Con{a, Con{b, rest}}:
      merge7(a, b) <> pairs7(rest)
    case _:
      Nil{}

# Level-8 merge: chunk 8 of the XOR must be 0 and left.first < right.first.
def merge8(l: Nd, r: Nd) -> Nd:
  Nd{ok1, +f1, +a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +a8, +a9} = l
  Nd{ok2, f2, +b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7, +b8, +b9} = r
  Nd{ok1 && ok2 && U32.is_eq((a8 .^. b8 : U32), 0) && U32.is_lt(f1, f2), f1, (a0 .^. b0 : U32), (a1 .^. b1 : U32), (a2 .^. b2 : U32), (a3 .^. b3 : U32), (a4 .^. b4 : U32), (a5 .^. b5 : U32), (a6 .^. b6 : U32), (a7 .^. b7 : U32), (a8 .^. b8 : U32), (a9 .^. b9 : U32)}

def pairs8(xs: List<Nd>) -> List<Nd>:
  match xs:
    case Con{a, Con{b, rest}}:
      merge8(a, b) <> pairs8(rest)
    case _:
      Nil{}

def nd_final(n: Nd) -> Bool:
  Nd{ok, _, _, _, _, _, _, _, _, _, _, c9} = n
  ok && U32.is_eq(c9, 0)

def root_ok(xs: List<Nd>) -> Bool:
  match xs:
    case Con{n, Nil{}}:
      nd_final(n)
    case _:
      False{}

# The 512 solution indices: 21 bytes (168 bits) hold 8 big-endian 21-bit indices.
def unpack_all(bs: +List<U32>) -> +List<U32>:
  match bs:
    case Con{+b0, Con{+b1, Con{+b2, Con{+b3, Con{+b4, Con{+b5, Con{+b6, Con{+b7, Con{+b8, Con{+b9, Con{+b10, Con{+b11, Con{+b12, Con{+b13, Con{+b14, Con{+b15, Con{+b16, Con{+b17, Con{+b18, Con{+b19, Con{+b20, rest}}}}}}}}}}}}}}}}}}}}}:
      ((((b0 << 24n) .|. (b1 << 16n) .|. (b2 << 8n)) >> 11n) .&. 2097151 : U32) <> ((((b2 << 24n) .|. (b3 << 16n) .|. (b4 << 8n) .|. (b5 << 0n)) >> 6n) .&. 2097151 : U32) <> ((((b5 << 24n) .|. (b6 << 16n) .|. (b7 << 8n)) >> 9n) .&. 2097151 : U32) <> ((((b7 << 24n) .|. (b8 << 16n) .|. (b9 << 8n) .|. (b10 << 0n)) >> 4n) .&. 2097151 : U32) <> ((((b10 << 24n) .|. (b11 << 16n) .|. (b12 << 8n) .|. (b13 << 0n)) >> 7n) .&. 2097151 : U32) <> ((((b13 << 24n) .|. (b14 << 16n) .|. (b15 << 8n)) >> 10n) .&. 2097151 : U32) <> ((((b15 << 24n) .|. (b16 << 16n) .|. (b17 << 8n) .|. (b18 << 0n)) >> 5n) .&. 2097151 : U32) <> ((((b18 << 24n) .|. (b19 << 16n) .|. (b20 << 8n)) >> 8n) .&. 2097151 : U32) <> unpack_all(rest)
    case _:
      Nil{}

def no_dups.go(xs: +List<U32>, +prev: U32) -> Bool:
  match xs:
    case Con{+b, rest}:
      U32.is_ne(prev, b) && no_dups.go(rest, b)
    case Nil{}:
      True{}

# No two adjacent elements of a sorted list are equal.
def no_dups(xs: +List<U32>) -> Bool:
  match xs:
    case Con{a, rest}:
      no_dups.go(rest, a)
    case Nil{}:
      True{}

def count(xs: +List<U32>) -> Nat:
  List.length(&2, U32, xs)

# Full Equihash(200, 9) check of one header's bytes.
def equihash_ok(+bs: +List<U32>, +ws: +List<U32>) -> Bool:
  +ix = unpack_all(List.drop(&2, U32, bs, 143n))
  +c = ec_of(ws)
  Nat.is_eq(count(ix), 512n) && no_dups(List.sort(~U32, ~U32.is_le, ix)) && root_ok(pairs8(pairs7(pairs6(pairs5(pairs4(pairs3(pairs2(pairs1(pairs0(leaves(ix, c)))))))))))

# ---------------------------------------------------------------------------
# One header
# ---------------------------------------------------------------------------

type HR is Data:
  HR{pow: Bool, under: Bool, hash: H8, prev: H8, time: U32, bits: U32}

def words_at(ws: +List<U32>, n: Nat) -> +List<U32>:
  List.drop(&2, U32, ws, n)

def h8_at(+ws: +List<U32>, n: Nat) -> H8:
  +xs = words_at(ws, n)
  H8{w(xs), w(words_at(xs, 1n)), w(words_at(xs, 2n)), w(words_at(xs, 3n)), w(words_at(xs, 4n)), w(words_at(xs, 5n)), w(words_at(xs, 6n)), w(words_at(xs, 7n))}

# Verifies everything a header can show about itself.
def check_header(+bs: +List<U32>) -> HR:
  +ws = rev(le_words(List.append(&2, U32, bs, [0]), Nil{}), Nil{})
  +hash = block_hash(bs)
  +bits = w(words_at(ws, 26n))
  HR{equihash_ok(bs, ws), h8_le(hash, target(bits)), hash, h8_at(ws, 1n), w(words_at(ws, 25n)), bits}
