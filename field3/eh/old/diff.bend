# Zcash difficulty adjustment (protocol spec § 7.7.3; zcashd pow.cpp
# GetNextWorkRequired / CalculateNextWorkRequired), mainnet, post-Blossom:
#
#   avg      = (sum of the targets of the last 17 blocks) / 17
#   actual   = MTP(last) - MTP(last - 17)        (MTP = median of 11 block times)
#   damped   = AWT + (actual - AWT) / 4          (AWT = 17 * 75 s = 1275 s; C++ truncation)
#   bounded  = clamp(damped, 1071, 1683)         (max adjust up 16%, down 32%)
#   next     = min(avg / AWT * bounded, powLimit), re-encoded in compact form
#
# The timespan part (damping + clamp) runs on Nat so its laws can be proven about
# the exact function the verifier executes (see LAWS.bend). The 256-bit target
# arithmetic runs on 16-bit limbs and is checked against mainnet data.
import Base
import ./pow.bend as P

# ---------------------------------------------------------------------------
# Timespan (proven part)
# ---------------------------------------------------------------------------

def AWT() -> Nat:
  1275n

def MIN_TS() -> Nat:
  1071n

def MAX_TS() -> Nat:
  1683n

# Damping of a signed actual timespan (neg, mag), matching C++ int64 truncation:
#   actual >= AWT:      AWT + (actual - AWT) / 4
#   0 <= actual < AWT:  AWT - (AWT - actual) / 4
#   actual = -mag < 0:  AWT - (mag + AWT) / 4   (saturating at 0; the clamp lifts it to MIN_TS)
def damp.pos(c: Bool, +mag: Nat) -> Nat:
  match c:
    case True{}:
      Nat.sub(AWT(), Nat.div(Nat.sub(AWT(), mag), 4n))
    case False{}:
      Nat.add(AWT(), Nat.div(Nat.sub(mag, AWT()), 4n))

def damp(neg: Bool, +mag: Nat) -> Nat:
  match neg:
    case True{}:
      Nat.sub(AWT(), Nat.div(Nat.add(mag, AWT()), 4n))
    case False{}:
      damp.pos(Nat.is_lt(mag, AWT()), mag)

def clamp.hi(c: Bool, x: Nat) -> Nat:
  match c:
    case True{}:
      MAX_TS()
    case False{}:
      x

def clamp.lo(c: Bool, +x: Nat) -> Nat:
  match c:
    case True{}:
      MIN_TS()
    case False{}:
      clamp.hi(Nat.is_lt(MAX_TS(), x), x)

def clamp(+x: Nat) -> Nat:
  clamp.lo(Nat.is_lt(x, MIN_TS()), x)

# The bounded actual timespan used to scale the average target.
def timespan(neg: Bool, +mag: Nat) -> Nat:
  clamp(damp(neg, mag))

# ---------------------------------------------------------------------------
# 256-bit targets as 16 little-endian 16-bit limbs (tested part)
# ---------------------------------------------------------------------------

def place16.go(c: Bool, +m: U32, +k: U32, +base: U32) -> U32:
  match c:
    case True{}:
      (P.shr_safe(m, (base - k : U32)) .&. 65535 : U32)
    case False{}:
      (P.shl_safe(m, (k - base : U32)) .&. 65535 : U32)

def place16(+m: U32, +k: U32, +base: U32) -> U32:
  place16.go(U32.is_le(k, base), m, k, base)

def limbs.go(n: Nat, +m: U32, +k: U32, +base: U32) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      place16(m, k, base) <> limbs.go(p, m, k, (base + 16 : U32))

# target(nBits) as 16 LE limbs.
def limbs(+bits: U32) -> +List<U32>:
  limbs.go(16n, (bits .&. 8388607 : U32), (((bits >> 24n) - 3 : U32) * 8 : U32), 0)

def add.go(a: +List<U32>, b: +List<U32>, +c: U32) -> +List<U32>:
  match a:
    case Con{x, xs}:
      match b:
        case Con{y, ys}:
          +s = (x + y + c : U32)
          (s .&. 65535 : U32) <> add.go(xs, ys, (s >> 16n : U32))
        case Nil{}:
          Nil{}
    case Nil{}:
      Nil{}

def add(a: +List<U32>, b: +List<U32>) -> +List<U32>:
  add.go(a, b, 0)

# Multiply LE limbs by m < 2^16.
def mul_small(a: +List<U32>, +m: U32, +c: U32) -> +List<U32>:
  match a:
    case Con{x, xs}:
      +s = ((x * m) + c : U32)
      (s .&. 65535 : U32) <> mul_small(xs, m, (s >> 16n : U32))
    case Nil{}:
      Nil{}

# Divide most-significant-first limbs by d < 2^16; quotient most-significant-first.
def div_small(a: +List<U32>, +d: U32, +r: U32) -> +List<U32>:
  match a:
    case Con{x, xs}:
      +cur = ((r << 16n) .|. x : U32)
      (cur / d : U32) <> div_small(xs, d, (cur % d : U32))
    case Nil{}:
      Nil{}

def rev(xs: +List<U32>) -> +List<U32>:
  P.rev(xs, Nil{})

# Limbs (most significant first) -> bytes (most significant first).
def limb_bytes(xs: +List<U32>) -> +List<U32>:
  match xs:
    case Con{+x, rest}:
      (x >> 8n : U32) <> (x .&. 255 : U32) <> limb_bytes(rest)
    case Nil{}:
      Nil{}

def prepend_unless(c: Bool, +x: U32, ys: +List<U32>) -> +List<U32>:
  match c:
    case True{}:
      ys
    case False{}:
      x <> ys

# Drops leading zeros (lead = still inside the leading run).
def drop_zeros(xs: +List<U32>, +lead: Bool) -> +List<U32>:
  match xs:
    case Con{+x, rest}:
      +z = lead && U32.is_eq(x, 0)
      prepend_unless(z, x, drop_zeros(rest, z))
    case Nil{}:
      Nil{}

def at(xs: +List<U32>, n: Nat) -> U32:
  P.w(List.drop(&2, U32, xs, n))

def compact.fin(c: Bool, +b0: U32, +b1: U32, +b2: U32, +size: U32) -> U32:
  match c:
    case True{}:
      ((b0 << 8n) .|. b1 .|. ((size + 1 : U32) << 24n) : U32)
    case False{}:
      ((b0 << 16n) .|. (b1 << 8n) .|. b2 .|. (size << 24n) : U32)

# arith_uint256::GetCompact of a most-significant-first byte string.
def compact(+bs: +List<U32>) -> U32:
  +ds = drop_zeros(bs, True{})
  +size = U32.from_nat(List.length(&2, U32, ds))
  +b0 = at(ds, 0n)
  compact.fin(U32.is_ge(b0, 128), b0, at(ds, 1n), at(ds, 2n), size)

# powLimit (mainnet): 0x0007ffff << 8*(0x1f - 3).
def pow_limit() -> +List<U32>:
  limbs(520617983)

def min_target.go(c: Bool, +a: +List<U32>, +b: +List<U32>) -> +List<U32>:
  match c:
    case True{}:
      a
    case False{}:
      b

def min_target(+a: +List<U32>, +b: +List<U32>) -> +List<U32>:
  min_target.go(P.le_desc(rev(a), rev(b)), a, b)


# ---------------------------------------------------------------------------
# Window of recent (time, bits), newest first
# ---------------------------------------------------------------------------

type TB is Data:
  TB{t: U32, b: U32}

type Win is Data:
  Win{xs: +List<TB>}

def empty() -> Win:
  Win{Nil{}}

def push(w: Win, +t: U32, +b: U32) -> Win:
  Win{xs} = w
  Win{List.take(&2, TB, TB{t, b} <> xs, 28n)}

def times(xs: +List<TB>) -> +List<U32>:
  match xs:
    case Con{x, rest}:
      TB{t, _} = x
      t <> times(rest)
    case Nil{}:
      Nil{}

def bitss(xs: +List<TB>) -> +List<U32>:
  match xs:
    case Con{x, rest}:
      TB{_, b} = x
      b <> bitss(rest)
    case Nil{}:
      Nil{}

def median11(xs: +List<U32>) -> U32:
  at(List.sort(~U32, ~U32.is_le, List.take(&2, U32, xs, 11n)), 5n)

def sum_targets(bs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match bs:
    case Con{+b, rest}:
      sum_targets(rest, add(acc, limbs(b)))
    case Nil{}:
      acc

def zeros16() -> +List<U32>:
  List.replicate(U32, 16n, 0)

# Capped signed difference last - first, so the Nat damping stays small.
# Any |actual| >= 100000 s is far outside [1071, 1683] after damping, so capping
# does not change the clamped result.
type SD is Data:
  SD{neg: Bool, mag: Nat}

def cap(+x: U32) -> Nat:
  U32.to_nat(U32.min(x, 100000))

def sdiff.go(c: Bool, +last: U32, +first: U32) -> SD:
  match c:
    case True{}:
      SD{False{}, cap((last - first : U32))}
    case False{}:
      SD{True{}, cap((first - last : U32))}

def sdiff(+last: U32, +first: U32) -> SD:
  sdiff.go(U32.is_ge(last, first), last, first)

def bounded(d: SD) -> Nat:
  SD{neg, mag} = d
  timespan(neg, mag)

# The nBits the next block must carry, from the 28 most recent (time, bits).
def expected(+xs: +List<TB>) -> U32:
  +ts = times(xs)
  +mtp_last = median11(ts)
  +mtp_first = median11(List.drop(&2, U32, ts, 17n))
  +avg = div_small(rev(sum_targets(List.take(&2, U32, bitss(xs), 17n), zeros16())), 17, 0)
  +scaled = mul_small(rev(div_small(avg, 1275, 0)), U32.from_nat(bounded(sdiff(mtp_last, mtp_first))), 0)
  compact(limb_bytes(rev(min_target(scaled, pow_limit()))))

type DC is Data:
  DC{applies: Bool, ok: Bool}

def check.go(c: Bool, +xs: +List<TB>, +bits: U32) -> DC:
  match c:
    case True{}:
      DC{True{}, U32.is_eq(expected(xs), bits)}
    case False{}:
      DC{False{}, False{}}

# Checks a header's nBits against the window of its 28 predecessors (if available).
def check(w: Win, +bits: U32) -> DC:
  Win{+xs} = w
  check.go(Nat.is_eq(List.length(&2, TB, xs), 28n), xs, bits)

def ok(d: DC) -> Bool:
  DC{_, k} = d
  k

def applies(d: DC) -> Bool:
  DC{a, _} = d
  a
