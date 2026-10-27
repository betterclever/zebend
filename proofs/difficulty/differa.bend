# Era-aware expected nBits: zcash/headers' target arithmetic (imported unchanged) with the
# proven era.bend timespan and the era's averaging window timespan.
import Base
import ./era.bend as E
import ../../zcash/headers/diff.bend as D

def bounded(+e: E.Era, d: D.SD) -> Nat:
  D.SD{neg, mag} = d
  E.timespan(e, neg, mag)

def expected(+e: E.Era, +xs: +List<D.TB>) -> U32:
  +ts = D.times(xs)
  +mtp_last = D.median11(ts)
  +mtp_first = D.median11(List.drop(&2, U32, ts, 17n))
  +avg = D.div_small(D.rev(D.sum_targets(List.take(&2, U32, D.bitss(xs), 17n), D.zeros16())), 17, 0)
  +scaled = D.mul_small(D.rev(D.div_small(avg, U32.from_nat(E.AWT(e)), 0)), U32.from_nat(bounded(e, D.sdiff(mtp_last, mtp_first))), 0)
  D.compact(D.limb_bytes(D.rev(D.min_target(scaled, D.pow_limit()))))
