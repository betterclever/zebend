# The Sapling Pedersen hash and MerkleCRH^Sapling (protocol spec 5.4.1.7, 5.4.1.3).
#
#   MerkleCRH(layer, l, r) = Extract_J(PedersenHash("Zcash_PH", I2LEBSP_6(layer) || l[0..255] || r[0..255]))
#
# with layer = 0 for the parents of leaves (sapling-crypto's merkle_hash(depth, ..)).
# The 516 message bits are 172 three-bit chunks (a, b, c) -> enc = (1 - 2c)(1 + a + 2b);
# chunk j of segment s (63 chunks per segment) carries weight 2^(4j) on generator I_s:
#   H = sum_s [ sum_j enc_j 2^(4j) ] I_s.
# Two chunks form one signed base-256 digit d = enc_{2k} + 16 enc_{2k+1}, |d| in 12..68
# (never 0, sign of enc_{2k+1}); segment 1 and 2's last chunk (j = 62) is a lone digit in
# 1..4 at 256^31. So a hash is 87 table lookups + 87 mixed additions:
#   windows: segment 1: 32, segment 2: 32, segment 3: 23 (46 chunks).
# Window table (k, s) holds the Niels form of [d * 256^k] I_s for d = 1..68 as a depth-7
# tree walked by |d|'s bits; it is built at start-up from the three generators.
import Base
import ../../halo2/lib/words.bend as Wd
import ../jubjub/fr.bend as F
import ../jubjub/jubjub.bend as J
import ../jubjub/consts.bend as K

# ------------------------------------------------------------------ tables

type WT is Data:
  WLeaf{n: J.Ni}
  WNode{l: WT, r: WT}

# Window: digit width in bits (6 = two chunks, 3 = one chunk) and its table.
type Win is Data:
  Win{bits: U32, t: WT}

type Tab is Data:
  Tab{ws: +List<Win>}

# [1]B .. [n]B (extended), then to Niels via one inversion each.
def mults(n: Nat, +b: J.Pt, +acc: J.Pt) -> +List<J.Pt>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      +nx = J.add(acc, b)
      acc <> mults(k, b, nx)

def ni_of(p: J.Pt) -> J.Ni:
  J.ni_of_aff(J.to_aff(p))

def ni_dummy() -> J.Ni:
  J.Ni{F.one(), F.one(), F.zero()}

# Depth-d tree over entries with index base .. base + 2^d - 1 (entry i = [i]B; index 0 and
# indices past the list are dummies, never looked up).
def wt_build(+d: Nat, xs: +List<J.Ni>) -> WT:
  match d:
    case 0n:
      match xs:
        case Con{h, _}:
          WLeaf{h}
        case Nil{}:
          WLeaf{ni_dummy()}
    case 1n+k:
      +half = Nat.pow(2n, k)
      +ys = xs
      WNode{wt_build(k, List.take(&2, J.Ni, ys, half)), wt_build(k, List.drop(&2, J.Ni, ys, half))}

def ni_list(ps: +List<J.Pt>) -> +List<J.Ni>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{p, t}:
      ni_of(p) <> ni_list(t)

# Table for base B: index 0 dummy, 1..68 = [i]B.
def win_table(+b: J.Pt) -> WT:
  wt_build(7n, ni_dummy() <> ni_list(mults(68n, b, b)))

# [256] p
def x256(p: J.Pt) -> J.Pt:
  J.double(J.double(J.double(J.double(J.double(J.double(J.double(J.double(p))))))))

# n windows of 6 bits starting at base b, then (if last3) one 3-bit window.
def seg_wins(n: Nat, +b: J.Pt, last3: Bool) -> +List<Win>:
  match n:
    case 0n:
      match last3:
        case True{}:
          Win{3, win_table(b)} <> Nil{}
        case False{}:
          Nil{}
    case 1n+k:
      Win{6, win_table(b)} <> seg_wins(k, x256(b), last3)

def tab() -> Tab:
  +s1 = seg_wins(31n, J.from_aff(K.ph0()), True{})
  +s2 = seg_wins(31n, J.from_aff(K.ph1()), True{})
  +s3 = seg_wins(23n, J.from_aff(K.ph2()), False{})
  Tab{List.append(&2, Win, s1, List.append(&2, Win, s2, s3))}

def pick(b: Bool, l: WT, r: WT) -> WT:
  match b:
    case True{}:
      r
    case False{}:
      l

def look(+k: Nat, +i: U32, t: WT) -> J.Ni:
  match k t:
    case _ WLeaf{n}:
      n
    case 1n+j WNode{l, r}:
      look(j, i, pick(U32.is_eq(((i >> j) .&. 1 : U32), 1), l, r))
    case 0n WNode{_, _}:
      ni_dummy()

# ------------------------------------------------------------------ message bit stream

# A piece of the message: the low m bits of w (m <= 32).
type Pc is Data:
  Pc{w: U32, m: U32}

# buf holds n pending bits (n < 32).
type BS is Data:
  BS{buf: U32, n: U32, ps: +List<Pc>}

type Took is Data:
  Took{v: U32, st: BS}

def mask(+k: U32) -> U32:
  ((1 << U32.to_nat(k)) - 1 : U32)

# Every piece is at least 6 bits wide, so one piece always completes a take (k <= 6).
def fill_b(done: Bool, +k: U32, +v: U32, +w: U32, +n: U32, +m: U32, rest: +List<Pc>) -> Took:
  match done:
    case True{}:
      Took{(v .&. mask(k) : U32), BS{(w >> U32.to_nat((k - n : U32)) : U32), (n + m - k : U32), rest}}
    case False{}:
      Took{(v .&. mask(k) : U32), BS{0, 0, Nil{}}}

# Shifts by 32 are avoided: n < 32 and k - n <= 6 < 32 throughout.
def take_fill(+k: U32, +buf: U32, +n: U32, ps: +List<Pc>) -> Took:
  match ps:
    case Nil{}:
      Took{(buf .&. mask(k) : U32), BS{0, 0, Nil{}}}
    case Con{Pc{+w, +m}, rest}:
      fill_b(U32.is_ge((n + m : U32), k), k, (buf .|. (w << U32.to_nat(n)) : U32), w, n, m, rest)

def take_b(have: Bool, +k: U32, +buf: U32, +n: U32, ps: +List<Pc>) -> Took:
  match have:
    case True{}:
      Took{(buf .&. mask(k) : U32), BS{(buf >> U32.to_nat(k) : U32), (n - k : U32), ps}}
    case False{}:
      take_fill(k, buf, n, ps)

def take(+k: U32, st: BS) -> Took:
  BS{+buf, +n, ps} = st
  take_b(U32.is_ge(n, k), k, buf, n, ps)

# The 8 words of a 255-bit value as pieces (top word 31 bits).
def w_pcs(w: Wd.W, tail: +List<Pc>) -> +List<Pc>:
  Wd.W{a, b, c, d, e, f, g, h} = w
  Pc{a, 32} <> Pc{b, 32} <> Pc{c, 32} <> Pc{d, 32} <> Pc{e, 32} <> Pc{f, 32} <> Pc{g, 32} <> Pc{(h .&. 2147483647 : U32), 31} <> tail

def msg(+layer: U32, l: Wd.W, r: Wd.W) -> BS:
  BS{0, 0, Pc{(layer .&. 63 : U32), 6} <> w_pcs(l, w_pcs(r, Nil{}))}

# ------------------------------------------------------------------ hashing

# |enc| of a 3-bit chunk: 1 + a + 2b.
def mag(+c: U32) -> U32:
  (1 + (c .&. 3) : U32)

def sgn(+c: U32) -> U32:
  ((c >> 2n) .&. 1 : U32)

# Signed digit of a window value v (bits = 6: two chunks; 3: one chunk) -> (|d|, negative?).
def pair_abs(same: Bool, +c0: U32, +c1: U32) -> U32:
  match same:
    case True{}:
      (16 * mag(c1) + mag(c0) : U32)
    case False{}:
      (16 * mag(c1) - mag(c0) : U32)

def digit_abs_b(two: Bool, +v: U32) -> U32:
  match two:
    case True{}:
      +c0 = (v .&. 7 : U32)
      +c1 = (v >> 3n : U32)
      pair_abs(U32.is_eq(sgn(c0), sgn(c1)), c0, c1)
    case False{}:
      mag(v)

def digit_abs(+bits: U32, +v: U32) -> U32:
  digit_abs_b(U32.is_eq(bits, 6), v)

def digit_neg(+bits: U32, +v: U32) -> Bool:
  U32.is_eq(sgn((v >> U32.to_nat((bits - 3 : U32)) : U32)), 1)

def signed_ni(neg: Bool, n: J.Ni) -> J.Ni:
  match neg:
    case True{}:
      J.ni_neg(n)
    case False{}:
      n

def step(w: Win, +v: U32, acc: J.Pt) -> J.Pt:
  Win{+bits, t} = w
  J.add_ni(acc, signed_ni(digit_neg(bits, v), look(7n, digit_abs(bits, v), t)))

def win_bits(w: Win) -> U32:
  Win{bits, _} = w
  bits

def took_v(t: Took) -> U32:
  Took{v, _} = t
  v

def took_st(t: Took) -> BS:
  Took{_, st} = t
  st

def fold(ws: +List<Win>, st: BS, acc: J.Pt) -> J.Pt:
  match ws:
    case Nil{}:
      acc
    case Con{+w, rest}:
      +t = take(win_bits(w), st)
      fold(rest, took_st(t), step(w, took_v(t), acc))

# The Pedersen hash point of I2LEBSP_6(layer) || l || r.
def hash_pt(+g: Tab, +layer: U32, l: Wd.W, r: Wd.W) -> J.Pt:
  Tab{ws} = g
  fold(ws, msg(layer, l, r), J.identity())

# MerkleCRH^Sapling: the u-coordinate, canonical LE words.
def merkle(+g: Tab, +layer: U32, l: Wd.W, r: Wd.W) -> Wd.W:
  J.u_of(hash_pt(g, layer, l, r))
