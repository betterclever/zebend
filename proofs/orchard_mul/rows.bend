import Base
import ../prims/natlib.bend as L
import ../orchard/fieldmodel.bend as F
import ./gates_model.bend as G

# The incomplete-addition loop of variable-base scalar mul (halo2_gadgets 0.6,
# ecc/chip/mul/incomplete.rs), as far as its base point is concerned.
#
# The loop occupies rows r_1 .. r_m of the region (q_mul_2 enabled on r_1 .. r_{m-1},
# q_mul_3 on r_m). On every q_mul_2 row the gate "q_mul_2 == 1 checks" holds, and two of its
# polynomials are the base-constancy constraints x_p_check = x_p(r) - x_p(r+1) and
# y_p_check = y_p(r) - y_p(r+1). Which of the four generated polynomials (x or y, hi or lo
# half) is meant is a `Check`.
#
# A row list [Row{sel, si, x}, ...] holds, for loop rows r_2 .. r_m, the base coordinate x on
# that row, the gate's (compressed) selector value sel on the row BEFORE it, and an inverse
# si of sel (the selector is non-zero there). `Steps(rows, c, pp, x1)` says every constancy
# constraint between consecutive rows holds, starting from the coordinate x1 on row r_1.

type Check is Data:
  XHi{}
  YHi{}
  XLo{}
  YLo{}

def gate(+c: Check, +pp: Nat, +sel: Nat, +cur: Nat, +next: Nat) -> Nat:
  match c:
    case XHi{}:
      G.gate_8_0(pp, sel, cur, next)
    case YHi{}:
      G.gate_8_1(pp, sel, cur, next)
    case XLo{}:
      G.gate_11_0(pp, sel, cur, next)
    case YLo{}:
      G.gate_11_1(pp, sel, cur, next)

type Row is Data:
  Row{sel: Nat, si: Nat, x: Nat}

def Steps(rows: List<&2, Row>, +c: Check, +pp: Nat, +prev: Nat) -> Type:
  match rows:
    case Nil{}:
      Unit
    case Con{+r, +t}:
      match r:
        case Row{+sel, +si, +x}:
          {F.fmul(1n+pp, si, sel) == 1n : Nat} & {gate(c, pp, sel, prev, x) == 0n : Nat} & L.Le(x, pp) & Steps(t, c, pp, x)

# Every row's base coordinate equals g.
def AllEq(rows: List<&2, Row>, +g: Nat) -> Type:
  match rows:
    case Nil{}:
      Unit
    case Con{+r, +t}:
      match r:
        case Row{_, _, +x}:
          {x == g : Nat} & AllEq(t, g)

# n rows, every selector 1 (inverse 1), every coordinate g.
def rep(n: Nat, +g: Nat) -> List<&2, Row>:
  match n:
    case 0n:
      Nil{}
    case 1n+q:
      Row{1n, 1n, g} <> rep(q, g)
