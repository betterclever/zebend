# Zcash difficulty adjustment in every era, Mainnet and Testnet (protocol § 7.7.3 + ZIP 218;
# Zebra 1e03ee75 zebra-state/src/service/check/difficulty.rs AdjustedDifficulty):
#
#   W        = PoWAveragingWindow(h)            17 before NU7, 102 from NU7
#   mean     = floor(sum of the targets of the last W blocks / W)   (17 limbs: 102 Testnet
#              targets of up to 2^251 overflow 256 bits; Zebra sums quotients and remainders)
#   actual   = MTP(h - 1) - MTP(h - 1 - W)      (MTP = median of 11 block times)
#   bounded  = era7.timespan(era, actual)       (damping /4, clamp to [84%, 132%] of AWT)
#   next     = min(mean / AWT * bounded, PoWLimit), re-encoded in compact form
#   Testnet: if h >= 299,188 and time(h) - time(h - 1) > 6 spacings (18 from NU7), next = PoWLimit.
#
# The 256-bit limb arithmetic is blake3x/eqv3/diff.bend's (the code follow and tiphdr run,
# tested on every mainnet header); this file adds the height/network dependence.
import Base
import ../../../blake3x/eqv3/pow.bend as P
import ../../../blake3x/eqv3/diff.bend as D
import ../nu7.bend as N
import ../era7.bend as E

def limbs17(+bits: U32) -> +List<U32>:
  List.append(&2, U32, D.limbs(bits), [0])

def zeros17() -> +List<U32>:
  List.replicate(U32, 17n, 0)

def sum17(bs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match bs:
    case Con{+b, rest}:
      sum17(rest, D.add(acc, limbs17(b)))
    case Nil{}:
      acc

# PoWLimit in compact form (Zebra target_difficulty_limit().to_compact()):
# Mainnet 2^243 - 1 -> 0x1f07ffff, Testnet 2^251 - 1 -> 0x2007ffff.
def limit_bits(n: N.Net) -> U32:
  match n:
    case N.Main{}:
      520617983
    case N.Test{}:
      537395199

def is_test(n: N.Net) -> Bool:
  match n:
    case N.Main{}:
      False{}
    case N.Test{}:
      True{}

def bounded7(+e: E.Era, d: D.SD) -> Nat:
  D.SD{neg, mag} = d
  E.timespan(e, neg, mag)

def first_time(xs: +List<U32>) -> U32:
  match xs:
    case Con{t, _}:
      t
    case Nil{}:
      0

# ThresholdBits for the block at h (era e) from its newest-first (time, bits) context.
def threshold(+n: N.Net, +e: E.Era, +xs: +List<D.TB>) -> U32:
  +w = E.WINDOW(e)
  +ts = D.times(xs)
  +mtp_last = D.median11(ts)
  +mtp_first = D.median11(List.drop(&2, U32, ts, w))
  +avg = D.div_small(D.rev(sum17(List.take(&2, U32, D.bitss(xs), w), zeros17())), U32.from_nat(w), 0)
  +scaled = D.mul_small(D.rev(D.div_small(avg, U32.from_nat(E.AWT(e)), 0)), U32.from_nat(bounded7(e, D.sdiff(mtp_last, mtp_first))), 0)
  D.compact(D.limb_bytes(D.rev(D.min_target(scaled, limbs17(limit_bits(n))))))

def min_diff_sel(c: Bool, +n: N.Net, +e: E.Era, +xs: +List<D.TB>) -> U32:
  match c:
    case True{}:
      limit_bits(n)
    case False{}:
      threshold(n, e, xs)

# Testnet minimum-difficulty block: strictly more than the gap after the previous block.
def min_diff(+n: N.Net, +h: Nat, +e: E.Era, +t: U32, +prev: U32) -> Bool:
  is_test(n) && Nat.is_ge(h, U32.to_nat(299188)) && U32.is_gt(t, prev)
    && Nat.is_lt(E.MIN_DIFF_GAP(e), U32.to_nat((t - prev : U32)))

# The nBits the block at height h with time t must carry.
def expected7(+n: N.Net, +h: Nat, +xs: +List<D.TB>, +t: U32) -> U32:
  +e = E.era_of(n, h)
  min_diff_sel(min_diff(n, h, e, t, first_time(D.times(xs))), n, e, xs)

# Context needed: PoWAveragingWindow(h) + PoWMedianBlockSpan.
def span(+n: N.Net, +h: Nat) -> Nat:
  Nat.add(E.WINDOW(E.era_of(n, h)), 11n)

def check7.go(c: Bool, +n: N.Net, +h: Nat, +xs: +List<D.TB>, +t: U32, +bits: U32) -> D.DC:
  match c:
    case True{}:
      D.DC{True{}, U32.is_eq(expected7(n, h, xs, t), bits)}
    case False{}:
      D.DC{False{}, False{}}

# Checks the nBits of the block at h against its predecessors (newest first), if enough.
def check7(+n: N.Net, +h: Nat, w: D.Win, +t: U32, +bits: U32) -> D.DC:
  D.Win{+xs} = w
  check7.go(Nat.is_ge(List.length(&2, D.TB, xs), span(n, h)), n, h, xs, t, bits)

# Keeps the 113 newest (time, bits): the largest span (102 + 11).
def push7(w: D.Win, +t: U32, +b: U32) -> D.Win:
  D.Win{xs} = w
  D.Win{List.take(&2, D.TB, D.TB{t, b} <> xs, 113n)}
