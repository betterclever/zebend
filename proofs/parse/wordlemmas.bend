# Small general lemmas about Word / U32 used by the generated bit proofs.
import Base

def u32(w: Word(32n)) -> U32:
  U32{w}

def wcon_h(-p: Nat, +t: Word(p), b: Bool) -> Word(1n+p):
  WCon{b, t}

def wcon_t(-p: Nat, +b: Bool, t: Word(p)) -> Word(1n+p):
  WCon{b, t}

# Bitwise congruence: equal heads and equal tails give equal words.
def wcon(-p: Nat, +a: Bool, +b: Bool, +s: Word(p), +t: Word(p), h: {a == b : Bool}, r: {s == t : Word(p)}) -> {WCon{a, s} == WCon{b, t} : Word(1n+p)}:
  Equal.trans(Word(1n+p), WCon{a, s}, WCon{b, s}, WCon{b, t},
    Equal.cong(Bool, Word(1n+p), wcon_h(p, s), a, b, h),
    Equal.cong(Word(p), Word(1n+p), wcon_t(p, b), s, t, r))

def IsTrue(b: Bool) -> Type:
  match b:
    case False{}:
      Empty
    case True{}:
      Unit

def false_not_true(e: {False{} == True{} : Bool}) -> Empty:
  %Equal.sym(Bool, False{}, True{}, e) : IsTrue(_)
  Unit{}

def absurd(-A: Type, bot: Empty) -> A:
  match bot:

def fin_eq(b: Bool) -> {Cmp.is_lt(Word.cmp.fin(b, False{}, EQ{})) == False{} : Bool}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def fin_nlt(+b: Bool, c: Cmp) -> {Cmp.is_lt(c) == False{} : Bool} -> {Cmp.is_lt(Word.cmp.fin(b, False{}, c)) == False{} : Bool}:
  match c:
    case LT{}:
      h => absurd({Cmp.is_lt(Word.cmp.fin(b, False{}, LT{})) == False{} : Bool}, false_not_true(Equal.sym(Bool, True{}, False{}, h)))
    case EQ{}:
      h => fin_eq(b)
    case GT{}:
      h => {==}

# Comparing any word with zero is never "less than".
def cmp_zero_nlt(+n: Nat, w: Word(n)) -> {Cmp.is_lt(Word.cmp(n, w, Word.zero(n))) == False{} : Bool}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      match w:
        case WCon{+b, +t}:
          fin_nlt(b, Word.cmp(p, t, Word.zero(p)), cmp_zero_nlt(p, t))
