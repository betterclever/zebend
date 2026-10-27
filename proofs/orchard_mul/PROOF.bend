import Base
import ../prims/natlib.bend as L
import ../orchard/fieldmodel.bend as F
import ../orchard/evals.bend as E
import ./gates_model.bend as G
import ./rows.bend as R
import ./LAWS.bend as Laws

# x + (0 - x) == 0 in Fp, for canonical x.
law self_cancel:
  for +pp: Nat
  for +x: Nat
  for +lx: L.Le(x, pp)
  {F.fadd(1n+pp, x, F.fsub(1n+pp, 0n, x)) == 0n : Nat}

def self_cancel(pp, x, lx):
  %Equal.sym(Nat, Nat.mod(Nat.add(x, Nat.mod(Nat.add(0n, Nat.sub(1n+pp, x)), 1n+pp)), 1n+pp), Nat.mod(Nat.add(x, Nat.add(0n, Nat.sub(1n+pp, x))), 1n+pp), L.mod_add_mod_r(x, Nat.add(0n, Nat.sub(1n+pp, x)), pp)) : {_ == 0n : Nat}
  %Equal.sym(Nat, Nat.add(x, Nat.sub(1n+pp, x)), 1n+pp, L.sub_add(1n+pp, x, F.le_succ(x, pp, lx))) : {Nat.mod(_, 1n+pp) == 0n : Nat}
  L.mod_add_self(0n, pp)

# One loop step: a vanishing constancy constraint with an invertible selector forces the
# base coordinate on the next row to equal the one on this row.
def step(+c: R.Check, +pp: Nat, +sel: Nat, +si: Nat, +prev: Nat, +x: Nat, +lprev: L.Le(prev, pp), +lx: L.Le(x, pp), inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}, hg: {R.gate(c, pp, sel, prev, x) == 0n : Nat}) -> {prev == x : Nat}:
  match c:
    case R.XHi{}:
      F.neg_zero(pp, prev, x, lprev, lx, E.strip_inv(pp, sel, F.fadd(1n+pp, prev, F.fsub(1n+pp, 0n, x)), si, inv, E.le_fadd(pp, prev, F.fsub(1n+pp, 0n, x)), hg))
    case R.YHi{}:
      F.neg_zero(pp, prev, x, lprev, lx, E.strip_inv(pp, sel, F.fadd(1n+pp, prev, F.fsub(1n+pp, 0n, x)), si, inv, E.le_fadd(pp, prev, F.fsub(1n+pp, 0n, x)), hg))
    case R.XLo{}:
      F.neg_zero(pp, prev, x, lprev, lx, E.strip_inv(pp, sel, F.fadd(1n+pp, prev, F.fsub(1n+pp, 0n, x)), si, inv, E.le_fadd(pp, prev, F.fsub(1n+pp, 0n, x)), hg))
    case R.YLo{}:
      F.neg_zero(pp, prev, x, lprev, lx, E.strip_inv(pp, sel, F.fadd(1n+pp, prev, F.fsub(1n+pp, 0n, x)), si, inv, E.le_fadd(pp, prev, F.fsub(1n+pp, 0n, x)), hg))

def le_of_eq(+x: Nat, +g: Nat, +pp: Nat, e: {x == g : Nat}, +lg: L.Le(g, pp)) -> L.Le(x, pp):
  %Equal.sym(Nat, x, g, e) : L.Le(_, pp)
  lg

def anchored_go(rows: List<&2, R.Row>, +c: R.Check, +pp: Nat, +g: Nat, +lg: L.Le(g, pp), +x1: Nat, +anchor: {x1 == g : Nat}, h: R.Steps(rows, c, pp, x1)) -> R.AllEq(rows, g):
  match rows:
    case Nil{}:
      Unit{}
    case Con{r, t}:
      match r:
        case R.Row{+sel, +si, +x}:
          (inv, rest1) = h
          (hg, rest2) = rest1
          (+lx, rest3) = rest2
          +e1 = step(c, pp, sel, si, x1, x, le_of_eq(x1, g, pp, anchor, lg), lx, inv, hg)
          +xg = Equal.trans(Nat, x, x1, g, Equal.sym(Nat, x1, x, e1), anchor)
          (xg, anchored_go(t, c, pp, g, lg, x, xg, rest3))

def Laws.base_anchored(rows, c, pp, g, lg, x1, anchor, h):
  anchored_go(rows, c, pp, g, lg, x1, anchor, h)

# The constraint on a row whose base equals the previous row's, with selector 1.
def gate_same(+c: R.Check, +pp: Nat, +g: Nat, +lg: L.Le(g, pp)) -> {R.gate(c, pp, 1n, g, g) == 0n : Nat}:
  match c:
    case R.XHi{}:
      %Equal.sym(Nat, F.fadd(1n+pp, g, F.fsub(1n+pp, 0n, g)), 0n, self_cancel(pp, g, lg)) : {F.fmul(1n+pp, 1n, _) == 0n : Nat}
      {==}
    case R.YHi{}:
      %Equal.sym(Nat, F.fadd(1n+pp, g, F.fsub(1n+pp, 0n, g)), 0n, self_cancel(pp, g, lg)) : {F.fmul(1n+pp, 1n, _) == 0n : Nat}
      {==}
    case R.XLo{}:
      %Equal.sym(Nat, F.fadd(1n+pp, g, F.fsub(1n+pp, 0n, g)), 0n, self_cancel(pp, g, lg)) : {F.fmul(1n+pp, 1n, _) == 0n : Nat}
      {==}
    case R.YLo{}:
      %Equal.sym(Nat, F.fadd(1n+pp, g, F.fsub(1n+pp, 0n, g)), 0n, self_cancel(pp, g, lg)) : {F.fmul(1n+pp, 1n, _) == 0n : Nat}
      {==}

def sat_go(n: Nat, +c: R.Check, +pp: Nat, +l1: L.Le(1n, pp), +g: Nat, +lg: L.Le(g, pp)) -> R.Steps(R.rep(n, g), c, pp, g):
  match n:
    case 0n:
      Unit{}
    case 1n+q:
      (E.fmul_1(pp, 1n, l1), (gate_same(c, pp, g, lg), (lg, sat_go(q, c, pp, l1, g, lg))))

def Laws.base_anchored_satisfiable(n, c, pp, l1, g, lg):
  sat_go(n, c, pp, l1, g, lg)

def le_zero(+pp: Nat) -> L.Le(0n, pp):
  (pp, {==})

def Laws.unanchored_counterexample(n, c, pp, l1, g, lg):
  match g:
    case 0n:
      (1n, (e => L.succ_ne_zero(0n, e), (sat_go(1n+n, c, pp, l1, 1n, l1), p => L.succ_ne_zero(0n, Pair.fst({1n == 0n : Nat}, R.AllEq(R.rep(n, 1n), 0n), p)))))
    case 1n+q:
      (0n, (e => L.succ_ne_zero(q, Equal.sym(Nat, 0n, 1n+q, e)), (sat_go(1n+n, c, pp, l1, 0n, le_zero(pp)), p => L.succ_ne_zero(q, Equal.sym(Nat, 0n, 1n+q, Pair.fst({0n == 1n+q : Nat}, R.AllEq(R.rep(n, 0n), 1n+q), p))))))
