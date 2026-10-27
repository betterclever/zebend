# Block headers and blocks, matching zcash_primitives BlockHeader::read + Transaction::read.
# A header is 140 fixed bytes, then the Equihash solution as a CompactSize-prefixed vector,
# which Zebend requires to be the (200,9) length 1344: canonically fd 40 05, 1487 bytes total.
# A block is a header, a CompactSize transaction count, the transactions, and nothing after.
import Base
import ../../../zcash/wire/hb.bend as H
import ../../../zcash/wire/cs.bend as CS
import ./txv.bend as T

def header_len() -> U32:
  1487

# MAX_BLOCK_SIZE (consensus): checked against the input length before anything is parsed.
def max_block() -> U32:
  2000000

# The smallest possible transaction (Sprout v1: header, two empty vectors, lock_time).
def min_tx() -> U32:
  10

def header_at(+xs: +List<U32>) -> Bool:
  U32.is_eq(H.at(xs, 140), 253) && U32.is_eq(H.at(xs, 141), 64) && U32.is_eq(H.at(xs, 142), 5)

# A byte string that is exactly one header.
def header_ok(+xs: +List<U32>) -> Bool:
  U32.is_eq(H.length(xs), header_len()) && header_at(xs)

def txs(n: Nat, +s: H.S) -> Maybe<&2, H.S>:
  match n:
    case 0n:
      Some{s}
    case 1n+m:
      do Maybe<&2, H.S>:
        s2 : H.S <- T.tx(s)
        s3 : H.S <- txs(m, s2)
        return s3

def keep_n(+n: U32, m: Maybe<&2, H.S>) -> Maybe<&2, H.V>:
  match m:
    case None{}:
      None{}
    case Some{s}:
      Some{H.V{n, s}}

def counted(fits: Bool, c: H.V) -> Maybe<&2, H.V>:
  match fits:
    case False{}:
      None{}
    case True{}:
      H.V{+n, +s} = c
      keep_n(n, txs(U32.to_nat(n), s))

# The count is bounded by the remaining bytes before any transaction is read.
def bounded(c: H.V) -> Maybe<&2, H.V>:
  H.V{+n, +s} = c
  counted(U32.is_le(n, (H.rem(s) / min_tx() : U32)), H.V{n, s})

def body(+s: H.S) -> Maybe<&2, H.V>:
  do Maybe<&2, H.V>:
    c : H.V <- CS.read(s)
    r : H.V <- bounded(c)
    return r

def after_header(ok: Bool, +s: H.S) -> Maybe<&2, H.V>:
  match ok:
    case False{}:
      None{}
    case True{}:
      do Maybe<&2, H.V>:
        t : H.S <- H.skip(s, header_len())
        r : H.V <- body(t)
        return r

def when_done(ok: Bool, +n: U32) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      Some{n}
    case False{}:
      None{}

def done_count(m: Maybe<&2, H.V>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{r}:
      H.V{+n, +s} = r
      when_done(H.is_done(s), n)

# A whole byte string that is exactly one block; answers its transaction count.
def parse(+xs: +List<U32>) -> Maybe<&2, U32>:
  +s = H.start(xs)
  done_count(after_header(U32.is_le(header_len(), H.rem(s)) && header_at(xs), s))

def capped(ok: Bool, +xs: +List<U32>) -> Maybe<&2, U32>:
  match ok:
    case False{}:
      None{}
    case True{}:
      parse(xs)

# parse, with the consensus size limit applied first.
def parse_capped(+xs: +List<U32>) -> Maybe<&2, U32>:
  capped(U32.is_le(H.length(xs), max_block()), xs)
