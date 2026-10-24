import Base
import ../field/natlemmas.bend as N
import ../field/wordadd.bend as W
import ./natlib.bend as L
import ./words.bend as Ws
import ./cong.bend as C

# Word.mul is multiplication mod 2^n, from Bend's own shift-and-add definition.

def tn_con(+p: Nat, +b: Bool, +t: Word(p)) -> {Nat.add(W.bv(b), Nat.double(Word.to_nat(p, t))) == Word.to_nat(1n+p, WCon{b, t}) : Nat}:
  match b:
    case False{}:
      {==}
    case True{}:
      {==}

# The bit Word.shl.put pushes out of the top.
def pout(n: Nat, c: Bool, w: Word(n)) -> Bool:
  match n:
    case 0n:
      c
    case 1n+p:
      match w:
        case WCon{b, t}:
          pout(p, b, t)

law put_ok:
  for +n: Nat
  for +c: Bool
  for +w: Word(n)
  {Nat.add(Word.to_nat(n, Word.shl.put(n, c, w)), W.kt(n, pout(n, c, w))) == Nat.add(W.bv(c), Nat.double(Word.to_nat(n, w))) : Nat}

def put_ok(n, c, w):
  match n:
    case 0n:
      match c:
        case False{}:
          {==}
        case True{}:
          {==}
    case 1n+p:
      match c:
        case False{}:
          match w:
            case WCon{b, t}:
              %Ws.dk(p, pout(p, b, t)) : {Nat.add(Nat.double(Word.to_nat(p, Word.shl.put(p, b, t))), _) == Nat.double(Word.to_nat(1n+p, WCon{b, t})) : Nat}
              %N.double_add(Word.to_nat(p, Word.shl.put(p, b, t)), W.kt(p, pout(p, b, t))) : {_ == Nat.double(Word.to_nat(1n+p, WCon{b, t})) : Nat}
              Equal.cong(Nat, Nat, v => Nat.double(v), Nat.add(Word.to_nat(p, Word.shl.put(p, b, t)), W.kt(p, pout(p, b, t))), Word.to_nat(1n+p, WCon{b, t}),
                Equal.trans(Nat, Nat.add(Word.to_nat(p, Word.shl.put(p, b, t)), W.kt(p, pout(p, b, t))), Nat.add(W.bv(b), Nat.double(Word.to_nat(p, t))), Word.to_nat(1n+p, WCon{b, t}), put_ok(p, b, t), tn_con(p, b, t)))
        case True{}:
          match w:
            case WCon{b, t}:
              %Ws.dk(p, pout(p, b, t)) : {Nat.add(1n+Nat.double(Word.to_nat(p, Word.shl.put(p, b, t))), _) == 1n+Nat.double(Word.to_nat(1n+p, WCon{b, t})) : Nat}
              %N.double_add(Word.to_nat(p, Word.shl.put(p, b, t)), W.kt(p, pout(p, b, t))) : {1n+_ == 1n+Nat.double(Word.to_nat(1n+p, WCon{b, t})) : Nat}
              Equal.cong(Nat, Nat, v => 1n+Nat.double(v), Nat.add(Word.to_nat(p, Word.shl.put(p, b, t)), W.kt(p, pout(p, b, t))), Word.to_nat(1n+p, WCon{b, t}),
                Equal.trans(Nat, Nat.add(Word.to_nat(p, Word.shl.put(p, b, t)), W.kt(p, pout(p, b, t))), Nat.add(W.bv(b), Nat.double(Word.to_nat(p, t))), Word.to_nat(1n+p, WCon{b, t}), put_ok(p, b, t), tn_con(p, b, t)))

# The bit Word.shl drops.
def sout(n: Nat, w: Word(n)) -> Bool:
  match n:
    case 0n:
      False{}
    case 1n+p:
      match w:
        case WCon{b, t}:
          pout(p, b, t)

law shl_ok:
  for +n: Nat
  for +w: Word(n)
  {Nat.add(Word.to_nat(n, Word.shl(n, w)), W.kt(n, sout(n, w))) == Nat.double(Word.to_nat(n, w)) : Nat}

def shl_ok(n, w):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match w:
        case WCon{b, t}:
          %Ws.dk(p, pout(p, b, t)) : {Nat.add(Nat.double(Word.to_nat(p, Word.shl.put(p, b, t))), _) == Nat.double(Word.to_nat(1n+p, WCon{b, t})) : Nat}
          %N.double_add(Word.to_nat(p, Word.shl.put(p, b, t)), W.kt(p, pout(p, b, t))) : {_ == Nat.double(Word.to_nat(1n+p, WCon{b, t})) : Nat}
          Equal.cong(Nat, Nat, v => Nat.double(v), Nat.add(Word.to_nat(p, Word.shl.put(p, b, t)), W.kt(p, pout(p, b, t))), Word.to_nat(1n+p, WCon{b, t}),
            Equal.trans(Nat, Nat.add(Word.to_nat(p, Word.shl.put(p, b, t)), W.kt(p, pout(p, b, t))), Nat.add(W.bv(b), Nat.double(Word.to_nat(p, t))), Word.to_nat(1n+p, WCon{b, t}), put_ok(p, b, t), tn_con(p, b, t)))

def shl_cg(+n: Nat, +w: Word(n)) -> C.Cg(W.pow2(n), Word.to_nat(n, Word.shl(n, w)), Nat.double(Word.to_nat(n, w))):
  C.cg_of(W.pow2(n), Word.to_nat(n, Word.shl(n, w)), Nat.double(Word.to_nat(n, w)), W.bv(sout(n, w)),
    Equal.trans(Nat, Nat.add(Word.to_nat(n, Word.shl(n, w)), Nat.mul(W.bv(sout(n, w)), W.pow2(n))), Nat.add(Word.to_nat(n, Word.shl(n, w)), W.kt(n, sout(n, w))), Nat.double(Word.to_nat(n, w)),
      Equal.cong(Nat, Nat, v => Nat.add(Word.to_nat(n, Word.shl(n, w)), v), Nat.mul(W.bv(sout(n, w)), W.pow2(n)), W.kt(n, sout(n, w)), Equal.sym(Nat, W.kt(n, sout(n, w)), Nat.mul(W.bv(sout(n, w)), W.pow2(n)), Ws.kt_bv(n, sout(n, w)))),
      shl_ok(n, w)))

def add_cg(+n: Nat, +a: Word(n), +b: Word(n)) -> C.Cg(W.pow2(n), Word.to_nat(n, Word.add(n, a, b)), Nat.add(Word.to_nat(n, a), Word.to_nat(n, b))):
  C.cg_of(W.pow2(n), Word.to_nat(n, Word.add(n, a, b)), Nat.add(Word.to_nat(n, a), Word.to_nat(n, b)), W.bv(W.wcarry(n, a, b, False{})),
    Equal.trans(Nat, Nat.add(Word.to_nat(n, Word.add(n, a, b)), Nat.mul(W.bv(W.wcarry(n, a, b, False{})), W.pow2(n))), Nat.add(Word.to_nat(n, Word.add(n, a, b)), W.kt(n, W.wcarry(n, a, b, False{}))), Nat.add(Word.to_nat(n, a), Word.to_nat(n, b)),
      Equal.cong(Nat, Nat, v => Nat.add(Word.to_nat(n, Word.add(n, a, b)), v), Nat.mul(W.bv(W.wcarry(n, a, b, False{})), W.pow2(n)), W.kt(n, W.wcarry(n, a, b, False{})), Equal.sym(Nat, W.kt(n, W.wcarry(n, a, b, False{})), Nat.mul(W.bv(W.wcarry(n, a, b, False{})), W.pow2(n)), Ws.kt_bv(n, W.wcarry(n, a, b, False{})))),
      Equal.trans(Nat, Nat.add(Word.to_nat(n, Word.add(n, a, b)), W.kt(n, W.wcarry(n, a, b, False{}))), Nat.add(Nat.add(Word.to_nat(n, a), Word.to_nat(n, b)), 0n), Nat.add(Word.to_nat(n, a), Word.to_nat(n, b)),
        W.adc_ok(n, a, b, False{}), N.add_zero_r(Nat.add(Word.to_nat(n, a), Word.to_nat(n, b))))))

law mul_double_r:
  for +a: Nat
  for +b: Nat
  {Nat.mul(a, Nat.double(b)) == Nat.double(Nat.mul(a, b)) : Nat}

def mul_double_r(a, b):
  %L.mul_comm(Nat.double(b), a) : {_ == Nat.double(Nat.mul(a, b)) : Nat}
  %L.mul_comm(b, a) : {Nat.mul(Nat.double(b), a) == Nat.double(_) : Nat}
  Ws.double_mul(b, a)

# a * 2b == 2a * b
def dbl_swap(+a: Nat, +b: Nat) -> {Nat.mul(a, Nat.double(b)) == Nat.mul(Nat.double(a), b) : Nat}:
  Equal.trans(Nat, Nat.mul(a, Nat.double(b)), Nat.double(Nat.mul(a, b)), Nat.mul(Nat.double(a), b), mul_double_r(a, b), Equal.sym(Nat, Nat.mul(Nat.double(a), b), Nat.double(Nat.mul(a, b)), Ws.double_mul(a, b)))

law zero_ok:
  for +n: Nat
  {Word.to_nat(n, Word.zero(n)) == 0n : Nat}

def zero_ok(n):
  match n:
    case 0n:
      {==}
    case 1n+p:
      Equal.cong(Nat, Nat, v => Nat.double(v), Word.to_nat(p, Word.zero(p)), 0n, zero_ok(p))

# The shift-and-add loop: its result ~ acc + a * b (mod 2^n).
law mulgo_ok:
  for +n: Nat
  for +m: Nat
  for +a: Word(m)
  for +b: Word(n)
  for +acc: Word(n)
  C.Cg(W.pow2(n), Word.to_nat(n, Word.mul.go(n, m, a, b, acc)), Nat.add(Word.to_nat(n, acc), Nat.mul(Word.to_nat(m, a), Word.to_nat(n, b))))

def mulgo_ok(n, m, a, b, acc):
  match m:
    case 0n:
      C.cg_eq(W.pow2(n), Word.to_nat(n, acc), Nat.add(Word.to_nat(n, acc), 0n), Equal.sym(Nat, Nat.add(Word.to_nat(n, acc), 0n), Word.to_nat(n, acc), N.add_zero_r(Word.to_nat(n, acc))))
    case 1n+mp:
      match a:
        case WCon{bit, at}:
          match bit:
            case False{}:
              C.cg_trans(W.pow2(n), Word.to_nat(n, Word.mul.go(n, mp, at, Word.shl(n, b), acc)), Nat.add(Word.to_nat(n, acc), Nat.mul(Word.to_nat(mp, at), Word.to_nat(n, Word.shl(n, b)))), Nat.add(Word.to_nat(n, acc), Nat.mul(Nat.double(Word.to_nat(mp, at)), Word.to_nat(n, b))),
                mulgo_ok(n, mp, at, Word.shl(n, b), acc),
                C.cg_trans(W.pow2(n), Nat.add(Word.to_nat(n, acc), Nat.mul(Word.to_nat(mp, at), Word.to_nat(n, Word.shl(n, b)))), Nat.add(Word.to_nat(n, acc), Nat.mul(Word.to_nat(mp, at), Nat.double(Word.to_nat(n, b)))), Nat.add(Word.to_nat(n, acc), Nat.mul(Nat.double(Word.to_nat(mp, at)), Word.to_nat(n, b))),
                  C.cg_add(W.pow2(n), Word.to_nat(n, acc), Word.to_nat(n, acc), Nat.mul(Word.to_nat(mp, at), Word.to_nat(n, Word.shl(n, b))), Nat.mul(Word.to_nat(mp, at), Nat.double(Word.to_nat(n, b))),
                    C.cg_eq(W.pow2(n), Word.to_nat(n, acc), Word.to_nat(n, acc), {==}),
                    C.cg_mul(W.pow2(n), Word.to_nat(mp, at), Word.to_nat(n, Word.shl(n, b)), Nat.double(Word.to_nat(n, b)), shl_cg(n, b))),
                  C.cg_eq(W.pow2(n), Nat.add(Word.to_nat(n, acc), Nat.mul(Word.to_nat(mp, at), Nat.double(Word.to_nat(n, b)))), Nat.add(Word.to_nat(n, acc), Nat.mul(Nat.double(Word.to_nat(mp, at)), Word.to_nat(n, b))),
                    Equal.cong(Nat, Nat, v => Nat.add(Word.to_nat(n, acc), v), Nat.mul(Word.to_nat(mp, at), Nat.double(Word.to_nat(n, b))), Nat.mul(Nat.double(Word.to_nat(mp, at)), Word.to_nat(n, b)), dbl_swap(Word.to_nat(mp, at), Word.to_nat(n, b))))))
            case True{}:
              C.cg_trans(W.pow2(n), Word.to_nat(n, Word.mul.go(n, mp, at, Word.shl(n, b), Word.add(n, acc, b))), Nat.add(Word.to_nat(n, Word.add(n, acc, b)), Nat.mul(Word.to_nat(mp, at), Word.to_nat(n, Word.shl(n, b)))), Nat.add(Word.to_nat(n, acc), Nat.add(Word.to_nat(n, b), Nat.mul(Nat.double(Word.to_nat(mp, at)), Word.to_nat(n, b)))),
                mulgo_ok(n, mp, at, Word.shl(n, b), Word.add(n, acc, b)),
                C.cg_trans(W.pow2(n), Nat.add(Word.to_nat(n, Word.add(n, acc, b)), Nat.mul(Word.to_nat(mp, at), Word.to_nat(n, Word.shl(n, b)))), Nat.add(Nat.add(Word.to_nat(n, acc), Word.to_nat(n, b)), Nat.mul(Word.to_nat(mp, at), Nat.double(Word.to_nat(n, b)))), Nat.add(Word.to_nat(n, acc), Nat.add(Word.to_nat(n, b), Nat.mul(Nat.double(Word.to_nat(mp, at)), Word.to_nat(n, b)))),
                  C.cg_add(W.pow2(n), Word.to_nat(n, Word.add(n, acc, b)), Nat.add(Word.to_nat(n, acc), Word.to_nat(n, b)), Nat.mul(Word.to_nat(mp, at), Word.to_nat(n, Word.shl(n, b))), Nat.mul(Word.to_nat(mp, at), Nat.double(Word.to_nat(n, b))),
                    add_cg(n, acc, b),
                    C.cg_mul(W.pow2(n), Word.to_nat(mp, at), Word.to_nat(n, Word.shl(n, b)), Nat.double(Word.to_nat(n, b)), shl_cg(n, b))),
                  C.cg_eq(W.pow2(n), Nat.add(Nat.add(Word.to_nat(n, acc), Word.to_nat(n, b)), Nat.mul(Word.to_nat(mp, at), Nat.double(Word.to_nat(n, b)))), Nat.add(Word.to_nat(n, acc), Nat.add(Word.to_nat(n, b), Nat.mul(Nat.double(Word.to_nat(mp, at)), Word.to_nat(n, b)))),
                    Equal.trans(Nat, Nat.add(Nat.add(Word.to_nat(n, acc), Word.to_nat(n, b)), Nat.mul(Word.to_nat(mp, at), Nat.double(Word.to_nat(n, b)))), Nat.add(Word.to_nat(n, acc), Nat.add(Word.to_nat(n, b), Nat.mul(Word.to_nat(mp, at), Nat.double(Word.to_nat(n, b))))), Nat.add(Word.to_nat(n, acc), Nat.add(Word.to_nat(n, b), Nat.mul(Nat.double(Word.to_nat(mp, at)), Word.to_nat(n, b)))),
                      N.add_assoc(Word.to_nat(n, acc), Word.to_nat(n, b), Nat.mul(Word.to_nat(mp, at), Nat.double(Word.to_nat(n, b)))),
                      Equal.cong(Nat, Nat, v => Nat.add(Word.to_nat(n, acc), Nat.add(Word.to_nat(n, b), v)), Nat.mul(Word.to_nat(mp, at), Nat.double(Word.to_nat(n, b))), Nat.mul(Nat.double(Word.to_nat(mp, at)), Word.to_nat(n, b)), dbl_swap(Word.to_nat(mp, at), Word.to_nat(n, b)))))))

law word_mul_cg:
  for +n: Nat
  for +a: Word(n)
  for +b: Word(n)
  C.Cg(W.pow2(n), Word.to_nat(n, Word.mul(n, a, b)), Nat.mul(Word.to_nat(n, a), Word.to_nat(n, b)))

def word_mul_cg(n, a, b):
  C.cg_trans(W.pow2(n), Word.to_nat(n, Word.mul(n, a, b)), Nat.add(Word.to_nat(n, Word.zero(n)), Nat.mul(Word.to_nat(n, a), Word.to_nat(n, b))), Nat.mul(Word.to_nat(n, a), Word.to_nat(n, b)),
    mulgo_ok(n, n, a, b, Word.zero(n)),
    C.cg_eq(W.pow2(n), Nat.add(Word.to_nat(n, Word.zero(n)), Nat.mul(Word.to_nat(n, a), Word.to_nat(n, b))), Nat.mul(Word.to_nat(n, a), Word.to_nat(n, b)),
      Equal.cong(Nat, Nat, v => Nat.add(v, Nat.mul(Word.to_nat(n, a), Word.to_nat(n, b))), Word.to_nat(n, Word.zero(n)), 0n, zero_ok(n))))

def cg_pm(+n: Nat, +x: Nat, +y: Nat, +c: C.Cg(W.pow2(n), x, y)) -> C.Cg(1n+Ws.mask(n), x, y):
  %Ws.pow2_mask(n) : C.Cg(_, x, y)
  c

# Word.mul(n) is exactly the product mod 2^n.
law word_mul_mod:
  for +n: Nat
  for +a: Word(n)
  for +b: Word(n)
  {Word.to_nat(n, Word.mul(n, a, b)) == Nat.mod(Nat.mul(Word.to_nat(n, a), Word.to_nat(n, b)), 1n+Ws.mask(n)) : Nat}

def word_mul_mod(n, a, b):
  C.cg_mod(Ws.mask(n), Word.to_nat(n, Word.mul(n, a, b)), Nat.mul(Word.to_nat(n, a), Word.to_nat(n, b)), Ws.tn_le(n, Word.mul(n, a, b)),
    cg_pm(n, Word.to_nat(n, Word.mul(n, a, b)), Nat.mul(Word.to_nat(n, a), Word.to_nat(n, b)), word_mul_cg(n, a, b)))
