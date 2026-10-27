# node/fast: SHA-256 / SHA-256d (FIPS 180-4) over byte lists, as zcash/block/sha256.bend
# (same rounds, same schedule window, same padding) with the list work made linear:
#   - a message block's 16 words are read in one pass (zcash/block re-dropped from the block
#     start for every word: 480 list steps per 64 bytes);
#   - the round constants are built once per message, not once per block;
#   - the padded message is ONE copy of the input prefix (take_onto), not take + append,
#     and its length is passed in instead of counted.
# Tested: every txid / block hash / merkle verdict identical to zcash/block's on the bench
# windows (research/fast/README.md).
import Base

type S8 is Data:
  S8{a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32}

type W16 is Data:
  W16{w0: U32, w1: U32, w2: U32, w3: U32, w4: U32, w5: U32, w6: U32, w7: U32,
      w8: U32, w9: U32, w10: U32, w11: U32, w12: U32, w13: U32, w14: U32, w15: U32}

def iv() -> S8:
  S8{1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635, 1541459225}

def ks() -> +List<U32>:
  [1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221,
   3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580,
   3835390401, 4022224774, 264347078, 604807628, 770255983, 1249150122, 1555081692, 1996064986,
   2554220882, 2821834349, 2952996808, 3210313671, 3336571891, 3584528711, 113926993, 338241895,
   666307205, 773529912, 1294757372, 1396182291, 1695183700, 1986661051, 2177026350, 2456956037,
   2730485921, 2820302411, 3259730800, 3345764771, 3516065817, 3600352804, 4094571909, 275423344,
   430227734, 506948616, 659060556, 883997877, 958139571, 1322822218, 1537002063, 1747873779,
   1955562222, 2024104815, 2227730452, 2361852424, 2428436474, 2756734187, 3204031479, 3329325298]

def big_s0(+a: U32) -> U32:
  (((a >> 2n) .|. (a << 30n)) .^. ((a >> 13n) .|. (a << 19n)) .^. ((a >> 22n) .|. (a << 10n)) : U32)

def big_s1(+e: U32) -> U32:
  (((e >> 6n) .|. (e << 26n)) .^. ((e >> 11n) .|. (e << 21n)) .^. ((e >> 25n) .|. (e << 7n)) : U32)

def small_s0(+x: U32) -> U32:
  (((x >> 7n) .|. (x << 25n)) .^. ((x >> 18n) .|. (x << 14n)) .^. (x >> 3n) : U32)

def small_s1(+x: U32) -> U32:
  (((x >> 17n) .|. (x << 15n)) .^. ((x >> 19n) .|. (x << 13n)) .^. (x >> 10n) : U32)

def ch(+e: U32, +f: U32, +g: U32) -> U32:
  ((e .&. f) .^. (U32.not(e) .&. g) : U32)

def maj(+a: U32, +b: U32, +c: U32) -> U32:
  ((a .&. b) .^. (a .&. c) .^. (b .&. c) : U32)

def round(st: S8, +k: U32, +w: U32) -> S8:
  S8{+a, +b, +c, +d, +e, +f, +g, +h} = st
  +t1 = (h + big_s1(e) + ch(e, f, g) + k + w : U32)
  +t2 = (big_s0(a) + maj(a, b, c) : U32)
  S8{(t1 + t2 : U32), a, b, c, (d + t1 : U32), e, f, g}

def shift(win: W16) -> W16:
  W16{+w0, +w1, w2, w3, w4, w5, w6, w7, w8, +w9, w10, w11, w12, w13, +w14, w15} = win
  W16{w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15,
      (small_s1(w14) + w9 + small_s0(w1) + w0 : U32)}

def head(+win: W16) -> U32:
  W16{w0, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} = win
  w0

def rounds(ks: +List<U32>, st: S8, +win: W16) -> S8:
  match ks:
    case Nil{}:
      st
    case Con{k, rest}:
      rounds(rest, round(st, k, head(win)), shift(win))

def add8(x: S8, y: S8) -> S8:
  S8{a0, b0, c0, d0, e0, f0, g0, h0} = x
  S8{a1, b1, c1, d1, e1, f1, g1, h1} = y
  S8{(a0 + a1 : U32), (b0 + b1 : U32), (c0 + c1 : U32), (d0 + d1 : U32),
     (e0 + e1 : U32), (f0 + f1 : U32), (g0 + g1 : U32), (h0 + h1 : U32)}

# A big-endian word and the bytes after it.
def rd4(xs: +List<U32>) -> U32 & +List<U32>:
  match xs:
    case Con{a, Con{b, Con{c, Con{d, t}}}}:
      (((a << 24n) .|. (b << 16n) .|. (c << 8n) .|. d : U32), t)
    case _:
      (0, Nil{})

# The 16 words of the next 64-byte block, read in one pass, and the bytes after it.
def bw15(+w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32, +w11: U32, +w12: U32, +w13: U32, +w14: U32, p: U32 & +List<U32>) -> W16 & +List<U32>:
  (w15, r) = p
  (W16{w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15}, r)

def bw14(+w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32, +w11: U32, +w12: U32, +w13: U32, p: U32 & +List<U32>) -> W16 & +List<U32>:
  (w14, r) = p
  bw15(w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, rd4(r))

def bw13(+w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32, +w11: U32, +w12: U32, p: U32 & +List<U32>) -> W16 & +List<U32>:
  (w13, r) = p
  bw14(w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, rd4(r))

def bw12(+w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32, +w11: U32, p: U32 & +List<U32>) -> W16 & +List<U32>:
  (w12, r) = p
  bw13(w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, rd4(r))

def bw11(+w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, +w10: U32, p: U32 & +List<U32>) -> W16 & +List<U32>:
  (w11, r) = p
  bw12(w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, rd4(r))

def bw10(+w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, +w9: U32, p: U32 & +List<U32>) -> W16 & +List<U32>:
  (w10, r) = p
  bw11(w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, rd4(r))

def bw9(+w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, +w8: U32, p: U32 & +List<U32>) -> W16 & +List<U32>:
  (w9, r) = p
  bw10(w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, rd4(r))

def bw8(+w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, +w7: U32, p: U32 & +List<U32>) -> W16 & +List<U32>:
  (w8, r) = p
  bw9(w0, w1, w2, w3, w4, w5, w6, w7, w8, rd4(r))

def bw7(+w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, +w6: U32, p: U32 & +List<U32>) -> W16 & +List<U32>:
  (w7, r) = p
  bw8(w0, w1, w2, w3, w4, w5, w6, w7, rd4(r))

def bw6(+w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, +w5: U32, p: U32 & +List<U32>) -> W16 & +List<U32>:
  (w6, r) = p
  bw7(w0, w1, w2, w3, w4, w5, w6, rd4(r))

def bw5(+w0: U32, +w1: U32, +w2: U32, +w3: U32, +w4: U32, p: U32 & +List<U32>) -> W16 & +List<U32>:
  (w5, r) = p
  bw6(w0, w1, w2, w3, w4, w5, rd4(r))

def bw4(+w0: U32, +w1: U32, +w2: U32, +w3: U32, p: U32 & +List<U32>) -> W16 & +List<U32>:
  (w4, r) = p
  bw5(w0, w1, w2, w3, w4, rd4(r))

def bw3(+w0: U32, +w1: U32, +w2: U32, p: U32 & +List<U32>) -> W16 & +List<U32>:
  (w3, r) = p
  bw4(w0, w1, w2, w3, rd4(r))

def bw2(+w0: U32, +w1: U32, p: U32 & +List<U32>) -> W16 & +List<U32>:
  (w2, r) = p
  bw3(w0, w1, w2, rd4(r))

def bw1(+w0: U32, p: U32 & +List<U32>) -> W16 & +List<U32>:
  (w1, r) = p
  bw2(w0, w1, rd4(r))

def bw0(p: U32 & +List<U32>) -> W16 & +List<U32>:
  (w0, r) = p
  bw1(w0, rd4(r))

def block_words(xs: +List<U32>) -> W16 & +List<U32>:
  bw0(rd4(xs))

def compress(+k: +List<U32>, +st: S8, +win: W16) -> S8:
  add8(st, rounds(k, st, win))

def blocks(n: Nat, +k: +List<U32>, wb: W16 & +List<U32>, +st: S8) -> S8:
  match n:
    case 0n:
      st
    case 1n+p:
      (win, rest) = wb
      blocks(p, k, block_words(rest), compress(k, st, win))

def be32(+x: U32) -> +List<U32>:
  [(x >> 24n : U32), ((x >> 16n) .&. 255 : U32), ((x >> 8n) .&. 255 : U32), (x .&. 255 : U32)]

def be32_onto(+x: U32, acc: +List<U32>) -> +List<U32>:
  (x >> 24n : U32) <> ((x >> 16n) .&. 255 : U32) <> ((x >> 8n) .&. 255 : U32) <> (x .&. 255 : U32) <> acc

def digest(st: S8) -> +List<U32>:
  S8{a, b, c, d, e, f, g, h} = st
  be32_onto(a, be32_onto(b, be32_onto(c, be32_onto(d, be32_onto(e, be32_onto(f, be32_onto(g, be32(h))))))))

def zeros_onto(n: Nat, acc: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      zeros_onto(p, 0 <> acc)

# 0x80, then zeros until the length is 56 mod 64, then the bit length (64-bit big-endian).
def padding(+len: U32) -> +List<U32>:
  +zs = ((119 - (len .&. 63)) .&. 63 : U32)
  128 <> zeros_onto(U32.to_nat(zs), be32_onto((len >> 29n : U32), be32((len << 3n : U32))))

# The first n bytes of xs followed by rest (one copy).
def take_onto(n: Nat, xs: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match n xs:
    case 0n _:
      rest
    case 1n+p Con{h, t}:
      h <> take_onto(p, t, rest)
    case 1n+p Nil{}:
      rest

# SHA-256 of the first len bytes of xs (xs must hold at least len bytes).
def hash_n(+xs: +List<U32>, +len: U32) -> +List<U32>:
  +nblk = ((len + 72) >> 6n : U32)
  +k = ks()
  digest(blocks(U32.to_nat(nblk), k, block_words(take_onto(U32.to_nat(len), xs, padding(len))), iv()))

def hash_d_n(+xs: +List<U32>, +len: U32) -> +List<U32>:
  hash_n(hash_n(xs, len), 32)
