# Proofs of LAWS.bend.
import Base
import ./LAWS.bend as L
import ../../zcash/p2p/bytes.bend as B
import ./canon.bend as C
import ./wordlemmas.bend as W
import ./bits.bend as T
import ../../zcash/headers/main.bend as M

# ---- small helpers ------------------------------------------------------------

def mk3(v: U32) -> B.Compact:
  B.Compact{v, 3}

def mk5(v: U32) -> B.Compact:
  B.Compact{v, 5}

def and_r(+y: Bool, x: Bool) -> Bool:
  Bool.and(x, y)

def and2(+x: Bool, +y: Bool, ex: {x == True{} : Bool}, ey: {y == True{} : Bool}) -> {Bool.and(x, y) == True{} : Bool}:
  Equal.trans(Bool, Bool.and(x, y), Bool.and(True{}, y), True{}, Equal.cong(Bool, Bool, and_r(y), x, True{}, ex), ey)

def bcmp_refl(b: Bool) -> {Bool.cmp(b, b) == EQ{} : Cmp}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def fin_c(+b: Bool, c: Cmp) -> Cmp:
  Word.cmp.fin(b, b, c)

def wcmp_refl(+n: Nat, w: Word(n)) -> {Word.cmp(n, w, w) == EQ{} : Cmp}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      match w:
        case WCon{+b, +t}:
          Equal.trans(Cmp, Word.cmp.fin(b, b, Word.cmp(p, t, t)), Word.cmp.fin(b, b, EQ{}), EQ{},
            Equal.cong(Cmp, Cmp, fin_c(b), Word.cmp(p, t, t), EQ{}, wcmp_refl(p, t)),
            bcmp_refl(b))

def u32_eq_refl(a: U32) -> {U32.is_eq(a, a) == True{} : Bool}:
  match a:
    case U32{+w}:
      Equal.cong(Cmp, Bool, Cmp.is_eq, Word.cmp(32n, w, w), EQ{}, wcmp_refl(32n, w))

def list_eq_refl(xs: +List<U32>) -> {B.is_eq(xs, xs) == True{} : Bool}:
  match xs:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      and2(U32.is_eq(h, h), B.is_eq(t, t), u32_eq_refl(h), list_eq_refl(t))

# ---- CompactSize round trip ---------------------------------------------------

def rsel(c: Bool, +b: U32, +r: +List<U32>) -> {c == True{} : Bool} -> {B.read_compact_sel(c, b, r) == B.Compact{b, 1} : B.Compact}:
  match c:
    case True{}:
      h => {==}
    case False{}:
      h => W.absurd({B.read_compact_sel(False{}, b, r) == B.Compact{b, 1} : B.Compact}, W.false_not_true(h))

# ---- comparison symmetry -------------------------------------------------------

def flip(c: Cmp) -> Cmp:
  match c:
    case LT{}:
      GT{}
    case EQ{}:
      EQ{}
    case GT{}:
      LT{}

def bcmp_flip(a: Bool, b: Bool) -> {Bool.cmp(b, a) == flip(Bool.cmp(a, b)) : Cmp}:
  match a b:
    case True{} True{}:
      {==}
    case True{} False{}:
      {==}
    case False{} True{}:
      {==}
    case False{} False{}:
      {==}

def fin_flip(+ab: Bool, +bb: Bool, t: Cmp) -> {Word.cmp.fin(bb, ab, flip(t)) == flip(Word.cmp.fin(ab, bb, t)) : Cmp}:
  match t:
    case LT{}:
      {==}
    case EQ{}:
      bcmp_flip(ab, bb)
    case GT{}:
      {==}

def fin_cc(+bb: Bool, +ab: Bool, t: Cmp) -> Cmp:
  Word.cmp.fin(bb, ab, t)

# Word.cmp is antisymmetric: swapping the operands flips the result.
def wcmp_flip(+n: Nat, a: Word(n), b: Word(n)) -> {Word.cmp(n, b, a) == flip(Word.cmp(n, a, b)) : Cmp}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      match a b:
        case WCon{+ab, +at} WCon{+bb, +bt}:
          Equal.trans(Cmp, Word.cmp.fin(bb, ab, Word.cmp(p, bt, at)), Word.cmp.fin(bb, ab, flip(Word.cmp(p, at, bt))), flip(Word.cmp.fin(ab, bb, Word.cmp(p, at, bt))),
            Equal.cong(Cmp, Cmp, fin_cc(bb, ab), Word.cmp(p, bt, at), flip(Word.cmp(p, at, bt)), wcmp_flip(p, at, bt)),
            fin_flip(ab, bb, Word.cmp(p, at, bt)))

def lt_flip_le(c: Cmp) -> {Cmp.is_lt(c) == False{} : Bool} -> {Cmp.is_le(flip(c)) == True{} : Bool}:
  match c:
    case LT{}:
      h => W.absurd({Cmp.is_le(flip(LT{})) == True{} : Bool}, W.false_not_true(Equal.sym(Bool, True{}, False{}, h)))
    case EQ{}:
      h => {==}
    case GT{}:
      h => {==}

def le_of_cmp(c: Cmp) -> Bool:
  Cmp.is_le(c)

# Not (a < b) gives b <= a.
def not_lt_le(a: U32, b: U32) -> {U32.is_lt(a, b) == False{} : Bool} -> {U32.is_le(b, a) == True{} : Bool}:
  match a b:
    case U32{+x} U32{+y}:
      h => Equal.trans(Bool, Cmp.is_le(Word.cmp(32n, y, x)), Cmp.is_le(flip(Word.cmp(32n, x, y))), True{},
        Equal.cong(Cmp, Bool, le_of_cmp, Word.cmp(32n, y, x), flip(Word.cmp(32n, x, y)), wcmp_flip(32n, x, y)),
        lt_flip_le(Word.cmp(32n, x, y), h))

# ---- CompactSize round trip (canonical, capped decoder) -------------------------

# has(xs, 0) holds for any list (the reader's 0-byte check on the abstract tail).
def has0(xs: +List<U32>) -> {B.has(xs, 0n) == True{} : Bool}:
  match xs:
    case Nil{}:
      {==}
    case Con{_, _}:
      {==}

def rne(+xs: +List<U32>, b: Bool) -> B.Compact:
  B.read_compact_nonempty(b, xs)

def okc(+g: U32, +w: U32, b: Bool) -> B.Compact:
  B.compact_ok(b, g, w)

def le_lo(+k: U32, x: U32) -> Bool:
  U32.is_le(k, x)

def le_hi(+k: U32, x: U32) -> Bool:
  U32.is_le(x, k)

# n in [253, 2^16): fd + le16(n) decodes to n, width 3, whatever follows.
def rt.r16(+n: U32, +rest: +List<U32>, hc: {U32.is_lt(n, 253) == False{} : Bool}, +hd: {U32.is_lt(n, 65536) == True{} : Bool}) -> {B.read_compact(B.append(253 <> B.le16(n), rest)) == B.Compact{n, 3} : B.Compact}:
  Equal.trans(B.Compact, B.compact_ok(Bool.and(B.has(rest, 0n), U32.is_le(253, B.get_le16(B.le16(n)))), B.get_le16(B.le16(n)), 3), B.Compact{B.get_le16(B.le16(n)), 3}, B.Compact{n, 3},
    Equal.cong(Bool, B.Compact, okc(B.get_le16(B.le16(n)), 3), Bool.and(B.has(rest, 0n), U32.is_le(253, B.get_le16(B.le16(n)))), True{},
      and2(B.has(rest, 0n), U32.is_le(253, B.get_le16(B.le16(n))), has0(rest),
        Equal.trans(Bool, U32.is_le(253, B.get_le16(B.le16(n))), U32.is_le(253, n), True{},
          Equal.cong(U32, Bool, le_lo(253), B.get_le16(B.le16(n)), n, T.le16.rt(n, hd)),
          not_lt_le(n, 253, hc)))),
    Equal.cong(U32, B.Compact, mk3, B.get_le16(B.le16(n)), n, T.le16.rt(n, hd)))

# n in [2^16, 0x02000000]: fe + le32(n) decodes to n, width 5, whatever follows.
def rt.r32(+n: U32, +rest: +List<U32>, hd: {U32.is_lt(n, 65536) == False{} : Bool}, hcap: {U32.is_le(n, 33554432) == True{} : Bool}) -> {B.read_compact(B.append(254 <> B.le32(n), rest)) == B.Compact{n, 5} : B.Compact}:
  Equal.trans(B.Compact, B.compact_ok(Bool.and(Bool.and(B.has(rest, 0n), U32.is_le(65536, B.get_le32(B.le32(n)))), U32.is_le(B.get_le32(B.le32(n)), 33554432)), B.get_le32(B.le32(n)), 5), B.Compact{B.get_le32(B.le32(n)), 5}, B.Compact{n, 5},
    Equal.cong(Bool, B.Compact, okc(B.get_le32(B.le32(n)), 5), Bool.and(Bool.and(B.has(rest, 0n), U32.is_le(65536, B.get_le32(B.le32(n)))), U32.is_le(B.get_le32(B.le32(n)), 33554432)), True{},
      and2(Bool.and(B.has(rest, 0n), U32.is_le(65536, B.get_le32(B.le32(n)))), U32.is_le(B.get_le32(B.le32(n)), 33554432),
        and2(B.has(rest, 0n), U32.is_le(65536, B.get_le32(B.le32(n))), has0(rest),
        Equal.trans(Bool, U32.is_le(65536, B.get_le32(B.le32(n))), U32.is_le(65536, n), True{},
          Equal.cong(U32, Bool, le_lo(65536), B.get_le32(B.le32(n)), n, T.le32.rt(n)),
          not_lt_le(n, 65536, hd))),
        Equal.trans(Bool, U32.is_le(B.get_le32(B.le32(n)), 33554432), U32.is_le(n, 33554432), True{},
          Equal.cong(U32, Bool, le_hi(33554432), B.get_le32(B.le32(n)), n, T.le32.rt(n)),
          hcap))),
    Equal.cong(U32, B.Compact, mk5, B.get_le32(B.le32(n)), n, T.le32.rt(n)))

def rt.big(+n: U32, +rest: +List<U32>, hc: {U32.is_lt(n, 253) == False{} : Bool}, hcap: {U32.is_le(n, 33554432) == True{} : Bool}, d: Bool) -> {U32.is_lt(n, 65536) == d : Bool} -> {B.read_compact(B.append(B.compact_big(d, n), rest)) == B.Compact{n, B.length(B.compact_big(d, n))} : B.Compact}:
  match d:
    case True{}:
      hd => rt.r16(n, rest, hc, hd)
    case False{}:
      hd => rt.r32(n, rest, hd, hcap)

def rt.sel(+n: U32, +rest: +List<U32>, hcap: {U32.is_le(n, 33554432) == True{} : Bool}, c: Bool) -> {U32.is_lt(n, 253) == c : Bool} -> {B.read_compact(B.append(B.compact_sel(c, n), rest)) == B.Compact{n, B.length(B.compact_sel(c, n))} : B.Compact}:
  match c:
    case True{}:
      h => Equal.trans(B.Compact, B.read_compact_nonempty(B.has(rest, 0n), n <> rest), B.read_compact_nonempty(True{}, n <> rest), B.Compact{n, 1},
        Equal.cong(Bool, B.Compact, rne(n <> rest), B.has(rest, 0n), True{}, has0(rest)),
        rsel(U32.is_lt(n, 253), n, B.drop(n <> rest, 1n), h))
    case False{}:
      h => rt.big(n, rest, h, hcap, U32.is_lt(n, 65536), {==})

def compact_rt(+n: U32, +rest: +List<U32>, hcap: {U32.is_le(n, 33554432) == True{} : Bool}) -> {B.read_compact(B.append(B.compact(n), rest)) == B.Compact{n, B.length(B.compact(n))} : B.Compact}:
  rt.sel(n, rest, hcap, U32.is_lt(n, 253), {==})

# ---- canonical decoder ----------------------------------------------------------

def check_c(+c: B.Compact, ok: Bool) -> Maybe<&2, B.Compact>:
  C.check(ok, c)

def go_c(+xs: +List<U32>, c: B.Compact) -> Maybe<&2, B.Compact>:
  C.go(xs, c)

# The prefix check succeeds on an encoding followed by anything (per size class).
# `rest` is split so that take(rest, 0n) reduces.
def pre.r16(+n: U32, rest: +List<U32>) -> {B.is_eq(B.take_u(B.append(253 <> B.le16(n), rest), 3), 253 <> B.le16(n)) == True{} : Bool}:
  match rest:
    case Nil{}:
      list_eq_refl(253 <> B.le16(n))
    case Con{_, _}:
      list_eq_refl(253 <> B.le16(n))

def pre.r32(+n: U32, rest: +List<U32>) -> {B.is_eq(B.take_u(B.append(254 <> B.le32(n), rest), 5), 254 <> B.le32(n)) == True{} : Bool}:
  match rest:
    case Nil{}:
      list_eq_refl(254 <> B.le32(n))
    case Con{_, _}:
      list_eq_refl(254 <> B.le32(n))

def pre.r8(+n: U32, rest: +List<U32>) -> {B.is_eq(B.take_u(B.append([n], rest), 1), [n]) == True{} : Bool}:
  match rest:
    case Nil{}:
      list_eq_refl([n])
    case Con{_, _}:
      list_eq_refl([n])

def pre.big(+n: U32, +rest: +List<U32>, d: Bool) -> {B.is_eq(B.take_u(B.append(B.compact_big(d, n), rest), B.length(B.compact_big(d, n))), B.compact_big(d, n)) == True{} : Bool}:
  match d:
    case True{}:
      pre.r16(n, rest)
    case False{}:
      pre.r32(n, rest)

def pre.sel(+n: U32, +rest: +List<U32>, c: Bool) -> {B.is_eq(B.take_u(B.append(B.compact_sel(c, n), rest), B.length(B.compact_sel(c, n))), B.compact_sel(c, n)) == True{} : Bool}:
  match c:
    case True{}:
      pre.r8(n, rest)
    case False{}:
      pre.big(n, rest, U32.is_lt(n, 65536))

def canon_ok(+n: U32, +rest: +List<U32>, hcap: {U32.is_le(n, 33554432) == True{} : Bool}) -> {C.read_compact_canon(B.append(B.compact(n), rest)) == Some{B.Compact{n, B.length(B.compact(n))}} : Maybe<&2, B.Compact>}:
  +xs : +List<U32> = B.append(B.compact(n), rest)
  +c : B.Compact = B.Compact{n, B.length(B.compact(n))}
  Equal.trans(Maybe<&2, B.Compact>, C.go(xs, B.read_compact(xs)), C.go(xs, c), Some{c},
    Equal.cong(B.Compact, Maybe<&2, B.Compact>, go_c(xs), B.read_compact(xs), c, compact_rt(n, rest, hcap)),
    Equal.cong(Bool, Maybe<&2, B.Compact>, check_c(c), B.is_eq(B.take_u(xs, B.length(B.compact(n))), B.compact(n)), True{}, pre.sel(n, rest, U32.is_lt(n, 253))))

# ---- soundness of the canonical decoder -----------------------------------------

def get_v(m: Maybe<&2, B.Compact>) -> U32:
  match m:
    case Some{c}:
      B.Compact{v, _} = c
      v
    case None{}:
      0

def get_w(m: Maybe<&2, B.Compact>) -> U32:
  match m:
    case Some{c}:
      B.Compact{_, w} = c
      w
    case None{}:
      0

def is_some(m: Maybe<&2, B.Compact>) -> Bool:
  match m:
    case Some{c}:
      True{}
    case None{}:
      False{}

def eq_at_v(+xs: +List<U32>, +cw: U32, a: U32) -> Bool:
  B.is_eq(B.take_u(xs, cw), B.compact(a))

def eq_at_w(+xs: +List<U32>, +v: U32, b: U32) -> Bool:
  B.is_eq(B.take_u(xs, b), B.compact(v))

def snd.check(+xs: +List<U32>, +cv: U32, +cw: U32, +v: U32, +w: U32, ok: Bool) -> {B.is_eq(B.take_u(xs, cw), B.compact(cv)) == ok : Bool} -> {C.check(ok, B.Compact{cv, cw}) == Some{B.Compact{v, w}} : Maybe<&2, B.Compact>} -> {B.is_eq(B.take_u(xs, w), B.compact(v)) == True{} : Bool}:
  match ok:
    case True{}:
      e => +h =>
        +ev = Equal.cong(Maybe<&2, B.Compact>, U32, get_v, Some{B.Compact{cv, cw}}, Some{B.Compact{v, w}}, h)
        +ew = Equal.cong(Maybe<&2, B.Compact>, U32, get_w, Some{B.Compact{cv, cw}}, Some{B.Compact{v, w}}, h)
        Equal.trans(Bool, B.is_eq(B.take_u(xs, w), B.compact(v)), B.is_eq(B.take_u(xs, cw), B.compact(cv)), True{},
          Equal.trans(Bool, B.is_eq(B.take_u(xs, w), B.compact(v)), B.is_eq(B.take_u(xs, cw), B.compact(v)), B.is_eq(B.take_u(xs, cw), B.compact(cv)),
            Equal.sym(Bool, B.is_eq(B.take_u(xs, cw), B.compact(v)), B.is_eq(B.take_u(xs, w), B.compact(v)), Equal.cong(U32, Bool, eq_at_w(xs, v), cw, w, ew)),
            Equal.sym(Bool, B.is_eq(B.take_u(xs, cw), B.compact(cv)), B.is_eq(B.take_u(xs, cw), B.compact(v)), Equal.cong(U32, Bool, eq_at_v(xs, cw), cv, v, ev))),
          e)
    case False{}:
      e => h => W.absurd({B.is_eq(B.take_u(xs, w), B.compact(v)) == True{} : Bool}, W.false_not_true(Equal.cong(Maybe<&2, B.Compact>, Bool, is_some, None{}, Some{B.Compact{v, w}}, h)))

def snd.go(+xs: +List<U32>, +v: U32, +w: U32, c: B.Compact) -> {C.go(xs, c) == Some{B.Compact{v, w}} : Maybe<&2, B.Compact>} -> {B.is_eq(B.take_u(xs, w), B.compact(v)) == True{} : Bool}:
  match c:
    case B.Compact{+cv, +cw}:
      snd.check(xs, cv, cw, v, w, B.is_eq(B.take_u(xs, cw), B.compact(cv)), {==})

# ---- the laws ---------------------------------------------------------------------

def L.le32_roundtrip(x):
  T.le32.rt(x)

def L.le16_roundtrip(x, h):
  T.le16.rt(x, h)

def L.compact_roundtrip(n, rest, h):
  compact_rt(n, rest, h)

def L.noncanonical_rejected():
  {==}

def L.ff_rejected():
  {==}

def L.over_cap_rejected():
  {==}

def L.noncanonical_differs():
  {==}

def L.canon_rejects_example():
  {==}

def L.canon_accepts(n, rest, h):
  canon_ok(n, rest, h)

def L.canon_sound(xs, v, w, h):
  snd.go(xs, v, w, B.read_compact(xs), h)

# ---- header stream split -----------------------------------------------------------

def cons_c(+h: U32, t: +List<U32>) -> +List<U32>:
  h <> t

# take(xs, a + b) == take(xs, a) ++ take(drop(xs, a), b)
def take_add(+a: Nat, xs: +List<U32>, +b: Nat) -> {List.take(&2, U32, xs, Nat.add(a, b)) == List.append(&2, U32, List.take(&2, U32, xs, a), List.take(&2, U32, List.drop(&2, U32, xs, a), b)) : +List<U32>}:
  match a:
    case 0n:
      match xs:
        case Nil{}:
          {==}
        case Con{_, _}:
          {==}
    case 1n+p:
      match xs:
        case Nil{}:
          {==}
        case Con{+h, +t}:
          Equal.cong(+List<U32>, +List<U32>, cons_c(h), List.take(&2, U32, t, Nat.add(p, b)), List.append(&2, U32, List.take(&2, U32, t, p), List.take(&2, U32, List.drop(&2, U32, t, p), b)), take_add(p, t, b))

def app_c(+pre: +List<U32>, ys: +List<U32>) -> +List<U32>:
  List.append(&2, U32, pre, ys)

def take0(xs: +List<U32>) -> {List.take(&2, U32, xs, 0n) == Nil{} : +List<U32>}:
  match xs:
    case Nil{}:
      {==}
    case Con{_, _}:
      {==}

def split_concat(+k: Nat, +bs: +List<U32>) -> {List.concat(&2, U32, M.split(k, bs)) == List.take(&2, U32, bs, Nat.mul(k, 1487n)) : +List<U32>}:
  match k:
    case 0n:
      Equal.sym(+List<U32>, List.take(&2, U32, bs, 0n), Nil{}, take0(bs))
    case 1n+p:
      +pre : +List<U32> = List.take(&2, U32, bs, 1487n)
      +rest : +List<U32> = List.drop(&2, U32, bs, 1487n)
      Equal.trans(+List<U32>,
        List.append(&2, U32, pre, List.concat(&2, U32, M.split(p, rest))),
        List.append(&2, U32, pre, List.take(&2, U32, rest, Nat.mul(p, 1487n))),
        List.take(&2, U32, bs, Nat.add(1487n, Nat.mul(p, 1487n))),
        Equal.cong(+List<U32>, +List<U32>, app_c(pre), List.concat(&2, U32, M.split(p, rest)), List.take(&2, U32, rest, Nat.mul(p, 1487n)), split_concat(p, rest)),
        Equal.sym(+List<U32>, List.take(&2, U32, bs, Nat.add(1487n, Nat.mul(p, 1487n))), List.append(&2, U32, pre, List.take(&2, U32, rest, Nat.mul(p, 1487n))), take_add(1487n, bs, Nat.mul(p, 1487n))))

def L.header_split_concat(k, bs):
  split_concat(k, bs)
