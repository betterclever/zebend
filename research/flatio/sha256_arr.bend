# EXPERIMENT (research/flatio): SHA-256 over a flat Array<U32>, as File.read_words gives
# bytes (little-endian, four to a word). Compression is the live code's
# (zcash/transparent/sighash2/sha256.bend, imported unchanged); only the block reader
# differs: each message word is one array read plus a byte swap, padding is computed
# per word, and no List cell is made.
import Base
import ../../zcash/transparent/sighash2/sha256.bend as S

def bswap(+x: U32) -> U32:
  ((x << 24n) .|. ((x << 8n) .&. 16711680) .|. ((x >> 8n) .&. 65280) .|. (x >> 24n) : U32)

# The data part of message word k (big-endian): the bytes before len, then 0x80, then zeros.
def mdata(+x: U32, +k: U32, +len: U32) -> U32:
  +at = (k << 2n : U32)
  +kb = U32.sub(len, at)
  +part = (U32.not(U32.shrn(4294967295, U32.to_nat((kb << 3n : U32)))) .&. bswap(x)
    .|. U32.shln(128, U32.to_nat(U32.sub(24, (kb << 3n : U32)))) : U32)
  Bool.pick(U32, U32.is_ge(len, (at + 4 : U32)), bswap(x),
    Bool.pick(U32, U32.is_ge(len, at), part, 0))

# Word k of the padded message of len bytes, nw words long (the last two: bit length).
def mword(+x: U32, +k: U32, +len: U32, +nw: U32) -> U32:
  Bool.pick(U32, U32.is_eq(k, (nw - 2 : U32)), (len >> 29n : U32),
    Bool.pick(U32, U32.is_eq(k, (nw - 1 : U32)), (len << 3n : U32), mdata(x, k, len)))

def push(win: S.W16, +x: U32) -> S.W16:
  S.W16{w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15} = win
  S.W16{w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15, x}

def z16() -> S.W16:
  S.W16{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}

# The 16 words of the block that starts at message word k (array word o + k); r holds
# the array and that word.
def fill16(n: Nat, r: Array<U32> & U32, +o: U32, +k: U32, +len: U32, +nw: U32, win: S.W16) -> Array<U32> & S.W16:
  match n:
    case 0n:
      (a, x) = r
      (a, push(win, mword(x, k, len, nw)))
    case 1n+p:
      (a, x) = r
      +j = U32.inc(k)
      fill16(p, a[(o + j : U32)], o, j, len, nw, push(win, mword(x, k, len, nw)))

def block(a: Array<U32>, +o: U32, +k: U32, +len: U32, +nw: U32) -> Array<U32> & S.W16:
  fill16(15n, a[(o + k : U32)], o, k, len, nw, z16())

# n blocks; r is the array and the next block, read ahead so the recursion stays direct.
def blocks(n: Nat, r: Array<U32> & S.W16, +o: U32, +k: U32, +len: U32, +nw: U32, +st: S.S8) -> Array<U32> & S.S8:
  match n:
    case 0n:
      (a, w) = r
      (a, st)
    case 1n+p:
      (a, +w) = r
      +nk = (k + 16 : U32)
      blocks(p, block(a, o, nk, len, nw), o, nk, len, nw, S.add8(st, S.rounds(S.ks(), st, w)))

# SHA-256 of the len bytes (len < 2^29) that start at word o of a; the array comes back
# unchanged.
def hash_at(a: Array<U32>, +o: U32, +len: U32) -> Array<U32> & S.S8:
  +nblk = ((len + 72) >> 6n : U32)
  +nw = (nblk << 4n : U32)
  blocks(U32.to_nat(nblk), block(a, o, 0, len, nw), o, 0, len, nw, S.iv())

def hash(a: Array<U32>, +len: U32) -> Array<U32> & S.S8:
  hash_at(a, 0, len)

# The digest as 8 little-endian-packed words (the same packing as File.read_words).
def digest_words(st: S.S8) -> Array<U32>:
  S.S8{d0, d1, d2, d3, d4, d5, d6, d7} = st
  a = [0 : U32^3n]
  a[0] <- bswap(d0)
  a[1] <- bswap(d1)
  a[2] <- bswap(d2)
  a[3] <- bswap(d3)
  a[4] <- bswap(d4)
  a[5] <- bswap(d5)
  a[6] <- bswap(d6)
  a[7] <- bswap(d7)
  a

def hash_d.k(r: Array<U32> & S.S8) -> Array<U32> & S.S8:
  (a, st) = r
  (a, Pair.snd(Array<U32>, S.S8, hash(digest_words(st), 32)))

# SHA-256d (HASH256).
def hash_d_at(a: Array<U32>, +o: U32, +len: U32) -> Array<U32> & S.S8:
  hash_d.k(hash_at(a, o, len))

def hash_d(a: Array<U32>, +len: U32) -> Array<U32> & S.S8:
  hash_d_at(a, 0, len)
