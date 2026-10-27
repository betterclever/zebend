# CompactSize exactly as zcash_encoding::CompactSize::read accepts it:
#   < 253         the byte itself
#   253 + u16     must be >= 253
#   254 + u32     must be >= 2^16
#   255 + u64     must be >= 2^32, which always exceeds the cap below
# and the value must be <= MAX_COMPACT_SIZE = 0x02000000. Fixes zcash/p2p's reader,
# which accepted non-canonical encodings (e.g. fd 05 00 as 5).
import Base
import ./hb.bend as H

def max_size() -> U32:
  33554432

def keep(ok: Bool, r: H.V) -> Maybe<&2, H.V>:
  match ok:
    case True{}:
      Some{r}
    case False{}:
      None{}

# A wide form must encode a value that needs it (canonical) and respect the cap.
def wide_check(+min: U32, r: H.V) -> Maybe<&2, H.V>:
  H.V{+v, +s} = r
  keep(U32.is_le(min, v) && U32.is_le(v, max_size()), H.V{v, s})

def wide(+min: U32, m: Maybe<&2, H.V>) -> Maybe<&2, H.V>:
  match m:
    case None{}:
      None{}
    case Some{r}:
      wide_check(min, r)

def by_254(is254: Bool, +s: H.S) -> Maybe<&2, H.V>:
  match is254:
    case True{}:
      wide(65536, H.rd(s, 4))
    case False{}:
      None{}

def by_253(is253: Bool, +f: U32, +s: H.S) -> Maybe<&2, H.V>:
  match is253:
    case True{}:
      wide(253, H.rd(s, 2))
    case False{}:
      by_254(U32.is_eq(f, 254), s)

def by_flag(small: Bool, +f: U32, +s: H.S) -> Maybe<&2, H.V>:
  match small:
    case True{}:
      Some{H.V{f, s}}
    case False{}:
      by_253(U32.is_eq(f, 253), f, s)

def after_flag(r: H.V) -> Maybe<&2, H.V>:
  H.V{+f, +s} = r
  by_flag(U32.is_lt(f, 253), f, s)

# Read a canonical, capped CompactSize.
def read(+s: H.S) -> Maybe<&2, H.V>:
  do Maybe<&2, H.V>:
    f : H.V <- H.u8(s)
    r : H.V <- after_flag(f)
    return r
