import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L
import ./comb.bend as C
import ./comblemmas.bend as CL
import ./comblemmas2.bend as CL2

def sub0(+d: Nat) -> {Nat.sub(d, 0n) == d : Nat}:
  match d:
    case 0n:
      {==}
    case 1n+k:
      {==}

def one_plus(+p: C.SP, +v: Nat) -> {C.padd(p, C.smul(v, p)) == C.smul(1n+v, p) : C.SP}:
  match p:
    case C.SP{+a, +b}:
      {==}

# the table of window j: entry with bits bs (value v) is (1 + v) * base
def table_entry(+d: Nat, +bs: +List<Bool>, +p: C.SP, +hb: {CL2.lenb(bs) == d : Nat}) -> {C.tget(d, C.window(1n+d, p), bs) == C.smul(1n+C.valb(bs), p) : C.SP}:
  +lt = {%hb : L.Le(1n+C.valb(bs), C.pow2(_)); CL2.valb_lt(bs) : L.Le(1n+C.valb(bs), C.pow2(d))}
  +xs = C.mults(C.pow2(d), p, p)
  %Equal.sym(Nat, Nat.sub(d, 0n), d, sub0(d)) : {C.tget(d, C.tbuild(_, C.mults(C.pow2(_), p, p)), bs) == C.smul(1n+C.valb(bs), p) : C.SP}
  Equal.trans(C.SP, C.tget(d, C.tbuild(d, xs), bs), C.nthp(xs, C.valb(bs)), C.smul(1n+C.valb(bs), p), CL2.tree_ok(d, bs, xs, hb, CL.len_mults(C.pow2(d), p, p)),
  Equal.trans(C.SP, C.nthp(xs, C.valb(bs)), C.padd(p, C.smul(C.valb(bs), p)), C.smul(1n+C.valb(bs), p), CL.nth_mults(C.pow2(d), p, p, C.valb(bs), lt), one_plus(p, C.valb(bs))))

def zero_term(+b: C.SP, +neg: Nat) -> {C.signed(neg, C.smul(0n, b)) == C.pzero() : C.SP}:
  match b:
    case C.SP{+x, +y}:
      match neg:
        case 0n:
          {==}
        case 1n+k:
          match k:
            case 0n:
              {==}
            case 1n+q:
              {==}

def zero_padd(+w: C.SP) -> {C.padd(C.pzero(), w) == w : C.SP}:
  match w:
    case C.SP{+x, +y}:
      {==}

# one window of the walk
def step_ok(+d: Nat, +m: Nat, +neg: Nat, +bs: +List<Bool>, +b: C.SP, +acc: C.SP, +w: C.SP, hd: Either<&2, &2, {m == 0n : Nat}, Sigma<&2, &2, {CL2.lenb(bs) == d : Nat}, _ => {1n+C.valb(bs) == m : Nat}>>) -> {C.padd(C.step(Nat.is_eq(m, 0n), d, bs, neg, C.window(1n+d, b), acc), w) == C.padd(acc, C.padd(C.signed(neg, C.smul(m, b)), w)) : C.SP}:
  match hd:
    case Inl{+e0}:
      %Equal.sym(Nat, m, 0n, e0) : {C.padd(C.step(Nat.is_eq(_, 0n), d, bs, neg, C.window(1n+d, b), acc), w) == C.padd(acc, C.padd(C.signed(neg, C.smul(_, b)), w)) : C.SP}
      %Equal.sym(C.SP, C.signed(neg, C.smul(0n, b)), C.pzero(), zero_term(b, neg)) : {C.padd(acc, w) == C.padd(acc, C.padd(_, w)) : C.SP}
      Equal.cong(C.SP, C.SP, z => C.padd(acc, z), w, C.padd(C.pzero(), w), Equal.sym(C.SP, C.padd(C.pzero(), w), w, zero_padd(w)))
    case Inr{+hr}:
      (+hl, +hv) = hr
      %hv : {C.padd(C.step(Nat.is_eq(_, 0n), d, bs, neg, C.window(1n+d, b), acc), w) == C.padd(acc, C.padd(C.signed(neg, C.smul(_, b)), w)) : C.SP}
      %Equal.sym(C.SP, C.tget(d, C.window(1n+d, b), bs), C.smul(1n+C.valb(bs), b), table_entry(d, bs, b, hl)) : {C.padd(C.padd(acc, C.signed(neg, _)), w) == C.padd(acc, C.padd(C.signed(neg, C.smul(1n+C.valb(bs), b)), w)) : C.SP}
      CL.padd_assoc(acc, C.signed(neg, C.smul(1n+C.valb(bs), b)), w)

# the walk over the windows: acc plus the signed digits times their bases
def walk_ok(+d: Nat, +bases: +List<C.SP>, +ds: +List<C.Dg>, +acc: C.SP, +h: C.DigOk(d, ds)) -> {C.walk(d, C.windows(1n+d, bases), ds, acc) == C.padd(acc, C.wsum(bases, ds)) : C.SP}:
  match bases ds:
    case Con{+b, +bt} Con{C.Dg{+m, +neg, +bs}, +dt}:
      (+hd, +hr) = h
      +a2 = C.step(Nat.is_eq(m, 0n), d, bs, neg, C.window(1n+d, b), acc)
      Equal.trans(C.SP, C.walk(d, C.windows(1n+d, bt), dt, a2), C.padd(a2, C.wsum(bt, dt)), C.padd(acc, C.padd(C.signed(neg, C.smul(m, b)), C.wsum(bt, dt))), walk_ok(d, bt, dt, a2, hr), step_ok(d, m, neg, bs, b, acc, C.wsum(bt, dt), hd))
    case Nil{} _:
      Equal.sym(C.SP, C.padd(acc, C.pzero()), acc, CL.padd_zero(acc))
    case Con{_, _} Nil{}:
      Equal.sym(C.SP, C.padd(acc, C.pzero()), acc, CL.padd_zero(acc))

# --- the window bases are 2^(c j) P ---------------------------------------------------------

def pow2_add(+a: Nat, +b: Nat) -> {C.pow2(Nat.add(a, b)) == Nat.mul(C.pow2(a), C.pow2(b)) : Nat}:
  match a:
    case 0n:
      Equal.sym(Nat, Nat.mul(1n, C.pow2(b)), C.pow2(b), L.mul_one_l(C.pow2(b)))
    case 1n+k:
      %Equal.sym(Nat, C.pow2(Nat.add(k, b)), Nat.mul(C.pow2(k), C.pow2(b)), pow2_add(k, b)) : {Nat.mul(2n, _) == Nat.mul(Nat.mul(2n, C.pow2(k)), C.pow2(b)) : Nat}
      Equal.sym(Nat, Nat.mul(Nat.mul(2n, C.pow2(k)), C.pow2(b)), Nat.mul(2n, Nat.mul(C.pow2(k), C.pow2(b))), L.mul_assoc(2n, C.pow2(k), C.pow2(b)))

def smul_dbl(+k: Nat, +p: C.SP) -> {C.padd(C.smul(k, p), C.smul(k, p)) == C.smul(Nat.add(k, k), p) : C.SP}:
  match p:
    case C.SP{+a, +b}:
      CL.sp_eq(Nat.add(Nat.mul(k, a), Nat.mul(k, a)), Nat.add(Nat.mul(k, b), Nat.mul(k, b)), Nat.mul(Nat.add(k, k), a), Nat.mul(Nat.add(k, k), b), Equal.sym(Nat, Nat.mul(Nat.add(k, k), a), Nat.add(Nat.mul(k, a), Nat.mul(k, a)), L.mul_add_r(k, k, a)), Equal.sym(Nat, Nat.mul(Nat.add(k, k), b), Nat.add(Nat.mul(k, b), Nat.mul(k, b)), L.mul_add_r(k, k, b)))

# x (k + k) == (2 x) k
def two_k(+x: Nat, +k: Nat) -> {Nat.mul(x, Nat.add(k, k)) == Nat.mul(Nat.mul(2n, x), k) : Nat}:
  %Equal.sym(Nat, Nat.mul(Nat.mul(2n, x), k), Nat.mul(2n, Nat.mul(x, k)), L.mul_assoc(2n, x, k)) : {Nat.mul(x, Nat.add(k, k)) == _ : Nat}
  %Equal.sym(Nat, Nat.add(Nat.mul(x, k), 0n), Nat.mul(x, k), N.add_zero_r(Nat.mul(x, k))) : {Nat.mul(x, Nat.add(k, k)) == Nat.add(Nat.mul(x, k), _) : Nat}
  L.mul_add_l(x, k, k)

def dbl_n_smul(+n: Nat, +k: Nat, +p: C.SP) -> {C.dbl_n(n, C.smul(k, p)) == C.smul(Nat.mul(C.pow2(n), k), p) : C.SP}:
  match n:
    case 0n:
      Equal.cong(Nat, C.SP, z => C.smul(z, p), k, Nat.mul(1n, k), Equal.sym(Nat, Nat.mul(1n, k), k, L.mul_one_l(k)))
    case 1n+m:
      %Equal.sym(C.SP, C.padd(C.smul(k, p), C.smul(k, p)), C.smul(Nat.add(k, k), p), smul_dbl(k, p)) : {C.dbl_n(m, _) == C.smul(Nat.mul(C.pow2(1n+m), k), p) : C.SP}
      Equal.trans(C.SP, C.dbl_n(m, C.smul(Nat.add(k, k), p)), C.smul(Nat.mul(C.pow2(m), Nat.add(k, k)), p), C.smul(Nat.mul(C.pow2(1n+m), k), p), dbl_n_smul(m, Nat.add(k, k), p), Equal.cong(Nat, C.SP, z => C.smul(z, p), Nat.mul(C.pow2(m), Nat.add(k, k)), Nat.mul(Nat.mul(2n, C.pow2(m)), k), two_k(C.pow2(m), k)))

# 2^(c (1 + j)) k == 2^(c j) (2^c k)
def pw_step(+c: Nat, +j: Nat, +k: Nat) -> {Nat.mul(C.pow2(Nat.mul(c, j)), Nat.mul(C.pow2(c), k)) == Nat.mul(C.pow2(Nat.mul(c, 1n+j)), k) : Nat}:
  %Equal.sym(Nat, Nat.mul(c, 1n+j), Nat.add(c, Nat.mul(c, j)), L.mul_succ_r(c, j)) : {Nat.mul(C.pow2(Nat.mul(c, j)), Nat.mul(C.pow2(c), k)) == Nat.mul(C.pow2(_), k) : Nat}
  %Equal.sym(Nat, C.pow2(Nat.add(c, Nat.mul(c, j))), Nat.mul(C.pow2(c), C.pow2(Nat.mul(c, j))), pow2_add(c, Nat.mul(c, j))) : {Nat.mul(C.pow2(Nat.mul(c, j)), Nat.mul(C.pow2(c), k)) == Nat.mul(_, k) : Nat}
  %L.mul_comm(C.pow2(Nat.mul(c, j)), C.pow2(c)) : {Nat.mul(C.pow2(Nat.mul(c, j)), Nat.mul(C.pow2(c), k)) == Nat.mul(_, k) : Nat}
  %Equal.sym(Nat, Nat.mul(Nat.mul(C.pow2(Nat.mul(c, j)), C.pow2(c)), k), Nat.mul(C.pow2(Nat.mul(c, j)), Nat.mul(C.pow2(c), k)), L.mul_assoc(C.pow2(Nat.mul(c, j)), C.pow2(c), k)) : {Nat.mul(C.pow2(Nat.mul(c, j)), Nat.mul(C.pow2(c), k)) == _ : Nat}
  {==}

def wb_gen(+n: Nat, +c: Nat, +k: Nat, +p: C.SP, +j: Nat, +hj: L.Le(1n+j, n)) -> {C.nthp(C.wbases(n, c, C.smul(k, p)), j) == C.smul(Nat.mul(C.pow2(Nat.mul(c, j)), k), p) : C.SP}:
  match n:
    case 0n:
      (+e, +he) = hj
      Empty.absurd({C.nthp(C.wbases(0n, c, C.smul(k, p)), j) == C.smul(Nat.mul(C.pow2(Nat.mul(c, j)), k), p) : C.SP}, L.succ_ne_zero(Nat.add(j, e), he))
    case 1n+n2:
      match j:
        case 0n:
          %Equal.sym(Nat, Nat.mul(c, 0n), 0n, L.mul_zero_r(c)) : {C.smul(k, p) == C.smul(Nat.mul(C.pow2(_), k), p) : C.SP}
          Equal.cong(Nat, C.SP, z => C.smul(z, p), k, Nat.mul(1n, k), Equal.sym(Nat, Nat.mul(1n, k), k, L.mul_one_l(k)))
        case 1n+j2:
          (+e, +he) = hj
          %Equal.sym(C.SP, C.dbl_n(c, C.smul(k, p)), C.smul(Nat.mul(C.pow2(c), k), p), dbl_n_smul(c, k, p)) : {C.nthp(C.wbases(n2, c, _), j2) == C.smul(Nat.mul(C.pow2(Nat.mul(c, 1n+j2)), k), p) : C.SP}
          Equal.trans(C.SP, C.nthp(C.wbases(n2, c, C.smul(Nat.mul(C.pow2(c), k), p)), j2), C.smul(Nat.mul(C.pow2(Nat.mul(c, j2)), Nat.mul(C.pow2(c), k)), p), C.smul(Nat.mul(C.pow2(Nat.mul(c, 1n+j2)), k), p), wb_gen(n2, c, Nat.mul(C.pow2(c), k), p, j2, (e, L.succ_inj(Nat.add(1n+j2, e), n2, he))), Equal.cong(Nat, C.SP, z => C.smul(z, p), Nat.mul(C.pow2(Nat.mul(c, j2)), Nat.mul(C.pow2(c), k)), Nat.mul(C.pow2(Nat.mul(c, 1n+j2)), k), pw_step(c, j2, k)))

def smul_one(+p: C.SP) -> {C.smul(1n, p) == p : C.SP}:
  match p:
    case C.SP{+a, +b}:
      CL.sp_eq(Nat.mul(1n, a), Nat.mul(1n, b), a, b, L.mul_one_l(a), L.mul_one_l(b))

def mul_one_r_sp(+x: Nat, +p: C.SP) -> {C.smul(Nat.mul(x, 1n), p) == C.smul(x, p) : C.SP}:
  Equal.cong(Nat, C.SP, z => C.smul(z, p), Nat.mul(x, 1n), x, L.mul_one_r(x))

def wbases_pow(+n: Nat, +c: Nat, +p: C.SP, +j: Nat, +hj: L.Le(1n+j, n)) -> {C.nthp(C.wbases(n, c, p), j) == C.smul(C.pow2(Nat.mul(c, j)), p) : C.SP}:
  %smul_one(p) : {C.nthp(C.wbases(n, c, _), j) == C.smul(C.pow2(Nat.mul(c, j)), p) : C.SP}
  Equal.trans(C.SP, C.nthp(C.wbases(n, c, C.smul(1n, p)), j), C.smul(Nat.mul(C.pow2(Nat.mul(c, j)), 1n), p), C.smul(C.pow2(Nat.mul(c, j)), p), wb_gen(n, c, 1n, p, j, hj), mul_one_r_sp(C.pow2(Nat.mul(c, j)), p))
