import Base
import ../prims/natlib.bend as L
import ./fieldmodel.bend as F
import ./gates_model.bend as G
import ./evals.bend as E
import ./LAWS.bend as Laws

# Proofs of LAWS.bend. Each one strips the invertible selector (E.strip_inv), splits a product
# that vanishes with the no-zero-divisor hypothesis or E.boolean, and moves negations
# across with F.neg_zero / F.neg_eq.

def neg(+pp: Nat, +y: Nat) -> Nat:
  F.fsub(1n+pp, 0n, y)

def Laws.value_balance(pp, sel, si, inv, a0, a1, a2, a3, la0, la1, h):
  F.neg_eq(pp, a0, a1, F.fmul(1n+pp, a2, a3), la0, la1,
    F.neg_zero(pp, F.fadd(1n+pp, a0, neg(pp, a1)), F.fmul(1n+pp, a2, a3), E.le_fadd(pp, a0, neg(pp, a1)), E.le_fmul(pp, a2, a3),
      E.strip_inv(pp, sel, F.fadd(1n+pp, F.fadd(1n+pp, a0, neg(pp, a1)), neg(pp, F.fmul(1n+pp, a2, a3))), si, inv, E.le_fadd(pp, F.fadd(1n+pp, a0, neg(pp, a1)), neg(pp, F.fmul(1n+pp, a2, a3))), h)))

# x * (u - v) == 0 split into x == 0 or u == v.
def zero_or_eq(+pp: Nat, +x: Nat, +u: Nat, +v: Nat, +lu: L.Le(u, pp), +lv: L.Le(v, pp), e: Either<&1, &1, {x == 0n : Nat}, {F.fadd(1n+pp, u, neg(pp, v)) == 0n : Nat}>) -> Either<&1, &1, {x == 0n : Nat}, {u == v : Nat}>:
  match e:
    case Inl{z}:
      Inl{z}
    case Inr{z}:
      Inr{F.neg_zero(pp, u, v, lu, lv, z)}

# x * (1 - b) == 0 split into x == 0 or b == 1.
def zero_or_one(+pp: Nat, +x: Nat, +b: Nat, +l1: L.Le(1n, pp), +lb: L.Le(b, pp), e: Either<&1, &1, {x == 0n : Nat}, {F.fadd(1n+pp, 1n, neg(pp, b)) == 0n : Nat}>) -> Either<&1, &1, {x == 0n : Nat}, {b == 1n : Nat}>:
  match e:
    case Inl{z}:
      Inl{z}
    case Inr{z}:
      Inr{Equal.sym(Nat, 1n, b, F.neg_zero(pp, 1n, b, l1, lb, z))}

def Laws.anchor_or_zero(pp, nzd, sel, si, inv, a0, a4, a5, la0, la4, la5, h):
  zero_or_eq(pp, a0, a4, a5, la4, la5,
    nzd(a0, F.fadd(1n+pp, a4, neg(pp, a5)), la0, E.le_fadd(pp, a4, neg(pp, a5)),
      E.strip_inv(pp, sel, F.fmul(1n+pp, a0, F.fadd(1n+pp, a4, neg(pp, a5))), si, inv, E.le_fmul(pp, a0, F.fadd(1n+pp, a4, neg(pp, a5))), h)))

def Laws.spend_disabled_zero(pp, nzd, l1, sel, si, inv, a0, a6, la0, la6, h):
  zero_or_one(pp, a0, a6, l1, la6,
    nzd(a0, F.fadd(1n+pp, 1n, neg(pp, a6)), la0, E.le_fadd(pp, 1n, neg(pp, a6)),
      E.strip_inv(pp, sel, F.fmul(1n+pp, a0, F.fadd(1n+pp, 1n, neg(pp, a6))), si, inv, E.le_fmul(pp, a0, F.fadd(1n+pp, 1n, neg(pp, a6))), h)))

def Laws.output_disabled_zero(pp, nzd, l1, sel, si, inv, a1, a7, la1, la7, h):
  zero_or_one(pp, a1, a7, l1, la7,
    nzd(a1, F.fadd(1n+pp, 1n, neg(pp, a7)), la1, E.le_fadd(pp, 1n, neg(pp, a7)),
      E.strip_inv(pp, sel, F.fmul(1n+pp, a1, F.fadd(1n+pp, 1n, neg(pp, a7))), si, inv, E.le_fmul(pp, a1, F.fadd(1n+pp, 1n, neg(pp, a7))), h)))

# b * (1 - b) as the gates write it.
def bodybool(+pp: Nat, +b: Nat) -> Nat:
  F.fmul(1n+pp, b, F.fadd(1n+pp, 1n, neg(pp, b)))

def Laws.last_window_bit(pp, nzd, l1, sel, si, inv, a5, la5, h):
  E.boolean(pp, a5, nzd, l1, la5,
    E.strip_inv(pp, sel, bodybool(pp, a5), si, inv, E.le_fmul(pp, a5, F.fadd(1n+pp, 1n, neg(pp, a5))), h))

# Gate 13: k = z_i - 2 z_{i+1}.
def kbit(+pp: Nat, +a10: Nat, +a11: Nat) -> Nat:
  F.fadd(1n+pp, a10, neg(pp, F.fmul(1n+pp, 2n, a11)))

def dec_0(+pp: Nat, +l1: L.Le(1n, pp), +a9: Nat, +a10: Nat, +a11: Nat, +a21: Nat, +la10: L.Le(a10, pp), +la9: L.Le(a9, pp), +la21: L.Le(a21, pp),
    m: {E.mux(pp, kbit(pp, a10, a11), F.fadd(1n+pp, a9, neg(pp, a21)), F.fadd(1n+pp, a9, a21)) == 0n : Nat},
    +z: {kbit(pp, a10, a11) == 0n : Nat}) -> {a10 == F.fadd(1n+pp, F.fmul(1n+pp, 2n, a11), 0n) : Nat} & {F.fadd(1n+pp, a9, a21) == 0n : Nat}:
  (F.neg_eq(pp, a10, F.fmul(1n+pp, 2n, a11), 0n, la10, E.le_fmul(pp, 2n, a11), z),
    Equal.trans(Nat, F.fadd(1n+pp, a9, a21), E.mux(pp, 0n, F.fadd(1n+pp, a9, neg(pp, a21)), F.fadd(1n+pp, a9, a21)), 0n,
      Equal.sym(Nat, E.mux(pp, 0n, F.fadd(1n+pp, a9, neg(pp, a21)), F.fadd(1n+pp, a9, a21)), F.fadd(1n+pp, a9, a21), E.mux_0(pp, F.fadd(1n+pp, a9, neg(pp, a21)), F.fadd(1n+pp, a9, a21), l1, E.le_fadd(pp, a9, a21))),
      Equal.trans(Nat, E.mux(pp, 0n, F.fadd(1n+pp, a9, neg(pp, a21)), F.fadd(1n+pp, a9, a21)), E.mux(pp, kbit(pp, a10, a11), F.fadd(1n+pp, a9, neg(pp, a21)), F.fadd(1n+pp, a9, a21)), 0n,
        Equal.sym(Nat, E.mux(pp, kbit(pp, a10, a11), F.fadd(1n+pp, a9, neg(pp, a21)), F.fadd(1n+pp, a9, a21)), E.mux(pp, 0n, F.fadd(1n+pp, a9, neg(pp, a21)), F.fadd(1n+pp, a9, a21)), E.mux_at(pp, kbit(pp, a10, a11), 0n, F.fadd(1n+pp, a9, neg(pp, a21)), F.fadd(1n+pp, a9, a21), z)),
        m)))

def dec_1(+pp: Nat, +l1: L.Le(1n, pp), +a9: Nat, +a10: Nat, +a11: Nat, +a21: Nat, +la10: L.Le(a10, pp), +la9: L.Le(a9, pp), +la21: L.Le(a21, pp),
    m: {E.mux(pp, kbit(pp, a10, a11), F.fadd(1n+pp, a9, neg(pp, a21)), F.fadd(1n+pp, a9, a21)) == 0n : Nat},
    +z: {kbit(pp, a10, a11) == 1n : Nat}) -> {a10 == F.fadd(1n+pp, F.fmul(1n+pp, 2n, a11), 1n) : Nat} & {a9 == a21 : Nat}:
  (F.neg_eq(pp, a10, F.fmul(1n+pp, 2n, a11), 1n, la10, E.le_fmul(pp, 2n, a11), z),
    F.neg_zero(pp, a9, a21, la9, la21,
      Equal.trans(Nat, F.fadd(1n+pp, a9, neg(pp, a21)), E.mux(pp, 1n, F.fadd(1n+pp, a9, neg(pp, a21)), F.fadd(1n+pp, a9, a21)), 0n,
        Equal.sym(Nat, E.mux(pp, 1n, F.fadd(1n+pp, a9, neg(pp, a21)), F.fadd(1n+pp, a9, a21)), F.fadd(1n+pp, a9, neg(pp, a21)), E.mux_1(pp, F.fadd(1n+pp, a9, neg(pp, a21)), F.fadd(1n+pp, a9, a21), E.le_fadd(pp, a9, neg(pp, a21)))),
        Equal.trans(Nat, E.mux(pp, 1n, F.fadd(1n+pp, a9, neg(pp, a21)), F.fadd(1n+pp, a9, a21)), E.mux(pp, kbit(pp, a10, a11), F.fadd(1n+pp, a9, neg(pp, a21)), F.fadd(1n+pp, a9, a21)), 0n,
          Equal.sym(Nat, E.mux(pp, kbit(pp, a10, a11), F.fadd(1n+pp, a9, neg(pp, a21)), F.fadd(1n+pp, a9, a21)), E.mux(pp, 1n, F.fadd(1n+pp, a9, neg(pp, a21)), F.fadd(1n+pp, a9, a21)), E.mux_at(pp, kbit(pp, a10, a11), 1n, F.fadd(1n+pp, a9, neg(pp, a21)), F.fadd(1n+pp, a9, a21), z)),
          m))))

def dec_go(+pp: Nat, +l1: L.Le(1n, pp), +a9: Nat, +a10: Nat, +a11: Nat, +a21: Nat, +la10: L.Le(a10, pp), +la9: L.Le(a9, pp), +la21: L.Le(a21, pp),
    m: {E.mux(pp, kbit(pp, a10, a11), F.fadd(1n+pp, a9, neg(pp, a21)), F.fadd(1n+pp, a9, a21)) == 0n : Nat},
    e: Either<&1, &1, {kbit(pp, a10, a11) == 0n : Nat}, {kbit(pp, a10, a11) == 1n : Nat}>)
    -> Either<&1, &1, {a10 == F.fadd(1n+pp, F.fmul(1n+pp, 2n, a11), 0n) : Nat} & {F.fadd(1n+pp, a9, a21) == 0n : Nat}, {a10 == F.fadd(1n+pp, F.fmul(1n+pp, 2n, a11), 1n) : Nat} & {a9 == a21 : Nat}>:
  match e:
    case Inl{z}:
      Inl{dec_0(pp, l1, a9, a10, a11, a21, la10, la9, la21, m, z)}
    case Inr{z}:
      Inr{dec_1(pp, l1, a9, a10, a11, a21, la10, la9, la21, m, z)}

def Laws.decompose_bit(pp, nzd, l1, sel, si, inv, a9, a10, a11, a21, la9, la10, la21, h0, h1):
  dec_go(pp, l1, a9, a10, a11, a21, la10, la9, la21,
    E.strip_inv(pp, sel, E.mux(pp, kbit(pp, a10, a11), F.fadd(1n+pp, a9, neg(pp, a21)), F.fadd(1n+pp, a9, a21)), si, inv,
      E.le_fadd(pp, F.fmul(1n+pp, kbit(pp, a10, a11), F.fadd(1n+pp, a9, neg(pp, a21))), F.fmul(1n+pp, F.fadd(1n+pp, 1n, neg(pp, kbit(pp, a10, a11))), F.fadd(1n+pp, a9, a21))), h1),
    E.boolean(pp, kbit(pp, a10, a11), nzd, l1, E.le_fadd(pp, a10, neg(pp, F.fmul(1n+pp, 2n, a11))),
      E.strip_inv(pp, sel, bodybool(pp, kbit(pp, a10, a11)), si, inv, E.le_fmul(pp, kbit(pp, a10, a11), F.fadd(1n+pp, 1n, neg(pp, kbit(pp, a10, a11)))), h0)))

# Gate 26: out == mux(swap, x, y) from out - mux(swap, x, y) == 0.
def swap_out(+pp: Nat, +sel: Nat, +si: Nat, +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}, +w: Nat, +x: Nat, +y: Nat, +o: Nat, +lo: L.Le(o, pp),
    h: {F.fmul(1n+pp, sel, F.fadd(1n+pp, o, neg(pp, E.mux(pp, w, x, y)))) == 0n : Nat}) -> {o == E.mux(pp, w, x, y) : Nat}:
  F.neg_zero(pp, o, E.mux(pp, w, x, y), lo, E.le_fadd(pp, F.fmul(1n+pp, w, x), F.fmul(1n+pp, F.fadd(1n+pp, 1n, neg(pp, w)), y)),
    E.strip_inv(pp, sel, F.fadd(1n+pp, o, neg(pp, E.mux(pp, w, x, y))), si, inv, E.le_fadd(pp, o, neg(pp, E.mux(pp, w, x, y))), h))

def swap_0(+pp: Nat, +l1: L.Le(1n, pp), +a0: Nat, +a1: Nat, +a2: Nat, +a3: Nat, +a4: Nat, +la0: L.Le(a0, pp), +la1: L.Le(a1, pp),
    o2: {a2 == E.mux(pp, a4, a1, a0) : Nat}, o3: {a3 == E.mux(pp, a4, a0, a1) : Nat},
    +z: {a4 == 0n : Nat}) -> {a4 == 0n : Nat} & {a2 == a0 : Nat} & {a3 == a1 : Nat}:
  (z,
    Equal.trans(Nat, a2, E.mux(pp, a4, a1, a0), a0, o2, Equal.trans(Nat, E.mux(pp, a4, a1, a0), E.mux(pp, 0n, a1, a0), a0, E.mux_at(pp, a4, 0n, a1, a0, z), E.mux_0(pp, a1, a0, l1, la0))),
    Equal.trans(Nat, a3, E.mux(pp, a4, a0, a1), a1, o3, Equal.trans(Nat, E.mux(pp, a4, a0, a1), E.mux(pp, 0n, a0, a1), a1, E.mux_at(pp, a4, 0n, a0, a1, z), E.mux_0(pp, a0, a1, l1, la1))))

def swap_1(+pp: Nat, +l1: L.Le(1n, pp), +a0: Nat, +a1: Nat, +a2: Nat, +a3: Nat, +a4: Nat, +la0: L.Le(a0, pp), +la1: L.Le(a1, pp),
    o2: {a2 == E.mux(pp, a4, a1, a0) : Nat}, o3: {a3 == E.mux(pp, a4, a0, a1) : Nat},
    +z: {a4 == 1n : Nat}) -> {a4 == 1n : Nat} & {a2 == a1 : Nat} & {a3 == a0 : Nat}:
  (z,
    Equal.trans(Nat, a2, E.mux(pp, a4, a1, a0), a1, o2, Equal.trans(Nat, E.mux(pp, a4, a1, a0), E.mux(pp, 1n, a1, a0), a1, E.mux_at(pp, a4, 1n, a1, a0, z), E.mux_1(pp, a1, a0, la1))),
    Equal.trans(Nat, a3, E.mux(pp, a4, a0, a1), a0, o3, Equal.trans(Nat, E.mux(pp, a4, a0, a1), E.mux(pp, 1n, a0, a1), a0, E.mux_at(pp, a4, 1n, a0, a1, z), E.mux_1(pp, a0, a1, la0))))

def swap_go(+pp: Nat, +l1: L.Le(1n, pp), +a0: Nat, +a1: Nat, +a2: Nat, +a3: Nat, +a4: Nat, +la0: L.Le(a0, pp), +la1: L.Le(a1, pp),
    o2: {a2 == E.mux(pp, a4, a1, a0) : Nat}, o3: {a3 == E.mux(pp, a4, a0, a1) : Nat},
    e: Either<&1, &1, {a4 == 0n : Nat}, {a4 == 1n : Nat}>)
    -> Either<&1, &1, {a4 == 0n : Nat} & {a2 == a0 : Nat} & {a3 == a1 : Nat}, {a4 == 1n : Nat} & {a2 == a1 : Nat} & {a3 == a0 : Nat}>:
  match e:
    case Inl{z}:
      Inl{swap_0(pp, l1, a0, a1, a2, a3, a4, la0, la1, o2, o3, z)}
    case Inr{z}:
      Inr{swap_1(pp, l1, a0, a1, a2, a3, a4, la0, la1, o2, o3, z)}

def Laws.cond_swap(pp, nzd, l1, sel, si, inv, a0, a1, a2, a3, a4, la0, la1, la2, la3, la4, h0, h1, h2):
  swap_go(pp, l1, a0, a1, a2, a3, a4, la0, la1,
    swap_out(pp, sel, si, inv, a4, a1, a0, a2, la2, h0),
    swap_out(pp, sel, si, inv, a4, a0, a1, a3, la3, h1),
    E.boolean(pp, a4, nzd, l1, la4,
      E.strip_inv(pp, sel, bodybool(pp, a4), si, inv, E.le_fmul(pp, a4, F.fadd(1n+pp, 1n, neg(pp, a4))), h2)))
