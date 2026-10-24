# Zcash difficulty timespan for both mainnet spacing eras (protocol spec § 7.7.3,
# zcashd pow.cpp CalculateNextWorkRequired with params.*(nextHeight)):
#
#   pre-Blossom  (next height <  653,600): PoWTargetSpacing 150 s, AWT = 17 * 150 = 2550 s
#   post-Blossom (next height >= 653,600): PoWTargetSpacing  75 s, AWT = 17 *  75 = 1275 s
#   MinActualTimespan = AWT * (100 - 16) / 100,  MaxActualTimespan = AWT * (100 + 32) / 100
#
# Same structure as node/headers/diff.bend's timespan, with the era as a parameter;
# LAWS.bend proves the post-Blossom instance equals node/headers' function exactly.
import Base

type Era is Data:
  Pre{}
  Post{}

def BLOSSOM() -> U32:
  653600

# The era that applies to the block at height h (the block whose nBits is checked).
def era_of.go(c: Bool) -> Era:
  match c:
    case True{}:
      Pre{}
    case False{}:
      Post{}

def era_of(+h: U32) -> Era:
  era_of.go(U32.is_lt(h, BLOSSOM()))

def AWT(e: Era) -> Nat:
  match e:
    case Pre{}:
      2550n
    case Post{}:
      1275n

def MIN_TS(e: Era) -> Nat:
  match e:
    case Pre{}:
      2142n
    case Post{}:
      1071n

def MAX_TS(e: Era) -> Nat:
  match e:
    case Pre{}:
      3366n
    case Post{}:
      1683n

def damp.pos(+e: Era, c: Bool, +mag: Nat) -> Nat:
  match c:
    case True{}:
      Nat.sub(AWT(e), Nat.div(Nat.sub(AWT(e), mag), 4n))
    case False{}:
      Nat.add(AWT(e), Nat.div(Nat.sub(mag, AWT(e)), 4n))

def damp(+e: Era, neg: Bool, +mag: Nat) -> Nat:
  match neg:
    case True{}:
      Nat.sub(AWT(e), Nat.div(Nat.add(mag, AWT(e)), 4n))
    case False{}:
      damp.pos(e, Nat.is_lt(mag, AWT(e)), mag)

def clamp.hi(+e: Era, c: Bool, x: Nat) -> Nat:
  match c:
    case True{}:
      MAX_TS(e)
    case False{}:
      x

def clamp.lo(+e: Era, c: Bool, +x: Nat) -> Nat:
  match c:
    case True{}:
      MIN_TS(e)
    case False{}:
      clamp.hi(e, Nat.is_lt(MAX_TS(e), x), x)

def clamp(+e: Era, +x: Nat) -> Nat:
  clamp.lo(e, Nat.is_lt(x, MIN_TS(e)), x)

def timespan(+e: Era, neg: Bool, +mag: Nat) -> Nat:
  clamp(e, damp(e, neg, mag))
