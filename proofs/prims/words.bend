import Base
import ../field/natlemmas.bend as N
import ../field/wordadd.bend as W
import ./natlib.bend as L

# Facts about Bend's Word(n) / U32 encoding that the fork primitives' laws rest on:
# powers of two, the bound on a word's value, increment, and U32.from_nat.

law double_self:
  for +x: Nat
  {Nat.double(x) == Nat.add(x, x) : Nat}

def double_self(x):
  match x:
    case 0n:
      {==}
    case 1n+p:
      %Equal.sym(Nat, Nat.add(p, 1n+p), 1n+Nat.add(p, p), N.add_succ_r(p, p)) : {2n+Nat.double(p) == 1n+_ : Nat}
      %Equal.sym(Nat, Nat.double(p), Nat.add(p, p), double_self(p)) : {2n+_ == 2n+Nat.add(p, p) : Nat}
      {==}

law double_mul:
  for +x: Nat
  for +y: Nat
  {Nat.mul(Nat.double(x), y) == Nat.double(Nat.mul(x, y)) : Nat}

def double_mul(x, y):
  %Equal.sym(Nat, Nat.double(x), Nat.add(x, x), double_self(x)) : {Nat.mul(_, y) == Nat.double(Nat.mul(x, y)) : Nat}
  %Equal.sym(Nat, Nat.double(Nat.mul(x, y)), Nat.add(Nat.mul(x, y), Nat.mul(x, y)), double_self(Nat.mul(x, y))) : {Nat.mul(Nat.add(x, x), y) == _ : Nat}
  L.mul_add_r(x, x, y)

law pow_pow2:
  for +n: Nat
  {Nat.pow(2n, n) == W.pow2(n) : Nat}

def pow_pow2(n):
  match n:
    case 0n:
      {==}
    case 1n+p:
      %pow_pow2(p) : {Nat.add(Nat.pow(2n, p), Nat.add(Nat.pow(2n, p), 0n)) == Nat.double(_) : Nat}
      %Equal.sym(Nat, Nat.add(Nat.pow(2n, p), 0n), Nat.pow(2n, p), N.add_zero_r(Nat.pow(2n, p))) : {Nat.add(Nat.pow(2n, p), _) == Nat.double(Nat.pow(2n, p)) : Nat}
      Equal.sym(Nat, Nat.double(Nat.pow(2n, p)), Nat.add(Nat.pow(2n, p), Nat.pow(2n, p)), double_self(Nat.pow(2n, p)))

law pow2_add:
  for +a: Nat
  for +b: Nat
  {W.pow2(Nat.add(a, b)) == Nat.mul(W.pow2(a), W.pow2(b)) : Nat}

def pow2_add(a, b):
  match a:
    case 0n:
      Equal.sym(Nat, Nat.add(W.pow2(b), 0n), W.pow2(b), N.add_zero_r(W.pow2(b)))
    case 1n+p:
      %Equal.sym(Nat, W.pow2(Nat.add(p, b)), Nat.mul(W.pow2(p), W.pow2(b)), pow2_add(p, b)) : {Nat.double(_) == Nat.mul(Nat.double(W.pow2(p)), W.pow2(b)) : Nat}
      Equal.sym(Nat, Nat.mul(Nat.double(W.pow2(p)), W.pow2(b)), Nat.double(Nat.mul(W.pow2(p), W.pow2(b))), double_mul(W.pow2(p), W.pow2(b)))

# mask(n) = 2^n - 1, the largest n-bit value.
def mask(n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n+p:
      1n+Nat.double(mask(p))

law pow2_mask:
  for +n: Nat
  {W.pow2(n) == 1n+mask(n) : Nat}

def pow2_mask(n):
  match n:
    case 0n:
      {==}
    case 1n+p:
      %Equal.sym(Nat, W.pow2(p), 1n+mask(p), pow2_mask(p)) : {Nat.double(_) == 1n+mask(1n+p) : Nat}
      {==}

def le_dbl0(+p: Nat, +t: Nat, +l: L.Le(t, mask(p))) -> L.Le(Nat.double(t), mask(1n+p)):
  (+e, he) = l
  (1n+Nat.double(e), Equal.trans(Nat, Nat.add(Nat.double(t), 1n+Nat.double(e)), 1n+Nat.add(Nat.double(t), Nat.double(e)), 1n+Nat.double(mask(p)), N.add_succ_r(Nat.double(t), Nat.double(e)),
    Equal.cong(Nat, Nat, w => 1n+w, Nat.add(Nat.double(t), Nat.double(e)), Nat.double(mask(p)),
      Equal.trans(Nat, Nat.add(Nat.double(t), Nat.double(e)), Nat.double(Nat.add(t, e)), Nat.double(mask(p)), Equal.sym(Nat, Nat.double(Nat.add(t, e)), Nat.add(Nat.double(t), Nat.double(e)), N.double_add(t, e)), Equal.cong(Nat, Nat, w => Nat.double(w), Nat.add(t, e), mask(p), he)))))

def le_dbl1(+p: Nat, +t: Nat, +l: L.Le(t, mask(p))) -> L.Le(1n+Nat.double(t), mask(1n+p)):
  (+e, he) = l
  (Nat.double(e), Equal.cong(Nat, Nat, w => 1n+w, Nat.add(Nat.double(t), Nat.double(e)), Nat.double(mask(p)),
      Equal.trans(Nat, Nat.add(Nat.double(t), Nat.double(e)), Nat.double(Nat.add(t, e)), Nat.double(mask(p)), Equal.sym(Nat, Nat.double(Nat.add(t, e)), Nat.add(Nat.double(t), Nat.double(e)), N.double_add(t, e)), Equal.cong(Nat, Nat, w => Nat.double(w), Nat.add(t, e), mask(p), he))))

# An n-bit word's value is at most 2^n - 1.
law tn_le:
  for +n: Nat
  for +w: Word(n)
  L.Le(Word.to_nat(n, w), mask(n))

def tn_le(n, w):
  match n:
    case 0n:
      (0n, {==})
    case 1n+p:
      match w:
        case WCon{b, t}:
          match b:
            case False{}:
              le_dbl0(p, Word.to_nat(p, t), tn_le(p, t))
            case True{}:
              le_dbl1(p, Word.to_nat(p, t), tn_le(p, t))

def u32_tn(-w: Word(32n)) -> {Word.to_nat(32n, w) == U32.to_nat(U32{w}) : Nat}:
  {==}

law u32_le:
  for +u: U32
  L.Le(U32.to_nat(u), mask(32n))

def u32_le(u):
  match u:
    case U32{w}:
      %u32_tn(w) : L.Le(_, mask(32n))
      tn_le(32n, w)

# The carry out of Word.inc: true exactly when every bit was set.
def incc(n: Nat, w: Word(n)) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      match w:
        case WCon{b, t}:
          match b:
            case False{}:
              False{}
            case True{}:
              incc(p, t)

def dk(-p: Nat, k: Bool) -> {Nat.double(W.kt(p, k)) == W.kt(1n+p, k) : Nat}:
  W.dk(p, k)

law inc_ok:
  for +n: Nat
  for +w: Word(n)
  {Nat.add(Word.to_nat(n, Word.inc(n, w)), W.kt(n, incc(n, w))) == 1n+Word.to_nat(n, w) : Nat}

def inc_ok(n, w):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match w:
        case WCon{b, t}:
          match b:
            case False{}:
              Equal.cong(Nat, Nat, v => 1n+v, Nat.add(Nat.double(Word.to_nat(p, t)), 0n), Nat.double(Word.to_nat(p, t)), N.add_zero_r(Nat.double(Word.to_nat(p, t))))
            case True{}:
              %dk(p, incc(p, t)) : {Nat.add(Nat.double(Word.to_nat(p, Word.inc(p, t))), _) == 2n+Nat.double(Word.to_nat(p, t)) : Nat}
              %N.double_add(Word.to_nat(p, Word.inc(p, t)), W.kt(p, incc(p, t))) : {_ == 2n+Nat.double(Word.to_nat(p, t)) : Nat}
              Equal.cong(Nat, Nat, v => Nat.double(v), Nat.add(Word.to_nat(p, Word.inc(p, t)), W.kt(p, incc(p, t))), 1n+Word.to_nat(p, t), inc_ok(p, t))

law kt_bv:
  for +n: Nat
  for +c: Bool
  {W.kt(n, c) == Nat.mul(W.bv(c), W.pow2(n)) : Nat}

def kt_bv(n, c):
  match c:
    case False{}:
      {==}
    case True{}:
      Equal.sym(Nat, Nat.add(W.pow2(n), 0n), W.pow2(n), N.add_zero_r(W.pow2(n)))

# The fork writes 2^32 as 65536 * 65536; natlib's modulus form is 1 + bp.
def e16() -> {65536n == W.pow2(16n) : Nat}:
  {==}

def e1632() -> {Nat.add(16n, 16n) == 32n : Nat}:
  {==}

law two32:
  {Nat.mul(65536n, 65536n) == 1n+mask(32n) : Nat}

def two32():
  %Equal.sym(Nat, 65536n, W.pow2(16n), e16()) : {Nat.mul(_, 65536n) == 1n+mask(32n) : Nat}
  %Equal.sym(Nat, 65536n, W.pow2(16n), e16()) : {Nat.mul(W.pow2(16n), _) == 1n+mask(32n) : Nat}
  %pow2_mask(32n) : {Nat.mul(W.pow2(16n), W.pow2(16n)) == _ : Nat}
  %e1632() : {Nat.mul(W.pow2(16n), W.pow2(16n)) == W.pow2(_) : Nat}
  Equal.sym(Nat, W.pow2(Nat.add(16n, 16n)), Nat.mul(W.pow2(16n), W.pow2(16n)), pow2_add(16n, 16n))
