import Base
import ../field/natlemmas.bend as N
import ../field/wordadd.bend as W
import ../prims/natlib.bend as L
import ../prims/words.bend as Ws
import ../prims/hi.bend as H
import ../prims/u32.bend as U
import ./bits.bend as Bt
import ./u32bits.bend as UB
import ./ac.bend as A

# U32 operations on values: exact addition and subtraction when nothing wraps,
# 0/1 words, and the branch-free mask select the field code uses.

# --- addition -----------------------------------------------------------------

law add_exact:
  for +a: U32
  for +b: U32
  for +l: L.Le(Nat.add(U32.to_nat(a), U32.to_nat(b)), Ws.mask(32n))
  {U32.to_nat(U32.add(a, b)) == Nat.add(U32.to_nat(a), U32.to_nat(b)) : Nat}

def add_exact(a, b, l):
  Equal.trans(Nat, U32.to_nat(U32.add(a, b)), Nat.mod(Nat.add(U32.to_nat(a), U32.to_nat(b)), 1n+Ws.mask(32n)), Nat.add(U32.to_nat(a), U32.to_nat(b)),
    U.u32_add(a, b), L.mod_small(Nat.add(U32.to_nat(a), U32.to_nat(b)), Ws.mask(32n), l))

# --- subtraction --------------------------------------------------------------

# Word.sub(a, b) = adc(a, b, True, True) is adc(a, not b, False, True).
law adc_not:
  for +n: Nat
  for +a: Word(n)
  for +b: Word(n)
  for +c: Bool
  {Word.adc(n, a, b, True{}, c) == Word.adc(n, a, Word.not(n, b), False{}, c) : Word(n)}

def adc_not(n, a, b, c):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match a:
        case WCon{ab, at}:
          match ab:
            case False{}:
              match b:
                case WCon{bb, bt}:
                  Equal.cong(Word(p), Word(1n+p), v => WCon{Bool.xor(Bool.not(bb), c), v}, Word.adc(p, at, bt, True{}, Bool.and(Bool.not(bb), c)), Word.adc(p, at, Word.not(p, bt), False{}, Bool.and(Bool.not(bb), c)), adc_not(p, at, bt, Bool.and(Bool.not(bb), c)))
            case True{}:
              match b:
                case WCon{bb, bt}:
                  Equal.cong(Word(p), Word(1n+p), v => WCon{Bool.not(Bool.xor(Bool.not(bb), c)), v}, Word.adc(p, at, bt, True{}, Bool.or(Bool.not(bb), c)), Word.adc(p, at, Word.not(p, bt), False{}, Bool.or(Bool.not(bb), c)), adc_not(p, at, bt, Bool.or(Bool.not(bb), c)))

def not_dbl(+p: Nat, +bt: Word(p), ih: {Nat.add(Word.to_nat(p, Word.not(p, bt)), Word.to_nat(p, bt)) == Ws.mask(p) : Nat}) -> {Nat.add(Nat.double(Word.to_nat(p, Word.not(p, bt))), Nat.double(Word.to_nat(p, bt))) == Nat.double(Ws.mask(p)) : Nat}:
  %N.double_add(Word.to_nat(p, Word.not(p, bt)), Word.to_nat(p, bt)) : {_ == Nat.double(Ws.mask(p)) : Nat}
  Equal.cong(Nat, Nat, v => Nat.double(v), Nat.add(Word.to_nat(p, Word.not(p, bt)), Word.to_nat(p, bt)), Ws.mask(p), ih)

# not(b) + b == 2^n - 1
law not_tn:
  for +n: Nat
  for +b: Word(n)
  {Nat.add(Word.to_nat(n, Word.not(n, b)), Word.to_nat(n, b)) == Ws.mask(n) : Nat}

def not_tn(n, b):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match b:
        case WCon{bb, bt}:
          match bb:
            case False{}:
              Equal.cong(Nat, Nat, v => 1n+v, Nat.add(Nat.double(Word.to_nat(p, Word.not(p, bt))), Nat.double(Word.to_nat(p, bt))), Nat.double(Ws.mask(p)), not_dbl(p, bt, not_tn(p, bt)))
            case True{}:
              %Equal.sym(Nat, Nat.add(Nat.double(Word.to_nat(p, Word.not(p, bt))), 1n+Nat.double(Word.to_nat(p, bt))), 1n+Nat.add(Nat.double(Word.to_nat(p, Word.not(p, bt))), Nat.double(Word.to_nat(p, bt))), N.add_succ_r(Nat.double(Word.to_nat(p, Word.not(p, bt))), Nat.double(Word.to_nat(p, bt)))) : {_ == Ws.mask(1n+p) : Nat}
              Equal.cong(Nat, Nat, v => 1n+v, Nat.add(Nat.double(Word.to_nat(p, Word.not(p, bt))), Nat.double(Word.to_nat(p, bt))), Nat.double(Ws.mask(p)), not_dbl(p, bt, not_tn(p, bt)))

def sub_t(+n: Nat, +S: Nat, +A0: Nat, +B0: Nat, +NB: Nat, +g: Nat,
    +hk: {Nat.add(S, W.kt(n, True{})) == Nat.add(Nat.add(A0, NB), 1n) : Nat},
    +hn: {Nat.add(NB, B0) == Ws.mask(n) : Nat},
    +hg: {Nat.add(B0, g) == A0 : Nat})
    -> {Nat.add(1n+Ws.mask(n), S) == Nat.add(1n+Ws.mask(n), g) : Nat}:
  %hn : {Nat.add(1n+Ws.mask(n), S) == Nat.add(1n+_, g) : Nat}
  %Equal.sym(Nat, Nat.add(1n+Nat.add(NB, B0), g), Nat.add(Nat.add(A0, NB), 1n), Equal.trans(Nat, Nat.add(1n+Nat.add(NB, B0), g), Nat.add(Nat.add(Nat.add(B0, g), NB), 1n), Nat.add(Nat.add(A0, NB), 1n),
     A.ac([NB, B0, g, 1n], A.AP{A.AP{A.AV{3n}, A.AP{A.AV{0n}, A.AV{1n}}}, A.AV{2n}}, A.AP{A.AP{A.AP{A.AV{1n}, A.AV{2n}}, A.AV{0n}}, A.AV{3n}}, {==}),
     Equal.cong(Nat, Nat, v => Nat.add(Nat.add(v, NB), 1n), Nat.add(B0, g), A0, hg))) : {Nat.add(1n+Ws.mask(n), S) == _ : Nat}
  %Ws.pow2_mask(n) : {Nat.add(_, S) == Nat.add(Nat.add(A0, NB), 1n) : Nat}
  %N.add_comm(S, W.pow2(n)) : {_ == Nat.add(Nat.add(A0, NB), 1n) : Nat}
  hk

def sub_f(+n: Nat, +S: Nat, +A0: Nat, +B0: Nat, +NB: Nat, +g: Nat, +e: Nat,
    +hk: {Nat.add(S, W.kt(n, False{})) == Nat.add(Nat.add(A0, NB), 1n) : Nat},
    +hn: {Nat.add(NB, B0) == Ws.mask(n) : Nat},
    +hg: {Nat.add(B0, g) == A0 : Nat},
    +he: {Nat.add(S, e) == Ws.mask(n) : Nat})
    -> {Nat.add(1n+Ws.mask(n), Nat.add(g, e)) == Ws.mask(n) : Nat}:
  %he : {Nat.add(1n+Ws.mask(n), Nat.add(g, e)) == _ : Nat}
  %hn : {Nat.add(1n+_, Nat.add(g, e)) == Nat.add(S, e) : Nat}
  %Equal.sym(Nat, Nat.add(1n+Nat.add(NB, B0), Nat.add(g, e)), Nat.add(Nat.add(Nat.add(A0, NB), 1n), e), Equal.trans(Nat, Nat.add(1n+Nat.add(NB, B0), Nat.add(g, e)), Nat.add(Nat.add(Nat.add(Nat.add(B0, g), NB), 1n), e), Nat.add(Nat.add(Nat.add(A0, NB), 1n), e),
     A.ac([NB, B0, g, 1n, e], A.AP{A.AP{A.AV{3n}, A.AP{A.AV{0n}, A.AV{1n}}}, A.AP{A.AV{2n}, A.AV{4n}}}, A.AP{A.AP{A.AP{A.AP{A.AV{1n}, A.AV{2n}}, A.AV{0n}}, A.AV{3n}}, A.AV{4n}}, {==}),
     Equal.cong(Nat, Nat, v => Nat.add(Nat.add(Nat.add(v, NB), 1n), e), Nat.add(B0, g), A0, hg))) : {_ == Nat.add(S, e) : Nat}
  %Equal.trans(Nat, Nat.add(S, 0n), Nat.add(S, W.kt(n, False{})), Nat.add(Nat.add(A0, NB), 1n), {==}, hk) : {Nat.add(_, e) == Nat.add(S, e) : Nat}
  Equal.cong(Nat, Nat, v => Nat.add(v, e), Nat.add(S, 0n), S, N.add_zero_r(S))

# The value algebra of a subtraction that does not wrap.
def sub_fin(+n: Nat, +S: Nat, +A0: Nat, +B0: Nat, +NB: Nat, +g: Nat, cr: Bool,
    +hk: {Nat.add(S, W.kt(n, cr)) == Nat.add(Nat.add(A0, NB), 1n) : Nat},
    +hn: {Nat.add(NB, B0) == Ws.mask(n) : Nat},
    +hg: {Nat.add(B0, g) == A0 : Nat},
    +lS: L.Le(S, Ws.mask(n)))
    -> {Nat.add(S, B0) == A0 : Nat}:
  match cr:
    case True{}:
      %hg : {Nat.add(S, B0) == _ : Nat}
      %N.add_comm(g, B0) : {Nat.add(S, B0) == _ : Nat}
      Equal.cong(Nat, Nat, v => Nat.add(v, B0), S, g, L.add_cancel_l(1n+Ws.mask(n), S, g, sub_t(n, S, A0, B0, NB, g, hk, hn, hg)))
    case False{}:
      (+e, he) = lS
      Empty.absurd({Nat.add(S, B0) == A0 : Nat}, L.succ_add_ne(Ws.mask(n), Nat.add(g, e), sub_f(n, S, A0, B0, NB, g, e, hk, hn, hg, he)))

law sub_val:
  for +n: Nat
  for +a: Word(n)
  for +b: Word(n)
  for +g: Nat
  for hg: {Nat.add(Word.to_nat(n, b), g) == Word.to_nat(n, a) : Nat}
  {Nat.add(Word.to_nat(n, Word.sub(n, a, b)), Word.to_nat(n, b)) == Word.to_nat(n, a) : Nat}

def sub_val(n, a, b, g, hg):
  %Equal.sym(Word(n), Word.adc(n, a, b, True{}, True{}), Word.adc(n, a, Word.not(n, b), False{}, True{}), adc_not(n, a, b, True{})) : {Nat.add(Word.to_nat(n, _), Word.to_nat(n, b)) == Word.to_nat(n, a) : Nat}
  sub_fin(n, Word.to_nat(n, Word.adc(n, a, Word.not(n, b), False{}, True{})), Word.to_nat(n, a), Word.to_nat(n, b), Word.to_nat(n, Word.not(n, b)), g, W.wcarry(n, a, Word.not(n, b), True{}),
    W.adc_ok(n, a, Word.not(n, b), True{}), not_tn(n, b), hg, Ws.tn_le(n, Word.adc(n, a, Word.not(n, b), False{}, True{})))

# A U32 subtraction that does not wrap is exact.
law sub_exact:
  for +a: U32
  for +b: U32
  for +l: L.Le(U32.to_nat(b), U32.to_nat(a))
  {Nat.add(U32.to_nat(U32.sub(a, b)), U32.to_nat(b)) == U32.to_nat(a) : Nat}

def sub_exact(a, b, l):
  match a b:
    case U32{x} U32{y}:
      (+g, hg) = l
      sub_val(32n, x, y, g, hg)

# --- 0/1 words ----------------------------------------------------------------

def dbl_zero(+t: Nat, +e: Nat, h: {Nat.add(Nat.double(t), e) == 0n : Nat}) -> {t == 0n : Nat}:
  match t:
    case 0n:
      {==}
    case 1n+y:
      Empty.absurd({1n+y == 0n : Nat}, L.succ_ne_zero(1n+Nat.add(Nat.double(y), e), h))

def dbl_one(+t: Nat, +e: Nat, h: {Nat.add(Nat.double(t), e) == 1n : Nat}) -> {t == 0n : Nat}:
  match t:
    case 0n:
      {==}
    case 1n+y:
      Empty.absurd({1n+y == 0n : Nat}, L.succ_ne_zero(Nat.add(Nat.double(y), e), L.succ_inj(1n+Nat.add(Nat.double(y), e), 0n, h)))

law zero_of:
  for +n: Nat
  for +w: Word(n)
  for h: {Word.to_nat(n, w) == 0n : Nat}
  {w == Word.zero(n) : Word(n)}

def zero_of(n, w, h):
  match n:
    case 0n:
      match w:
        case WNil{}:
          {==}
    case 1n+p:
      match w:
        case WCon{b, t}:
          match b:
            case False{}:
              Equal.cong(Word(p), Word(1n+p), v => WCon{False{}, v}, t, Word.zero(p), zero_of(p, t, dbl_zero(Word.to_nat(p, t), 0n, Equal.trans(Nat, Nat.add(Nat.double(Word.to_nat(p, t)), 0n), Nat.double(Word.to_nat(p, t)), 0n, N.add_zero_r(Nat.double(Word.to_nat(p, t))), h))))
            case True{}:
              Empty.absurd({WCon{True{}, t} == Word.zero(1n+p) : Word(1n+p)}, L.succ_ne_zero(Nat.double(Word.to_nat(p, t)), h))

def Is01(u: U32) -> Type:
  Either<&1, &1, {u == 0 : U32}, {u == 1 : U32}>

def cls_f(+t: Word(31n), +e: Nat, he: {Nat.add(Nat.double(Word.to_nat(31n, t)), e) == 1n : Nat}) -> Is01(U32{WCon{False{}, t}}):
  %Equal.sym(Word(31n), t, Word.zero(31n), zero_of(31n, t, dbl_one(Word.to_nat(31n, t), e, he))) : Is01(U32{WCon{False{}, _}})
  Inl{{==}}

def cls_t(+t: Word(31n), +e: Nat, he: {Nat.add(1n+Nat.double(Word.to_nat(31n, t)), e) == 1n : Nat}) -> Is01(U32{WCon{True{}, t}}):
  %Equal.sym(Word(31n), t, Word.zero(31n), zero_of(31n, t, dbl_zero(Word.to_nat(31n, t), e, L.succ_inj(Nat.add(Nat.double(Word.to_nat(31n, t)), e), 0n, he)))) : Is01(U32{WCon{True{}, _}})
  Inr{{==}}

# A U32 whose value is at most 1 is the word 0 or the word 1.
law classify:
  for +u: U32
  for +l: L.Le(U32.to_nat(u), 1n)
  Is01(u)

def classify(u, l):
  match u:
    case U32{w}:
      match w:
        case WCon{b, t}:
          match b:
            case False{}:
              (+e, he) = l
              cls_f(t, e, he)
            case True{}:
              (+e, he) = l
              cls_t(t, e, he)

# 1 - h for a 0/1 word h: the values add up to 1.
def om_go(+h: U32, c: Is01(h)) -> {Nat.add(U32.to_nat(U32.sub(1, h)), U32.to_nat(h)) == 1n : Nat}:
  match c:
    case Inl{e}:
      %Equal.sym(U32, h, 0, e) : {Nat.add(U32.to_nat(U32.sub(1, _)), U32.to_nat(_)) == 1n : Nat}
      {==}
    case Inr{e}:
      %Equal.sym(U32, h, 1, e) : {Nat.add(U32.to_nat(U32.sub(1, _)), U32.to_nat(_)) == 1n : Nat}
      {==}

law one_minus:
  for +h: U32
  for +l: L.Le(U32.to_nat(h), 1n)
  {Nat.add(U32.to_nat(U32.sub(1, h)), U32.to_nat(h)) == 1n : Nat}

def one_minus(h, l):
  om_go(h, classify(h, l))

def omle_go(+h: U32, c: Is01(h)) -> L.Le(U32.to_nat(U32.sub(1, h)), 1n):
  match c:
    case Inl{e}:
      %Equal.sym(U32, h, 0, e) : L.Le(U32.to_nat(U32.sub(1, _)), 1n)
      (0n, {==})
    case Inr{e}:
      %Equal.sym(U32, h, 1, e) : L.Le(U32.to_nat(U32.sub(1, _)), 1n)
      (1n, {==})

law one_minus_le:
  for +h: U32
  for +l: L.Le(U32.to_nat(h), 1n)
  L.Le(U32.to_nat(U32.sub(1, h)), 1n)

def one_minus_le(h, l):
  omle_go(h, classify(h, l))

# --- the mask select ----------------------------------------------------------

def bsel_x(+x: Bool, +y: Bool) -> {Bool.or(Bool.and(x, True{}), Bool.and(y, False{})) == x : Bool}:
  match x y:
    case False{} False{}:
      {==}
    case False{} True{}:
      {==}
    case True{} False{}:
      {==}
    case True{} True{}:
      {==}

def bsel_y(+x: Bool, +y: Bool) -> {Bool.or(Bool.and(x, False{}), Bool.and(y, True{})) == y : Bool}:
  match x y:
    case False{} False{}:
      {==}
    case False{} True{}:
      {==}
    case True{} False{}:
      {==}
    case True{} True{}:
      {==}

law wsel_x:
  for +n: Nat
  for +x: Word(n)
  for +y: Word(n)
  {Word.or(n, Word.and(n, x, Bt.lowmask(n, n)), Word.and(n, y, Word.zero(n))) == x : Word(n)}

def wsel_x(n, x, y):
  match n:
    case 0n:
      match x:
        case WNil{}:
          {==}
    case 1n+p:
      match x y:
        case WCon{xb, xt} WCon{yb, yt}:
          %Equal.sym(Bool, Bool.or(Bool.and(xb, True{}), Bool.and(yb, False{})), xb, bsel_x(xb, yb)) : {WCon{_, Word.or(p, Word.and(p, xt, Bt.lowmask(p, p)), Word.and(p, yt, Word.zero(p)))} == WCon{xb, xt} : Word(1n+p)}
          Equal.cong(Word(p), Word(1n+p), v => WCon{xb, v}, Word.or(p, Word.and(p, xt, Bt.lowmask(p, p)), Word.and(p, yt, Word.zero(p))), xt, wsel_x(p, xt, yt))

law wsel_y:
  for +n: Nat
  for +x: Word(n)
  for +y: Word(n)
  {Word.or(n, Word.and(n, x, Word.zero(n)), Word.and(n, y, Bt.lowmask(n, n))) == y : Word(n)}

def wsel_y(n, x, y):
  match n:
    case 0n:
      match y:
        case WNil{}:
          {==}
    case 1n+p:
      match x y:
        case WCon{xb, xt} WCon{yb, yt}:
          %Equal.sym(Bool, Bool.or(Bool.and(xb, False{}), Bool.and(yb, True{})), yb, bsel_y(xb, yb)) : {WCon{_, Word.or(p, Word.and(p, xt, Word.zero(p)), Word.and(p, yt, Bt.lowmask(p, p)))} == WCon{yb, yt} : Word(1n+p)}
          Equal.cong(Word(p), Word(1n+p), v => WCon{yb, v}, Word.or(p, Word.and(p, xt, Word.zero(p)), Word.and(p, yt, Bt.lowmask(p, p))), yt, wsel_y(p, xt, yt))

law sel_ones:
  for +x: U32
  for +y: U32
  {U32.or(U32.and(x, 4294967295), U32.and(y, 0)) == x : U32}

def sel_ones(x, y):
  match x y:
    case U32{w} U32{v}:
      Equal.cong(Word(32n), U32, z => U32{z}, Word.or(32n, Word.and(32n, w, Bt.lowmask(32n, 32n)), Word.and(32n, v, Word.zero(32n))), w, wsel_x(32n, w, v))

law sel_zero:
  for +x: U32
  for +y: U32
  {U32.or(U32.and(x, 0), U32.and(y, 4294967295)) == y : U32}

def sel_zero(x, y):
  match x y:
    case U32{w} U32{v}:
      Equal.cong(Word(32n), U32, z => U32{z}, Word.or(32n, Word.and(32n, w, Word.zero(32n)), Word.and(32n, v, Bt.lowmask(32n, 32n))), v, wsel_y(32n, w, v))

# The field code's select: mask = 0 - (e & (1 - c)); (x & mask) | (y & ~mask).
def Sel(+e: U32, +c: U32, +x: U32, +y: U32) -> U32:
  U32.or(U32.and(x, U32.sub(0, U32.and(e, U32.sub(1, c)))), U32.and(y, U32.xor(U32.sub(0, U32.and(e, U32.sub(1, c))), 4294967295)))

law sel_x:
  for +e: U32
  for +c: U32
  for +x: U32
  for +y: U32
  for he: {e == 1 : U32}
  for hc: {c == 0 : U32}
  {U32.or(U32.and(x, U32.sub(0, U32.and(e, U32.sub(1, c)))), U32.and(y, U32.xor(U32.sub(0, U32.and(e, U32.sub(1, c))), 4294967295))) == x : U32}

def sel_x(e, c, x, y, he, hc):
  %Equal.sym(U32, e, 1, he) : {U32.or(U32.and(x, U32.sub(0, U32.and(_, U32.sub(1, c)))), U32.and(y, U32.xor(U32.sub(0, U32.and(_, U32.sub(1, c))), 4294967295))) == x : U32}
  %Equal.sym(U32, c, 0, hc) : {U32.or(U32.and(x, U32.sub(0, U32.and(1, U32.sub(1, _)))), U32.and(y, U32.xor(U32.sub(0, U32.and(1, U32.sub(1, _))), 4294967295))) == x : U32}
  sel_ones(x, y)

law sel_y:
  for +e: U32
  for +c: U32
  for +x: U32
  for +y: U32
  for +E: U32
  for +C: U32
  for he: {e == E : U32}
  for hc: {c == C : U32}
  for hz: {U32.sub(0, U32.and(E, U32.sub(1, C))) == 0 : U32}
  {U32.or(U32.and(x, U32.sub(0, U32.and(e, U32.sub(1, c)))), U32.and(y, U32.xor(U32.sub(0, U32.and(e, U32.sub(1, c))), 4294967295))) == y : U32}

def sel_y(e, c, x, y, E, C, he, hc, hz):
  %Equal.sym(U32, e, E, he) : {U32.or(U32.and(x, U32.sub(0, U32.and(_, U32.sub(1, c)))), U32.and(y, U32.xor(U32.sub(0, U32.and(_, U32.sub(1, c))), 4294967295))) == y : U32}
  %Equal.sym(U32, c, C, hc) : {U32.or(U32.and(x, U32.sub(0, U32.and(E, U32.sub(1, _)))), U32.and(y, U32.xor(U32.sub(0, U32.and(E, U32.sub(1, _))), 4294967295))) == y : U32}
  %Equal.sym(U32, U32.sub(0, U32.and(E, U32.sub(1, C))), 0, hz) : {U32.or(U32.and(x, _), U32.and(y, U32.xor(_, 4294967295))) == y : U32}
  sel_zero(x, y)

# --- constants ----------------------------------------------------------------

def tn65536() -> {U32.to_nat(65536) == 65536n : Nat}:
  {==}

# A U32 literal that fits in 16 bits is at most 65535.
law lit16:
  for +x: U32
  for h: {U32.and(x, 65535) == x : U32}
  L.Le(U32.to_nat(x), 65535n)

def lit16(x, h):
  %h : L.Le(U32.to_nat(_), 65535n)
  UB.low16_le(x)
