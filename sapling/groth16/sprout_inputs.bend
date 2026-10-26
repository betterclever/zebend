# Public inputs of a post-Sapling Sprout JoinSplit's Groth16 proof, from its raw fields, as
# zcash_proofs::sprout::verify_proof packs them:
#   h_sig = BLAKE2b-256("ZcashComputehSig", randomSeed | nf1 | nf2 | joinSplitPubKey)
#   bytes = rt | h_sig | nf1 | mac1 | nf2 | mac2 | cm1 | cm2 | vpub_old (8 LE) | vpub_new (8 LE)
#   bits  = each byte most significant bit first (bellman multipack::bytes_to_bits)
#   inputs = consecutive 254-bit chunks, bit k of a chunk worth 2^k (compute_multipacking): 9
# BLAKE2b is node/tx's (imported read-only).
import Base
import ../../halo2/lib/words.bend as Wd
import ../../node/tx/blake2b.bend as B2

def pers() -> B2.P4:
  B2.P4{1935762266, 1836008296, 1702131056, 1734955880}

# LE words -> bytes
def bytes(ws: +List<U32>) -> +List<U32>:
  match ws:
    case Con{+w, t}:
      (w .&. 255 : U32) <> ((w >> 8n) .&. 255 : U32) <> ((w >> 16n) .&. 255 : U32) <> (w >> 24n : U32) <> bytes(t)
    case Nil{}:
      Nil{}

def field(+i: Nat, +bs: +List<U32>) -> +List<U32>:
  List.take(&2, U32, List.drop(&2, U32, bs, Nat.mul(32n, i)), 32n)

# each byte's bits, most significant first
def bits(bs: +List<U32>) -> +List<U32>:
  match bs:
    case Con{+b, t}:
      ((b >> 7n) .&. 1 : U32) <> ((b >> 6n) .&. 1 : U32) <> ((b >> 5n) .&. 1 : U32) <> ((b >> 4n) .&. 1 : U32) <> ((b >> 3n) .&. 1 : U32) <> ((b >> 2n) .&. 1 : U32) <> ((b >> 1n) .&. 1 : U32) <> (b .&. 1 : U32) <> bits(t)
    case Nil{}:
      Nil{}

def sel_or(+i: U32, +j: U32, +w: U32, +v: U32) -> U32:
  (w .|. (v * Bool.to_u32(U32.is_eq(i, j))) : U32)

# set bit `pos` (< 256) of an 8-word LE integer to `bit`'s value (it was 0)
def put(w: Wd.W, +pos: U32, +bit: U32) -> Wd.W:
  Wd.W{a0, a1, a2, a3, a4, a5, a6, a7} = w
  +i = (pos >> 5n : U32)
  +v = (bit << U32.to_nat((pos .&. 31 : U32)) : U32)
  Wd.W{sel_or(i, 0, a0, v), sel_or(i, 1, a1, v), sel_or(i, 2, a2, v), sel_or(i, 3, a3, v), sel_or(i, 4, a4, v), sel_or(i, 5, a5, v), sel_or(i, 6, a6, v), sel_or(i, 7, a7, v)}

# the first n bits of xs as an integer (bit k worth 2^k)
def chunk(bs: +List<U32>, n: Nat, +pos: U32, w: Wd.W) -> Wd.W:
  match bs n:
    case Con{+b, t} 1n+k:
      chunk(t, k, (pos + 1 : U32), put(w, pos, b))
    case _ _:
      w

def wl(w: Wd.W) -> +List<U32>:
  Wd.W{a, b, c, d, e, f, g, h} = w
  [a, b, c, d, e, f, g, h]

def packs(fuel: Nat, +bs: +List<U32>) -> +List<U32>:
  match fuel bs:
    case 1n+k Con{_, _}:
      List.append(&2, U32, wl(chunk(bs, 254n, 0, Wd.zero())), packs(k, List.drop(&2, U32, bs, 254n)))
    case _ _:
      Nil{}

# raw: 76 LE words (304 bytes) = rt | randomSeed | nf1 | nf2 | mac1 | mac2 | cm1 | cm2 | joinSplitPubKey |
# vpub_old | vpub_new. Returns the 9 inputs, 8 LE words each.
def inputs(+raw: +List<U32>) -> +List<U32>:
  +bs = bytes(raw)
  +hs = B2.hash32(pers(), List.append(&2, U32, field(1n, bs), List.append(&2, U32, field(2n, bs), List.append(&2, U32, field(3n, bs), field(8n, bs)))))
  +msg = List.append(&2, U32, field(0n, bs), List.append(&2, U32, hs, List.append(&2, U32, field(2n, bs), List.append(&2, U32, field(4n, bs), List.append(&2, U32, field(3n, bs), List.append(&2, U32, field(5n, bs), List.append(&2, U32, field(6n, bs), List.append(&2, U32, field(7n, bs), List.take(&2, U32, List.drop(&2, U32, bs, 288n), 16n)))))))))
  packs(9n, bits(msg))
