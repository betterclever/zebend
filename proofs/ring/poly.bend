import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L
import ../opt_gates/term.bend as T
import ./expr.bend as X

# A normaliser for Nat polynomials, proven sound: nf_ok says nv(t) == evp(nf(t)) for every
# expression t, every bp and every env. It is a semiring normaliser (Nat coefficients, no
# cancellation), so its soundness needs only the Nat laws of natlemmas/natlib; Z/p enters
# through expr.bend's ev_nv and cert.bend.
#
# A monomial is a list of exponents [e0, e1, ...] over the variables [bp, env0, env1, ...];
# a polynomial is a list of terms Tm{c, m} = c * monomial. nf keeps polynomials sorted by
# the lexicographic order on monomials (mcmp) and merges equal monomials, so equal
# polynomials get equal normal forms; soundness does not depend on that.

# Coefficients are binary (Bn), so that the checker never builds a large unary Nat.
type Bn is Data:
  BE{}
  B0{h: Bn}
  B1{h: Bn}

def bv(b: Bn) -> Nat:
  match b:
    case BE{}:
      0n
    case B0{h}:
      +v = bv(h)
      Nat.add(v, v)
    case B1{h}:
      +v = bv(h)
      1n+Nat.add(v, v)

def binc(b: Bn) -> Bn:
  match b:
    case BE{}:
      B1{BE{}}
    case B0{h}:
      B1{h}
    case B1{h}:
      B0{binc(h)}

def badd(a: Bn, b: Bn) -> Bn:
  match a:
    case BE{}:
      b
    case B0{x}:
      match b:
        case BE{}:
          B0{x}
        case B0{y}:
          B0{badd(x, y)}
        case B1{y}:
          B1{badd(x, y)}
    case B1{x}:
      match b:
        case BE{}:
          B1{x}
        case B0{y}:
          B1{badd(x, y)}
        case B1{y}:
          B0{binc(badd(x, y))}

def b0s(b: Bn) -> Bn:
  match b:
    case BE{}:
      BE{}
    case B0{h}:
      B0{B0{h}}
    case B1{h}:
      B0{B1{h}}

def bmul(a: Bn, +b: Bn) -> Bn:
  match a:
    case BE{}:
      BE{}
    case B0{x}:
      b0s(bmul(x, b))
    case B1{x}:
      badd(b, b0s(bmul(x, b)))

def tobin(n: Nat) -> Bn:
  match n:
    case 0n:
      BE{}
    case 1n+k:
      binc(tobin(k))

type Tm is Data:
  Tm{c: Bn, m: +List<Nat>}

def hd(xs: +List<Nat>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{h, t}:
      h

def tl(xs: +List<Nat>) -> +List<Nat>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      t

def evm(m: +List<Nat>, +vals: +List<Nat>) -> Nat:
  match m:
    case Nil{}:
      1n
    case Con{e, es}:
      Nat.mul(Nat.pow(hd(vals), e), evm(es, tl(vals)))

def evt(t: Tm, +vals: +List<Nat>) -> Nat:
  Tm{c, m} = t
  Nat.mul(bv(c), evm(m, vals))

def evp(ps: +List<Tm>, +vals: +List<Nat>) -> Nat:
  match ps:
    case Nil{}:
      0n
    case Con{t, r}:
      Nat.add(evt(t, vals), evp(r, vals))

# --- monomials -------------------------------------------------------------------------

def mm(a: +List<Nat>, b: +List<Nat>) -> +List<Nat>:
  match a b:
    case Nil{} _:
      b
    case Con{x, xs} Nil{}:
      x <> xs
    case Con{x, xs} Con{y, ys}:
      Nat.add(x, y) <> mm(xs, ys)

def ncmp(a: Nat, b: Nat) -> Cmp:
  match a b:
    case 0n 0n:
      EQ{}
    case 0n 1n+y:
      LT{}
    case 1n+x 0n:
      GT{}
    case 1n+x 1n+y:
      ncmp(x, y)

def lexc(c: Cmp, d: Cmp) -> Cmp:
  match c:
    case EQ{}:
      d
    case LT{}:
      LT{}
    case GT{}:
      GT{}

def mcmp(a: +List<Nat>, b: +List<Nat>) -> Cmp:
  match a b:
    case Nil{} Nil{}:
      EQ{}
    case Nil{} Con{y, ys}:
      LT{}
    case Con{x, xs} Nil{}:
      GT{}
    case Con{x, xs} Con{y, ys}:
      lexc(ncmp(x, y), mcmp(xs, ys))

def var(i: Nat) -> +List<Nat>:
  match i:
    case 0n:
      [1n]
    case 1n+k:
      0n <> var(k)

# --- polynomials -----------------------------------------------------------------------

def tc(t: Tm) -> Bn:
  Tm{c, _} = t
  c

def tm(t: Tm) -> +List<Nat>:
  Tm{_, m} = t
  m

# The state of a merge: Go merges two lists; Lt / Eq / Gt emit one term after comparing
# the heads (Eq: equal monomials, coefficients added). Every list is used once, so the
# checker's evaluator never copies or re-normalises a long list.
type St is Data:
  Go{p: +List<Tm>, q: +List<Tm>}
  Lt{a: Tm, pr: +List<Tm>, q: +List<Tm>}
  Eq{a: Tm, b: Tm, pr: +List<Tm>, qr: +List<Tm>}
  Gt{b: Tm, p: +List<Tm>, qr: +List<Tm>}

def mk(c: Cmp, +a: Tm, pr: +List<Tm>, +b: Tm, qr: +List<Tm>) -> St:
  match c:
    case LT{}:
      Lt{a, pr, b <> qr}
    case EQ{}:
      Eq{a, b, pr, qr}
    case GT{}:
      Gt{b, a <> pr, qr}

def sum2(a: Tm, b: Tm) -> Tm:
  Tm{+c1, +m1} = a
  Tm{c2, _} = b
  Tm{badd(c1, c2), m1}

# what is left when the fuel runs out (never, with plus's fuel): append, still sound
def stl(st: St) -> +List<Tm>:
  match st:
    case Go{p, q}:
      List.append(&2, Tm, p, q)
    case Lt{a, pr, q}:
      a <> List.append(&2, Tm, pr, q)
    case Eq{a, b, pr, qr}:
      sum2(a, b) <> List.append(&2, Tm, pr, qr)
    case Gt{b, p, qr}:
      b <> List.append(&2, Tm, p, qr)

# Merge two sorted polynomials. Fuel 2 (length p + length q) + 1 suffices.
def padd(fuel: Nat, st: St) -> +List<Tm>:
  match fuel:
    case 0n:
      stl(st)
    case 1n+f:
      match st:
        case Go{p, q}:
          match p:
            case Nil{}:
              q
            case Con{+a, pr}:
              match q:
                case Nil{}:
                  a <> pr
                case Con{+b, qr}:
                  padd(f, mk(mcmp(tm(a), tm(b)), a, pr, b, qr))
        case Lt{a, pr, q}:
          a <> padd(f, Go{pr, q})
        case Eq{a, b, pr, qr}:
          sum2(a, b) <> padd(f, Go{pr, qr})
        case Gt{b, p, qr}:
          b <> padd(f, Go{p, qr})

def plus(+p: +List<Tm>, +q: +List<Tm>) -> +List<Tm>:
  +n = Nat.add(List.length(&2, Tm, p), List.length(&2, Tm, q))
  padd(1n+Nat.add(n, n), Go{p, q})

def smul(+c: Bn, +m: +List<Nat>, q: +List<Tm>) -> +List<Tm>:
  match q:
    case Nil{}:
      Nil{}
    case Con{Tm{c2, m2}, r}:
      Tm{bmul(c, c2), mm(m, m2)} <> smul(c, m, r)

def pmul(p: +List<Tm>, +q: +List<Tm>) -> +List<Tm>:
  match p:
    case Nil{}:
      Nil{}
    case Con{Tm{+c, +m}, r}:
      plus(smul(c, m, q), pmul(r, q))

def pvar(+i: Nat) -> +List<Tm>:
  [Tm{B1{BE{}}, var(i)}]

def pconst(n: Nat) -> +List<Tm>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      [Tm{tobin(1n+k), Nil{}}]

def nf(t: X.E) -> +List<Tm>:
  match t:
    case X.V{i}:
      pvar(1n+i)
    case X.C{n}:
      pconst(n)
    case X.Pp{}:
      pvar(0n)
    case X.Ad{a, b}:
      plus(nf(a), nf(b))
    case X.Sb{a, b}:
      plus(nf(a), pmul(pvar(0n), nf(b)))
    case X.Ml{a, b}:
      pmul(nf(a), nf(b))
    case X.Ng{a}:
      pmul(pvar(0n), nf(a))

# --- soundness -------------------------------------------------------------------------

def bv_binc(+b: Bn) -> {bv(binc(b)) == 1n+bv(b) : Nat}:
  match b:
    case BE{}:
      {==}
    case B0{+h}:
      {==}
    case B1{+h}:
      %Equal.sym(Nat, bv(binc(h)), 1n+bv(h), bv_binc(h)) : {Nat.add(_, _) == 1n+(1n+Nat.add(bv(h), bv(h))) : Nat}
      Equal.cong(Nat, Nat, w => 1n+w, Nat.add(bv(h), 1n+bv(h)), 1n+Nat.add(bv(h), bv(h)), N.add_succ_r(bv(h), bv(h)))

def bv_badd(+a: Bn, +b: Bn) -> {bv(badd(a, b)) == Nat.add(bv(a), bv(b)) : Nat}:
  match a:
    case BE{}:
      {==}
    case B0{+x}:
      match b:
        case BE{}:
          Equal.sym(Nat, Nat.add(bv(B0{x}), 0n), bv(B0{x}), N.add_zero_r(bv(B0{x})))
        case B0{+y}:
          %Equal.sym(Nat, bv(badd(x, y)), Nat.add(bv(x), bv(y)), bv_badd(x, y)) : {Nat.add(_, _) == Nat.add(Nat.add(bv(x), bv(x)), Nat.add(bv(y), bv(y))) : Nat}
          N.swap_mid(bv(x), bv(y), bv(x), bv(y))
        case B1{+y}:
          %Equal.sym(Nat, bv(badd(x, y)), Nat.add(bv(x), bv(y)), bv_badd(x, y)) : {1n+Nat.add(_, _) == Nat.add(Nat.add(bv(x), bv(x)), 1n+Nat.add(bv(y), bv(y))) : Nat}
          %Equal.sym(Nat, Nat.add(Nat.add(bv(x), bv(x)), 1n+Nat.add(bv(y), bv(y))), 1n+Nat.add(Nat.add(bv(x), bv(x)), Nat.add(bv(y), bv(y))), N.add_succ_r(Nat.add(bv(x), bv(x)), Nat.add(bv(y), bv(y)))) : {1n+Nat.add(Nat.add(bv(x), bv(y)), Nat.add(bv(x), bv(y))) == _ : Nat}
          Equal.cong(Nat, Nat, w => 1n+w, Nat.add(Nat.add(bv(x), bv(y)), Nat.add(bv(x), bv(y))), Nat.add(Nat.add(bv(x), bv(x)), Nat.add(bv(y), bv(y))), N.swap_mid(bv(x), bv(y), bv(x), bv(y)))
    case B1{+x}:
      match b:
        case BE{}:
          Equal.sym(Nat, Nat.add(bv(B1{x}), 0n), bv(B1{x}), N.add_zero_r(bv(B1{x})))
        case B0{+y}:
          %Equal.sym(Nat, bv(badd(x, y)), Nat.add(bv(x), bv(y)), bv_badd(x, y)) : {1n+Nat.add(_, _) == 1n+Nat.add(Nat.add(bv(x), bv(x)), Nat.add(bv(y), bv(y))) : Nat}
          Equal.cong(Nat, Nat, w => 1n+w, Nat.add(Nat.add(bv(x), bv(y)), Nat.add(bv(x), bv(y))), Nat.add(Nat.add(bv(x), bv(x)), Nat.add(bv(y), bv(y))), N.swap_mid(bv(x), bv(y), bv(x), bv(y)))
        case B1{+y}:
          %Equal.sym(Nat, bv(binc(badd(x, y))), 1n+bv(badd(x, y)), bv_binc(badd(x, y))) : {Nat.add(_, _) == 1n+Nat.add(Nat.add(bv(x), bv(x)), 1n+Nat.add(bv(y), bv(y))) : Nat}
          %Equal.sym(Nat, bv(badd(x, y)), Nat.add(bv(x), bv(y)), bv_badd(x, y)) : {1n+Nat.add(_, 1n+_) == 1n+Nat.add(Nat.add(bv(x), bv(x)), 1n+Nat.add(bv(y), bv(y))) : Nat}
          %Equal.sym(Nat, Nat.add(Nat.add(bv(x), bv(y)), 1n+Nat.add(bv(x), bv(y))), 1n+Nat.add(Nat.add(bv(x), bv(y)), Nat.add(bv(x), bv(y))), N.add_succ_r(Nat.add(bv(x), bv(y)), Nat.add(bv(x), bv(y)))) : {1n+_ == 1n+Nat.add(Nat.add(bv(x), bv(x)), 1n+Nat.add(bv(y), bv(y))) : Nat}
          %Equal.sym(Nat, Nat.add(Nat.add(bv(x), bv(x)), 1n+Nat.add(bv(y), bv(y))), 1n+Nat.add(Nat.add(bv(x), bv(x)), Nat.add(bv(y), bv(y))), N.add_succ_r(Nat.add(bv(x), bv(x)), Nat.add(bv(y), bv(y)))) : {2n+Nat.add(Nat.add(bv(x), bv(y)), Nat.add(bv(x), bv(y))) == 1n+_ : Nat}
          Equal.cong(Nat, Nat, w => 2n+w, Nat.add(Nat.add(bv(x), bv(y)), Nat.add(bv(x), bv(y))), Nat.add(Nat.add(bv(x), bv(x)), Nat.add(bv(y), bv(y))), N.swap_mid(bv(x), bv(y), bv(x), bv(y)))

def bv_b0s(+b: Bn) -> {bv(b0s(b)) == Nat.add(bv(b), bv(b)) : Nat}:
  match b:
    case BE{}:
      {==}
    case B0{+h}:
      {==}
    case B1{+h}:
      {==}

def bv_bmul(+a: Bn, +b: Bn) -> {bv(bmul(a, b)) == Nat.mul(bv(a), bv(b)) : Nat}:
  match a:
    case BE{}:
      {==}
    case B0{+x}:
      %Equal.sym(Nat, bv(b0s(bmul(x, b))), Nat.add(bv(bmul(x, b)), bv(bmul(x, b))), bv_b0s(bmul(x, b))) : {_ == Nat.mul(Nat.add(bv(x), bv(x)), bv(b)) : Nat}
      %Equal.sym(Nat, bv(bmul(x, b)), Nat.mul(bv(x), bv(b)), bv_bmul(x, b)) : {Nat.add(_, _) == Nat.mul(Nat.add(bv(x), bv(x)), bv(b)) : Nat}
      Equal.sym(Nat, Nat.mul(Nat.add(bv(x), bv(x)), bv(b)), Nat.add(Nat.mul(bv(x), bv(b)), Nat.mul(bv(x), bv(b))), L.mul_add_r(bv(x), bv(x), bv(b)))
    case B1{+x}:
      %Equal.sym(Nat, bv(badd(b, b0s(bmul(x, b)))), Nat.add(bv(b), bv(b0s(bmul(x, b)))), bv_badd(b, b0s(bmul(x, b)))) : {_ == Nat.mul(1n+Nat.add(bv(x), bv(x)), bv(b)) : Nat}
      %Equal.sym(Nat, bv(b0s(bmul(x, b))), Nat.add(bv(bmul(x, b)), bv(bmul(x, b))), bv_b0s(bmul(x, b))) : {Nat.add(bv(b), _) == Nat.mul(1n+Nat.add(bv(x), bv(x)), bv(b)) : Nat}
      %Equal.sym(Nat, bv(bmul(x, b)), Nat.mul(bv(x), bv(b)), bv_bmul(x, b)) : {Nat.add(bv(b), Nat.add(_, _)) == Nat.mul(1n+Nat.add(bv(x), bv(x)), bv(b)) : Nat}
      Equal.cong(Nat, Nat, w => Nat.add(bv(b), w), Nat.add(Nat.mul(bv(x), bv(b)), Nat.mul(bv(x), bv(b))), Nat.mul(Nat.add(bv(x), bv(x)), bv(b)), Equal.sym(Nat, Nat.mul(Nat.add(bv(x), bv(x)), bv(b)), Nat.add(Nat.mul(bv(x), bv(b)), Nat.mul(bv(x), bv(b))), L.mul_add_r(bv(x), bv(x), bv(b))))

def bv_tobin(+n: Nat) -> {bv(tobin(n)) == n : Nat}:
  match n:
    case 0n:
      {==}
    case 1n+k:
      Equal.trans(Nat, bv(binc(tobin(k))), 1n+bv(tobin(k)), 1n+k, bv_binc(tobin(k)), Equal.cong(Nat, Nat, w => 1n+w, bv(tobin(k)), k, bv_tobin(k)))

def IsEQ(c: Cmp) -> Type:
  match c:
    case EQ{}:
      Unit
    case LT{}:
      Empty
    case GT{}:
      Empty

def lt_ne_eq(e: {LT{} == EQ{} : Cmp}) -> Empty:
  %Equal.sym(Cmp, LT{}, EQ{}, e) : IsEQ(_)
  Unit{}

def gt_ne_eq(e: {GT{} == EQ{} : Cmp}) -> Empty:
  %Equal.sym(Cmp, GT{}, EQ{}, e) : IsEQ(_)
  Unit{}

def ncmp_eq(a: Nat, b: Nat) -> {ncmp(a, b) == EQ{} : Cmp} -> {a == b : Nat}:
  match a b:
    case 0n 0n:
      e => {==}
    case 0n 1n+y:
      e => Empty.absurd({0n == 1n+y : Nat}, lt_ne_eq(e))
    case 1n+x 0n:
      e => Empty.absurd({1n+x == 0n : Nat}, gt_ne_eq(e))
    case 1n+x 1n+y:
      e => Equal.cong(Nat, Nat, w => 1n+w, x, y, ncmp_eq(x, y, e))

def lexc_eq(c: Cmp, -d: Cmp) -> {lexc(c, d) == EQ{} : Cmp} -> Pair({c == EQ{} : Cmp}, {d == EQ{} : Cmp}):
  match c:
    case EQ{}:
      e => ({==}, e)
    case LT{}:
      e => Empty.absurd(Pair({LT{} == EQ{} : Cmp}, {d == EQ{} : Cmp}), lt_ne_eq(e))
    case GT{}:
      e => Empty.absurd(Pair({GT{} == EQ{} : Cmp}, {d == EQ{} : Cmp}), gt_ne_eq(e))

def cons_eq(+x: Nat, +xs: +List<Nat>, +y: Nat, +ys: +List<Nat>, hx: {x == y : Nat}, hxs: {xs == ys : +List<Nat>}) -> {x <> xs == y <> ys : +List<Nat>}:
  %hx : {x <> xs == _ <> ys : +List<Nat>}
  %hxs : {x <> xs == x <> _ : +List<Nat>}
  {==}

def mcmp_fin(+x: Nat, +xs: +List<Nat>, +y: Nat, +ys: +List<Nat>, pr: Pair({ncmp(x, y) == EQ{} : Cmp}, {mcmp(xs, ys) == EQ{} : Cmp}), ih: {mcmp(xs, ys) == EQ{} : Cmp} -> {xs == ys : +List<Nat>}) -> {x <> xs == y <> ys : +List<Nat>}:
  (h1, h2) = pr
  cons_eq(x, xs, y, ys, ncmp_eq(x, y, h1), ih(h2))

def mcmp_eq(a: +List<Nat>, b: +List<Nat>) -> {mcmp(a, b) == EQ{} : Cmp} -> {a == b : +List<Nat>}:
  match a b:
    case Nil{} Nil{}:
      e => {==}
    case Nil{} Con{y, ys}:
      e => Empty.absurd({Nil{} == y <> ys : +List<Nat>}, lt_ne_eq(e))
    case Con{x, xs} Nil{}:
      e => Empty.absurd({x <> xs == Nil{} : +List<Nat>}, gt_ne_eq(e))
    case Con{+x, +xs} Con{+y, +ys}:
      e => mcmp_fin(x, xs, y, ys, lexc_eq(ncmp(x, y), mcmp(xs, ys), e), mcmp_eq(xs, ys))

# (a b)(c d) == (a c)(b d)
def mul4(+a: Nat, +b: Nat, +c: Nat, +d: Nat) -> {Nat.mul(Nat.mul(a, b), Nat.mul(c, d)) == Nat.mul(Nat.mul(a, c), Nat.mul(b, d)) : Nat}:
  %Equal.sym(Nat, Nat.mul(Nat.mul(a, b), Nat.mul(c, d)), Nat.mul(a, Nat.mul(b, Nat.mul(c, d))), L.mul_assoc(a, b, Nat.mul(c, d))) : {_ == Nat.mul(Nat.mul(a, c), Nat.mul(b, d)) : Nat}
  %Equal.sym(Nat, Nat.mul(Nat.mul(a, c), Nat.mul(b, d)), Nat.mul(a, Nat.mul(c, Nat.mul(b, d))), L.mul_assoc(a, c, Nat.mul(b, d))) : {Nat.mul(a, Nat.mul(b, Nat.mul(c, d))) == _ : Nat}
  %L.mul_assoc(b, c, d) : {Nat.mul(a, _) == Nat.mul(a, Nat.mul(c, Nat.mul(b, d))) : Nat}
  %L.mul_assoc(c, b, d) : {Nat.mul(a, Nat.mul(Nat.mul(b, c), d)) == Nat.mul(a, _) : Nat}
  %L.mul_comm(c, b) : {Nat.mul(a, Nat.mul(_, d)) == Nat.mul(a, Nat.mul(Nat.mul(c, b), d)) : Nat}
  {==}

def pow_add(+v: Nat, +a: Nat, +b: Nat) -> {Nat.pow(v, Nat.add(a, b)) == Nat.mul(Nat.pow(v, a), Nat.pow(v, b)) : Nat}:
  match a:
    case 0n:
      Equal.sym(Nat, Nat.mul(1n, Nat.pow(v, b)), Nat.pow(v, b), L.mul_one_l(Nat.pow(v, b)))
    case 1n+k:
      %Equal.sym(Nat, Nat.pow(v, Nat.add(k, b)), Nat.mul(Nat.pow(v, k), Nat.pow(v, b)), pow_add(v, k, b)) : {Nat.mul(v, _) == Nat.mul(Nat.mul(v, Nat.pow(v, k)), Nat.pow(v, b)) : Nat}
      Equal.sym(Nat, Nat.mul(Nat.mul(v, Nat.pow(v, k)), Nat.pow(v, b)), Nat.mul(v, Nat.mul(Nat.pow(v, k), Nat.pow(v, b))), L.mul_assoc(v, Nat.pow(v, k), Nat.pow(v, b)))

def evm_mm(+a: +List<Nat>, +b: +List<Nat>, +vals: +List<Nat>) -> {evm(mm(a, b), vals) == Nat.mul(evm(a, vals), evm(b, vals)) : Nat}:
  match a b:
    case Nil{} _:
      Equal.sym(Nat, Nat.mul(1n, evm(b, vals)), evm(b, vals), L.mul_one_l(evm(b, vals)))
    case Con{+x, +xs} Nil{}:
      Equal.sym(Nat, Nat.mul(evm(x <> xs, vals), 1n), evm(x <> xs, vals), L.mul_one_r(evm(x <> xs, vals)))
    case Con{+x, +xs} Con{+y, +ys}:
      %Equal.sym(Nat, evm(mm(xs, ys), tl(vals)), Nat.mul(evm(xs, tl(vals)), evm(ys, tl(vals))), evm_mm(xs, ys, tl(vals))) : {Nat.mul(Nat.pow(hd(vals), Nat.add(x, y)), _) == Nat.mul(Nat.mul(Nat.pow(hd(vals), x), evm(xs, tl(vals))), Nat.mul(Nat.pow(hd(vals), y), evm(ys, tl(vals)))) : Nat}
      %Equal.sym(Nat, Nat.pow(hd(vals), Nat.add(x, y)), Nat.mul(Nat.pow(hd(vals), x), Nat.pow(hd(vals), y)), pow_add(hd(vals), x, y)) : {Nat.mul(_, Nat.mul(evm(xs, tl(vals)), evm(ys, tl(vals)))) == Nat.mul(Nat.mul(Nat.pow(hd(vals), x), evm(xs, tl(vals))), Nat.mul(Nat.pow(hd(vals), y), evm(ys, tl(vals)))) : Nat}
      mul4(Nat.pow(hd(vals), x), Nat.pow(hd(vals), y), evm(xs, tl(vals)), evm(ys, tl(vals)))

def append_ok(+p: +List<Tm>, +q: +List<Tm>, +vals: +List<Nat>) -> {evp(List.append(&2, Tm, p, q), vals) == Nat.add(evp(p, vals), evp(q, vals)) : Nat}:
  match p:
    case Nil{}:
      {==}
    case Con{+t, +r}:
      %Equal.sym(Nat, evp(List.append(&2, Tm, r, q), vals), Nat.add(evp(r, vals), evp(q, vals)), append_ok(r, q, vals)) : {Nat.add(evt(t, vals), _) == Nat.add(Nat.add(evt(t, vals), evp(r, vals)), evp(q, vals)) : Nat}
      Equal.sym(Nat, Nat.add(Nat.add(evt(t, vals), evp(r, vals)), evp(q, vals)), Nat.add(evt(t, vals), Nat.add(evp(r, vals), evp(q, vals))), N.add_assoc(evt(t, vals), evp(r, vals), evp(q, vals)))

def evst(st: St, +vals: +List<Nat>) -> Nat:
  match st:
    case Go{p, q}:
      Nat.add(evp(p, vals), evp(q, vals))
    case Lt{a, pr, q}:
      Nat.add(evt(a, vals), Nat.add(evp(pr, vals), evp(q, vals)))
    case Eq{a, b, pr, qr}:
      Nat.add(evt(sum2(a, b), vals), Nat.add(evp(pr, vals), evp(qr, vals)))
    case Gt{b, p, qr}:
      Nat.add(evt(b, vals), Nat.add(evp(p, vals), evp(qr, vals)))

def stl_ok(+st: St, +vals: +List<Nat>) -> {evp(stl(st), vals) == evst(st, vals) : Nat}:
  match st:
    case Go{+p, +q}:
      append_ok(p, q, vals)
    case Lt{+a, +pr, +q}:
      Equal.cong(Nat, Nat, w => Nat.add(evt(a, vals), w), evp(List.append(&2, Tm, pr, q), vals), Nat.add(evp(pr, vals), evp(q, vals)), append_ok(pr, q, vals))
    case Eq{+a, +b, +pr, +qr}:
      Equal.cong(Nat, Nat, w => Nat.add(evt(sum2(a, b), vals), w), evp(List.append(&2, Tm, pr, qr), vals), Nat.add(evp(pr, vals), evp(qr, vals)), append_ok(pr, qr, vals))
    case Gt{+b, +p, +qr}:
      Equal.cong(Nat, Nat, w => Nat.add(evt(b, vals), w), evp(List.append(&2, Tm, p, qr), vals), Nat.add(evp(p, vals), evp(qr, vals)), append_ok(p, qr, vals))

# equal monomials: the coefficients add
def mk_eq(+a: Tm, +pr: +List<Tm>, +b: Tm, +qr: +List<Tm>, +vals: +List<Nat>, e: {mcmp(tm(a), tm(b)) == EQ{} : Cmp}) -> {Nat.add(evt(sum2(a, b), vals), Nat.add(evp(pr, vals), evp(qr, vals))) == Nat.add(Nat.add(evt(a, vals), evp(pr, vals)), Nat.add(evt(b, vals), evp(qr, vals))) : Nat}:
  match a b:
    case Tm{+c1, +m1} Tm{+c2, +m2}:
      %mcmp_eq(m1, m2, e) : {Nat.add(Nat.mul(bv(badd(c1, c2)), evm(m1, vals)), Nat.add(evp(pr, vals), evp(qr, vals))) == Nat.add(Nat.add(Nat.mul(bv(c1), evm(m1, vals)), evp(pr, vals)), Nat.add(Nat.mul(bv(c2), evm(_, vals)), evp(qr, vals))) : Nat}
      %Equal.sym(Nat, bv(badd(c1, c2)), Nat.add(bv(c1), bv(c2)), bv_badd(c1, c2)) : {Nat.add(Nat.mul(_, evm(m1, vals)), Nat.add(evp(pr, vals), evp(qr, vals))) == Nat.add(Nat.add(Nat.mul(bv(c1), evm(m1, vals)), evp(pr, vals)), Nat.add(Nat.mul(bv(c2), evm(m1, vals)), evp(qr, vals))) : Nat}
      %Equal.sym(Nat, Nat.mul(Nat.add(bv(c1), bv(c2)), evm(m1, vals)), Nat.add(Nat.mul(bv(c1), evm(m1, vals)), Nat.mul(bv(c2), evm(m1, vals))), L.mul_add_r(bv(c1), bv(c2), evm(m1, vals))) : {Nat.add(_, Nat.add(evp(pr, vals), evp(qr, vals))) == Nat.add(Nat.add(Nat.mul(bv(c1), evm(m1, vals)), evp(pr, vals)), Nat.add(Nat.mul(bv(c2), evm(m1, vals)), evp(qr, vals))) : Nat}
      N.swap_mid(Nat.mul(bv(c1), evm(m1, vals)), Nat.mul(bv(c2), evm(m1, vals)), evp(pr, vals), evp(qr, vals))

def mk_ok(+c: Cmp, +a: Tm, +pr: +List<Tm>, +b: Tm, +qr: +List<Tm>, +vals: +List<Nat>) -> {mcmp(tm(a), tm(b)) == c : Cmp} -> {evst(mk(c, a, pr, b, qr), vals) == Nat.add(evp(a <> pr, vals), evp(b <> qr, vals)) : Nat}:
  match c:
    case LT{}:
      e => Equal.sym(Nat, Nat.add(Nat.add(evt(a, vals), evp(pr, vals)), evp(b <> qr, vals)), Nat.add(evt(a, vals), Nat.add(evp(pr, vals), evp(b <> qr, vals))), N.add_assoc(evt(a, vals), evp(pr, vals), evp(b <> qr, vals)))
    case EQ{}:
      e => mk_eq(a, pr, b, qr, vals, e)
    case GT{}:
      e => L.add_left_comm(evp(a <> pr, vals), evt(b, vals), evp(qr, vals))

def padd_ok(+fuel: Nat, +st: St, +vals: +List<Nat>) -> {evp(padd(fuel, st), vals) == evst(st, vals) : Nat}:
  match fuel:
    case 0n:
      stl_ok(st, vals)
    case 1n+f:
      match st:
        case Go{+p, +q}:
          match p:
            case Nil{}:
              {==}
            case Con{+a, +pr}:
              match q:
                case Nil{}:
                  Equal.sym(Nat, Nat.add(evp(a <> pr, vals), 0n), evp(a <> pr, vals), N.add_zero_r(evp(a <> pr, vals)))
                case Con{+b, +qr}:
                  Equal.trans(Nat, evp(padd(f, mk(mcmp(tm(a), tm(b)), a, pr, b, qr)), vals), evst(mk(mcmp(tm(a), tm(b)), a, pr, b, qr), vals), Nat.add(evp(a <> pr, vals), evp(b <> qr, vals)), padd_ok(f, mk(mcmp(tm(a), tm(b)), a, pr, b, qr), vals), mk_ok(mcmp(tm(a), tm(b)), a, pr, b, qr, vals, {==}))
        case Lt{+a, +pr, +q}:
          Equal.cong(Nat, Nat, w => Nat.add(evt(a, vals), w), evp(padd(f, Go{pr, q}), vals), Nat.add(evp(pr, vals), evp(q, vals)), padd_ok(f, Go{pr, q}, vals))
        case Eq{+a, +b, +pr, +qr}:
          Equal.cong(Nat, Nat, w => Nat.add(evt(sum2(a, b), vals), w), evp(padd(f, Go{pr, qr}), vals), Nat.add(evp(pr, vals), evp(qr, vals)), padd_ok(f, Go{pr, qr}, vals))
        case Gt{+b, +p, +qr}:
          Equal.cong(Nat, Nat, w => Nat.add(evt(b, vals), w), evp(padd(f, Go{p, qr}), vals), Nat.add(evp(p, vals), evp(qr, vals)), padd_ok(f, Go{p, qr}, vals))

def plus_ok(+p: +List<Tm>, +q: +List<Tm>, +vals: +List<Nat>) -> {evp(plus(p, q), vals) == Nat.add(evp(p, vals), evp(q, vals)) : Nat}:
  +n = Nat.add(List.length(&2, Tm, p), List.length(&2, Tm, q))
  padd_ok(1n+Nat.add(n, n), Go{p, q}, vals)

def smul_ok(+c: Bn, +m: +List<Nat>, +q: +List<Tm>, +vals: +List<Nat>) -> {evp(smul(c, m, q), vals) == Nat.mul(Nat.mul(bv(c), evm(m, vals)), evp(q, vals)) : Nat}:
  match q:
    case Nil{}:
      Equal.sym(Nat, Nat.mul(Nat.mul(bv(c), evm(m, vals)), 0n), 0n, L.mul_zero_r(Nat.mul(bv(c), evm(m, vals))))
    case Con{Tm{+c2, +m2}, +r}:
      %Equal.sym(Nat, Nat.mul(Nat.mul(bv(c), evm(m, vals)), Nat.add(Nat.mul(bv(c2), evm(m2, vals)), evp(r, vals))), Nat.add(Nat.mul(Nat.mul(bv(c), evm(m, vals)), Nat.mul(bv(c2), evm(m2, vals))), Nat.mul(Nat.mul(bv(c), evm(m, vals)), evp(r, vals))), L.mul_add_l(Nat.mul(bv(c), evm(m, vals)), Nat.mul(bv(c2), evm(m2, vals)), evp(r, vals))) : {Nat.add(Nat.mul(bv(bmul(c, c2)), evm(mm(m, m2), vals)), evp(smul(c, m, r), vals)) == _ : Nat}
      %Equal.sym(Nat, evp(smul(c, m, r), vals), Nat.mul(Nat.mul(bv(c), evm(m, vals)), evp(r, vals)), smul_ok(c, m, r, vals)) : {Nat.add(Nat.mul(bv(bmul(c, c2)), evm(mm(m, m2), vals)), _) == Nat.add(Nat.mul(Nat.mul(bv(c), evm(m, vals)), Nat.mul(bv(c2), evm(m2, vals))), Nat.mul(Nat.mul(bv(c), evm(m, vals)), evp(r, vals))) : Nat}
      %Equal.sym(Nat, evm(mm(m, m2), vals), Nat.mul(evm(m, vals), evm(m2, vals)), evm_mm(m, m2, vals)) : {Nat.add(Nat.mul(bv(bmul(c, c2)), _), Nat.mul(Nat.mul(bv(c), evm(m, vals)), evp(r, vals))) == Nat.add(Nat.mul(Nat.mul(bv(c), evm(m, vals)), Nat.mul(bv(c2), evm(m2, vals))), Nat.mul(Nat.mul(bv(c), evm(m, vals)), evp(r, vals))) : Nat}
      %Equal.sym(Nat, bv(bmul(c, c2)), Nat.mul(bv(c), bv(c2)), bv_bmul(c, c2)) : {Nat.add(Nat.mul(_, Nat.mul(evm(m, vals), evm(m2, vals))), Nat.mul(Nat.mul(bv(c), evm(m, vals)), evp(r, vals))) == Nat.add(Nat.mul(Nat.mul(bv(c), evm(m, vals)), Nat.mul(bv(c2), evm(m2, vals))), Nat.mul(Nat.mul(bv(c), evm(m, vals)), evp(r, vals))) : Nat}
      Equal.cong(Nat, Nat, w => Nat.add(w, Nat.mul(Nat.mul(bv(c), evm(m, vals)), evp(r, vals))), Nat.mul(Nat.mul(bv(c), bv(c2)), Nat.mul(evm(m, vals), evm(m2, vals))), Nat.mul(Nat.mul(bv(c), evm(m, vals)), Nat.mul(bv(c2), evm(m2, vals))), mul4(bv(c), bv(c2), evm(m, vals), evm(m2, vals)))

def pmul_ok(+p: +List<Tm>, +q: +List<Tm>, +vals: +List<Nat>) -> {evp(pmul(p, q), vals) == Nat.mul(evp(p, vals), evp(q, vals)) : Nat}:
  match p:
    case Nil{}:
      {==}
    case Con{Tm{+c, +m}, +r}:
      %Equal.sym(Nat, evp(plus(smul(c, m, q), pmul(r, q)), vals), Nat.add(evp(smul(c, m, q), vals), evp(pmul(r, q), vals)), plus_ok(smul(c, m, q), pmul(r, q), vals)) : {_ == Nat.mul(Nat.add(Nat.mul(bv(c), evm(m, vals)), evp(r, vals)), evp(q, vals)) : Nat}
      %Equal.sym(Nat, evp(smul(c, m, q), vals), Nat.mul(Nat.mul(bv(c), evm(m, vals)), evp(q, vals)), smul_ok(c, m, q, vals)) : {Nat.add(_, evp(pmul(r, q), vals)) == Nat.mul(Nat.add(Nat.mul(bv(c), evm(m, vals)), evp(r, vals)), evp(q, vals)) : Nat}
      %Equal.sym(Nat, evp(pmul(r, q), vals), Nat.mul(evp(r, vals), evp(q, vals)), pmul_ok(r, q, vals)) : {Nat.add(Nat.mul(Nat.mul(bv(c), evm(m, vals)), evp(q, vals)), _) == Nat.mul(Nat.add(Nat.mul(bv(c), evm(m, vals)), evp(r, vals)), evp(q, vals)) : Nat}
      Equal.sym(Nat, Nat.mul(Nat.add(Nat.mul(bv(c), evm(m, vals)), evp(r, vals)), evp(q, vals)), Nat.add(Nat.mul(Nat.mul(bv(c), evm(m, vals)), evp(q, vals)), Nat.mul(evp(r, vals), evp(q, vals))), L.mul_add_r(Nat.mul(bv(c), evm(m, vals)), evp(r, vals), evp(q, vals)))

def nth_tl(+vals: +List<Nat>, +k: Nat) -> {T.nth(tl(vals), k) == T.nth(vals, 1n+k) : Nat}:
  match vals:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      {==}

def evm_var(+i: Nat, +vals: +List<Nat>) -> {evm(var(i), vals) == T.nth(vals, i) : Nat}:
  match i:
    case 0n:
      match vals:
        case Nil{}:
          {==}
        case Con{+h, +t}:
          %Equal.sym(Nat, Nat.mul(h, 1n), h, L.mul_one_r(h)) : {Nat.mul(_, 1n) == h : Nat}
          L.mul_one_r(h)
    case 1n+k:
      %Equal.sym(Nat, evm(var(k), tl(vals)), T.nth(tl(vals), k), evm_var(k, tl(vals))) : {Nat.mul(1n, _) == T.nth(vals, 1n+k) : Nat}
      %Equal.sym(Nat, Nat.mul(1n, T.nth(tl(vals), k)), T.nth(tl(vals), k), L.mul_one_l(T.nth(tl(vals), k))) : {_ == T.nth(vals, 1n+k) : Nat}
      nth_tl(vals, k)

def pvar_ok(+i: Nat, +vals: +List<Nat>) -> {evp(pvar(i), vals) == T.nth(vals, i) : Nat}:
  Equal.trans(Nat, Nat.add(Nat.mul(1n, evm(var(i), vals)), 0n), Nat.mul(1n, evm(var(i), vals)), T.nth(vals, i), N.add_zero_r(Nat.mul(1n, evm(var(i), vals))),
  Equal.trans(Nat, Nat.mul(1n, evm(var(i), vals)), evm(var(i), vals), T.nth(vals, i), L.mul_one_l(evm(var(i), vals)), evm_var(i, vals)))

def pconst_ok(+n: Nat, +vals: +List<Nat>) -> {evp(pconst(n), vals) == n : Nat}:
  match n:
    case 0n:
      {==}
    case 1n+k:
      Equal.trans(Nat, Nat.add(Nat.mul(bv(tobin(1n+k)), 1n), 0n), Nat.mul(bv(tobin(1n+k)), 1n), 1n+k, N.add_zero_r(Nat.mul(bv(tobin(1n+k)), 1n)), Equal.trans(Nat, Nat.mul(bv(tobin(1n+k)), 1n), bv(tobin(1n+k)), 1n+k, L.mul_one_r(bv(tobin(1n+k))), bv_tobin(1n+k)))

def add_cong(+x: Nat, +x2: Nat, +y: Nat, +y2: Nat, hx: {x == x2 : Nat}, hy: {y == y2 : Nat}) -> {Nat.add(x, y) == Nat.add(x2, y2) : Nat}:
  %hx : {Nat.add(x, y) == Nat.add(_, y2) : Nat}
  %hy : {Nat.add(x, y) == Nat.add(x, _) : Nat}
  {==}

def mul_cong(+x: Nat, +x2: Nat, +y: Nat, +y2: Nat, hx: {x == x2 : Nat}, hy: {y == y2 : Nat}) -> {Nat.mul(x, y) == Nat.mul(x2, y2) : Nat}:
  %hx : {Nat.mul(x, y) == Nat.mul(_, y2) : Nat}
  %hy : {Nat.mul(x, y) == Nat.mul(x, _) : Nat}
  {==}

# The normaliser is sound: the normal form evaluates to the Nat reading of the expression.
def nf_ok(+bp: Nat, +env: +List<Nat>, t: X.E) -> {X.nv(bp, env, t) == evp(nf(t), bp <> env) : Nat}:
  match t:
    case X.V{+i}:
      Equal.sym(Nat, evp(pvar(1n+i), bp <> env), T.nth(env, i), pvar_ok(1n+i, bp <> env))
    case X.C{+n}:
      Equal.sym(Nat, evp(pconst(n), bp <> env), n, pconst_ok(n, bp <> env))
    case X.Pp{}:
      Equal.sym(Nat, evp(pvar(0n), bp <> env), bp, pvar_ok(0n, bp <> env))
    case X.Ad{+a, +b}:
      Equal.trans(Nat, Nat.add(X.nv(bp, env, a), X.nv(bp, env, b)), Nat.add(evp(nf(a), bp <> env), evp(nf(b), bp <> env)), evp(plus(nf(a), nf(b)), bp <> env),
        add_cong(X.nv(bp, env, a), evp(nf(a), bp <> env), X.nv(bp, env, b), evp(nf(b), bp <> env), nf_ok(bp, env, a), nf_ok(bp, env, b)),
        Equal.sym(Nat, evp(plus(nf(a), nf(b)), bp <> env), Nat.add(evp(nf(a), bp <> env), evp(nf(b), bp <> env)), plus_ok(nf(a), nf(b), bp <> env)))
    case X.Sb{+a, +b}:
      Equal.trans(Nat, Nat.add(X.nv(bp, env, a), Nat.mul(bp, X.nv(bp, env, b))), Nat.add(evp(nf(a), bp <> env), evp(pmul(pvar(0n), nf(b)), bp <> env)), evp(plus(nf(a), pmul(pvar(0n), nf(b))), bp <> env),
        add_cong(X.nv(bp, env, a), evp(nf(a), bp <> env), Nat.mul(bp, X.nv(bp, env, b)), evp(pmul(pvar(0n), nf(b)), bp <> env), nf_ok(bp, env, a),
          Equal.trans(Nat, Nat.mul(bp, X.nv(bp, env, b)), Nat.mul(evp(pvar(0n), bp <> env), evp(nf(b), bp <> env)), evp(pmul(pvar(0n), nf(b)), bp <> env),
            mul_cong(bp, evp(pvar(0n), bp <> env), X.nv(bp, env, b), evp(nf(b), bp <> env), Equal.sym(Nat, evp(pvar(0n), bp <> env), bp, pvar_ok(0n, bp <> env)), nf_ok(bp, env, b)),
            Equal.sym(Nat, evp(pmul(pvar(0n), nf(b)), bp <> env), Nat.mul(evp(pvar(0n), bp <> env), evp(nf(b), bp <> env)), pmul_ok(pvar(0n), nf(b), bp <> env)))),
        Equal.sym(Nat, evp(plus(nf(a), pmul(pvar(0n), nf(b))), bp <> env), Nat.add(evp(nf(a), bp <> env), evp(pmul(pvar(0n), nf(b)), bp <> env)), plus_ok(nf(a), pmul(pvar(0n), nf(b)), bp <> env)))
    case X.Ml{+a, +b}:
      Equal.trans(Nat, Nat.mul(X.nv(bp, env, a), X.nv(bp, env, b)), Nat.mul(evp(nf(a), bp <> env), evp(nf(b), bp <> env)), evp(pmul(nf(a), nf(b)), bp <> env),
        mul_cong(X.nv(bp, env, a), evp(nf(a), bp <> env), X.nv(bp, env, b), evp(nf(b), bp <> env), nf_ok(bp, env, a), nf_ok(bp, env, b)),
        Equal.sym(Nat, evp(pmul(nf(a), nf(b)), bp <> env), Nat.mul(evp(nf(a), bp <> env), evp(nf(b), bp <> env)), pmul_ok(nf(a), nf(b), bp <> env)))
    case X.Ng{+a}:
      Equal.trans(Nat, Nat.mul(bp, X.nv(bp, env, a)), Nat.mul(evp(pvar(0n), bp <> env), evp(nf(a), bp <> env)), evp(pmul(pvar(0n), nf(a)), bp <> env),
        mul_cong(bp, evp(pvar(0n), bp <> env), X.nv(bp, env, a), evp(nf(a), bp <> env), Equal.sym(Nat, evp(pvar(0n), bp <> env), bp, pvar_ok(0n, bp <> env)), nf_ok(bp, env, a)),
        Equal.sym(Nat, evp(pmul(pvar(0n), nf(a)), bp <> env), Nat.mul(evp(pvar(0n), bp <> env), evp(nf(a), bp <> env)), pmul_ok(pvar(0n), nf(a), bp <> env)))
