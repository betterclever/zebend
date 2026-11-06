import Base
import ../prims/natlib.bend as L
import ../opt_gates/term.bend as T
import ../ring/expr.bend as X
import ./model.bend as M
import ./lemmas.bend as B
import ./LAWS.bend as Laws

def Laws.bi_inverts(bp, l1, xs, hc, h):
  B.bi_ring(bp, l1, xs, hc, h)

def Laws.bi_finv(bp, l1, xs, hc, hnz, f):
  B.bi_field(bp, l1, xs, hc, hnz, f)

def Laws.bi_zero(bp, l2, xs, hc, hz):
  B.bi_zero(bp, l2, xs, hc, hz)

def Laws.binvs_finv(bp, l2, xs, hc, f):
  B.binvs_ok(bp, l2, xs, hc, f)

def Laws.ba_is_bi(bp, xs):
  B.ba_eq(bp, xs)

# --- p = 5 -----------------------------------------------------------------------------

def IsT(b: Bool) -> Type:
  match b:
    case True{}:
      Unit
    case False{}:
      Empty

def true_ne_false(e: {True{} == False{} : Bool}) -> Empty:
  %e : IsT(_)
  Unit{}

# x <= 4, x != 0  ==>  x * x^3 == 1 mod 5
def f5(+x: Nat, l: L.Le(x, 4n), nz: {Nat.is_eq(x, 0n) == False{} : Bool}) -> {T.fmul(4n, x, T.finv(4n, x)) == 1n : Nat}:
  match x:
    case 0n:
      Empty.absurd({T.fmul(4n, 0n, T.finv(4n, 0n)) == 1n : Nat}, true_ne_false(nz))
    case 1n+a:
      match a:
        case 0n:
          {==}
        case 1n+b:
          match b:
            case 0n:
              {==}
            case 1n+c:
              match c:
                case 0n:
                  {==}
                case 1n+d:
                  match d:
                    case 0n:
                      {==}
                    case 1n+k:
                      (+e, he) = l
                      Empty.absurd({T.fmul(4n, 5n+k, T.finv(4n, 5n+k)) == 1n : Nat}, L.succ_ne_zero(Nat.add(k, e), L.succ_inj(1n+Nat.add(k, e), 0n, L.succ_inj(2n+Nat.add(k, e), 1n, L.succ_inj(3n+Nat.add(k, e), 2n, L.succ_inj(4n+Nat.add(k, e), 3n, he))))))

def fermat5_c(+x: Nat, +t: +List<Nat>, hc: X.Canon(4n, x <> t), hn: B.NZs(x <> t), ih: X.Canon(4n, t) -> B.NZs(t) -> B.FInv(4n, t)) -> B.FInv(4n, x <> t):
  (+lx, +lt) = hc
  (+nx, +nt) = hn
  (f5(x, lx, nx), ih(lt, nt))

def fermat5(xs: +List<Nat>) -> X.Canon(4n, xs) -> B.NZs(xs) -> B.FInv(4n, xs):
  match xs:
    case Nil{}:
      hc => hn => Unit{}
    case Con{+x, +t}:
      hc => hn => fermat5_c(x, t, hc, hn, fermat5(t))

def Laws.fermat_5():
  xs => fermat5(xs)

def Laws.bi_inverts_sat():
  ((3n, {==}), (((2n, {==}), ((1n, {==}), Unit{})), {==}))

def Laws.bi_finv_sat():
  ((3n, {==}), (((2n, {==}), ((1n, {==}), Unit{})), ({==}, ({==}, Unit{}))))

def Laws.bi_zero_sat():
  ((2n, {==}), (((1n, {==}), ((4n, {==}), Unit{})), Inr{Inl{{==}}}))
