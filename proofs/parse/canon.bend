# A canonical-checking CompactSize decoder over node/p2p's decoder: it accepts a
# decoded value only if the bytes it consumed are exactly the minimal encoding,
# as zcashd's ReadCompactSize requires ("non-canonical ReadCompactSize()").
import Base
import ../../node/p2p/bytes.bend as B

def check(ok: Bool, c: B.Compact) -> Maybe<&2, B.Compact>:
  match ok:
    case True{}:
      Some{c}
    case False{}:
      None{}

def go(+xs: +List<U32>, c: B.Compact) -> Maybe<&2, B.Compact>:
  B.Compact{+v, +w} = c
  check(B.is_eq(B.take_u(xs, w), B.compact(v)), B.Compact{v, w})

def read_compact_canon(+xs: +List<U32>) -> Maybe<&2, B.Compact>:
  go(xs, B.read_compact(xs))
