# Proofs for LAWS.bend.
import Base
import ../../halo2/lib/words.bend as Wd
import ./hist.bend as H
import ./LAWS.bend as Laws

def IsNone(m: Maybe<&2, H.HE>) -> Type:
  match m:
    case None{}:
      Unit
    case Some{_}:
      Empty

law none_ne_some:
  for +e: H.HE
  for h: {None{} == Some{e} : Maybe<&2, H.HE>}
  Empty

def none_ne_some(e, h):
  %h : IsNone(_)
  Unit{}

def absurd(-T: Type, z: Empty) -> T:
  match z:

def get_or(d: H.HE, m: Maybe<&2, H.HE>) -> H.HE:
  match m:
    case None{}:
      d
    case Some{v}:
      v

law some_inj:
  for +x: H.HE
  for +e: H.HE
  for h: {Some{x} == Some{e} : Maybe<&2, H.HE>}
  {x == e : H.HE}

def some_inj(x, e, h):
  Equal.cong(Maybe<&2, H.HE>, H.HE, m => get_or(x, m), Some{x}, Some{e}, h)

law wrap_inr:
  for +x: H.HE
  for +e: H.HE
  for +rest: +List<H.HE>
  for +a: Wd.W
  for +b: Nat
  for pm: {H.hits(a, b, e) == True{} : Bool} & H.Mem(e, rest)
  {H.hits(a, b, e) == True{} : Bool} & H.Mem(e, x <> rest)

def wrap_inr(x, e, rest, a, b, pm):
  (p, m) = pm
  (p, Inr{m})

# The Con case, with the hit test generalised to a variable so it can be matched on.
law pick_sound:
  for c: Bool
  for +x: H.HE
  for +e: H.HE
  for +rest: +List<H.HE>
  for +a: Wd.W
  for +b: Nat
  for hc: {c == H.hits(a, b, x) : Bool}
  for ih: {H.find(rest, a, b) == Some{e} : Maybe<&2, H.HE>} -> ({H.hits(a, b, e) == True{} : Bool} & H.Mem(e, rest))
  for h: {H.pick(c, x, H.find(rest, a, b)) == Some{e} : Maybe<&2, H.HE>}
  {H.hits(a, b, e) == True{} : Bool} & H.Mem(e, x <> rest)

def pick_sound(c, x, e, rest, a, b, hc, ih, h):
  match c:
    case True{}:
      +xe = some_inj(x, e, h)
      +hx = Equal.sym(Bool, True{}, H.hits(a, b, x), hc)
      (Equal.trans(Bool, H.hits(a, b, e), H.hits(a, b, x), True{}, Equal.cong(H.HE, Bool, y => H.hits(a, b, y), e, x, Equal.sym(H.HE, x, e, xe)), hx), Inl{xe})
    case False{}:
      wrap_inr(x, e, rest, a, b, ih(h))

def Laws.find_sound(xs, a, b, e, h):
  match xs:
    case Nil{}:
      absurd({H.hits(a, b, e) == True{} : Bool} & H.Mem(e, Nil{}), none_ne_some(e, h))
    case Con{x, rest}:
      pick_sound(H.hits(a, b, x), x, e, rest, a, b, {==}, hh => Laws.find_sound(rest, a, b, e, hh), h)

def Laws.snoc_keeps(xs, n, e, m):
  match xs:
    case Nil{}:
      match m:
    case Con{x, rest}:
      match m:
        case Inl{p}:
          Inl{p}
        case Inr{q}:
          Inr{Laws.snoc_keeps(rest, n, e, q)}

def Laws.snoc_has(xs, n):
  match xs:
    case Nil{}:
      Inl{{==}}
    case Con{x, rest}:
      Inr{Laws.snoc_has(rest, n)}
