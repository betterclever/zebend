import Base
import ./gadget.bend as G
import ./LAWS.bend as Laws

def IsTrue(b: Bool) -> Type:
  match b:
    case False{}:
      Empty
    case True{}:
      Unit

def IsSucc(n: Nat) -> Type:
  match n:
    case 0n:
      Empty
    case 1n+p:
      Unit

law false_not_true:
  for e: {False{} == True{} : Bool}
  Empty

def false_not_true(e):
  %Equal.sym(Bool, False{}, True{}, e) : IsTrue(_)
  Unit{}

law succ_not_zero:
  for -q: Nat
  for e: {1n+q == 0n : Nat}
  Empty

def succ_not_zero(q, e):
  %e : IsSucc(_)
  Unit{}

# If 2 + r < p then p - (1 + r) is not zero.
law pos_sub:
  for p: Nat
  for r: Nat
  for lt: {Nat.is_lt(2n+r, p) == True{} : Bool}
  for z: {Nat.sub(p, 1n+r) == 0n : Nat}
  Empty

def pos_sub(p, r, lt, z):
  match p:
    case 0n:
      false_not_true(lt)
    case 1n+pp:
      match pp:
        case 0n:
          false_not_true(lt)
        case 1n+q:
          match r:
            case 0n:
              succ_not_zero(q, z)
            case 1n+rr:
              pos_sub(1n+q, rr, lt, z)

# 1 - b = 0 for a canonical b forces b = 1.
law one_minus_zero:
  for +p: Nat
  for b: Nat
  for lt: {Nat.is_lt(b, p) == True{} : Bool}
  for z: {G.one_minus(p, b) == 0n : Nat}
  {b == 1n : Nat}

def one_minus_zero(p, b, lt, z):
  match b:
    case 0n:
      Empty.absurd({0n == 1n : Nat}, succ_not_zero(0n, z))
    case 1n+q:
      match q:
        case 0n:
          {==}
        case 1n+r:
          Empty.absurd({2n+r == 1n : Nat}, pos_sub(p, r, lt, z))

def finish(+p: Nat, +b: Nat, lt: {Nat.is_lt(b, p) == True{} : Bool}, e: Either<&1, &1, {b == 0n : Nat}, {G.one_minus(p, b) == 0n : Nat}>) -> Either<&1, &1, {b == 0n : Nat}, {b == 1n : Nat}>:
  match e:
    case Inl{z}:
      Inl{z}
    case Inr{z}:
      Inr{one_minus_zero(p, b, lt, z)}

def Laws.bool_gate_sound(p, b, lt, nzd, h):
  finish(p, b, lt, nzd(b, G.one_minus(p, b), h))
