import Base
import ../field/natlemmas.bend as N
import ../field/wordadd.bend as W
import ./natlib.bend as L
import ./words.bend as Ws
import ./cong.bend as C
import ./wmul.bend as M

# U32 arithmetic as Nat arithmetic mod 2^32 = 1 + mask(32). Every step that turns a
# U32 term into a Word(32n) term is its own small equation, so the checker never
# compares two copies of a closed 2^32 term (it would expand them in unary).

def inc_cg(+n: Nat, +w: Word(n)) -> C.Cg(W.pow2(n), Word.to_nat(n, Word.inc(n, w)), 1n+Word.to_nat(n, w)):
  C.cg_of(W.pow2(n), Word.to_nat(n, Word.inc(n, w)), 1n+Word.to_nat(n, w), W.bv(Ws.incc(n, w)),
    Equal.trans(Nat, Nat.add(Word.to_nat(n, Word.inc(n, w)), Nat.mul(W.bv(Ws.incc(n, w)), W.pow2(n))), Nat.add(Word.to_nat(n, Word.inc(n, w)), W.kt(n, Ws.incc(n, w))), 1n+Word.to_nat(n, w),
      Equal.cong(Nat, Nat, v => Nat.add(Word.to_nat(n, Word.inc(n, w)), v), Nat.mul(W.bv(Ws.incc(n, w)), W.pow2(n)), W.kt(n, Ws.incc(n, w)), Equal.sym(Nat, W.kt(n, Ws.incc(n, w)), Nat.mul(W.bv(Ws.incc(n, w)), W.pow2(n)), Ws.kt_bv(n, Ws.incc(n, w)))),
      Ws.inc_ok(n, w)))

def word_add_mod(+n: Nat, +a: Word(n), +b: Word(n)) -> {Word.to_nat(n, Word.add(n, a, b)) == Nat.mod(Nat.add(Word.to_nat(n, a), Word.to_nat(n, b)), 1n+Ws.mask(n)) : Nat}:
  C.cg_mod(Ws.mask(n), Word.to_nat(n, Word.add(n, a, b)), Nat.add(Word.to_nat(n, a), Word.to_nat(n, b)), Ws.tn_le(n, Word.add(n, a, b)),
    M.cg_pm(n, Word.to_nat(n, Word.add(n, a, b)), Nat.add(Word.to_nat(n, a), Word.to_nat(n, b)), M.add_cg(n, a, b)))

def e_inc(-w: Word(32n)) -> {Word.to_nat(32n, Word.inc(32n, w)) == U32.to_nat(U32.inc(U32{w})) : Nat}:
  {==}

def e_mul(-x: Word(32n), -y: Word(32n)) -> {Word.to_nat(32n, Word.mul(32n, x, y)) == U32.to_nat(U32.mul(U32{x}, U32{y})) : Nat}:
  {==}

def e_add(-x: Word(32n), -y: Word(32n)) -> {Word.to_nat(32n, Word.add(32n, x, y)) == U32.to_nat(U32.add(U32{x}, U32{y})) : Nat}:
  {==}

def u32_inc_cg(+u: U32) -> C.Cg(W.pow2(32n), U32.to_nat(U32.inc(u)), 1n+U32.to_nat(u)):
  match u:
    case U32{w}:
      %e_inc(w) : C.Cg(W.pow2(32n), _, 1n+U32.to_nat(U32{w}))
      %Ws.u32_tn(w) : C.Cg(W.pow2(32n), Word.to_nat(32n, Word.inc(32n, w)), 1n+_)
      inc_cg(32n, w)

def fn_inc(+P: Nat, +em: {P == W.pow2(32n) : Nat}, +u: U32) -> C.Cg(P, U32.to_nat(U32.inc(u)), 1n+U32.to_nat(u)):
  %Equal.sym(Nat, P, W.pow2(32n), em) : C.Cg(_, U32.to_nat(U32.inc(u)), 1n+U32.to_nat(u))
  u32_inc_cg(u)

# from_nat(y) ~ y, with the modulus abstracted as P (em says what it is).
def fn_cg(+P: Nat, +em: {P == W.pow2(32n) : Nat}, +y: Nat) -> C.Cg(P, U32.to_nat(U32.from_nat(y)), y):
  match y:
    case 0n:
      C.cg_eq(P, U32.to_nat(U32.from_nat(0n)), 0n, {==})
    case 1n+p:
      C.cg_trans(P, U32.to_nat(U32.inc(U32.from_nat(p))), 1n+U32.to_nat(U32.from_nat(p)), 1n+p,
        fn_inc(P, em, U32.from_nat(p)),
        C.cg_add(P, 1n, 1n, U32.to_nat(U32.from_nat(p)), p, C.cg_eq(P, 1n, 1n, {==}), fn_cg(P, em, p)))

law u32_from_nat:
  for +y: Nat
  {U32.to_nat(U32.from_nat(y)) == Nat.mod(y, 1n+Ws.mask(32n)) : Nat}

def u32_from_nat(y):
  C.cg_mod(Ws.mask(32n), U32.to_nat(U32.from_nat(y)), y, Ws.u32_le(U32.from_nat(y)),
    M.cg_pm(32n, U32.to_nat(U32.from_nat(y)), y, fn_cg(W.pow2(32n), {==}, y)))

law u32_mul:
  for +a: U32
  for +b: U32
  {U32.to_nat(U32.mul(a, b)) == Nat.mod(Nat.mul(U32.to_nat(a), U32.to_nat(b)), 1n+Ws.mask(32n)) : Nat}

def u32_mul(a, b):
  match a b:
    case U32{x} U32{y}:
      %e_mul(x, y) : {_ == Nat.mod(Nat.mul(U32.to_nat(U32{x}), U32.to_nat(U32{y})), 1n+Ws.mask(32n)) : Nat}
      %Ws.u32_tn(x) : {Word.to_nat(32n, Word.mul(32n, x, y)) == Nat.mod(Nat.mul(_, U32.to_nat(U32{y})), 1n+Ws.mask(32n)) : Nat}
      %Ws.u32_tn(y) : {Word.to_nat(32n, Word.mul(32n, x, y)) == Nat.mod(Nat.mul(Word.to_nat(32n, x), _), 1n+Ws.mask(32n)) : Nat}
      M.word_mul_mod(32n, x, y)

law u32_add:
  for +a: U32
  for +b: U32
  {U32.to_nat(U32.add(a, b)) == Nat.mod(Nat.add(U32.to_nat(a), U32.to_nat(b)), 1n+Ws.mask(32n)) : Nat}

def u32_add(a, b):
  match a b:
    case U32{x} U32{y}:
      %e_add(x, y) : {_ == Nat.mod(Nat.add(U32.to_nat(U32{x}), U32.to_nat(U32{y})), 1n+Ws.mask(32n)) : Nat}
      %Ws.u32_tn(x) : {Word.to_nat(32n, Word.add(32n, x, y)) == Nat.mod(Nat.add(_, U32.to_nat(U32{y})), 1n+Ws.mask(32n)) : Nat}
      %Ws.u32_tn(y) : {Word.to_nat(32n, Word.add(32n, x, y)) == Nat.mod(Nat.add(Word.to_nat(32n, x), _), 1n+Ws.mask(32n)) : Nat}
      word_add_mod(32n, x, y)
