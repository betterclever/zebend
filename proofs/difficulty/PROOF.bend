# Proofs of LAWS.bend.
import Base
import ./LAWS.bend as L
import ./era.bend as E
import ../../zcash/headers/diff.bend as D

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

def add0(n: Nat) -> {Nat.add(n, 0n) == n : Nat}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      Equal.cong(Nat, Nat, succ, Nat.add(p, 0n), p, add0(p))

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

# MIN + gap == MAX in each era.
def gap(e: E.Era) -> &k: Nat -> {Nat.add(E.MIN_TS(e), k) == E.MAX_TS(e) : Nat}:
  match e:
    case E.Pre{}:
      (1224n, {==})
    case E.Post{}:
      (612n, {==})

# ---- MIN <= clamp(x) --------------------------------------------------------

def ge.hi(+e: E.Era, +x: Nat, b: Bool) -> {Nat.is_lt(x, E.MIN_TS(e)) == False{} : Bool} -> {Nat.is_lt(E.MAX_TS(e), x) == b : Bool} -> &k: Nat -> {Nat.add(E.MIN_TS(e), k) == E.clamp.hi(e, b, x) : Nat}:
  match b:
    case True{}:
      lo => h => gap(e)
    case False{}:
      lo => h => not_lt.go(x, E.MIN_TS(e), lo)

def ge.lo(+e: E.Era, +x: Nat, b: Bool) -> {Nat.is_lt(x, E.MIN_TS(e)) == b : Bool} -> &k: Nat -> {Nat.add(E.MIN_TS(e), k) == E.clamp.lo(e, b, x) : Nat}:
  match b:
    case True{}:
      h => (0n, add0(E.MIN_TS(e)))
    case False{}:
      h => ge.hi(e, x, Nat.is_lt(E.MAX_TS(e), x), h, {==})

# ---- clamp(x) <= MAX --------------------------------------------------------

def le.hi(+e: E.Era, +x: Nat, b: Bool) -> {Nat.is_lt(E.MAX_TS(e), x) == b : Bool} -> &k: Nat -> {Nat.add(E.clamp.hi(e, b, x), k) == E.MAX_TS(e) : Nat}:
  match b:
    case True{}:
      h => (0n, add0(E.MAX_TS(e)))
    case False{}:
      h => not_lt.go(E.MAX_TS(e), x, h)

def le.lo(+e: E.Era, +x: Nat, b: Bool) -> {Nat.is_lt(x, E.MIN_TS(e)) == b : Bool} -> &k: Nat -> {Nat.add(E.clamp.lo(e, b, x), k) == E.MAX_TS(e) : Nat}:
  match b:
    case True{}:
      h => gap(e)
    case False{}:
      h => le.hi(e, x, Nat.is_lt(E.MAX_TS(e), x), {==})

# ---- identity inside the bounds -----------------------------------------------

def id.hi(+e: E.Era, +x: Nat, b: Bool) -> {Nat.is_lt(E.MAX_TS(e), x) == b : Bool} -> {Nat.is_lt(E.MAX_TS(e), x) == False{} : Bool} -> {E.clamp.hi(e, b, x) == x : Nat}:
  match b:
    case True{}:
      h => hi => absurd({E.MAX_TS(e) == x : Nat}, false_not_true(Equal.trans(Bool, False{}, Nat.is_lt(E.MAX_TS(e), x), True{}, Equal.sym(Bool, Nat.is_lt(E.MAX_TS(e), x), False{}, hi), h)))
    case False{}:
      h => hi => {==}

def id.lo(+e: E.Era, +x: Nat, b: Bool) -> {Nat.is_lt(x, E.MIN_TS(e)) == b : Bool} -> {Nat.is_lt(x, E.MIN_TS(e)) == False{} : Bool} -> {Nat.is_lt(E.MAX_TS(e), x) == False{} : Bool} -> {E.clamp.lo(e, b, x) == x : Nat}:
  match b:
    case True{}:
      h => lo => hi => absurd({E.MIN_TS(e) == x : Nat}, false_not_true(Equal.trans(Bool, False{}, Nat.is_lt(x, E.MIN_TS(e)), True{}, Equal.sym(Bool, Nat.is_lt(x, E.MIN_TS(e)), False{}, lo), h)))
    case False{}:
      h => lo => hi => id.hi(e, x, Nat.is_lt(E.MAX_TS(e), x), {==}, hi)

# ---- agreement with zcash/headers (post-Blossom) -------------------------------

def agree.hi(b: Bool, x: Nat) -> {E.clamp.hi(E.Post{}, b, x) == D.clamp.hi(b, x) : Nat}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def agree.lo(b: Bool, +x: Nat) -> {E.clamp.lo(E.Post{}, b, x) == D.clamp.lo(b, x) : Nat}:
  match b:
    case True{}:
      {==}
    case False{}:
      agree.hi(Nat.is_lt(1683n, x), x)

def agree.clamp(+x: Nat) -> {E.clamp(E.Post{}, x) == D.clamp(x) : Nat}:
  agree.lo(Nat.is_lt(x, 1071n), x)

def agree.pos(b: Bool, +mag: Nat) -> {E.damp.pos(E.Post{}, b, mag) == D.damp.pos(b, mag) : Nat}:
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def agree.damp(neg: Bool, +mag: Nat) -> {E.damp(E.Post{}, neg, mag) == D.damp(neg, mag) : Nat}:
  match neg:
    case True{}:
      {==}
    case False{}:
      agree.pos(Nat.is_lt(mag, 1275n), mag)

def era_clamp_post(z: Nat) -> Nat:
  E.clamp(E.Post{}, z)

# ---- the laws ---------------------------------------------------------------

def L.clamp_ge_min(e, x):
  ge.lo(e, x, Nat.is_lt(x, E.MIN_TS(e)), {==})

def L.clamp_le_max(e, x):
  le.lo(e, x, Nat.is_lt(x, E.MIN_TS(e)), {==})

def L.clamp_id(e, x, lo, hi):
  id.lo(e, x, Nat.is_lt(x, E.MIN_TS(e)), {==}, lo, hi)

def L.timespan_ge_min(e, neg, mag):
  +z = E.damp(e, neg, mag)
  ge.lo(e, z, Nat.is_lt(z, E.MIN_TS(e)), {==})

def L.timespan_le_max(e, neg, mag):
  +z = E.damp(e, neg, mag)
  le.lo(e, z, Nat.is_lt(z, E.MIN_TS(e)), {==})

def L.on_schedule(e):
  match e:
    case E.Pre{}:
      {==}
    case E.Post{}:
      {==}

def L.post_agrees(neg, mag):
  Equal.trans(Nat, E.timespan(E.Post{}, neg, mag), E.clamp(E.Post{}, D.damp(neg, mag)), D.timespan(neg, mag),
    Equal.cong(Nat, Nat, era_clamp_post, E.damp(E.Post{}, neg, mag), D.damp(neg, mag), agree.damp(neg, mag)),
    agree.clamp(D.damp(neg, mag)))

def L.pre_awt_double():
  {==}
