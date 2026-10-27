# Difficulty adjustment parameters in all three spacing eras (protocol § 7.7.3 as amended by
# ZIP 218, Zebra 1e03ee75 zebra-chain network_upgrade.rs / zebra-state check/difficulty.rs):
#
#   era         heights               PoWTargetSpacing  PoWAveragingWindow  AWT     Min/Max actual timespan
#   pre-Blossom h <  Blossom          150 s             17                  2550 s  2142 / 3366
#   post-Bloss. Blossom <= h < NU7     75 s             17                  1275 s  1071 / 1683
#   NU7         h >= NU7               25 s             102                 2550 s  2142 / 3366
#
#   MinActualTimespan = AWT * (100 - 16) / 100, MaxActualTimespan = AWT * (100 + 32) / 100,
#   ActualTimespanDamped = AWT + (ActualTimespan - AWT) / 4 (C/Rust truncation toward zero).
# The era is that of the block whose nBits is checked. Testnet minimum-difficulty threshold
# (ZIPs 205/208/218): a gap strictly greater than 6 spacings (pre-NU7) or 18 spacings (NU7):
# 900 s / 450 s / 450 s, from testnet height 299,188.
#
# Same structure as proofs/difficulty/era.bend (whose pre/post instances LAWS.bend shows equal
# to these), with the NU7 era added. The timespan runs on Nat so its laws are about this code.
import Base
import ./nu7.bend as N

type Era is Data:
  Pre{}
  Post{}
  Nu7{}

def era_lt_nu7(c: Bool) -> Era:
  match c:
    case True{}:
      Post{}
    case False{}:
      Nu7{}

def era_sel(c: Bool, +n: N.Net, +h: Nat) -> Era:
  match c:
    case True{}:
      Pre{}
    case False{}:
      era_lt_nu7(Nat.is_lt(h, N.nu7(n)))

# The era of the block at height h on network n.
def era_of(+n: N.Net, +h: Nat) -> Era:
  era_sel(Nat.is_lt(h, N.blossom(n)), n, h)

def SPACING(e: Era) -> Nat:
  match e:
    case Pre{}:
      150n
    case Post{}:
      75n
    case Nu7{}:
      25n

def WINDOW(e: Era) -> Nat:
  match e:
    case Pre{}:
      17n
    case Post{}:
      17n
    case Nu7{}:
      102n

def AWT(e: Era) -> Nat:
  match e:
    case Pre{}:
      2550n
    case Post{}:
      1275n
    case Nu7{}:
      2550n

def MIN_TS(e: Era) -> Nat:
  match e:
    case Pre{}:
      2142n
    case Post{}:
      1071n
    case Nu7{}:
      2142n

def MAX_TS(e: Era) -> Nat:
  match e:
    case Pre{}:
      3366n
    case Post{}:
      1683n
    case Nu7{}:
      3366n

# Testnet minimum-difficulty gap: 6 spacings before NU7, 18 from NU7 (ZIP 218).
def MIN_DIFF_GAP(e: Era) -> Nat:
  match e:
    case Pre{}:
      900n
    case Post{}:
      450n
    case Nu7{}:
      450n

def damp.pos(+e: Era, c: Bool, +mag: Nat) -> Nat:
  match c:
    case True{}:
      Nat.sub(AWT(e), Nat.div(Nat.sub(AWT(e), mag), 4n))
    case False{}:
      Nat.add(AWT(e), Nat.div(Nat.sub(mag, AWT(e)), 4n))

# Damping of a signed actual timespan (neg, mag), matching truncation toward zero.
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

# ActualTimespanBounded.
def timespan(+e: Era, neg: Bool, +mag: Nat) -> Nat:
  clamp(e, damp(e, neg, mag))
