# Usage: block_main <block.bin> <hist.bin> <height> <verified headers file> <first height in it>
#   block.bin: a raw mainnet block; hist.bin: its 32-byte chain history root (ZIP 221,
#   internal byte order): the one input taken from outside (an oracle, labelled).
# Prints the same lines as the Rust oracle's <height>.expected, then whether the block's
# header is byte-identical to the header node/headers verified (Equihash, target, links).
import Base
import ./block.bend as K
import ./tx.bend as T
import ./bytes.bend as Y
import ./sha256.bend as S
import ./util.bend as U
import ../wire/blk.bend as KB

def bytes_of(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> +List<U32>:
  (_, res) = r
  match res:
    case Done{bs}:
      bs
    case Fail{_}:
      Nil{}

def len_of(i: K.Info) -> Nat:
  K.Info{n, _, _, _} = i
  n

def id_of(i: K.Info) -> +List<U32>:
  K.Info{_, d, _, _} = i
  d

def auth_of(i: K.Info) -> +List<U32>:
  K.Info{_, _, a, _} = i
  a

def infos(n: Nat, +xs: +List<U32>) -> List<&2, K.Info>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +i = K.info(xs)
      i <> infos(p, Y.drop(xs, len_of(i)))

def ids(xs_i: List<&2, K.Info>) -> List<&2, +List<U32>>:
  match xs_i:
    case Nil{}:
      Nil{}
    case Con{i, t}:
      id_of(i) <> ids(t)

def auths(xs_i: List<&2, K.Info>) -> List<&2, +List<U32>>:
  match xs_i:
    case Nil{}:
      Nil{}
    case Con{i, t}:
      auth_of(i) <> auths(t)

def tx_line(+k: Nat, i: K.Info) -> String:
  K.Info{n, d, a, v} = i
  "tx " ++ Nat.show(k) ++ " v" ++ U32.show(v) ++ " bytes " ++ Nat.show(n) ++ " txid " ++ U.bhex(d) ++ " auth " ++ U.bhex(a) ++ "\n"

def tx_lines(xs_i: List<&2, K.Info>, +k: Nat) -> String:
  match xs_i:
    case Nil{}:
      ""
    case Con{i, t}:
      tx_line(k, i) ++ tx_lines(t, 1n+k)

def verdict(b: Bool) -> String:
  match b:
    case True{}:
      "MATCH"
    case False{}:
      "MISMATCH"

def report(+height: U32, +blk: +List<U32>, +hist: +List<U32>, +verified: +List<U32>) -> String:
  +hdr = Y.take(blk, 1487n)
  +rest = Y.drop(blk, 1487n)
  +n = T.cs_val(rest, 0n)
  +xs_i = infos(n, Y.drop(rest, T.cs_size(rest, 0n)))
  +mr = K.merkle_root(ids(xs_i))
  +ar = K.auth_root(auths(xs_i))
  +bc = K.block_commitments(hist, ar)
  tx_lines(xs_i, 0n)
    ++ "block " ++ U32.show(height) ++ " hash " ++ U.bhex(S.hash_d(hdr)) ++ " txs " ++ Nat.show(n) ++ "\n"
    ++ "merkle " ++ U.bhex(mr) ++ " " ++ verdict(Y.is_eq(mr, T.at(hdr, 36n, 32n))) ++ "\n"
    ++ "authroot " ++ U.bhex(ar) ++ "\n"
    ++ "commitments " ++ U.bhex(bc) ++ " " ++ verdict(Y.is_eq(bc, T.at(hdr, 68n, 32n))) ++ "\n"
    ++ "verified_header " ++ verdict(Y.is_eq(hdr, verified)) ++ "\n"

# Blocks go through the wire validator first (node/wire/blk.bend: header, CompactSize tx count,
# every transaction well-formed, exact end, at most MAX_BLOCK_SIZE = 2,000,000 bytes),
# differentially fuzzed against zcash_primitives; only accepted blocks reach the digest code.
def gated(m: Maybe<&2, U32>, +height: U32, +blk: +List<U32>, +hist: +List<U32>, +verified: +List<U32>) -> String:
  match m:
    case Some{_}:
      report(height, blk, hist, verified)
    case None{}:
      "INVALID malformed or oversized block (rejected by the wire validator)\n"

def or_zero(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{v}:
      v
    case None{}:
      0

def num(s: String) -> U32:
  or_zero(U32.read(s))

type Args is Type:
  Args{blk: String, hist: String, h: String, hdrs: String, h0: String}

def args_of(xs: List<String>) -> Args:
  match xs:
    case Con{_, Con{b, Con{hi, Con{h, Con{f, Con{s, _}}}}}}:
      Args{b, hi, h, f, s}
    case _:
      Args{"", "", "0", "", "0"}

def run(a: Args) -> IO(Unit):
  Args{bp, hp, hs, fp, h0s} = a
  +h = num(hs)
  +h0 = num(h0s)
  do IO<Unit>:
    f : File <- IO.try(File, File.open(bp, "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 2000001)
    g : File <- IO.try(File, File.open(hp, "r"))
    s : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(g, 64)
    v : File <- IO.try(File, File.open(fp, "r"))
    w : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(v, ((h - h0 : U32) * 1487 : U32), 1487)
    +blk : +List<U32> = bytes_of(r)
    IO.print(gated(KB.parse_capped(blk), h, blk, bytes_of(s), bytes_of(w)))

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<String> <- IO.args()
    run(args_of(xs))
