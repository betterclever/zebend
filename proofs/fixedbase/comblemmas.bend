import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L
import ./comb.bend as C

def lenp(xs: +List<C.SP>) -> Nat:
  List.length(&2, C.SP, xs)

def take(xs: +List<C.SP>, n: Nat) -> +List<C.SP>:
  List.take(&2, C.SP, xs, n)

def drop(xs: +List<C.SP>, n: Nat) -> +List<C.SP>:
  List.drop(&2, C.SP, xs, n)

# --- points ---------------------------------------------------------------------------

def sp_eq(+a: Nat, +b: Nat, +a2: Nat, +b2: Nat, ha: {a == a2 : Nat}, hb: {b == b2 : Nat}) -> {C.SP{a, b} == C.SP{a2, b2} : C.SP}:
  %ha : {C.SP{a, b} == C.SP{_, b2} : C.SP}
  %hb : {C.SP{a, b} == C.SP{a, _} : C.SP}
  {==}

def padd_zero(+x: C.SP) -> {C.padd(x, C.pzero()) == x : C.SP}:
  match x:
    case C.SP{+a, +b}:
      sp_eq(Nat.add(a, 0n), Nat.add(b, 0n), a, b, N.add_zero_r(a), N.add_zero_r(b))

def padd_zero_s(+x: C.SP, +p: C.SP) -> {C.padd(x, C.smul(0n, p)) == x : C.SP}:
  match p:
    case C.SP{+a, +b}:
      padd_zero(x)

def padd_assoc(+x: C.SP, +y: C.SP, +z: C.SP) -> {C.padd(C.padd(x, y), z) == C.padd(x, C.padd(y, z)) : C.SP}:
  match x y z:
    case C.SP{+a1, +b1} C.SP{+a2, +b2} C.SP{+a3, +b3}:
      sp_eq(Nat.add(Nat.add(a1, a2), a3), Nat.add(Nat.add(b1, b2), b3), Nat.add(a1, Nat.add(a2, a3)), Nat.add(b1, Nat.add(b2, b3)), N.add_assoc(a1, a2, a3), N.add_assoc(b1, b2, b3))

# acc + p + j p == acc + (1 + j) p
def mults_step(+x: C.SP, +p: C.SP, +j: Nat) -> {C.padd(C.padd(x, p), C.smul(j, p)) == C.padd(x, C.smul(1n+j, p)) : C.SP}:
  match x p:
    case C.SP{+a1, +b1} C.SP{+a, +b}:
      sp_eq(Nat.add(Nat.add(a1, a), Nat.mul(j, a)), Nat.add(Nat.add(b1, b), Nat.mul(j, b)), Nat.add(a1, Nat.add(a, Nat.mul(j, a))), Nat.add(b1, Nat.add(b, Nat.mul(j, b))), N.add_assoc(a1, a, Nat.mul(j, a)), N.add_assoc(b1, b, Nat.mul(j, b)))

# --- mults --------------------------------------------------------------------------------

def len_mults(+m: Nat, +p: C.SP, +acc: C.SP) -> {lenp(C.mults(m, p, acc)) == m : Nat}:
  match m:
    case 0n:
      {==}
    case 1n+k:
      Equal.cong(Nat, Nat, w => 1n+w, lenp(C.mults(k, p, C.padd(acc, p))), k, len_mults(k, p, C.padd(acc, p)))

def nth_mults(+m: Nat, +p: C.SP, +acc: C.SP, +i: Nat, +hi: L.Le(1n+i, m)) -> {C.nthp(C.mults(m, p, acc), i) == C.padd(acc, C.smul(i, p)) : C.SP}:
  match m:
    case 0n:
      (+e, +he) = hi
      Empty.absurd({C.nthp(C.mults(0n, p, acc), i) == C.padd(acc, C.smul(i, p)) : C.SP}, L.succ_ne_zero(Nat.add(i, e), he))
    case 1n+k:
      match i:
        case 0n:
          Equal.sym(C.SP, C.padd(acc, C.smul(0n, p)), acc, padd_zero_s(acc, p))
        case 1n+j:
          (+e, +he) = hi
          Equal.trans(C.SP, C.nthp(C.mults(k, p, C.padd(acc, p)), j), C.padd(C.padd(acc, p), C.smul(j, p)), C.padd(acc, C.smul(1n+j, p)), nth_mults(k, p, C.padd(acc, p), j, (e, L.succ_inj(Nat.add(1n+j, e), k, he))), mults_step(acc, p, j))
