import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L
import ./fieldmodel.bend as F

# Small evaluations in the field model and the two reasoning steps every gadget
# proof uses: stripping a non-zero selector, and booleanity.

law sub_zero:
  for +x: Nat
  {Nat.sub(x, 0n) == x : Nat}

def sub_zero(x):
  match x:
    case 0n:
      {==}
    case 1n+p:
      {==}

def le_refl(+pp: Nat) -> L.Le(pp, pp):
  (0n, N.add_zero_r(pp))

# 0 - 0 == 0
law fsub_0_0:
  for +pp: Nat
  {F.fsub(1n+pp, 0n, 0n) == 0n : Nat}

def fsub_0_0(pp):
  L.mod_add_self(0n, pp)

# 0 - 1 == p - 1
law fsub_0_1:
  for +pp: Nat
  {F.fsub(1n+pp, 0n, 1n) == pp : Nat}

def fsub_0_1(pp):
  %Equal.sym(Nat, Nat.sub(pp, 0n), pp, sub_zero(pp)) : {Nat.mod(_, 1n+pp) == pp : Nat}
  L.mod_small(pp, pp, le_refl(pp))

# 1 + (0 - 1) == 0
law one_minus_one:
  for +pp: Nat
  {F.fadd(1n+pp, 1n, F.fsub(1n+pp, 0n, 1n)) == 0n : Nat}

def one_minus_one(pp):
  %Equal.sym(Nat, F.fsub(1n+pp, 0n, 1n), pp, fsub_0_1(pp)) : {Nat.mod(Nat.add(1n, _), 1n+pp) == 0n : Nat}
  L.mod_add_self(0n, pp)

# 1 + (0 - 0) == 1
law one_minus_zero:
  for +pp: Nat
  for +l1: L.Le(1n, pp)
  {F.fadd(1n+pp, 1n, F.fsub(1n+pp, 0n, 0n)) == 1n : Nat}

def one_minus_zero(pp, l1):
  %Equal.sym(Nat, F.fsub(1n+pp, 0n, 0n), 0n, fsub_0_0(pp)) : {Nat.mod(Nat.add(1n, _), 1n+pp) == 1n : Nat}
  L.mod_small(1n, pp, l1)

law fmul_0:
  for +pp: Nat
  for +y: Nat
  {F.fmul(1n+pp, 0n, y) == 0n : Nat}

def fmul_0(pp, y):
  {==}

law fmul_1:
  for +pp: Nat
  for +y: Nat
  for +ly: L.Le(y, pp)
  {F.fmul(1n+pp, 1n, y) == y : Nat}

def fmul_1(pp, y, ly):
  %Equal.sym(Nat, Nat.mul(1n, y), y, L.mul_one_l(y)) : {Nat.mod(_, 1n+pp) == y : Nat}
  L.mod_small(y, pp, ly)

law fadd_x_0:
  for +pp: Nat
  for +x: Nat
  for +lx: L.Le(x, pp)
  {F.fadd(1n+pp, x, 0n) == x : Nat}

def fadd_x_0(pp, x, lx):
  %Equal.sym(Nat, Nat.add(x, 0n), x, N.add_zero_r(x)) : {Nat.mod(_, 1n+pp) == x : Nat}
  L.mod_small(x, pp, lx)

law fadd_0_x:
  for +pp: Nat
  for +x: Nat
  for +lx: L.Le(x, pp)
  {F.fadd(1n+pp, 0n, x) == x : Nat}

def fadd_0_x(pp, x, lx):
  L.mod_small(x, pp, lx)

# Every field-model operation returns a canonical element.
def le_fadd(+pp: Nat, +x: Nat, +y: Nat) -> L.Le(F.fadd(1n+pp, x, y), pp):
  L.mod_le(Nat.add(x, y), pp)

def le_fsub(+pp: Nat, +x: Nat, +y: Nat) -> L.Le(F.fsub(1n+pp, x, y), pp):
  L.mod_le(Nat.add(x, Nat.sub(1n+pp, y)), pp)

def le_fmul(+pp: Nat, +x: Nat, +y: Nat) -> L.Le(F.fmul(1n+pp, x, y), pp):
  L.mod_le(Nat.mul(x, y), pp)

# A gate is selector * body; with a non-zero selector the body must vanish.
law strip:
  for +pp: Nat
  for +sel: Nat
  for +body: Nat
  for nzd: F.NZD(pp)
  for +ls: L.Le(sel, pp)
  for snz: {sel == 0n : Nat} -> Empty
  for +lb: L.Le(body, pp)
  for h: {F.fmul(1n+pp, sel, body) == 0n : Nat}
  {body == 0n : Nat}

def strip_go(+sel: Nat, +body: Nat, snz: {sel == 0n : Nat} -> Empty, e: Either<&1, &1, {sel == 0n : Nat}, {body == 0n : Nat}>) -> {body == 0n : Nat}:
  match e:
    case Inl{z}:
      Empty.absurd({body == 0n : Nat}, snz(z))
    case Inr{z}:
      z

def strip(pp, sel, body, nzd, ls, snz, lb, h):
  strip_go(sel, body, snz, nzd(sel, body, ls, lb, h))

# b * (1 - b) == 0  ==>  b == 0 or b == 1.
law boolean:
  for +pp: Nat
  for +b: Nat
  for nzd: F.NZD(pp)
  for +l1: L.Le(1n, pp)
  for +lb: L.Le(b, pp)
  for h: {F.fmul(1n+pp, b, F.fadd(1n+pp, 1n, F.fsub(1n+pp, 0n, b))) == 0n : Nat}
  Either<&1, &1, {b == 0n : Nat}, {b == 1n : Nat}>

def boolean_go(+pp: Nat, +b: Nat, +l1: L.Le(1n, pp), +lb: L.Le(b, pp), e: Either<&1, &1, {b == 0n : Nat}, {F.fadd(1n+pp, 1n, F.fsub(1n+pp, 0n, b)) == 0n : Nat}>) -> Either<&1, &1, {b == 0n : Nat}, {b == 1n : Nat}>:
  match e:
    case Inl{z}:
      Inl{z}
    case Inr{z}:
      Inr{Equal.sym(Nat, 1n, b, F.neg_zero(pp, 1n, b, l1, lb, z))}

def boolean(pp, b, nzd, l1, lb, h):
  boolean_go(pp, b, l1, lb, nzd(b, F.fadd(1n+pp, 1n, F.fsub(1n+pp, 0n, b)), lb, le_fadd(pp, 1n, F.fsub(1n+pp, 0n, b)), h))

# w * x + (1 - w) * y: the selection shape of the y_switch and conditional-swap gates.
def mux(+pp: Nat, +w: Nat, +x: Nat, +y: Nat) -> Nat:
  F.fadd(1n+pp, F.fmul(1n+pp, w, x), F.fmul(1n+pp, F.fadd(1n+pp, 1n, F.fsub(1n+pp, 0n, w)), y))

law mux_at:
  for +pp: Nat
  for +w: Nat
  for +c: Nat
  for +x: Nat
  for +y: Nat
  for z: {w == c : Nat}
  {mux(pp, w, x, y) == mux(pp, c, x, y) : Nat}

def mux_at(pp, w, c, x, y, z):
  Equal.cong(Nat, Nat, v => mux(pp, v, x, y), w, c, z)

# mux(0, x, y) == y
law mux_0:
  for +pp: Nat
  for +x: Nat
  for +y: Nat
  for +l1: L.Le(1n, pp)
  for +ly: L.Le(y, pp)
  {mux(pp, 0n, x, y) == y : Nat}

def mux_0(pp, x, y, l1, ly):
  %Equal.sym(Nat, F.fmul(1n+pp, 0n, x), 0n, fmul_0(pp, x)) : {F.fadd(1n+pp, _, F.fmul(1n+pp, F.fadd(1n+pp, 1n, F.fsub(1n+pp, 0n, 0n)), y)) == y : Nat}
  %Equal.sym(Nat, F.fadd(1n+pp, 1n, F.fsub(1n+pp, 0n, 0n)), 1n, one_minus_zero(pp, l1)) : {F.fadd(1n+pp, 0n, F.fmul(1n+pp, _, y)) == y : Nat}
  %Equal.sym(Nat, F.fmul(1n+pp, 1n, y), y, fmul_1(pp, y, ly)) : {F.fadd(1n+pp, 0n, _) == y : Nat}
  fadd_0_x(pp, y, ly)

# mux(1, x, y) == x
law mux_1:
  for +pp: Nat
  for +x: Nat
  for +y: Nat
  for +lx: L.Le(x, pp)
  {mux(pp, 1n, x, y) == x : Nat}

def mux_1(pp, x, y, lx):
  %Equal.sym(Nat, F.fmul(1n+pp, 1n, x), x, fmul_1(pp, x, lx)) : {F.fadd(1n+pp, _, F.fmul(1n+pp, F.fadd(1n+pp, 1n, F.fsub(1n+pp, 0n, 1n)), y)) == x : Nat}
  %Equal.sym(Nat, F.fadd(1n+pp, 1n, F.fsub(1n+pp, 0n, 1n)), 0n, one_minus_one(pp)) : {F.fadd(1n+pp, x, F.fmul(1n+pp, _, y)) == x : Nat}
  %Equal.sym(Nat, F.fmul(1n+pp, 0n, y), 0n, fmul_0(pp, y)) : {F.fadd(1n+pp, x, _) == x : Nat}
  fadd_x_0(pp, x, lx)

# A gate is selector * body; with an invertible selector (in Fp: a non-zero one) the
# body must vanish. Unlike E.strip this needs no use of the prime hypothesis, so a law
# can strip several gates and still use NZD once (a function hypothesis is affine).
law strip_inv:
  for +pp: Nat
  for +sel: Nat
  for +body: Nat
  for +si: Nat
  for +inv: {F.fmul(1n+pp, si, sel) == 1n : Nat}
  for +lb: L.Le(body, pp)
  for h: {F.fmul(1n+pp, sel, body) == 0n : Nat}
  {body == 0n : Nat}

def strip_inv(pp, sel, body, si, inv, lb, h):
  %L.mod_small(body, pp, lb) : {_ == 0n : Nat}
  %L.mul_one_l(body) : {Nat.mod(_, 1n+pp) == 0n : Nat}
  %inv : {Nat.mod(Nat.mul(_, body), 1n+pp) == 0n : Nat}
  %Equal.sym(Nat, Nat.mod(Nat.mul(Nat.mod(Nat.mul(si, sel), 1n+pp), body), 1n+pp), Nat.mod(Nat.mul(Nat.mul(si, sel), body), 1n+pp), L.mod_mul_mod_l(Nat.mul(si, sel), body, pp)) : {_ == 0n : Nat}
  %Equal.sym(Nat, Nat.mul(Nat.mul(si, sel), body), Nat.mul(si, Nat.mul(sel, body)), L.mul_assoc(si, sel, body)) : {Nat.mod(_, 1n+pp) == 0n : Nat}
  %L.mod_mul_mod_r(si, Nat.mul(sel, body), pp) : {_ == 0n : Nat}
  %Equal.sym(Nat, F.fmul(1n+pp, sel, body), 0n, h) : {Nat.mod(Nat.mul(si, _), 1n+pp) == 0n : Nat}
  %Equal.sym(Nat, Nat.mul(si, 0n), 0n, L.mul_zero_r(si)) : {Nat.mod(_, 1n+pp) == 0n : Nat}
  {==}
