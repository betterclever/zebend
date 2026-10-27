# Proofs of LAWS.bend.
import Base
import ./LAWS.bend as L
import ./diff.bend as D

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

def succ(n: Nat) -> Nat:
  1n+n

def not_lt.step(-p: Nat, -q: Nat, r: &d: Nat -> {Nat.add(q, d) == p : Nat}) -> &d: Nat -> {Nat.add(1n+q, d) == 1n+p : Nat}:
  (d, pr) = r
  (d, Equal.cong(Nat, Nat, succ, Nat.add(q, d), p, pr))

# is_lt(x, m) == False  ==>  m + d == x for some d.
def not_lt.go(x: Nat, +m: Nat) -> {Nat.is_lt(x, m) == False{} : Bool} -> &d: Nat -> {Nat.add(m, d) == x : Nat}:
  match x m:
    case 0n 0n:
      e => (0n, {==})
    case 0n 1n+q:
      e => absurd(&d: Nat -> {Nat.add(1n+q, d) == 0n : Nat}, false_not_true(Equal.sym(Bool, True{}, False{}, e)))
    case 1n+p 0n:
      e => (1n+p, {==})
    case 1n+p 1n+q:
      e => not_lt.step(p, q, not_lt.go(p, q, e))


# ---- MIN <= clamp(x) --------------------------------------------------------

def ge.hi(+x: Nat, b: Bool) -> {Nat.is_lt(x, D.MIN_TS()) == False{} : Bool} -> {Nat.is_lt(D.MAX_TS(), x) == b : Bool} -> &k: Nat -> {Nat.add(D.MIN_TS(), k) == D.clamp.hi(b, x) : Nat}:
  match b:
    case True{}:
      lo => e => (612n, {==})
    case False{}:
      lo => e => not_lt.go(x, D.MIN_TS(), lo)

def ge.lo(+x: Nat, b: Bool) -> {Nat.is_lt(x, D.MIN_TS()) == b : Bool} -> &k: Nat -> {Nat.add(D.MIN_TS(), k) == D.clamp.lo(b, x) : Nat}:
  match b:
    case True{}:
      e => (0n, {==})
    case False{}:
      e => ge.hi(x, Nat.is_lt(D.MAX_TS(), x), e, {==})

# ---- clamp(x) <= MAX --------------------------------------------------------

def le.hi(+x: Nat, b: Bool) -> {Nat.is_lt(D.MAX_TS(), x) == b : Bool} -> &k: Nat -> {Nat.add(D.clamp.hi(b, x), k) == D.MAX_TS() : Nat}:
  match b:
    case True{}:
      e => (0n, {==})
    case False{}:
      e => not_lt.go(D.MAX_TS(), x, e)

def le.lo(+x: Nat, b: Bool) -> {Nat.is_lt(x, D.MIN_TS()) == b : Bool} -> &k: Nat -> {Nat.add(D.clamp.lo(b, x), k) == D.MAX_TS() : Nat}:
  match b:
    case True{}:
      e => (612n, {==})
    case False{}:
      e => le.hi(x, Nat.is_lt(D.MAX_TS(), x), {==})

# ---- clamp is the identity inside the bounds --------------------------------

def id.hi(+x: Nat, b: Bool) -> {Nat.is_lt(D.MAX_TS(), x) == b : Bool} -> {Nat.is_lt(D.MAX_TS(), x) == False{} : Bool} -> {D.clamp.hi(b, x) == x : Nat}:
  match b:
    case True{}:
      e => hi => absurd({D.MAX_TS() == x : Nat}, false_not_true(Equal.trans(Bool, False{}, Nat.is_lt(D.MAX_TS(), x), True{}, Equal.sym(Bool, Nat.is_lt(D.MAX_TS(), x), False{}, hi), e)))
    case False{}:
      e => hi => {==}

def id.lo(+x: Nat, b: Bool) -> {Nat.is_lt(x, D.MIN_TS()) == b : Bool} -> {Nat.is_lt(x, D.MIN_TS()) == False{} : Bool} -> {Nat.is_lt(D.MAX_TS(), x) == False{} : Bool} -> {D.clamp.lo(b, x) == x : Nat}:
  match b:
    case True{}:
      e => lo => hi => absurd({D.MIN_TS() == x : Nat}, false_not_true(Equal.trans(Bool, False{}, Nat.is_lt(x, D.MIN_TS()), True{}, Equal.sym(Bool, Nat.is_lt(x, D.MIN_TS()), False{}, lo), e)))
    case False{}:
      e => lo => hi => id.hi(x, Nat.is_lt(D.MAX_TS(), x), {==}, hi)

# ---- the laws ---------------------------------------------------------------

def L.clamp_ge_min(x):
  ge.lo(x, Nat.is_lt(x, D.MIN_TS()), {==})

def L.clamp_le_max(x):
  le.lo(x, Nat.is_lt(x, D.MIN_TS()), {==})

def L.clamp_id(x, lo, hi):
  id.lo(x, Nat.is_lt(x, D.MIN_TS()), {==}, lo, hi)

def L.timespan_ge_min(neg, mag):
  +z = D.damp(neg, mag)
  ge.lo(z, Nat.is_lt(z, D.MIN_TS()), {==})

def L.timespan_le_max(neg, mag):
  +z = D.damp(neg, mag)
  le.lo(z, Nat.is_lt(z, D.MIN_TS()), {==})

def L.on_schedule():
  {==}
