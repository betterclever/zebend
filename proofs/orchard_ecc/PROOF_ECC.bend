import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L
import ../orchard/fieldmodel.bend as F
import ../orchard/evals.bend as E
import ../orchard/rowlemmas.bend as R
import ../orchard/nzd11.bend as Z
import ./gates_model.bend as G
import ./ECC.bend as Laws

# Proofs of ECC.bend. Each strips the invertible selector (E.strip_inv), then either
# replaces a guard by 1 (R.guard_one: x == 0 makes 1 - x y equal 1) and drops it
# (R.one_mul_zero), or strips an invertible factor the same way as the selector, and
# finally moves negations across (F.neg_zero). Incomplete addition multiplies through by
# the inverse of x_p - x_q (R.cancel, R.rearr1, R.rearr2).

def neg(+pp: Nat, +x: Nat) -> Nat:
  F.fsub(1n+pp, 0n, x)

# u - v == 0 behind a guard g that equals 1: u == v.
def guarded(+pp: Nat, +g: Nat, +u: Nat, +v: Nat, +lu: L.Le(u, pp), +lv: L.Le(v, pp), +g1: {g == 1n : Nat},
    h: {F.fmul(1n+pp, g, F.fadd(1n+pp, u, neg(pp, v))) == 0n : Nat}) -> {u == v : Nat}:
  F.neg_zero(pp, u, v, lu, lv, R.one_mul_zero(pp, g, F.fadd(1n+pp, u, neg(pp, v)), E.le_fadd(pp, u, neg(pp, v)), g1, h))

def strip(+pp: Nat, +sel: Nat, +si: Nat, +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}, +x: Nat, +y: Nat,
    h: {F.fmul(1n+pp, sel, F.fmul(1n+pp, x, y)) == 0n : Nat}) -> {F.fmul(1n+pp, x, y) == 0n : Nat}:
  E.strip_inv(pp, sel, F.fmul(1n+pp, x, y), si, inv, E.le_fmul(pp, x, y), h)

def Laws.cadd_p_identity(pp, l1, sel, si, inv, a0, a2, a3, a6, a12, a13, la2, la3, la12, la13, z, h6, h7):
  (guarded(pp, F.fadd(1n+pp, 1n, neg(pp, F.fmul(1n+pp, a0, a6))), a12, a2, la12, la2, R.guard_one(pp, l1, a0, a6, z),
     strip(pp, sel, si, inv, F.fadd(1n+pp, 1n, neg(pp, F.fmul(1n+pp, a0, a6))), F.fadd(1n+pp, a12, neg(pp, a2)), h6)),
   guarded(pp, F.fadd(1n+pp, 1n, neg(pp, F.fmul(1n+pp, a0, a6))), a13, a3, la13, la3, R.guard_one(pp, l1, a0, a6, z),
     strip(pp, sel, si, inv, F.fadd(1n+pp, 1n, neg(pp, F.fmul(1n+pp, a0, a6))), F.fadd(1n+pp, a13, neg(pp, a3)), h7)))

def Laws.cadd_p_identity_satisfiable():
  ((9n, {==}), {==}, (7n, {==}), (6n, {==}), (7n, {==}), (6n, {==}), {==}, {==}, {==})

def Laws.cadd_q_identity(pp, l1, sel, si, inv, a0, a1, a2, a7, a12, a13, la0, la1, la12, la13, z, h8, h9):
  (guarded(pp, F.fadd(1n+pp, 1n, neg(pp, F.fmul(1n+pp, a2, a7))), a12, a0, la12, la0, R.guard_one(pp, l1, a2, a7, z),
     strip(pp, sel, si, inv, F.fadd(1n+pp, 1n, neg(pp, F.fmul(1n+pp, a2, a7))), F.fadd(1n+pp, a12, neg(pp, a0)), h8)),
   guarded(pp, F.fadd(1n+pp, 1n, neg(pp, F.fmul(1n+pp, a2, a7))), a13, a1, la13, la1, R.guard_one(pp, l1, a2, a7, z),
     strip(pp, sel, si, inv, F.fadd(1n+pp, 1n, neg(pp, F.fmul(1n+pp, a2, a7))), F.fadd(1n+pp, a13, neg(pp, a1)), h9)))

def Laws.cadd_q_identity_satisfiable():
  ((9n, {==}), {==}, (7n, {==}), (6n, {==}), (7n, {==}), (6n, {==}), {==}, {==}, {==})

# The guard of "6a"/"6b": (1 - (x_q - x_p) alpha) - (y_q + y_p) delta.
def g6(+pp: Nat, +a0: Nat, +a1: Nat, +a2: Nat, +a3: Nat, +a5: Nat, +a8: Nat) -> Nat:
  F.fadd(1n+pp, F.fadd(1n+pp, 1n, neg(pp, F.fmul(1n+pp, F.fadd(1n+pp, a2, neg(pp, a0)), a5))), neg(pp, F.fmul(1n+pp, F.fadd(1n+pp, a3, a1), a8)))

def g6_one(+pp: Nat, +l1: L.Le(1n, pp), +a0: Nat, +a1: Nat, +a2: Nat, +a3: Nat, +a5: Nat, +a8: Nat, +la0: L.Le(a0, pp),
    +zx: {a2 == a0 : Nat}, +zy: {F.fadd(1n+pp, a3, a1) == 0n : Nat}) -> {g6(pp, a0, a1, a2, a3, a5, a8) == 1n : Nat}:
  R.guard_one2(pp, l1, F.fadd(1n+pp, a2, neg(pp, a0)), a5, F.fadd(1n+pp, a3, a1), a8, R.sub_self(pp, a2, a0, la0, zx), zy)

def Laws.cadd_inverse(pp, l1, sel, si, inv, a0, a1, a2, a3, a5, a8, a12, a13, la0, la12, la13, zx, zy, h10, h11):
  (R.one_mul_zero(pp, g6(pp, a0, a1, a2, a3, a5, a8), a12, la12, g6_one(pp, l1, a0, a1, a2, a3, a5, a8, la0, zx, zy),
     strip(pp, sel, si, inv, g6(pp, a0, a1, a2, a3, a5, a8), a12, h10)),
   R.one_mul_zero(pp, g6(pp, a0, a1, a2, a3, a5, a8), a13, la13, g6_one(pp, l1, a0, a1, a2, a3, a5, a8, la0, zx, zy),
     strip(pp, sel, si, inv, g6(pp, a0, a1, a2, a3, a5, a8), a13, h11)))

def Laws.cadd_inverse_satisfiable():
  ((9n, {==}), {==}, (7n, {==}), (10n, {==}), (10n, {==}), {==}, {==}, {==}, {==})

# x * body == 0 with x invertible: body == 0.
def unfactor(+pp: Nat, +x: Nat, +xi: Nat, +hx: {F.fmul(1n+pp, xi, x) == 1n : Nat}, +body: Nat, +lb: L.Le(body, pp),
    h: {F.fmul(1n+pp, x, body) == 0n : Nat}) -> {body == 0n : Nat}:
  E.strip_inv(pp, x, body, xi, hx, lb, h)

# The output rows "3a" / "3b" (and "3c" / "3d"): x_r and y_r from lambda.
def xr_of(+pp: Nat, +a0: Nat, +a2: Nat, +a4: Nat, +a12: Nat, +la12: L.Le(a12, pp),
    z: {F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a4, a4), neg(pp, a0)), neg(pp, a2)), neg(pp, a12)) == 0n : Nat})
    -> {F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a4, a4), neg(pp, a0)), neg(pp, a2)) == a12 : Nat}:
  F.neg_zero(pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a4, a4), neg(pp, a0)), neg(pp, a2)), a12, E.le_fadd(pp, F.fadd(1n+pp, F.fmul(1n+pp, a4, a4), neg(pp, a0)), neg(pp, a2)), la12, z)

def yr_of(+pp: Nat, +a0: Nat, +a1: Nat, +a4: Nat, +a12: Nat, +a13: Nat, +la13: L.Le(a13, pp),
    z: {F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a4, F.fadd(1n+pp, a0, neg(pp, a12))), neg(pp, a1)), neg(pp, a13)) == 0n : Nat})
    -> {F.fadd(1n+pp, F.fmul(1n+pp, a4, F.fadd(1n+pp, a0, neg(pp, a12))), neg(pp, a1)) == a13 : Nat}:
  F.neg_zero(pp, F.fadd(1n+pp, F.fmul(1n+pp, a4, F.fadd(1n+pp, a0, neg(pp, a12))), neg(pp, a1)), a13, E.le_fadd(pp, F.fmul(1n+pp, a4, F.fadd(1n+pp, a0, neg(pp, a12))), neg(pp, a1)), la13, z)

def Laws.cadd_distinct(pp, l1, sel, si, inv, a0, a1, a2, a3, a4, a12, a13, la12, la13, ip, hp, iq, hq, id, hd, h0, h2, h3):
  +d = F.fadd(1n+pp, a2, neg(pp, a0))
  +m = F.fmul(1n+pp, F.fmul(1n+pp, a0, a2), d)
  +mi = F.fmul(1n+pp, F.fmul(1n+pp, ip, iq), id)
  +hm = R.inv_mul(pp, l1, F.fmul(1n+pp, a0, a2), F.fmul(1n+pp, ip, iq), d, id, R.inv_mul(pp, l1, a0, ip, a2, iq, hp, hq), hd)
  +xb = F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a4, a4), neg(pp, a0)), neg(pp, a2)), neg(pp, a12))
  +yb = F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a4, F.fadd(1n+pp, a0, neg(pp, a12))), neg(pp, a1)), neg(pp, a13))
  +w = F.fadd(1n+pp, F.fmul(1n+pp, d, a4), neg(pp, F.fadd(1n+pp, a3, neg(pp, a1))))
  (F.neg_zero(pp, F.fmul(1n+pp, d, a4), F.fadd(1n+pp, a3, neg(pp, a1)), E.le_fmul(pp, d, a4), E.le_fadd(pp, a3, neg(pp, a1)),
     unfactor(pp, d, id, hd, w, E.le_fadd(pp, F.fmul(1n+pp, d, a4), neg(pp, F.fadd(1n+pp, a3, neg(pp, a1)))), strip(pp, sel, si, inv, d, w, h0))),
   xr_of(pp, a0, a2, a4, a12, la12, unfactor(pp, m, mi, hm, xb, E.le_fadd(pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a4, a4), neg(pp, a0)), neg(pp, a2)), neg(pp, a12)), strip(pp, sel, si, inv, m, xb, h2))),
   yr_of(pp, a0, a1, a4, a12, a13, la13, unfactor(pp, m, mi, hm, yb, E.le_fadd(pp, F.fadd(1n+pp, F.fmul(1n+pp, a4, F.fadd(1n+pp, a0, neg(pp, a12))), neg(pp, a1)), neg(pp, a13)), strip(pp, sel, si, inv, m, yb, h3))))

def Laws.cadd_distinct_satisfiable():
  ((9n, {==}), {==}, (10n, {==}), (5n, {==}), {==}, {==}, {==}, {==}, {==}, {==})

def Laws.cadd_double(pp, l1, sel, si, inv, a0, a1, a2, a3, a4, a5, a12, a13, la0, la12, la13, zx, ip, hp, iq, hq, iy, hs, h1, h4, h5):
  +g = F.fadd(1n+pp, 1n, neg(pp, F.fmul(1n+pp, F.fadd(1n+pp, a2, neg(pp, a0)), a5)))
  +u = F.fmul(1n+pp, F.fmul(1n+pp, 2n, a1), a4)
  +v = F.fmul(1n+pp, 3n, F.fmul(1n+pp, a0, a0))
  +m = F.fmul(1n+pp, F.fmul(1n+pp, a0, a2), F.fadd(1n+pp, a3, a1))
  +mi = F.fmul(1n+pp, F.fmul(1n+pp, ip, iq), iy)
  +hm = R.inv_mul(pp, l1, F.fmul(1n+pp, a0, a2), F.fmul(1n+pp, ip, iq), F.fadd(1n+pp, a3, a1), iy, R.inv_mul(pp, l1, a0, ip, a2, iq, hp, hq), hs)
  +xb = F.fadd(1n+pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a4, a4), neg(pp, a0)), neg(pp, a2)), neg(pp, a12))
  +yb = F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a4, F.fadd(1n+pp, a0, neg(pp, a12))), neg(pp, a1)), neg(pp, a13))
  (guarded(pp, g, u, v, E.le_fmul(pp, F.fmul(1n+pp, 2n, a1), a4), E.le_fmul(pp, 3n, F.fmul(1n+pp, a0, a0)),
     R.guard_one(pp, l1, F.fadd(1n+pp, a2, neg(pp, a0)), a5, R.sub_self(pp, a2, a0, la0, zx)),
     strip(pp, sel, si, inv, g, F.fadd(1n+pp, u, neg(pp, v)), h1)),
   xr_of(pp, a0, a2, a4, a12, la12, unfactor(pp, m, mi, hm, xb, E.le_fadd(pp, F.fadd(1n+pp, F.fadd(1n+pp, F.fmul(1n+pp, a4, a4), neg(pp, a0)), neg(pp, a2)), neg(pp, a12)), strip(pp, sel, si, inv, m, xb, h4))),
   yr_of(pp, a0, a1, a4, a12, a13, la13, unfactor(pp, m, mi, hm, yb, E.le_fadd(pp, F.fadd(1n+pp, F.fmul(1n+pp, a4, F.fadd(1n+pp, a0, neg(pp, a12))), neg(pp, a1)), neg(pp, a13)), strip(pp, sel, si, inv, m, yb, h5))))

def Laws.cadd_double_satisfiable():
  ((9n, {==}), {==}, (8n, {==}), (10n, {==}), (9n, {==}), {==}, {==}, {==}, {==}, {==}, {==}, {==})

# --- incomplete addition -------------------------------------------------------------------

def Laws.incomplete_add(pp, sel, si, inv, a0, a1, a2, a3, a12, a13, di, hd, h0, h1):
  +d = F.fadd(1n+pp, a0, neg(pp, a2))
  +dy = F.fadd(1n+pp, a1, neg(pp, a3))
  +lam = F.fmul(1n+pp, dy, di)
  +s = F.fadd(1n+pp, F.fadd(1n+pp, a12, a2), a0)
  +y = F.fadd(1n+pp, a13, a3)
  +e = F.fadd(1n+pp, a2, neg(pp, a12))
  +sdd = F.fmul(1n+pp, F.fmul(1n+pp, s, d), d)
  +q0 = F.neg_zero(pp, sdd, F.fmul(1n+pp, dy, dy), E.le_fmul(pp, F.fmul(1n+pp, s, d), d), E.le_fmul(pp, dy, dy),
          E.strip_inv(pp, sel, F.fadd(1n+pp, sdd, neg(pp, F.fmul(1n+pp, dy, dy))), si, inv, E.le_fadd(pp, sdd, neg(pp, F.fmul(1n+pp, dy, dy))), h0))
  +q1 = F.neg_zero(pp, F.fmul(1n+pp, y, d), F.fmul(1n+pp, dy, e), E.le_fmul(pp, y, d), E.le_fmul(pp, dy, e),
          E.strip_inv(pp, sel, F.fadd(1n+pp, F.fmul(1n+pp, y, d), neg(pp, F.fmul(1n+pp, dy, e))), si, inv, E.le_fadd(pp, F.fmul(1n+pp, y, d), neg(pp, F.fmul(1n+pp, dy, e))), h1))
  (Equal.trans(Nat, s, F.fmul(1n+pp, F.fmul(1n+pp, s, d), di), F.fmul(1n+pp, lam, lam),
     Equal.sym(Nat, F.fmul(1n+pp, F.fmul(1n+pp, s, d), di), s, R.cancel(pp, s, d, di, hd, E.le_fadd(pp, F.fadd(1n+pp, a12, a2), a0))),
   Equal.trans(Nat, F.fmul(1n+pp, F.fmul(1n+pp, s, d), di), F.fmul(1n+pp, F.fmul(1n+pp, sdd, di), di), F.fmul(1n+pp, lam, lam),
     Equal.cong(Nat, Nat, w => F.fmul(1n+pp, w, di), F.fmul(1n+pp, s, d), F.fmul(1n+pp, sdd, di),
       Equal.sym(Nat, F.fmul(1n+pp, sdd, di), F.fmul(1n+pp, s, d), R.cancel(pp, F.fmul(1n+pp, s, d), d, di, hd, E.le_fmul(pp, s, d)))),
   Equal.trans(Nat, F.fmul(1n+pp, F.fmul(1n+pp, sdd, di), di), F.fmul(1n+pp, F.fmul(1n+pp, F.fmul(1n+pp, dy, dy), di), di), F.fmul(1n+pp, lam, lam),
     Equal.cong(Nat, Nat, w => F.fmul(1n+pp, F.fmul(1n+pp, w, di), di), sdd, F.fmul(1n+pp, dy, dy), q0),
     R.rearr2(pp, dy, di)))),
   Equal.trans(Nat, y, F.fmul(1n+pp, F.fmul(1n+pp, y, d), di), F.fmul(1n+pp, lam, e),
     Equal.sym(Nat, F.fmul(1n+pp, F.fmul(1n+pp, y, d), di), y, R.cancel(pp, y, d, di, hd, E.le_fadd(pp, a13, a3))),
   Equal.trans(Nat, F.fmul(1n+pp, F.fmul(1n+pp, y, d), di), F.fmul(1n+pp, F.fmul(1n+pp, dy, e), di), F.fmul(1n+pp, lam, e),
     Equal.cong(Nat, Nat, w => F.fmul(1n+pp, w, di), F.fmul(1n+pp, y, d), F.fmul(1n+pp, dy, e), q1),
     R.rearr1(pp, dy, e, di))))

def Laws.incomplete_add_satisfiable():
  ({==}, {==}, {==}, {==})

# --- LSB check -----------------------------------------------------------------------------

def mux0(+pp: Nat, +l1: L.Le(1n, pp), +w: Nat, +x: Nat, +y: Nat, +ly: L.Le(y, pp), +z: {w == 0n : Nat},
    m: {E.mux(pp, w, x, y) == 0n : Nat}) -> {y == 0n : Nat}:
  Equal.trans(Nat, y, E.mux(pp, 0n, x, y), 0n, Equal.sym(Nat, E.mux(pp, 0n, x, y), y, E.mux_0(pp, x, y, l1, ly)),
    Equal.trans(Nat, E.mux(pp, 0n, x, y), E.mux(pp, w, x, y), 0n, Equal.sym(Nat, E.mux(pp, w, x, y), E.mux(pp, 0n, x, y), E.mux_at(pp, w, 0n, x, y, z)), m))

def mux1(+pp: Nat, +w: Nat, +x: Nat, +y: Nat, +lx: L.Le(x, pp), +z: {w == 1n : Nat},
    m: {E.mux(pp, w, x, y) == 0n : Nat}) -> {x == 0n : Nat}:
  Equal.trans(Nat, x, E.mux(pp, 1n, x, y), 0n, Equal.sym(Nat, E.mux(pp, 1n, x, y), x, E.mux_1(pp, x, y, lx)),
    Equal.trans(Nat, E.mux(pp, 1n, x, y), E.mux(pp, w, x, y), 0n, Equal.sym(Nat, E.mux(pp, w, x, y), E.mux(pp, 1n, x, y), E.mux_at(pp, w, 1n, x, y, z)), m))

def kb(+pp: Nat, +a9: Nat, +a10: Nat) -> Nat:
  F.fadd(1n+pp, a10, neg(pp, F.fmul(1n+pp, a9, 2n)))

def lsb_go(+pp: Nat, +l1: L.Le(1n, pp), +a0: Nat, +a1: Nat, +a9: Nat, +a10: Nat, +a16: Nat, +a17: Nat, +la0: L.Le(a0, pp), +la1: L.Le(a1, pp), +la16: L.Le(a16, pp),
    m1: {E.mux(pp, kb(pp, a9, a10), a0, F.fadd(1n+pp, a0, neg(pp, a16))) == 0n : Nat},
    m2: {E.mux(pp, kb(pp, a9, a10), a1, F.fadd(1n+pp, a1, a17)) == 0n : Nat},
    e: Either<&1, &1, {kb(pp, a9, a10) == 0n : Nat}, {kb(pp, a9, a10) == 1n : Nat}>)
    -> Either<&1, &1, {kb(pp, a9, a10) == 0n : Nat} & {a0 == a16 : Nat} & {F.fadd(1n+pp, a1, a17) == 0n : Nat}, {kb(pp, a9, a10) == 1n : Nat} & {a0 == 0n : Nat} & {a1 == 0n : Nat}>:
  match e:
    case Inl{+z}:
      Inl{(z, F.neg_zero(pp, a0, a16, la0, la16, mux0(pp, l1, kb(pp, a9, a10), a0, F.fadd(1n+pp, a0, neg(pp, a16)), E.le_fadd(pp, a0, neg(pp, a16)), z, m1)),
          mux0(pp, l1, kb(pp, a9, a10), a1, F.fadd(1n+pp, a1, a17), E.le_fadd(pp, a1, a17), z, m2))}
    case Inr{+z}:
      Inr{(z, mux1(pp, kb(pp, a9, a10), a0, F.fadd(1n+pp, a0, neg(pp, a16)), la0, z, m1), mux1(pp, kb(pp, a9, a10), a1, F.fadd(1n+pp, a1, a17), la1, z, m2))}

def Laws.lsb_check(pp, nzd, l1, sel, si, inv, a0, a1, a9, a10, a16, a17, la0, la1, la16, h0, h1, h2):
  +k = kb(pp, a9, a10)
  lsb_go(pp, l1, a0, a1, a9, a10, a16, a17, la0, la1, la16,
    E.strip_inv(pp, sel, E.mux(pp, k, a0, F.fadd(1n+pp, a0, neg(pp, a16))), si, inv, E.le_fadd(pp, F.fmul(1n+pp, k, a0), F.fmul(1n+pp, F.fadd(1n+pp, 1n, neg(pp, k)), F.fadd(1n+pp, a0, neg(pp, a16)))), h1),
    E.strip_inv(pp, sel, E.mux(pp, k, a1, F.fadd(1n+pp, a1, a17)), si, inv, E.le_fadd(pp, F.fmul(1n+pp, k, a1), F.fmul(1n+pp, F.fadd(1n+pp, 1n, neg(pp, k)), F.fadd(1n+pp, a1, a17))), h2),
    E.boolean(pp, k, nzd, l1, E.le_fadd(pp, a10, neg(pp, F.fmul(1n+pp, a9, 2n))),
      E.strip_inv(pp, sel, F.fmul(1n+pp, k, F.fadd(1n+pp, 1n, neg(pp, k))), si, inv, E.le_fmul(pp, k, F.fadd(1n+pp, 1n, neg(pp, k))), h0)))

def Laws.lsb_check_satisfiable():
  (Z.nzd11, (9n, {==}), {==}, (7n, {==}), (6n, {==}), (7n, {==}), {==}, {==}, {==})

# --- short fixed-base sign -----------------------------------------------------------------

# s s == 1 (mod p)  ==>  (s - 1)(s + 1) == 0, by computing (s + pp)(s + 1) over Nat.
law sq_one:
  for +pp: Nat
  for +s: Nat
  for +hs: {Nat.mod(Nat.mul(s, s), 1n+pp) == 1n : Nat}
  {Nat.mod(Nat.mul(Nat.add(s, pp), Nat.add(s, 1n)), 1n+pp) == 0n : Nat}

def sq_one(pp, s, hs):
  # (s + pp)(s + 1) == (s s + pp) + s (1 + pp)
  %Equal.sym(Nat, Nat.mul(Nat.add(s, pp), Nat.add(s, 1n)), Nat.add(Nat.mul(s, Nat.add(s, 1n)), Nat.mul(pp, Nat.add(s, 1n))), L.mul_add_r(s, pp, Nat.add(s, 1n))) : {Nat.mod(_, 1n+pp) == 0n : Nat}
  %Equal.sym(Nat, Nat.mul(s, Nat.add(s, 1n)), Nat.add(Nat.mul(s, s), Nat.mul(s, 1n)), L.mul_add_l(s, s, 1n)) : {Nat.mod(Nat.add(_, Nat.mul(pp, Nat.add(s, 1n))), 1n+pp) == 0n : Nat}
  %Equal.sym(Nat, Nat.mul(pp, Nat.add(s, 1n)), Nat.add(Nat.mul(pp, s), Nat.mul(pp, 1n)), L.mul_add_l(pp, s, 1n)) : {Nat.mod(Nat.add(Nat.add(Nat.mul(s, s), Nat.mul(s, 1n)), _), 1n+pp) == 0n : Nat}
  %Equal.sym(Nat, Nat.mul(s, 1n), s, L.mul_one_r(s)) : {Nat.mod(Nat.add(Nat.add(Nat.mul(s, s), _), Nat.add(Nat.mul(pp, s), Nat.mul(pp, 1n))), 1n+pp) == 0n : Nat}
  %Equal.sym(Nat, Nat.mul(pp, 1n), pp, L.mul_one_r(pp)) : {Nat.mod(Nat.add(Nat.add(Nat.mul(s, s), s), Nat.add(Nat.mul(pp, s), _)), 1n+pp) == 0n : Nat}
  %N.add_comm(pp, Nat.mul(pp, s)) : {Nat.mod(Nat.add(Nat.add(Nat.mul(s, s), s), _), 1n+pp) == 0n : Nat}
  %N.swap_mid(Nat.mul(s, s), pp, s, Nat.mul(pp, s)) : {Nat.mod(_, 1n+pp) == 0n : Nat}
  %L.mul_comm(s, pp) : {Nat.mod(Nat.add(Nat.add(Nat.mul(s, s), pp), Nat.add(s, _)), 1n+pp) == 0n : Nat}
  %L.mul_succ_r(s, pp) : {Nat.mod(Nat.add(Nat.add(Nat.mul(s, s), pp), _), 1n+pp) == 0n : Nat}
  %Equal.sym(Nat, Nat.mod(Nat.add(Nat.add(Nat.mul(s, s), pp), Nat.mul(s, 1n+pp)), 1n+pp), Nat.mod(Nat.add(Nat.mul(s, s), pp), 1n+pp), L.mod_add_mul(Nat.add(Nat.mul(s, s), pp), s, pp)) : {_ == 0n : Nat}
  %L.mod_add_mod_l(Nat.mul(s, s), pp, pp) : {_ == 0n : Nat}
  %Equal.sym(Nat, Nat.mod(Nat.mul(s, s), 1n+pp), 1n, hs) : {Nat.mod(Nat.add(_, pp), 1n+pp) == 0n : Nat}
  L.mod_add_self(0n, pp)

def le_refl(+pp: Nat) -> L.Le(pp, pp):
  (0n, N.add_zero_r(pp))

# (s - 1)(s + 1) in Fp is the Nat expression of sq_one.
law sq_one_f:
  for +pp: Nat
  for +s: Nat
  {F.fmul(1n+pp, F.fadd(1n+pp, s, F.fsub(1n+pp, 0n, 1n)), F.fadd(1n+pp, s, 1n)) == Nat.mod(Nat.mul(Nat.add(s, pp), Nat.add(s, 1n)), 1n+pp) : Nat}

def sq_one_f(pp, s):
  %Equal.sym(Nat, F.fsub(1n+pp, 0n, 1n), pp, E.fsub_0_1(pp)) : {F.fmul(1n+pp, F.fadd(1n+pp, s, _), F.fadd(1n+pp, s, 1n)) == Nat.mod(Nat.mul(Nat.add(s, pp), Nat.add(s, 1n)), 1n+pp) : Nat}
  Equal.trans(Nat, F.fmul(1n+pp, F.fadd(1n+pp, s, pp), F.fadd(1n+pp, s, 1n)), Nat.mod(Nat.mul(Nat.add(s, pp), F.fadd(1n+pp, s, 1n)), 1n+pp), Nat.mod(Nat.mul(Nat.add(s, pp), Nat.add(s, 1n)), 1n+pp),
    L.mod_mul_mod_l(Nat.add(s, pp), F.fadd(1n+pp, s, 1n), pp), L.mod_mul_mod_r(Nat.add(s, pp), Nat.add(s, 1n), pp))

def sign_go(+pp: Nat, +l1: L.Le(1n, pp), +s: Nat, +ls: L.Le(s, pp),
    e: Either<&1, &1, {F.fadd(1n+pp, s, F.fsub(1n+pp, 0n, 1n)) == 0n : Nat}, {F.fadd(1n+pp, s, 1n) == 0n : Nat}>)
    -> Either<&1, &1, {s == 1n : Nat}, {F.fadd(1n+pp, s, 1n) == 0n : Nat}>:
  match e:
    case Inl{z}:
      Inl{F.neg_zero(pp, s, 1n, ls, l1, z)}
    case Inr{z}:
      Inr{z}

def Laws.short_sign(pp, nzd, l1, sel, si, inv, a4, la4, h):
  +ss = F.neg_zero(pp, F.fmul(1n+pp, a4, a4), 1n, E.le_fmul(pp, a4, a4), l1,
          E.strip_inv(pp, sel, F.fadd(1n+pp, F.fmul(1n+pp, a4, a4), neg(pp, 1n)), si, inv, E.le_fadd(pp, F.fmul(1n+pp, a4, a4), neg(pp, 1n)), h))
  sign_go(pp, l1, a4, la4,
    nzd(F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, 1n)), F.fadd(1n+pp, a4, 1n), E.le_fadd(pp, a4, F.fsub(1n+pp, 0n, 1n)), E.le_fadd(pp, a4, 1n),
      Equal.trans(Nat, F.fmul(1n+pp, F.fadd(1n+pp, a4, F.fsub(1n+pp, 0n, 1n)), F.fadd(1n+pp, a4, 1n)), Nat.mod(Nat.mul(Nat.add(a4, pp), Nat.add(a4, 1n)), 1n+pp), 0n,
        sq_one_f(pp, a4), sq_one(pp, a4, ss))))

def Laws.short_sign_satisfiable():
  (Z.nzd11, (9n, {==}), {==}, (0n, {==}), {==})
