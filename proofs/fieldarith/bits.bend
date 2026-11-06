import Base
import ../field/natlemmas.bend as N
import ../field/wordadd.bend as W
import ../prims/natlib.bend as L
import ../prims/words.bend as Ws
import ../prims/wmul.bend as M

# Value semantics of masking and shifting (step 1 of proofs/README.md's plan):
# for every width n, word w and count k,
#   to_nat(w & lowmask(k)) + to_nat(w >> k) * 2^k == to_nat(w),  to_nat(w & lowmask(k)) <= 2^k - 1,
# so the low k bits are the value mod 2^k and the shifted word is the value div 2^k.

# The word whose low k bits are set (all n bits when k >= n).
def lowmask(n: Nat, k: Nat) -> Word(n):
  match n:
    case 0n:
      WNil{}
    case 1n+p:
      match k:
        case 0n:
          WCon{False{}, lowmask(p, 0n)}
        case 1n+q:
          WCon{True{}, lowmask(p, q)}

# k logical right shifts, in the order U32.shrn applies them.
def shrk(+n: Nat, w: Word(n), k: Nat) -> Word(n):
  match k:
    case 0n:
      w
    case 1n+q:
      Word.shr(n, shrk(n, w, q))

# Padding a word with a zero on top keeps its value.
law pad_tn:
  for +n: Nat
  for +t: Word(n)
  {Word.to_nat(1n+n, Word.shr.pad(n, t)) == Word.to_nat(n, t) : Nat}

def pad_tn(n, t):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match t:
        case WCon{b, u}:
          match b:
            case False{}:
              Equal.cong(Nat, Nat, v => Nat.double(v), Word.to_nat(1n+p, Word.shr.pad(p, u)), Word.to_nat(p, u), pad_tn(p, u))
            case True{}:
              Equal.cong(Nat, Nat, v => 1n+Nat.double(v), Word.to_nat(1n+p, Word.shr.pad(p, u)), Word.to_nat(p, u), pad_tn(p, u))

law shr_pad1:
  for +p: Nat
  for +u: Word(p)
  {Word.shr(1n+p, Word.shr.pad(p, u)) == Word.shr.pad(p, Word.shr(p, u)) : Word(1n+p)}

def shr_pad1(p, u):
  match p:
    case 0n:
      match u:
        case WNil{}:
          {==}
    case 1n+r:
      match u:
        case WCon{b, v}:
          {==}

law shr_pad:
  for +p: Nat
  for +t: Word(p)
  for +k: Nat
  {shrk(1n+p, Word.shr.pad(p, t), k) == Word.shr.pad(p, shrk(p, t, k)) : Word(1n+p)}

def shr_pad(p, t, k):
  match k:
    case 0n:
      {==}
    case 1n+q:
      %Equal.sym(Word(1n+p), shrk(1n+p, Word.shr.pad(p, t), q), Word.shr.pad(p, shrk(p, t, q)), shr_pad(p, t, q)) : {Word.shr(1n+p, _) == Word.shr.pad(p, Word.shr(p, shrk(p, t, q))) : Word(1n+p)}
      shr_pad1(p, shrk(p, t, q))

law shr_comm:
  for +n: Nat
  for +w: Word(n)
  for +k: Nat
  {shrk(n, Word.shr(n, w), k) == Word.shr(n, shrk(n, w, k)) : Word(n)}

def shr_comm(n, w, k):
  match k:
    case 0n:
      {==}
    case 1n+q:
      Equal.cong(Word(n), Word(n), v => Word.shr(n, v), shrk(n, Word.shr(n, w), q), Word.shr(n, shrk(n, w, q)), shr_comm(n, w, q))

# The high part after one more shift, on a word split into its low bit and the rest.
law shr_step:
  for +p: Nat
  for +b: Bool
  for +t: Word(p)
  for +q: Nat
  {Word.to_nat(1n+p, shrk(1n+p, WCon{b, t}, 1n+q)) == Word.to_nat(p, shrk(p, t, q)) : Nat}

def shr_step(p, b, t, q):
  %shr_comm(1n+p, WCon{b, t}, q) : {Word.to_nat(1n+p, _) == Word.to_nat(p, shrk(p, t, q)) : Nat}
  %Equal.sym(Word(1n+p), shrk(1n+p, Word.shr.pad(p, t), q), Word.shr.pad(p, shrk(p, t, q)), shr_pad(p, t, q)) : {Word.to_nat(1n+p, _) == Word.to_nat(p, shrk(p, t, q)) : Nat}
  pad_tn(p, shrk(p, t, q))

law and_zero:
  for +n: Nat
  for +w: Word(n)
  {Word.to_nat(n, Word.and(n, w, lowmask(n, 0n))) == 0n : Nat}

def and_zero(n, w):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match w:
        case WCon{b, t}:
          match b:
            case False{}:
              Equal.cong(Nat, Nat, v => Nat.double(v), Word.to_nat(p, Word.and(p, t, lowmask(p, 0n))), 0n, and_zero(p, t))
            case True{}:
              Equal.cong(Nat, Nat, v => Nat.double(v), Word.to_nat(p, Word.and(p, t, lowmask(p, 0n))), 0n, and_zero(p, t))

# x + y * (2 * P) == 2 * (x' ) when x + y * P == x'  (the doubling step of split)
law dbl_step:
  for +x: Nat
  for +y: Nat
  for +P: Nat
  for +z: Nat
  for h: {Nat.add(x, Nat.mul(y, P)) == z : Nat}
  {Nat.add(Nat.double(x), Nat.mul(y, Nat.double(P))) == Nat.double(z) : Nat}

def dbl_step(x, y, P, z, h):
  %Equal.sym(Nat, Nat.mul(y, Nat.double(P)), Nat.double(Nat.mul(y, P)), M.mul_double_r(y, P)) : {Nat.add(Nat.double(x), _) == Nat.double(z) : Nat}
  %h : {Nat.add(Nat.double(x), Nat.double(Nat.mul(y, P))) == Nat.double(_) : Nat}
  Equal.sym(Nat, Nat.double(Nat.add(x, Nat.mul(y, P))), Nat.add(Nat.double(x), Nat.double(Nat.mul(y, P))), N.double_add(x, Nat.mul(y, P)))

# The split: low k bits + (word >> k) * 2^k == word, at every width n.
law split:
  for +k: Nat
  for +n: Nat
  for +w: Word(n)
  {Nat.add(Word.to_nat(n, Word.and(n, w, lowmask(n, k))), Nat.mul(Word.to_nat(n, shrk(n, w, k)), W.pow2(k))) == Word.to_nat(n, w) : Nat}

def split(k, n, w):
  match k:
    case 0n:
      %Equal.sym(Nat, Word.to_nat(n, Word.and(n, w, lowmask(n, 0n))), 0n, and_zero(n, w)) : {Nat.add(_, Nat.mul(Word.to_nat(n, w), 1n)) == Word.to_nat(n, w) : Nat}
      L.mul_one_r(Word.to_nat(n, w))
    case 1n+q:
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
                  %Equal.sym(Nat, Word.to_nat(1n+p, shrk(1n+p, WCon{False{}, t}, 1n+q)), Word.to_nat(p, shrk(p, t, q)), shr_step(p, False{}, t, q)) : {Nat.add(Word.to_nat(1n+p, Word.and(1n+p, WCon{False{}, t}, lowmask(1n+p, 1n+q))), Nat.mul(_, W.pow2(1n+q))) == Word.to_nat(1n+p, WCon{False{}, t}) : Nat}
                  dbl_step(Word.to_nat(p, Word.and(p, t, lowmask(p, q))), Word.to_nat(p, shrk(p, t, q)), W.pow2(q), Word.to_nat(p, t), split(q, p, t))
                case True{}:
                  %Equal.sym(Nat, Word.to_nat(1n+p, shrk(1n+p, WCon{True{}, t}, 1n+q)), Word.to_nat(p, shrk(p, t, q)), shr_step(p, True{}, t, q)) : {Nat.add(Word.to_nat(1n+p, Word.and(1n+p, WCon{True{}, t}, lowmask(1n+p, 1n+q))), Nat.mul(_, W.pow2(1n+q))) == Word.to_nat(1n+p, WCon{True{}, t}) : Nat}
                  Equal.cong(Nat, Nat, v => 1n+v, Nat.add(Nat.double(Word.to_nat(p, Word.and(p, t, lowmask(p, q)))), Nat.mul(Word.to_nat(p, shrk(p, t, q)), Nat.double(W.pow2(q)))), Nat.double(Word.to_nat(p, t)),
                    dbl_step(Word.to_nat(p, Word.and(p, t, lowmask(p, q))), Word.to_nat(p, shrk(p, t, q)), W.pow2(q), Word.to_nat(p, t), split(q, p, t)))

# The low part is at most 2^k - 1.
law low_le:
  for +k: Nat
  for +n: Nat
  for +w: Word(n)
  L.Le(Word.to_nat(n, Word.and(n, w, lowmask(n, k))), Ws.mask(k))

def low_le(k, n, w):
  match k:
    case 0n:
      %Equal.sym(Nat, Word.to_nat(n, Word.and(n, w, lowmask(n, 0n))), 0n, and_zero(n, w)) : L.Le(_, 0n)
      (0n, {==})
    case 1n+q:
      match n:
        case 0n:
          match w:
            case WNil{}:
              (Ws.mask(1n+q), {==})
        case 1n+p:
          match w:
            case WCon{b, t}:
              match b:
                case False{}:
                  Ws.le_dbl0(q, Word.to_nat(p, Word.and(p, t, lowmask(p, q))), low_le(q, p, t))
                case True{}:
                  Ws.le_dbl1(q, Word.to_nat(p, Word.and(p, t, lowmask(p, q))), low_le(q, p, t))
