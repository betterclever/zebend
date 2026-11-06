# fq2.decompress2 vs decomp's decompress, lane by lane: every pair of the 9 edge encodings
# (x = 0 either sign, p - 1, p, p + 1, 2^255 - 1, ...), and 2^18 random encodings in pairs (half
# with x in [0, 2^255), so non-canonical x is common). Prints mismatches (must be 0) and the valid count.
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ../../../crypto/field3/fq64.bend as Fq
import ../../../crypto/field3/lib64/vesta.bend as V
import ../../decomp/vesta_dec.bend as VD
import ../lib/fq2.bend as F2

def xs(+s: U32) -> U32:
  +a = (s .^. (s << 13n) : U32)
  +b = (a .^. (a >> 17n) : U32)
  (b .^. (b << 5n) : U32)

# Random encodings: the low 255 bits uniform below 2^254 (or 2^255 when s is odd: x >= p is
# then common), sign bit from s.
def rw(+s: U32) -> Wd.W:
  +s1 = xs(s)
  +s2 = xs(s1)
  +s3 = xs(s2)
  +s4 = xs(s3)
  +s5 = xs(s4)
  +s6 = xs(s5)
  +s7 = xs(s6)
  +s8 = xs(s7)
  +top = (s8 .&. (1073741823 + ((s .&. 1 : U32) << 30n)) : U32)
  Wd.W{s1, s2, s3, s4, s5, s6, s7, (top .|. ((s .&. 2 : U32) << 30n) : U32)}

def next8(+s: U32) -> U32:
  xs(xs(xs(xs(xs(xs(xs(xs(s))))))))

def edges(+i: U32) -> Wd.W:
  match i:
    case 0:
      Wd.W{0, 0, 0, 0, 0, 0, 0, 0}
    case 1:
      Wd.W{0, 0, 0, 0, 0, 0, 0, 2147483648}
    case 2:
      Wd.W{0, 2569875693, 156039451, 575052028, 0, 0, 0, 1073741824}
    case 3:
      Wd.W{1, 2569875693, 156039451, 575052028, 0, 0, 0, 1073741824}
    case 4:
      Wd.W{2, 2569875693, 156039451, 575052028, 0, 0, 0, 1073741824}
    case 5:
      Wd.W{0, 2353457953, 160737501, 575052028, 0, 0, 0, 1073741824}
    case 6:
      Wd.W{1, 2353457953, 160737501, 575052028, 0, 0, 0, 1073741824}
    case 7:
      Wd.W{4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 2147483647}
    case _:
      Wd.W{5, 0, 0, 0, 0, 0, 0, 2147483648}

type D is Data:
  D{bad: U32, ok: U32}

def dadd(a: D, b: D) -> D:
  D{+x, +y} = a
  D{+u, +v} = b
  D{(x + u : U32), (y + v : U32)}

def v_same(+a: V.Pt, +b: V.Pt) -> Bool:
  V.Pt{+ax, +ay, +az} = a
  V.Pt{+bx, +by, +bz} = b
  Bool.and(Fq.is_eq(ax, bx), Bool.and(Fq.is_eq(ay, by), Fq.is_eq(az, bz)))

def cmp_some(+a: V.Pt, c: VD.Dec) -> D:
  VD.Dec{+cok, +cp} = c
  D{Bool.to_u32(Bool.not(Bool.and(U32.is_eq(cok, 1), v_same(a, cp)))), 1}

def cmp_none(c: VD.Dec) -> D:
  VD.Dec{+cok, _} = c
  D{Bool.to_u32(Bool.not(U32.is_eq(cok, 0))), 0}

def cmp1(m: Maybe<&2, V.Pt>, c: VD.Dec) -> D:
  match m:
    case Some{+a}:
      cmp_some(a, c)
    case None{}:
      cmp_none(c)

def cmp2(+w1: Wd.W, +w2: Wd.W, d: F2.D2) -> D:
  F2.D2{+a, +b} = d
  dadd(cmp1(VD.decompress(w1), a), cmp1(VD.decompress(w2), b))

def pair(+w1: Wd.W, +w2: Wd.W) -> D:
  cmp2(w1, w2, F2.decompress2(w1, w2))

def edge_j(n: Nat, +i: U32, +j: U32, a: D) -> D:
  match n:
    case 0n:
      a
    case 1n+k:
      edge_j(k, i, (j + 1 : U32), dadd(a, pair(edges(i), edges(j))))

def edge_i(n: Nat, +i: U32, a: D) -> D:
  match n:
    case 0n:
      a
    case 1n+k:
      edge_i(k, (i + 1 : U32), edge_j(9n, i, 0, a))

def run(n: Nat, +s: U32, a: D) -> D:
  match n:
    case 0n:
      a
    case 1n+k:
      run(k, next8(next8(s)), dadd(a, pair(rw(s), rw(next8(s)))))

def par(+d: Nat, +seed: U32, +n: Nat) -> D:
  match d:
    case 0n:
      run(n, (seed * 2654435761 + 99 : U32), D{0, 0})
    case 1n+p:
      a b = par(p, (seed * 2 : U32), n) par(p, (seed * 2 + 1 : U32), n)
      dadd(a, b)

def show(+s: String, d: D) -> String:
  D{+b, +o} = d
  s ++ ": mismatches " ++ U32.show(b) ++ ", valid " ++ U32.show(o)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(show("edge pairs (9 x 9)", edge_i(9n, 0, D{0, 0})))
    IO.print(show("random 2^18 encodings in 2^17 pairs", par(7n, 5, 1024n)))
