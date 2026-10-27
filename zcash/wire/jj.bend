# Jubjub point decoding, exactly as jubjub 0.11 AffinePoint::from_bytes (ZIP 216 enabled):
#   v = the low 255 bits, which must be canonical (< r); sign = bit 255;
#   u^2 = (v^2 - 1) / (1 + d v^2), with 1/0 read as 0 (the crate's unwrap_or(zero));
#   pick the root whose low bit equals sign; reject u = 0 with sign = 1 (ZIP 216).
# Small order (sapling-crypto's from_bytes_not_small_order): [4]P has u = 0. On the curve
# -u^2 + v^2 = 1 + d u^2 v^2 doubling is complete, so u([2]P) = 0 iff u v = 0 and
# v([2]P) = 0 iff u^2 + v^2 = 0; hence [4]P has u = 0 iff u v = 0 or u^2 + v^2 = 0.
import Base
import ../halo2/lib/words.bend as Wd
import ./fr.bend as F

type Jp is Data:
  Jp{u: F.Fr, v: F.Fr}

# d = -10240/10241 mod r
def d() -> F.Fr:
  F.from_words(Wd.W{3593748145, 17194966, 928488742, 690847597, 3871178708, 4127035911, 1274686280, 714283239})

def reject_or(zero: Bool, +u: F.Fr, +v: F.Fr) -> Maybe<&2, Jp>:
  match zero:
    case True{}:
      None{}
    case False{}:
      Some{Jp{F.neg(u), v}}

def fix(flip: Bool, +u: F.Fr, +v: F.Fr) -> Maybe<&2, Jp>:
  match flip:
    case False{}:
      Some{Jp{u, v}}
    case True{}:
      reject_or(F.is_zero(u), u, v)

def with_root(m: Maybe<&2, F.Fr>, +v: F.Fr, +sign: U32) -> Maybe<&2, Jp>:
  match m:
    case None{}:
      None{}
    case Some{u}:
      +uu = u
      fix(U32.is_eq((F.low_bit(uu) .^. sign : U32), 1), uu, v)

def from_v(+v: F.Fr, +sign: U32) -> Maybe<&2, Jp>:
  +v2 = F.sqr(v)
  +num = F.sub(v2, F.one())
  +den = F.add(F.one(), F.mul(d(), v2))
  with_root(F.sqrt(F.mul(num, F.inv(den))), v, sign)

def dec_canon(ok: Bool, +vw: Wd.W, +sign: U32) -> Maybe<&2, Jp>:
  match ok:
    case False{}:
      None{}
    case True{}:
      from_v(F.from_words(vw), sign)

def decode(+w: Wd.W) -> Maybe<&2, Jp>:
  +vw = Wd.clear_top_bit(w)
  dec_canon(Wd.is_lt(vw, F.modulus()), vw, Wd.top_bit(w))

def is_small_order(p: Jp) -> Bool:
  Jp{+u, +v} = p
  F.is_zero(F.mul(u, v)) || F.is_zero(F.add(F.sqr(u), F.sqr(v)))
