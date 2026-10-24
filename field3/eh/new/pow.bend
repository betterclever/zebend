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

# ---------------------------------------------------------------------------
# Equihash (n = 200, k = 9)
# ---------------------------------------------------------------------------

# Unpacks big-endian bit fields of width w from a byte list.
type UP is Data:
  UP{acc: U32, nb: U32, out: +List<U32>}

def unpack.emit(c: Bool, +a: U32, +n: U32, +w: U32, out: +List<U32>) -> UP:
  match c:
    case True{}:
      +r = (n - w : U32)
      UP{(a .&. mask(r) : U32), r, (shr_safe(a, r) .&. mask(w) : U32) <> out}
    case False{}:
      UP{a, n, out}

def unpack.step(+b: U32, +w: U32, st: UP) -> UP:
  UP{acc, nb, out} = st
  +a2 = ((acc << 8n) .|. b : U32)
  +n2 = (nb + 8 : U32)
  unpack.emit(U32.is_ge(n2, w), a2, n2, w, out)

def unpack.go(bs: +List<U32>, +w: U32, st: UP) -> UP:
  match bs:
    case Con{b, rest}:
      unpack.go(rest, w, unpack.step(b, w, st))
    case Nil{}:
      st

def unpack.out(st: UP) -> +List<U32>:
  UP{_, _, out} = st
  rev(out, Nil{})

def unpack(bs: +List<U32>, +w: U32) -> +List<U32>:
  unpack.out(unpack.go(bs, w, UP{0, 0, Nil{}}))

# The first 50 bytes of a BLAKE2b-400 digest.
def bh_bytes(h: H.BH) -> +List<U32>:
  H.BH{h0l, h0h, h1l, h1h, h2l, h2h, h3l, h3h, h4l, h4h, h5l, h5h, h6l, _, _, _} = h
  List.take(&2, U32, word_bytes(h0l, word_bytes(h0h, word_bytes(h1l, word_bytes(h1h, word_bytes(h2l, word_bytes(h2h, word_bytes(h3l, word_bytes(h3h, word_bytes(h4l, word_bytes(h4h, word_bytes(h5l, word_bytes(h5h, word_bytes(h6l, Nil{}))))))))))))), 50n)

# Head of a word list (0 if empty).
def w(xs: +List<U32>) -> U32:
  match xs:
    case Con{h, _}:
      h
    case Nil{}:
      0

# Context shared by the 512 leaf hashes of one header: the BLAKE2b state after
# the first 128 header bytes, and header bytes 128..139 (words 32..34).
type EC is Data:
  EC{mid: H.BH, w32: U32, w33: U32, w34: U32}

def ec_of(+ws: +List<U32>) -> EC:
  EC{H.b2_compress(H.eh_h0(), H.bm_of(ws), 128, 0), w(List.drop(&2, U32, ws, 32n)), w(List.drop(&2, U32, ws, 33n)), w(List.drop(&2, U32, ws, 34n))}

# BLAKE2b(I || LE32(g)) for g = x / 2, then the half selected by x mod 2, as ten
# 20-bit big-endian chunks.
def leaf_chunks(+c: EC, +x: U32) -> +List<U32>:
  EC{mid, w32, w33, w34} = c
  +d = H.b2_compress(mid, H.BM{w32, w33, w34, (x >> 1n : U32), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, 144, 4294967295)
  unpack(List.take(&2, U32, List.drop(&2, U32, bh_bytes(d), U32.to_nat(((x .&. 1) * 25 : U32))), 25n), 20)

# A subtree of the solution: still valid so far, its first index, and the XOR of
# its leaves' remaining (not yet collided) chunks.
type Nd is Data:
  Nd{ok: Bool, first: U32, cs: +List<U32>}

def zx(a: +List<U32>, b: +List<U32>) -> +List<U32>:
  match a:
    case Con{x, xs}:
      match b:
        case Con{y, ys}:
          (x .^. y : U32) <> zx(xs, ys)
        case Nil{}:
          Nil{}
    case Nil{}:
      Nil{}

def head_zero(xs: +List<U32>) -> Bool:
  match xs:
    case Con{h, _}:
      U32.is_eq(h, 0)
    case Nil{}:
      False{}

def tail(xs: +List<U32>) -> +List<U32>:
  match xs:
    case Con{_, t}:
      t
    case Nil{}:
      Nil{}

# Merging two sibling subtrees: their next 20-bit chunk must collide and the left
# subtree's first index must be smaller than the right's (protocol spec § 7.7.1).
def merge(l: Nd, r: Nd) -> Nd:
  Nd{ok1, +f1, cs1} = l
  Nd{ok2, f2, cs2} = r
  +x = zx(cs1, cs2)
  Nd{ok1 && ok2 && head_zero(x) && U32.is_lt(f1, f2), f1, tail(x)}

def pairs(xs: List<Nd>) -> List<Nd>:
  match xs:
    case Con{a, Con{b, rest}}:
      merge(a, b) <> pairs(rest)
    case _:
      Nil{}

def levels(n: Nat, xs: List<Nd>) -> List<Nd>:
  match n:
    case 0n:
      xs
    case 1n+p:
      levels(p, pairs(xs))

def leaves(xs: +List<U32>, +c: EC) -> List<Nd>:
  match xs:
    case Con{+x, rest}:
      Nd{True{}, x, leaf_chunks(c, x)} <> leaves(rest, c)
    case Nil{}:
      Nil{}

def nd_final(n: Nd) -> Bool:
  Nd{ok, _, cs} = n
  ok && head_zero(cs)

def root_ok(xs: List<Nd>) -> Bool:
  match xs:
    case Con{n, Nil{}}:
      nd_final(n)
    case _:
      False{}

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
  +sol = List.drop(&2, U32, bs, 143n)
  +ix = unpack(sol, 21)
  +c = ec_of(ws)
  Nat.is_eq(count(ix), 512n) && no_dups(List.sort(~U32, ~U32.is_le, ix)) && root_ok(levels(9n, leaves(ix, c)))

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
