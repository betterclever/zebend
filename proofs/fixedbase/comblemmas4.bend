import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L
import ./comb.bend as C
import ./comblemmas.bend as CL
import ./comblemmas3.bend as CL3

# The walk over wbases is the sum of digit_j 2^(c j) P.

def smul_smul(+m: Nat, +k: Nat, +p: C.SP) -> {C.smul(m, C.smul(k, p)) == C.smul(Nat.mul(m, k), p) : C.SP}:
  match p:
    case C.SP{+a, +b}:
      CL.sp_eq(Nat.mul(m, Nat.mul(k, a)), Nat.mul(m, Nat.mul(k, b)), Nat.mul(Nat.mul(m, k), a), Nat.mul(Nat.mul(m, k), b), Equal.sym(Nat, Nat.mul(Nat.mul(m, k), a), Nat.mul(m, Nat.mul(k, a)), L.mul_assoc(m, k, a)), Equal.sym(Nat, Nat.mul(Nat.mul(m, k), b), Nat.mul(m, Nat.mul(k, b)), L.mul_assoc(m, k, b)))

# dbl_n(c, 2^(c j) P) == 2^(c (1 + j)) P
def next_base(+c: Nat, +j: Nat, +p: C.SP) -> {C.dbl_n(c, C.smul(C.pow2(Nat.mul(c, j)), p)) == C.smul(C.pow2(Nat.mul(c, 1n+j)), p) : C.SP}:
  Equal.trans(C.SP, C.dbl_n(c, C.smul(C.pow2(Nat.mul(c, j)), p)), C.smul(Nat.mul(C.pow2(c), C.pow2(Nat.mul(c, j))), p), C.smul(C.pow2(Nat.mul(c, 1n+j)), p), CL3.dbl_n_smul(c, C.pow2(Nat.mul(c, j)), p),
    Equal.cong(Nat, C.SP, z => C.smul(z, p), Nat.mul(C.pow2(c), C.pow2(Nat.mul(c, j))), C.pow2(Nat.mul(c, 1n+j)),
      Equal.trans(Nat, Nat.mul(C.pow2(c), C.pow2(Nat.mul(c, j))), C.pow2(Nat.add(c, Nat.mul(c, j))), C.pow2(Nat.mul(c, 1n+j)), Equal.sym(Nat, C.pow2(Nat.add(c, Nat.mul(c, j))), Nat.mul(C.pow2(c), C.pow2(Nat.mul(c, j))), CL3.pow2_add(c, Nat.mul(c, j))), Equal.cong(Nat, Nat, z => C.pow2(z), Nat.add(c, Nat.mul(c, j)), Nat.mul(c, 1n+j), Equal.sym(Nat, Nat.mul(c, 1n+j), Nat.add(c, Nat.mul(c, j)), L.mul_succ_r(c, j))))))

def lend(ds: +List<C.Dg>) -> Nat:
  List.length(&2, C.Dg, ds)

def ws_cs(+ds: +List<C.Dg>, +n: Nat, +c: Nat, +j: Nat, +p: C.SP, +hl: L.Le(lend(ds), n)) -> {C.wsum(C.wbases(n, c, C.smul(C.pow2(Nat.mul(c, j)), p)), ds) == C.comb_sum(ds, c, j, p) : C.SP}:
  match ds:
    case Nil{}:
      match n:
        case 0n:
          {==}
        case 1n+k:
          {==}
    case Con{C.Dg{+m, +neg, +bs}, +dt}:
      match n:
        case 0n:
          (+e, +he) = hl
          Empty.absurd({C.wsum(C.wbases(0n, c, C.smul(C.pow2(Nat.mul(c, j)), p)), C.Dg{m, neg, bs} <> dt) == C.comb_sum(C.Dg{m, neg, bs} <> dt, c, j, p) : C.SP}, L.succ_ne_zero(Nat.add(lend(dt), e), he))
        case 1n+k:
          (+e, +he) = hl
          +q = C.smul(C.pow2(Nat.mul(c, j)), p)
          %Equal.sym(C.SP, C.dbl_n(c, q), C.smul(C.pow2(Nat.mul(c, 1n+j)), p), next_base(c, j, p)) : {C.padd(C.signed(neg, C.smul(m, q)), C.wsum(C.wbases(k, c, _), dt)) == C.comb_sum(C.Dg{m, neg, bs} <> dt, c, j, p) : C.SP}
          %Equal.sym(C.SP, C.smul(m, q), C.smul(Nat.mul(m, C.pow2(Nat.mul(c, j))), p), smul_smul(m, C.pow2(Nat.mul(c, j)), p)) : {C.padd(C.signed(neg, _), C.wsum(C.wbases(k, c, C.smul(C.pow2(Nat.mul(c, 1n+j)), p)), dt)) == C.comb_sum(C.Dg{m, neg, bs} <> dt, c, j, p) : C.SP}
          Equal.cong(C.SP, C.SP, z => C.padd(C.signed(neg, C.smul(Nat.mul(m, C.pow2(Nat.mul(c, j))), p)), z), C.wsum(C.wbases(k, c, C.smul(C.pow2(Nat.mul(c, 1n+j)), p)), dt), C.comb_sum(dt, c, 1n+j, p), ws_cs(dt, k, c, 1n+j, p, (e, L.succ_inj(Nat.add(lend(dt), e), k, he))))

def ws_cs0(+ds: +List<C.Dg>, +n: Nat, +c: Nat, +p: C.SP, +hl: L.Le(lend(ds), n)) -> {C.wsum(C.wbases(n, c, p), ds) == C.comb_sum(ds, c, 0n, p) : C.SP}:
  +e1 = Equal.trans(C.SP, C.smul(C.pow2(Nat.mul(c, 0n)), p), C.smul(1n, p), p, Equal.cong(Nat, C.SP, z => C.smul(C.pow2(z), p), Nat.mul(c, 0n), 0n, L.mul_zero_r(c)), CL3.smul_one(p))
  %e1 : {C.wsum(C.wbases(n, c, _), ds) == C.comb_sum(ds, c, 0n, p) : C.SP}
  ws_cs(ds, n, c, 0n, p, hl)
