import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L
import ./comb.bend as C
import ./comblemmas.bend as CL

# --- lists ------------------------------------------------------------------------------

def nth_take(+xs: +List<C.SP>, +n: Nat, +i: Nat, +hi: L.Le(1n+i, n)) -> {C.nthp(CL.take(xs, n), i) == C.nthp(xs, i) : C.SP}:
  match xs:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      match n:
        case 0n:
          (+e, +he) = hi
          Empty.absurd({C.nthp(CL.take(h <> t, 0n), i) == C.nthp(h <> t, i) : C.SP}, L.succ_ne_zero(Nat.add(i, e), he))
        case 1n+k:
          match i:
            case 0n:
              {==}
            case 1n+j:
              (+e, +he) = hi
              nth_take(t, k, j, (e, L.succ_inj(Nat.add(1n+j, e), k, he)))

def nth_drop(+xs: +List<C.SP>, +n: Nat, +i: Nat) -> {C.nthp(CL.drop(xs, n), i) == C.nthp(xs, Nat.add(n, i)) : C.SP}:
  match xs:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      match n:
        case 0n:
          {==}
        case 1n+k:
          nth_drop(t, k, i)

def len_take(+xs: +List<C.SP>, +n: Nat, +k: Nat, +hl: {CL.lenp(xs) == Nat.add(n, k) : Nat}) -> {CL.lenp(CL.take(xs, n)) == n : Nat}:
  match xs:
    case Nil{}:
      match n:
        case 0n:
          {==}
        case 1n+m:
          Empty.absurd({CL.lenp(CL.take(Nil{}, 1n+m)) == 1n+m : Nat}, L.succ_ne_zero(Nat.add(m, k), Equal.sym(Nat, 0n, 1n+Nat.add(m, k), hl)))
    case Con{+h, +t}:
      match n:
        case 0n:
          {==}
        case 1n+m:
          Equal.cong(Nat, Nat, w => 1n+w, CL.lenp(CL.take(t, m)), m, len_take(t, m, k, L.succ_inj(CL.lenp(t), Nat.add(m, k), hl)))

def len_drop(+xs: +List<C.SP>, +n: Nat, +k: Nat, +hl: {CL.lenp(xs) == Nat.add(n, k) : Nat}) -> {CL.lenp(CL.drop(xs, n)) == k : Nat}:
  match xs:
    case Nil{}:
      match n:
        case 0n:
          hl
        case 1n+m:
          Empty.absurd({CL.lenp(CL.drop(Nil{}, 1n+m)) == k : Nat}, L.succ_ne_zero(Nat.add(m, k), Equal.sym(Nat, 0n, 1n+Nat.add(m, k), hl)))
    case Con{+h, +t}:
      match n:
        case 0n:
          hl
        case 1n+m:
          len_drop(t, m, k, L.succ_inj(CL.lenp(t), Nat.add(m, k), hl))

# --- bits -------------------------------------------------------------------------------

def pow2_double(+k: Nat) -> {C.pow2(1n+k) == Nat.add(C.pow2(k), C.pow2(k)) : Nat}:
  Equal.cong(Nat, Nat, w => Nat.add(C.pow2(k), w), Nat.add(C.pow2(k), 0n), C.pow2(k), N.add_zero_r(C.pow2(k)))

def lenb(bs: +List<Bool>) -> Nat:
  List.length(&2, Bool, bs)

def vl_step(b: Bool, +t: +List<Bool>, +e: Nat, +he: {Nat.add(1n+C.valb(t), e) == C.pow2(lenb(t)) : Nat}) -> L.Le(1n+C.valb(b <> t), C.pow2(lenb(b <> t))):
  match b:
    case True{}:
      +v = C.valb(t)
      +pl = C.pow2(lenb(t))
      (e, Equal.trans(Nat, 1n+Nat.add(Nat.add(pl, v), e), 1n+Nat.add(pl, Nat.add(v, e)), C.pow2(1n+lenb(t)), Equal.cong(Nat, Nat, w => 1n+w, Nat.add(Nat.add(pl, v), e), Nat.add(pl, Nat.add(v, e)), N.add_assoc(pl, v, e)),
        Equal.trans(Nat, 1n+Nat.add(pl, Nat.add(v, e)), Nat.add(pl, pl), C.pow2(1n+lenb(t)), Equal.trans(Nat, 1n+Nat.add(pl, Nat.add(v, e)), Nat.add(pl, 1n+Nat.add(v, e)), Nat.add(pl, pl), Equal.sym(Nat, Nat.add(pl, 1n+Nat.add(v, e)), 1n+Nat.add(pl, Nat.add(v, e)), N.add_succ_r(pl, Nat.add(v, e))), Equal.cong(Nat, Nat, w => Nat.add(pl, w), 1n+Nat.add(v, e), pl, he)), Equal.sym(Nat, C.pow2(1n+lenb(t)), Nat.add(pl, pl), pow2_double(lenb(t))))))
    case False{}:
      +v = C.valb(t)
      +pl = C.pow2(lenb(t))
      (Nat.add(e, pl), Equal.trans(Nat, Nat.add(1n+v, Nat.add(e, pl)), Nat.add(pl, pl), C.pow2(1n+lenb(t)), Equal.trans(Nat, Nat.add(1n+v, Nat.add(e, pl)), Nat.add(Nat.add(1n+v, e), pl), Nat.add(pl, pl), Equal.sym(Nat, Nat.add(Nat.add(1n+v, e), pl), Nat.add(1n+v, Nat.add(e, pl)), N.add_assoc(1n+v, e, pl)), Equal.cong(Nat, Nat, w => Nat.add(w, pl), Nat.add(1n+v, e), pl, he)), Equal.sym(Nat, C.pow2(1n+lenb(t)), Nat.add(pl, pl), pow2_double(lenb(t)))))

def vlt_c(b: Bool, +t: +List<Bool>, le: L.Le(1n+C.valb(t), C.pow2(lenb(t)))) -> L.Le(1n+C.valb(b <> t), C.pow2(lenb(b <> t))):
  (+e, +he) = le
  vl_step(b, t, e, he)

# valb(bs) < 2^length(bs)
def valb_lt(+bs: +List<Bool>) -> L.Le(1n+C.valb(bs), C.pow2(lenb(bs))):
  match bs:
    case Nil{}:
      (0n, {==})
    case Con{+b, +t}:
      vlt_c(b, t, valb_lt(t))

# --- the tree -----------------------------------------------------------------------------

def head_nth(+xs: +List<C.SP>) -> {C.head_ap(xs) == C.nthp(xs, 0n) : C.SP}:
  match xs:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      {==}

# the right half: the entry pow2(k) + valb(bt)
def tree_r(+k: Nat, +bt: +List<Bool>, +xs: +List<C.SP>, +hk: {lenb(bt) == k : Nat}, ih: {C.tget(k, C.tbuild(k, CL.drop(xs, C.pow2(k))), bt) == C.nthp(CL.drop(xs, C.pow2(k)), C.valb(bt)) : C.SP}) -> {C.tget(k, C.tbuild(k, CL.drop(xs, C.pow2(k))), bt) == C.nthp(xs, C.valb(True{} <> bt)) : C.SP}:
  %Equal.sym(Nat, lenb(bt), k, hk) : {C.tget(k, C.tbuild(k, CL.drop(xs, C.pow2(k))), bt) == C.nthp(xs, Nat.add(C.pow2(_), C.valb(bt))) : C.SP}
  Equal.trans(C.SP, C.tget(k, C.tbuild(k, CL.drop(xs, C.pow2(k))), bt), C.nthp(CL.drop(xs, C.pow2(k)), C.valb(bt)), C.nthp(xs, Nat.add(C.pow2(k), C.valb(bt))), ih, nth_drop(xs, C.pow2(k), C.valb(bt)))

# the left half: the entry valb(bt) < pow2(k)
def tree_l(+k: Nat, +bt: +List<Bool>, +xs: +List<C.SP>, +hk: {lenb(bt) == k : Nat}, ih: {C.tget(k, C.tbuild(k, CL.take(xs, C.pow2(k))), bt) == C.nthp(CL.take(xs, C.pow2(k)), C.valb(bt)) : C.SP}) -> {C.tget(k, C.tbuild(k, CL.take(xs, C.pow2(k))), bt) == C.nthp(xs, C.valb(False{} <> bt)) : C.SP}:
  +lt = {%hk : L.Le(1n+C.valb(bt), C.pow2(_)); valb_lt(bt) : L.Le(1n+C.valb(bt), C.pow2(k))}
  Equal.trans(C.SP, C.tget(k, C.tbuild(k, CL.take(xs, C.pow2(k))), bt), C.nthp(CL.take(xs, C.pow2(k)), C.valb(bt)), C.nthp(xs, C.valb(bt)), ih, nth_take(xs, C.pow2(k), C.valb(bt), lt))

# a lookup in the tree built from 2^d entries returns the entry the bits name
def tree_ok(+d: Nat, +bs: +List<Bool>, +xs: +List<C.SP>, +hb: {lenb(bs) == d : Nat}, +hx: {CL.lenp(xs) == C.pow2(d) : Nat}) -> {C.tget(d, C.tbuild(d, xs), bs) == C.nthp(xs, C.valb(bs)) : C.SP}:
  match d:
    case 0n:
      match bs:
        case Nil{}:
          head_nth(xs)
        case Con{+b, +bt}:
          Empty.absurd({C.tget(0n, C.tbuild(0n, xs), b <> bt) == C.nthp(xs, C.valb(b <> bt)) : C.SP}, L.succ_ne_zero(lenb(bt), hb))
    case 1n+k:
      match bs:
        case Nil{}:
          Empty.absurd({C.tget(1n+k, C.tbuild(1n+k, xs), Nil{}) == C.nthp(xs, C.valb(Nil{})) : C.SP}, L.succ_ne_zero(k, Equal.sym(Nat, 0n, 1n+k, hb)))
        case Con{+b, +bt}:
          match b:
            case True{}:
              +hk = L.succ_inj(lenb(bt), k, hb)
              +h2 = Equal.trans(Nat, CL.lenp(xs), C.pow2(1n+k), Nat.add(C.pow2(k), C.pow2(k)), hx, pow2_double(k))
              tree_r(k, bt, xs, hk, tree_ok(k, bt, CL.drop(xs, C.pow2(k)), hk, len_drop(xs, C.pow2(k), C.pow2(k), h2)))
            case False{}:
              +hk = L.succ_inj(lenb(bt), k, hb)
              +h2 = Equal.trans(Nat, CL.lenp(xs), C.pow2(1n+k), Nat.add(C.pow2(k), C.pow2(k)), hx, pow2_double(k))
              tree_l(k, bt, xs, hk, tree_ok(k, bt, CL.take(xs, C.pow2(k)), hk, len_take(xs, C.pow2(k), C.pow2(k), h2)))
