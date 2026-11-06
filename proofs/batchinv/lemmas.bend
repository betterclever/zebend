import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L
import ../opt_gates/term.bend as T
import ../opt_gates/sound.bend as S
import ../ring/expr.bend as X
import ../ring/poly.bend as P
import ../ring/cert.bend as R
import ./model.bend as M
import ./certs.bend as K

# --- relations ---------------------------------------------------------------------------

# ys is the list of inverses of xs: same length, x * y == 1 and y canonical, pointwise.
def Inv(+bp: Nat, xs: +List<Nat>, ys: +List<Nat>) -> Data:
  match xs ys:
    case Nil{} Nil{}:
      Unit
    case Con{+x, xr} Con{+y, yr}:
      Sigma<&2, &2, L.Le(y, bp), _ => Sigma<&2, &2, {T.fmul(bp, x, y) == 1n : Nat}, _ => Inv(bp, xr, yr)>>
    case _ _:
      Empty

# rx = [x_k .. x_0] (inputs, newest first), rp = [a_(k-1) .. a_0] (prefix products, newest
# first, without a_k) and a = a_k, where a_0 = 1 x_0 and a_j = a_(j-1) x_j.
def Rr(+bp: Nat, rp: +List<Nat>, rx: +List<Nat>, +a: Nat) -> Data:
  match rp:
    case Nil{}:
      match rx:
        case Con{+x, rx2}:
          match rx2:
            case Nil{}:
              Sigma<&2, &2, L.Le(x, bp), _ => {a == T.fmul(bp, 1n, x) : Nat}>
            case Con{_, _}:
              Empty
        case Nil{}:
          Empty
    case Con{+a2, rp2}:
      match rx:
        case Con{+x, rx2}:
          Sigma<&2, &2, L.Le(x, bp), _ => Sigma<&2, &2, L.Le(a2, bp), _ => Sigma<&2, &2, {a == T.fmul(bp, a2, x) : Nat}, _ => Rr(bp, rp2, rx2, a2)>>>
        case Nil{}:
          Empty

# rpd = [a_k ..] with a_k == acc and Rr below it; or nothing processed yet and acc == 1.
def G(+bp: Nat, rpd: +List<Nat>, +rxd: +List<Nat>, +acc: Nat) -> Data:
  match rpd:
    case Nil{}:
      Sigma<&2, &2, {rxd == Nil{} : +List<Nat>}, _ => {acc == 1n : Nat}>
    case Con{+a, rp}:
      Sigma<&2, &2, {a == acc : Nat}, _ => Rr(bp, rp, rxd, a)>

def one_c(+bp: Nat, +l1: L.Le(1n, bp)) -> {Nat.mod(1n, 1n+bp) == 1n : Nat}:
  L.mod_small(1n, bp, l1)

# --- the walk back (bi_back) ----------------------------------------------------------------

def le_eq(+bp: Nat, +u: Nat, +v: Nat, e: {u == v : Nat}, l: L.Le(v, bp)) -> L.Le(u, bp):
  %Equal.sym(Nat, u, v, e) : L.Le(_, bp)
  l

# one input left: its inverse is inv
def back_one(+bp: Nat, +x: Nat, +a: Nat, +inv: Nat, +done: +List<Nat>, +out: +List<Nat>, rr: Sigma<&2, &2, L.Le(x, bp), _ => {a == T.fmul(bp, 1n, x) : Nat}>, li: L.Le(inv, bp), h: {T.fmul(bp, a, inv) == 1n : Nat}, hi: Inv(bp, done, out)) -> Inv(bp, x <> done, inv <> out):
  (+lx, +ha) = rr
  +xa = Equal.trans(Nat, x, T.fmul(bp, 1n, x), a, Equal.sym(Nat, T.fmul(bp, 1n, x), x, S.fmul_one_l(bp, x, lx)), Equal.sym(Nat, a, T.fmul(bp, 1n, x), ha))
  (li, (Equal.trans(Nat, T.fmul(bp, x, inv), T.fmul(bp, a, inv), 1n, Equal.cong(Nat, Nat, w => T.fmul(bp, w, inv), x, a, xa), h), hi))

# one step back: x_k^-1 = inv a_(k-1), then inv := inv x_k
def back_step(+bp: Nat, +l1: L.Le(1n, bp), +x: Nat, +rx2: +List<Nat>, +a2: Nat, +rp2: +List<Nat>, +a: Nat, +inv: Nat, +done: +List<Nat>, +out: +List<Nat>, rr: Rr(bp, a2 <> rp2, x <> rx2, a), +li: L.Le(inv, bp), +h: {T.fmul(bp, a, inv) == 1n : Nat}, hi: Inv(bp, done, out), ih: Rr(bp, rp2, rx2, a2) -> L.Le(T.fmul(bp, inv, x), bp) -> {T.fmul(bp, a2, T.fmul(bp, inv, x)) == 1n : Nat} -> Inv(bp, x <> done, T.fmul(bp, inv, a2) <> out) -> Inv(bp, List.reverse.go(&2, Nat, rx2, x <> done), M.bi_back(bp, rx2, rp2, T.fmul(bp, inv, x), T.fmul(bp, inv, a2) <> out))) -> Inv(bp, List.reverse.go(&2, Nat, rx2, x <> done), M.bi_back(bp, rx2, rp2, T.fmul(bp, inv, x), T.fmul(bp, inv, a2) <> out)):
  (+lx, rest) = rr
  (+la2, rest2) = rest
  (+ha, rr2) = rest2
  +la = le_eq(bp, a, T.fmul(bp, a2, x), ha, L.mod_le(Nat.mul(a2, x), bp))
  +hc = {(lx, (li, (la2, (la, Unit{})))) : X.Canon(bp, [x, inv, a2, a])}
  +h1 = Equal.trans(Nat, T.fmul(bp, a, inv), 1n, Nat.mod(1n, 1n+bp), h, Equal.sym(Nat, Nat.mod(1n, 1n+bp), 1n, one_c(bp, l1)))
  +c1 = R.cert_ok2(bp, [x, inv, a2, a], hc, K.r1_t1(), K.r1_t2(), K.r1_cs(), K.r1_rs(), K.r1_k1(), K.r1_k2(), (ha, (h1, Unit{})), K.r1_lt(), K.r1_rt(), K.r1_el(), K.r1_er(), K.r1_h())
  +c2 = R.cert_ok2(bp, [x, inv, a2, a], hc, K.r2_t1(), K.r2_t2(), K.r2_cs(), K.r2_rs(), K.r2_k1(), K.r2_k2(), (ha, (h1, Unit{})), K.r2_lt(), K.r2_rt(), K.r2_el(), K.r2_er(), K.r2_h())
  +e1 = Equal.trans(Nat, T.fmul(bp, x, T.fmul(bp, inv, a2)), Nat.mod(1n, 1n+bp), 1n, c1, one_c(bp, l1))
  +e2 = Equal.trans(Nat, T.fmul(bp, a2, T.fmul(bp, inv, x)), Nat.mod(1n, 1n+bp), 1n, c2, one_c(bp, l1))
  ih(rr2, L.mod_le(Nat.mul(inv, x), bp), e2, (L.mod_le(Nat.mul(inv, a2), bp), (e1, hi)))

def back_ok(+bp: Nat, +l1: L.Le(1n, bp), +rp: +List<Nat>, +rx: +List<Nat>, +a: Nat, +inv: Nat, +done: +List<Nat>, +out: +List<Nat>) -> Rr(bp, rp, rx, a) -> L.Le(inv, bp) -> {T.fmul(bp, a, inv) == 1n : Nat} -> Inv(bp, done, out) -> Inv(bp, List.reverse.go(&2, Nat, rx, done), M.bi_back(bp, rx, rp, inv, out)):
  match rp:
    case Nil{}:
      match rx:
        case Con{+x, +rx2}:
          match rx2:
            case Nil{}:
              rr => li => h => hi => back_one(bp, x, a, inv, done, out, rr, li, h, hi)
            case Con{+y, +ys}:
              rr => li => h => hi => Empty.absurd(Inv(bp, List.reverse.go(&2, Nat, x <> (y <> ys), done), M.bi_back(bp, x <> (y <> ys), Nil{}, inv, out)), rr)
        case Nil{}:
          rr => li => h => hi => Empty.absurd(Inv(bp, List.reverse.go(&2, Nat, Nil{}, done), M.bi_back(bp, Nil{}, Nil{}, inv, out)), rr)
    case Con{+a2, +rp2}:
      match rx:
        case Con{+x, +rx2}:
          rr => li => h => hi => back_step(bp, l1, x, rx2, a2, rp2, a, inv, done, out, rr, li, h, hi, back_ok(bp, l1, rp2, rx2, a2, T.fmul(bp, inv, x), x <> done, T.fmul(bp, inv, a2) <> out))
        case Nil{}:
          rr => li => h => hi => Empty.absurd(Inv(bp, List.reverse.go(&2, Nat, Nil{}, done), M.bi_back(bp, Nil{}, a2 <> rp2, inv, out)), rr)

# --- the prefix products (bi_pre), reversed ------------------------------------------------

def g_base(+bp: Nat, +h: Nat, +lh: L.Le(h, bp), +rxd: +List<Nat>, +acc: Nat, g: G(bp, Nil{}, rxd, acc)) -> G(bp, T.fmul(bp, acc, h) <> Nil{}, h <> rxd, T.fmul(bp, acc, h)):
  (erx, eacc) = g
  %Equal.sym(+List<Nat>, rxd, Nil{}, erx) : G(bp, T.fmul(bp, acc, h) <> Nil{}, h <> _, T.fmul(bp, acc, h))
  ({==}, (lh, Equal.cong(Nat, Nat, w => T.fmul(bp, w, h), acc, 1n, eacc)))

def g_cons(+bp: Nat, +h: Nat, +lh: L.Le(h, bp), +a: Nat, +rp: +List<Nat>, +rxd: +List<Nat>, +acc: Nat, +lacc: L.Le(acc, bp), g: G(bp, a <> rp, rxd, acc)) -> G(bp, T.fmul(bp, acc, h) <> (a <> rp), h <> rxd, T.fmul(bp, acc, h)):
  (+ea, rr) = g
  ({==}, (lh, (le_eq(bp, a, acc, ea, lacc), (Equal.cong(Nat, Nat, w => T.fmul(bp, w, h), acc, a, Equal.sym(Nat, a, acc, ea)), rr))))

def g_step(+bp: Nat, +h: Nat, +lh: L.Le(h, bp), +rpd: +List<Nat>, +rxd: +List<Nat>, +acc: Nat, +lacc: L.Le(acc, bp)) -> G(bp, rpd, rxd, acc) -> G(bp, T.fmul(bp, acc, h) <> rpd, h <> rxd, T.fmul(bp, acc, h)):
  match rpd:
    case Nil{}:
      g => g_base(bp, h, lh, rxd, acc, g)
    case Con{+a, +rp}:
      g => g_cons(bp, h, lh, a, rp, rxd, acc, lacc, g)

def pre_ok(+bp: Nat, +xs: +List<Nat>, +hc: X.Canon(bp, xs), +rpd: +List<Nat>, +rxd: +List<Nat>, +acc: Nat, +lacc: L.Le(acc, bp)) -> G(bp, rpd, rxd, acc) -> G(bp, List.reverse.go(&2, Nat, M.bi_pre(bp, xs, acc), rpd), List.reverse.go(&2, Nat, xs, rxd), M.prod(bp, xs, acc)):
  match xs:
    case Nil{}:
      g => g
    case Con{+h, +t}:
      (+lh, +lt) = hc
      g => pre_ok(bp, t, lt, T.fmul(bp, acc, h) <> rpd, h <> rxd, T.fmul(bp, acc, h), L.mod_le(Nat.mul(acc, h), bp), g_step(bp, h, lh, rpd, rxd, acc, lacc, g))

# --- the single inversion and the whole batch_inv ----------------------------------------------

def go_nil(+bp: Nat, +xs: +List<Nat>, +pr: Nat, g: G(bp, Nil{}, List.reverse(&2, Nat, xs), pr)) -> Inv(bp, List.reverse.go(&2, Nat, List.reverse(&2, Nat, xs), Nil{}), M.bi_go(bp, xs, Nil{})):
  (erx, _) = g
  %Equal.sym(+List<Nat>, List.reverse(&2, Nat, xs), Nil{}, erx) : Inv(bp, List.reverse.go(&2, Nat, _, Nil{}), M.bi_go(bp, xs, Nil{}))
  Unit{}

def go_cons(+bp: Nat, +l1: L.Le(1n, bp), +xs: +List<Nat>, +top: Nat, +rest: +List<Nat>, +pr: Nat, g: G(bp, top <> rest, List.reverse(&2, Nat, xs), pr), h: {T.fmul(bp, pr, T.finv(bp, pr)) == 1n : Nat}) -> Inv(bp, List.reverse.go(&2, Nat, List.reverse(&2, Nat, xs), Nil{}), M.bi_go(bp, xs, top <> rest)):
  (+et, rr) = g
  +h2 = Equal.trans(Nat, T.fmul(bp, top, T.finv(bp, top)), T.fmul(bp, pr, T.finv(bp, pr)), 1n, Equal.cong(Nat, Nat, w => T.fmul(bp, w, T.finv(bp, w)), top, pr, et), h)
  back_ok(bp, l1, rest, List.reverse(&2, Nat, xs), top, T.finv(bp, top), Nil{}, Nil{}, rr, L.mod_le(Nat.pow(top, Nat.sub(bp, 1n)), bp), h2, Unit{})

def go_ok(+bp: Nat, +l1: L.Le(1n, bp), +xs: +List<Nat>, +rps: +List<Nat>, +pr: Nat) -> G(bp, rps, List.reverse(&2, Nat, xs), pr) -> {T.fmul(bp, pr, T.finv(bp, pr)) == 1n : Nat} -> Inv(bp, List.reverse.go(&2, Nat, List.reverse(&2, Nat, xs), Nil{}), M.bi_go(bp, xs, rps)):
  match rps:
    case Nil{}:
      g => h => go_nil(bp, xs, pr, g)
    case Con{+top, +rest}:
      g => h => go_cons(bp, l1, xs, top, rest, pr, g, h)

def revgo(xs: +List<Nat>, +a: +List<Nat>, +b: +List<Nat>) -> {List.reverse.go(&2, Nat, List.reverse.go(&2, Nat, xs, a), b) == List.reverse.go(&2, Nat, a, List.append(&2, Nat, xs, b)) : +List<Nat>}:
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +t}:
      revgo(t, x <> a, b)

def app_nil(xs: +List<Nat>) -> {List.append(&2, Nat, xs, Nil{}) == xs : +List<Nat>}:
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +t}:
      Equal.cong(+List<Nat>, +List<Nat>, w => x <> w, List.append(&2, Nat, t, Nil{}), t, app_nil(t))

def revrev(+xs: +List<Nat>) -> {List.reverse.go(&2, Nat, List.reverse.go(&2, Nat, xs, Nil{}), Nil{}) == xs : +List<Nat>}:
  Equal.trans(+List<Nat>, List.reverse.go(&2, Nat, List.reverse.go(&2, Nat, xs, Nil{}), Nil{}), List.append(&2, Nat, xs, Nil{}), xs, revgo(xs, Nil{}, Nil{}), app_nil(xs))

# batch_inv returns the inverses whenever the one inversion it performs succeeds.
def bi_ring(+bp: Nat, +l1: L.Le(1n, bp), +xs: +List<Nat>, +hc: X.Canon(bp, xs), h: {T.fmul(bp, M.prod(bp, xs, 1n), T.finv(bp, M.prod(bp, xs, 1n))) == 1n : Nat}) -> Inv(bp, xs, M.batch_inv(bp, xs)):
  +g0 = {({==}, {==}) : G(bp, Nil{}, Nil{}, 1n)}
  +g = pre_ok(bp, xs, hc, Nil{}, Nil{}, 1n, l1, g0)
  +r = go_ok(bp, l1, xs, List.reverse(&2, Nat, M.bi_pre(bp, xs, 1n)), M.prod(bp, xs, 1n), g, h)
  %revrev(xs) : Inv(bp, _, M.batch_inv(bp, xs))
  r

# --- in a prime field: Fermat's little theorem gives the inversion ------------------------------

def NZs(xs: +List<Nat>) -> Data:
  match xs:
    case Nil{}:
      Unit
    case Con{+x, t}:
      Sigma<&2, &2, {Nat.is_eq(x, 0n) == False{} : Bool}, _ => NZs(t)>

def FInv(+bp: Nat, xs: +List<Nat>) -> Data:
  match xs:
    case Nil{}:
      Unit
    case Con{+x, t}:
      Sigma<&2, &2, {T.fmul(bp, x, T.finv(bp, x)) == 1n : Nat}, _ => FInv(bp, t)>

# Fermat's little theorem for p = 1 + bp, stated for a list of nonzero elements at once (a
# hypothesis can be used only once in Bend): every nonzero x has x * x^(p-2) == 1. It holds
# exactly when p is prime; that Pallas' and Vesta's p are prime is not proven here.
def Fermat(+bp: Nat) -> Type:
  @xs: +List<Nat> -> X.Canon(bp, xs) -> NZs(xs) -> FInv(bp, xs)

def pow_one(+k: Nat) -> {Nat.pow(1n, k) == 1n : Nat}:
  match k:
    case 0n:
      {==}
    case 1n+j:
      Equal.trans(Nat, Nat.mul(1n, Nat.pow(1n, j)), Nat.pow(1n, j), 1n, L.mul_one_l(Nat.pow(1n, j)), pow_one(j))

def finv_one(+bp: Nat, +l1: L.Le(1n, bp)) -> {T.finv(bp, 1n) == 1n : Nat}:
  Equal.trans(Nat, Nat.mod(Nat.pow(1n, Nat.sub(bp, 1n)), 1n+bp), Nat.mod(1n, 1n+bp), 1n, Equal.cong(Nat, Nat, w => Nat.mod(w, 1n+bp), Nat.pow(1n, Nat.sub(bp, 1n)), 1n, pow_one(Nat.sub(bp, 1n))), one_c(bp, l1))

def pow_mul(+a: Nat, +b: Nat, +k: Nat) -> {Nat.pow(Nat.mul(a, b), k) == Nat.mul(Nat.pow(a, k), Nat.pow(b, k)) : Nat}:
  match k:
    case 0n:
      {==}
    case 1n+j:
      %Equal.sym(Nat, Nat.pow(Nat.mul(a, b), j), Nat.mul(Nat.pow(a, j), Nat.pow(b, j)), pow_mul(a, b, j)) : {Nat.mul(Nat.mul(a, b), _) == Nat.mul(Nat.mul(a, Nat.pow(a, j)), Nat.mul(b, Nat.pow(b, j))) : Nat}
      P.mul4(a, b, Nat.pow(a, j), Nat.pow(b, j))

def pow_mod(+bp: Nat, +x: Nat, +k: Nat) -> {Nat.mod(Nat.pow(Nat.mod(x, 1n+bp), k), 1n+bp) == Nat.mod(Nat.pow(x, k), 1n+bp) : Nat}:
  match k:
    case 0n:
      {==}
    case 1n+j:
      R.mmul_cong(bp, Nat.mod(x, 1n+bp), x, Nat.pow(Nat.mod(x, 1n+bp), j), Nat.pow(x, j), L.mod_small(Nat.mod(x, 1n+bp), bp, L.mod_le(x, bp)), pow_mod(bp, x, j))

def finv_mul(+bp: Nat, +a: Nat, +b: Nat) -> {T.finv(bp, T.fmul(bp, a, b)) == T.fmul(bp, T.finv(bp, a), T.finv(bp, b)) : Nat}:
  +k = Nat.sub(bp, 1n)
  +m = {1n+bp : Nat}
  Equal.trans(Nat, Nat.mod(Nat.pow(Nat.mod(Nat.mul(a, b), m), k), m), Nat.mod(Nat.pow(Nat.mul(a, b), k), m), Nat.mod(Nat.mul(Nat.mod(Nat.pow(a, k), m), Nat.mod(Nat.pow(b, k), m)), m), pow_mod(bp, Nat.mul(a, b), k),
  Equal.trans(Nat, Nat.mod(Nat.pow(Nat.mul(a, b), k), m), Nat.mod(Nat.mul(Nat.pow(a, k), Nat.pow(b, k)), m), Nat.mod(Nat.mul(Nat.mod(Nat.pow(a, k), m), Nat.mod(Nat.pow(b, k), m)), m), Equal.cong(Nat, Nat, w => Nat.mod(w, m), Nat.pow(Nat.mul(a, b), k), Nat.mul(Nat.pow(a, k), Nat.pow(b, k)), pow_mul(a, b, k)),
  R.mmul_cong(bp, Nat.pow(a, k), Nat.mod(Nat.pow(a, k), m), Nat.pow(b, k), Nat.mod(Nat.pow(b, k), m), Equal.sym(Nat, Nat.mod(Nat.mod(Nat.pow(a, k), m), m), Nat.mod(Nat.pow(a, k), m), L.mod_small(Nat.mod(Nat.pow(a, k), m), bp, L.mod_le(Nat.pow(a, k), bp))), Equal.sym(Nat, Nat.mod(Nat.mod(Nat.pow(b, k), m), m), Nat.mod(Nat.pow(b, k), m), L.mod_small(Nat.mod(Nat.pow(b, k), m), bp, L.mod_le(Nat.pow(b, k), bp))))))

def finv_le(+bp: Nat, +x: Nat) -> L.Le(T.finv(bp, x), bp):
  L.mod_le(Nat.pow(x, Nat.sub(bp, 1n)), bp)

def fmul_le(+bp: Nat, +x: Nat, +y: Nat) -> L.Le(T.fmul(bp, x, y), bp):
  L.mod_le(Nat.mul(x, y), bp)

# the product of elements with Fermat inverses is inverted by x^(p-2)
def prod_inv(+bp: Nat, +l1: L.Le(1n, bp), +xs: +List<Nat>, +hc: X.Canon(bp, xs), +fi: FInv(bp, xs), +acc: Nat, +lacc: L.Le(acc, bp)) -> {T.fmul(bp, M.prod(bp, xs, acc), T.finv(bp, M.prod(bp, xs, acc))) == T.fmul(bp, acc, T.finv(bp, acc)) : Nat}:
  match xs:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      (+lh, +lt) = hc
      (+eh, +ft) = fi
      +a2 = T.fmul(bp, acc, h)
      +ia = T.finv(bp, acc)
      +ih = T.finv(bp, h)
      +hc4 = {(lacc, (lh, (finv_le(bp, acc), (finv_le(bp, h), Unit{})))) : X.Canon(bp, [acc, h, ia, ih])}
      +c4 = R.cert_ok2(bp, [acc, h, ia, ih], hc4, K.r4_t1(), K.r4_t2(), K.r4_cs(), K.r4_rs(), K.r4_k1(), K.r4_k2(), Unit{}, K.r4_lt(), K.r4_rt(), K.r4_el(), K.r4_er(), K.r4_h())
      Equal.trans(Nat, T.fmul(bp, M.prod(bp, t, a2), T.finv(bp, M.prod(bp, t, a2))), T.fmul(bp, a2, T.finv(bp, a2)), T.fmul(bp, acc, ia), prod_inv(bp, l1, t, lt, ft, a2, fmul_le(bp, acc, h)),
      Equal.trans(Nat, T.fmul(bp, a2, T.finv(bp, a2)), T.fmul(bp, a2, T.fmul(bp, ia, ih)), T.fmul(bp, acc, ia), Equal.cong(Nat, Nat, w => T.fmul(bp, a2, w), T.finv(bp, a2), T.fmul(bp, ia, ih), finv_mul(bp, acc, h)),
      Equal.trans(Nat, T.fmul(bp, a2, T.fmul(bp, ia, ih)), T.fmul(bp, T.fmul(bp, acc, ia), T.fmul(bp, h, ih)), T.fmul(bp, acc, ia), c4,
      Equal.trans(Nat, T.fmul(bp, T.fmul(bp, acc, ia), T.fmul(bp, h, ih)), T.fmul(bp, T.fmul(bp, acc, ia), 1n), T.fmul(bp, acc, ia), Equal.cong(Nat, Nat, w => T.fmul(bp, T.fmul(bp, acc, ia), w), T.fmul(bp, h, ih), 1n, eh), S.fmul_one_r(bp, T.fmul(bp, acc, ia), fmul_le(bp, acc, ia))))))

# inverses are unique: x y == 1 and x f == 1 give y == f
def uniq(+bp: Nat, +l1: L.Le(1n, bp), +x: Nat, +y: Nat, +f: Nat, +lx: L.Le(x, bp), +ly: L.Le(y, bp), +lf: L.Le(f, bp), h1: {T.fmul(bp, x, y) == 1n : Nat}, h2: {T.fmul(bp, x, f) == 1n : Nat}) -> {y == f : Nat}:
  +hc = {(lx, (ly, (lf, Unit{}))) : X.Canon(bp, [x, y, f])}
  +m1 = Equal.sym(Nat, Nat.mod(1n, 1n+bp), 1n, one_c(bp, l1))
  +hr = {(Equal.trans(Nat, T.fmul(bp, x, y), 1n, Nat.mod(1n, 1n+bp), h1, m1), (Equal.trans(Nat, T.fmul(bp, x, f), 1n, Nat.mod(1n, 1n+bp), h2, m1), Unit{})) : R.Holds(bp, [x, y, f], K.r5_rs())}
  R.cert_ok2(bp, [x, y, f], hc, K.r5_t1(), K.r5_t2(), K.r5_cs(), K.r5_rs(), K.r5_k1(), K.r5_k2(), hr, K.r5_lt(), K.r5_rt(), K.r5_el(), K.r5_er(), K.r5_h())

def cons_eq(+x: Nat, +xs: +List<Nat>, +y: Nat, +ys: +List<Nat>, hx: {x == y : Nat}, hxs: {xs == ys : +List<Nat>}) -> {x <> xs == y <> ys : +List<Nat>}:
  %hx : {x <> xs == _ <> ys : +List<Nat>}
  %hxs : {x <> xs == x <> _ : +List<Nat>}
  {==}

def inv_finvs(+bp: Nat, +l1: L.Le(1n, bp), +xs: +List<Nat>, +ys: +List<Nat>, +hc: X.Canon(bp, xs), +hi: Inv(bp, xs, ys), +fi: FInv(bp, xs)) -> {ys == M.finvs(bp, xs) : +List<Nat>}:
  match xs ys:
    case Nil{} Nil{}:
      {==}
    case Con{+x, +xr} Con{+y, +yr}:
      (+lx, +lr) = hc
      (+ly, rest) = hi
      (+exy, +ir) = rest
      (+efx, +fr) = fi
      cons_eq(y, yr, T.finv(bp, x), M.finvs(bp, xr), uniq(bp, l1, x, y, T.finv(bp, x), lx, ly, finv_le(bp, x), exy, efx), inv_finvs(bp, l1, xr, yr, lr, ir, fr))
    case Nil{} Con{+y, +yr}:
      Empty.absurd({y <> yr == M.finvs(bp, Nil{}) : +List<Nat>}, hi)
    case Con{+x, +xr} Nil{}:
      Empty.absurd({Nil{} == M.finvs(bp, x <> xr) : +List<Nat>}, hi)

def bi_top(+bp: Nat, +l1: L.Le(1n, bp), +xs: +List<Nat>, +hc: X.Canon(bp, xs), +fi: FInv(bp, xs)) -> {T.fmul(bp, M.prod(bp, xs, 1n), T.finv(bp, M.prod(bp, xs, 1n))) == 1n : Nat}:
  Equal.trans(Nat, T.fmul(bp, M.prod(bp, xs, 1n), T.finv(bp, M.prod(bp, xs, 1n))), T.fmul(bp, 1n, T.finv(bp, 1n)), 1n, prod_inv(bp, l1, xs, hc, fi, 1n, l1),
  Equal.trans(Nat, T.fmul(bp, 1n, T.finv(bp, 1n)), T.fmul(bp, 1n, 1n), 1n, Equal.cong(Nat, Nat, w => T.fmul(bp, 1n, w), T.finv(bp, 1n), 1n, finv_one(bp, l1)), one_c(bp, l1)))

# in a prime field, batch_inv of nonzero elements is x |-> x^(p-2), pointwise
def bi_field(+bp: Nat, +l1: L.Le(1n, bp), +xs: +List<Nat>, +hc: X.Canon(bp, xs), +hnz: NZs(xs), f: Fermat(bp)) -> {M.batch_inv(bp, xs) == M.finvs(bp, xs) : +List<Nat>}:
  +fi = f(xs, hc, hnz)
  inv_finvs(bp, l1, xs, M.batch_inv(bp, xs), hc, bi_ring(bp, l1, xs, hc, bi_top(bp, l1, xs, hc, fi)), fi)

# --- vlib.binvs: zeros masked ------------------------------------------------------------------

def nz1_canon(+bp: Nat, +l1: L.Le(1n, bp), +xs: +List<Nat>, +hc: X.Canon(bp, xs)) -> X.Canon(bp, M.nz1(xs)):
  match xs:
    case Nil{}:
      Unit{}
    case Con{+x, +t}:
      match x:
        case 0n:
          (+lx, +lt) = hc
          (l1, nz1_canon(bp, l1, t, lt))
        case 1n+k:
          (+lx, +lt) = hc
          (lx, nz1_canon(bp, l1, t, lt))

def nz1_nz(+xs: +List<Nat>) -> NZs(M.nz1(xs)):
  match xs:
    case Nil{}:
      Unit{}
    case Con{+x, +t}:
      match x:
        case 0n:
          ({==}, nz1_nz(t))
        case 1n+k:
          ({==}, nz1_nz(t))

# 0^(p-2) == 0 when p >= 3
def finv_zero(+bp: Nat, +l2: L.Le(2n, bp)) -> {T.finv(bp, 0n) == 0n : Nat}:
  (+e, +he) = l2
  %he : {T.finv(_, 0n) == 0n : Nat}
  X.mod_zero(2n+e)

def z0_ok(+bp: Nat, +l2: L.Le(2n, bp), +xs: +List<Nat>) -> {M.z0(xs, M.finvs(bp, M.nz1(xs))) == M.finvs(bp, xs) : +List<Nat>}:
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +t}:
      match x:
        case 0n:
          cons_eq(0n, M.z0(t, M.finvs(bp, M.nz1(t))), T.finv(bp, 0n), M.finvs(bp, t), Equal.sym(Nat, T.finv(bp, 0n), 0n, finv_zero(bp, l2)), z0_ok(bp, l2, t))
        case 1n+k:
          Equal.cong(+List<Nat>, +List<Nat>, w => T.finv(bp, 1n+k) <> w, M.z0(t, M.finvs(bp, M.nz1(t))), M.finvs(bp, t), z0_ok(bp, l2, t))

def le1(+bp: Nat, +l2: L.Le(2n, bp)) -> L.Le(1n, bp):
  (+e, +he) = l2
  (1n+e, he)

# binvs(xs) == [x^(p-2) for x in xs]: the reading opt_gates trusts (0 maps to 0)
def binvs_ok(+bp: Nat, +l2: L.Le(2n, bp), +xs: +List<Nat>, +hc: X.Canon(bp, xs), f: Fermat(bp)) -> {M.binvs(bp, xs) == M.finvs(bp, xs) : +List<Nat>}:
  +l1 = le1(bp, l2)
  %Equal.sym(+List<Nat>, M.batch_inv(bp, M.nz1(xs)), M.finvs(bp, M.nz1(xs)), bi_field(bp, l1, M.nz1(xs), nz1_canon(bp, l1, xs, hc), nz1_nz(xs), f)) : {M.z0(xs, _) == M.finvs(bp, xs) : +List<Nat>}
  z0_ok(bp, l2, xs)

# --- msm_ba.batch_inv is fp64.batch_inv -----------------------------------------------------------

def prefix_eq(+bp: Nat, +xs: +List<Nat>, +acc: Nat, +out: +List<Nat>) -> {M.prefix(bp, xs, acc, out) == List.reverse.go(&2, Nat, M.bi_pre(bp, xs, acc), out) : +List<Nat>}:
  match xs:
    case Nil{}:
      {==}
    case Con{+x, +t}:
      prefix_eq(bp, t, T.fmul(bp, acc, x), T.fmul(bp, acc, x) <> out)

def back_eq(+bp: Nat, +rx: +List<Nat>, +h: Nat, +rest: +List<Nat>, +inv: Nat, +out: +List<Nat>) -> {M.back(bp, rx, h <> rest, inv, out) == M.bi_back(bp, rx, rest, inv, out) : +List<Nat>}:
  match rx:
    case Nil{}:
      {==}
    case Con{+x, +xt}:
      match rest:
        case Nil{}:
          {==}
        case Con{+cp, +ct}:
          back_eq(bp, xt, cp, ct, T.fmul(bp, inv, x), T.fmul(bp, inv, cp) <> out)

def back_nil(+bp: Nat, +rx: +List<Nat>, +inv: Nat) -> {M.back(bp, rx, Nil{}, inv, Nil{}) == Nil{} : +List<Nat>}:
  match rx:
    case Nil{}:
      {==}
    case Con{+x, +xt}:
      {==}

def ba_go(+bp: Nat, +xs: +List<Nat>, +rps: +List<Nat>) -> {M.back(bp, List.reverse(&2, Nat, xs), rps, T.finv(bp, M.top_or_one(rps)), Nil{}) == M.bi_go(bp, xs, rps) : +List<Nat>}:
  match rps:
    case Nil{}:
      back_nil(bp, List.reverse(&2, Nat, xs), T.finv(bp, 1n))
    case Con{+top, +rest}:
      back_eq(bp, List.reverse(&2, Nat, xs), top, rest, T.finv(bp, top), Nil{})

def ba_eq(+bp: Nat, +xs: +List<Nat>) -> {M.ba_batch_inv(bp, xs) == M.batch_inv(bp, xs) : +List<Nat>}:
  %Equal.sym(+List<Nat>, M.prefix(bp, xs, 1n, Nil{}), List.reverse(&2, Nat, M.bi_pre(bp, xs, 1n)), prefix_eq(bp, xs, 1n, Nil{})) : {M.back(bp, List.reverse(&2, Nat, xs), _, T.finv(bp, M.top_or_one(_)), Nil{}) == M.batch_inv(bp, xs) : +List<Nat>}
  ba_go(bp, xs, List.reverse(&2, Nat, M.bi_pre(bp, xs, 1n)))

# --- a zero input: every output is zero ---------------------------------------------------------

def Has0(xs: +List<Nat>) -> Data:
  match xs:
    case Nil{}:
      Empty
    case Con{+x, t}:
      Either<&2, &2, {x == 0n : Nat}, Has0(t)>

# ys has the length of xs and is all zeros
def Zs(xs: +List<Nat>, ys: +List<Nat>) -> Data:
  match xs ys:
    case Nil{} Nil{}:
      Unit
    case Con{_, xr} Con{+y, yr}:
      Sigma<&2, &2, {y == 0n : Nat}, _ => Zs(xr, yr)>
    case _ _:
      Empty

def fmul_z(+bp: Nat, +y: Nat) -> {T.fmul(bp, 0n, y) == 0n : Nat}:
  X.mod_zero(bp)

def prod0(+bp: Nat, +xs: +List<Nat>) -> {M.prod(bp, xs, 0n) == 0n : Nat}:
  match xs:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      %Equal.sym(Nat, T.fmul(bp, 0n, h), 0n, fmul_z(bp, h)) : {M.prod(bp, t, _) == 0n : Nat}
      prod0(bp, t)

def prod_zero(+bp: Nat, +xs: +List<Nat>, +acc: Nat, +hz: Has0(xs)) -> {M.prod(bp, xs, acc) == 0n : Nat}:
  match xs:
    case Nil{}:
      Empty.absurd({M.prod(bp, Nil{}, acc) == 0n : Nat}, hz)
    case Con{+h, +t}:
      match hz:
        case Inl{+eh}:
          %Equal.sym(Nat, h, 0n, eh) : {M.prod(bp, t, T.fmul(bp, acc, _)) == 0n : Nat}
          %Equal.sym(Nat, T.fmul(bp, acc, 0n), 0n, S.fmul_zero_r(bp, acc)) : {M.prod(bp, t, _) == 0n : Nat}
          prod0(bp, t)
        case Inr{+ht}:
          prod_zero(bp, t, T.fmul(bp, acc, h), ht)

def back0_step(+bp: Nat, +x: Nat, +rx2: +List<Nat>, +a2: Nat, +rp2: +List<Nat>, +a: Nat, +done: +List<Nat>, +out: +List<Nat>, rr: Rr(bp, a2 <> rp2, x <> rx2, a), hz: Zs(done, out), ih: Rr(bp, rp2, rx2, a2) -> Zs(x <> done, 0n <> out) -> Zs(List.reverse.go(&2, Nat, rx2, x <> done), M.bi_back(bp, rx2, rp2, 0n, 0n <> out))) -> Zs(List.reverse.go(&2, Nat, rx2, x <> done), M.bi_back(bp, rx2, rp2, T.fmul(bp, 0n, x), T.fmul(bp, 0n, a2) <> out)):
  (_, rest) = rr
  (_, rest2) = rest
  (_, rr2) = rest2
  %Equal.sym(Nat, T.fmul(bp, 0n, x), 0n, fmul_z(bp, x)) : Zs(List.reverse.go(&2, Nat, rx2, x <> done), M.bi_back(bp, rx2, rp2, _, T.fmul(bp, 0n, a2) <> out))
  %Equal.sym(Nat, T.fmul(bp, 0n, a2), 0n, fmul_z(bp, a2)) : Zs(List.reverse.go(&2, Nat, rx2, x <> done), M.bi_back(bp, rx2, rp2, 0n, _ <> out))
  ih(rr2, ({==}, hz))

def back0(+bp: Nat, +rp: +List<Nat>, +rx: +List<Nat>, +a: Nat, +done: +List<Nat>, +out: +List<Nat>) -> Rr(bp, rp, rx, a) -> Zs(done, out) -> Zs(List.reverse.go(&2, Nat, rx, done), M.bi_back(bp, rx, rp, 0n, out)):
  match rp:
    case Nil{}:
      match rx:
        case Con{+x, +rx2}:
          match rx2:
            case Nil{}:
              rr => hz => ({==}, hz)
            case Con{+y, +ys}:
              rr => hz => Empty.absurd(Zs(List.reverse.go(&2, Nat, x <> (y <> ys), done), M.bi_back(bp, x <> (y <> ys), Nil{}, 0n, out)), rr)
        case Nil{}:
          rr => hz => Empty.absurd(Zs(List.reverse.go(&2, Nat, Nil{}, done), M.bi_back(bp, Nil{}, Nil{}, 0n, out)), rr)
    case Con{+a2, +rp2}:
      match rx:
        case Con{+x, +rx2}:
          rr => hz => back0_step(bp, x, rx2, a2, rp2, a, done, out, rr, hz, back0(bp, rp2, rx2, a2, x <> done, 0n <> out))
        case Nil{}:
          rr => hz => Empty.absurd(Zs(List.reverse.go(&2, Nat, Nil{}, done), M.bi_back(bp, Nil{}, a2 <> rp2, 0n, out)), rr)

def gz_nil(+bp: Nat, +xs: +List<Nat>, +pr: Nat, g: G(bp, Nil{}, List.reverse(&2, Nat, xs), pr)) -> Zs(List.reverse.go(&2, Nat, List.reverse(&2, Nat, xs), Nil{}), M.bi_go(bp, xs, Nil{})):
  (erx, _) = g
  %Equal.sym(+List<Nat>, List.reverse(&2, Nat, xs), Nil{}, erx) : Zs(List.reverse.go(&2, Nat, _, Nil{}), M.bi_go(bp, xs, Nil{}))
  Unit{}

def gz_cons(+bp: Nat, +l2: L.Le(2n, bp), +xs: +List<Nat>, +top: Nat, +rest: +List<Nat>, +pr: Nat, g: G(bp, top <> rest, List.reverse(&2, Nat, xs), pr), hp: {pr == 0n : Nat}) -> Zs(List.reverse.go(&2, Nat, List.reverse(&2, Nat, xs), Nil{}), M.bi_go(bp, xs, top <> rest)):
  (+et, rr) = g
  +t0 = Equal.trans(Nat, T.finv(bp, top), T.finv(bp, 0n), 0n, Equal.cong(Nat, Nat, w => T.finv(bp, w), top, 0n, Equal.trans(Nat, top, pr, 0n, et, hp)), finv_zero(bp, l2))
  %Equal.sym(Nat, T.finv(bp, top), 0n, t0) : Zs(List.reverse.go(&2, Nat, List.reverse(&2, Nat, xs), Nil{}), M.bi_back(bp, List.reverse(&2, Nat, xs), rest, _, Nil{}))
  back0(bp, rest, List.reverse(&2, Nat, xs), top, Nil{}, Nil{}, rr, Unit{})

def go_zero(+bp: Nat, +l2: L.Le(2n, bp), +xs: +List<Nat>, +rps: +List<Nat>, +pr: Nat) -> G(bp, rps, List.reverse(&2, Nat, xs), pr) -> {pr == 0n : Nat} -> Zs(List.reverse.go(&2, Nat, List.reverse(&2, Nat, xs), Nil{}), M.bi_go(bp, xs, rps)):
  match rps:
    case Nil{}:
      g => h => gz_nil(bp, xs, pr, g)
    case Con{+top, +rest}:
      g => h => gz_cons(bp, l2, xs, top, rest, pr, g, h)

# a zero input makes the product zero, the inversion returns 0, and every output is 0
def bi_zero(+bp: Nat, +l2: L.Le(2n, bp), +xs: +List<Nat>, +hc: X.Canon(bp, xs), +hz: Has0(xs)) -> Zs(xs, M.batch_inv(bp, xs)):
  +l1 = le1(bp, l2)
  +g0 = {({==}, {==}) : G(bp, Nil{}, Nil{}, 1n)}
  +g = pre_ok(bp, xs, hc, Nil{}, Nil{}, 1n, l1, g0)
  +r = go_zero(bp, l2, xs, List.reverse(&2, Nat, M.bi_pre(bp, xs, 1n)), M.prod(bp, xs, 1n), g, prod_zero(bp, xs, 1n, hz))
  %revrev(xs) : Zs(_, M.batch_inv(bp, xs))
  r
