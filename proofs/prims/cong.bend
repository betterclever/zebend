import Base
import ../field/natlemmas.bend as N
import ./natlib.bend as L

# Congruence modulo P: x and y differ by a multiple of P on each side,
# x + q1 * P == y + q2 * P. An equivalence, compatible with + and with
# multiplication by a constant.
def Cg(P: Nat, x: Nat, y: Nat) -> Data:
  Sigma<&2, &2, Nat, q1 => Sigma<&2, &2, Nat, q2 => {Nat.add(x, Nat.mul(q1, P)) == Nat.add(y, Nat.mul(q2, P)) : Nat}>>

def cg_eq(+P: Nat, +x: Nat, +y: Nat, e: {x == y : Nat}) -> Cg(P, x, y):
  (0n, (0n, Equal.cong(Nat, Nat, w => Nat.add(w, Nat.mul(0n, P)), x, y, e)))

# x + k * P == y gives x ~ y.
def cg_of(+P: Nat, +x: Nat, +y: Nat, +k: Nat, h: {Nat.add(x, Nat.mul(k, P)) == y : Nat}) -> Cg(P, x, y):
  (k, (0n, Equal.trans(Nat, Nat.add(x, Nat.mul(k, P)), y, Nat.add(y, 0n), h, Equal.sym(Nat, Nat.add(y, 0n), y, N.add_zero_r(y)))))

def cg_trans_go(+P: Nat, +x: Nat, +y: Nat, +z: Nat, +q1: Nat, +q2: Nat, +r1: Nat, +r2: Nat,
    h1: {Nat.add(x, Nat.mul(q1, P)) == Nat.add(y, Nat.mul(q2, P)) : Nat},
    h2: {Nat.add(y, Nat.mul(r1, P)) == Nat.add(z, Nat.mul(r2, P)) : Nat})
    -> {Nat.add(x, Nat.mul(Nat.add(q1, r1), P)) == Nat.add(z, Nat.mul(Nat.add(r2, q2), P)) : Nat}:
  %Equal.sym(Nat, Nat.mul(Nat.add(q1, r1), P), Nat.add(Nat.mul(q1, P), Nat.mul(r1, P)), L.mul_add_r(q1, r1, P)) : {Nat.add(x, _) == Nat.add(z, Nat.mul(Nat.add(r2, q2), P)) : Nat}
  %Equal.sym(Nat, Nat.mul(Nat.add(r2, q2), P), Nat.add(Nat.mul(r2, P), Nat.mul(q2, P)), L.mul_add_r(r2, q2, P)) : {Nat.add(x, Nat.add(Nat.mul(q1, P), Nat.mul(r1, P))) == Nat.add(z, _) : Nat}
  %N.add_assoc(x, Nat.mul(q1, P), Nat.mul(r1, P)) : {_ == Nat.add(z, Nat.add(Nat.mul(r2, P), Nat.mul(q2, P))) : Nat}
  %N.add_assoc(z, Nat.mul(r2, P), Nat.mul(q2, P)) : {Nat.add(Nat.add(x, Nat.mul(q1, P)), Nat.mul(r1, P)) == _ : Nat}
  %Equal.sym(Nat, Nat.add(x, Nat.mul(q1, P)), Nat.add(y, Nat.mul(q2, P)), h1) : {Nat.add(_, Nat.mul(r1, P)) == Nat.add(Nat.add(z, Nat.mul(r2, P)), Nat.mul(q2, P)) : Nat}
  %h2 : {Nat.add(Nat.add(y, Nat.mul(q2, P)), Nat.mul(r1, P)) == Nat.add(_, Nat.mul(q2, P)) : Nat}
  L.add_right_comm(y, Nat.mul(q2, P), Nat.mul(r1, P))

def cg_trans(+P: Nat, +x: Nat, +y: Nat, +z: Nat, +c1: Cg(P, x, y), +c2: Cg(P, y, z)) -> Cg(P, x, z):
  (+q1, +r) = c1
  (+q2, h1) = r
  (+s1, +t) = c2
  (+s2, h2) = t
  (Nat.add(q1, s1), (Nat.add(s2, q2), cg_trans_go(P, x, y, z, q1, q2, s1, s2, h1, h2)))

def cg_add_go(+P: Nat, +x: Nat, +u: Nat, +y: Nat, +v: Nat, +q1: Nat, +q2: Nat, +r1: Nat, +r2: Nat,
    h1: {Nat.add(x, Nat.mul(q1, P)) == Nat.add(u, Nat.mul(q2, P)) : Nat},
    h2: {Nat.add(y, Nat.mul(r1, P)) == Nat.add(v, Nat.mul(r2, P)) : Nat})
    -> {Nat.add(Nat.add(x, y), Nat.mul(Nat.add(q1, r1), P)) == Nat.add(Nat.add(u, v), Nat.mul(Nat.add(q2, r2), P)) : Nat}:
  %Equal.sym(Nat, Nat.mul(Nat.add(q1, r1), P), Nat.add(Nat.mul(q1, P), Nat.mul(r1, P)), L.mul_add_r(q1, r1, P)) : {Nat.add(Nat.add(x, y), _) == Nat.add(Nat.add(u, v), Nat.mul(Nat.add(q2, r2), P)) : Nat}
  %Equal.sym(Nat, Nat.mul(Nat.add(q2, r2), P), Nat.add(Nat.mul(q2, P), Nat.mul(r2, P)), L.mul_add_r(q2, r2, P)) : {Nat.add(Nat.add(x, y), Nat.add(Nat.mul(q1, P), Nat.mul(r1, P))) == Nat.add(Nat.add(u, v), _) : Nat}
  %Equal.sym(Nat, Nat.add(Nat.add(x, y), Nat.add(Nat.mul(q1, P), Nat.mul(r1, P))), Nat.add(Nat.add(x, Nat.mul(q1, P)), Nat.add(y, Nat.mul(r1, P))), N.swap_mid(x, y, Nat.mul(q1, P), Nat.mul(r1, P))) : {_ == Nat.add(Nat.add(u, v), Nat.add(Nat.mul(q2, P), Nat.mul(r2, P))) : Nat}
  %Equal.sym(Nat, Nat.add(Nat.add(u, v), Nat.add(Nat.mul(q2, P), Nat.mul(r2, P))), Nat.add(Nat.add(u, Nat.mul(q2, P)), Nat.add(v, Nat.mul(r2, P))), N.swap_mid(u, v, Nat.mul(q2, P), Nat.mul(r2, P))) : {Nat.add(Nat.add(x, Nat.mul(q1, P)), Nat.add(y, Nat.mul(r1, P))) == _ : Nat}
  %Equal.sym(Nat, Nat.add(x, Nat.mul(q1, P)), Nat.add(u, Nat.mul(q2, P)), h1) : {Nat.add(_, Nat.add(y, Nat.mul(r1, P))) == Nat.add(Nat.add(u, Nat.mul(q2, P)), Nat.add(v, Nat.mul(r2, P))) : Nat}
  %Equal.sym(Nat, Nat.add(y, Nat.mul(r1, P)), Nat.add(v, Nat.mul(r2, P)), h2) : {Nat.add(Nat.add(u, Nat.mul(q2, P)), _) == Nat.add(Nat.add(u, Nat.mul(q2, P)), Nat.add(v, Nat.mul(r2, P))) : Nat}
  {==}

def cg_add(+P: Nat, +x: Nat, +u: Nat, +y: Nat, +v: Nat, +c1: Cg(P, x, u), +c2: Cg(P, y, v)) -> Cg(P, Nat.add(x, y), Nat.add(u, v)):
  (+q1, +r) = c1
  (+q2, h1) = r
  (+s1, +t) = c2
  (+s2, h2) = t
  (Nat.add(q1, s1), (Nat.add(q2, s2), cg_add_go(P, x, u, y, v, q1, q2, s1, s2, h1, h2)))

def cg_mul_go(+P: Nat, +c: Nat, +x: Nat, +u: Nat, +q1: Nat, +q2: Nat,
    h: {Nat.add(x, Nat.mul(q1, P)) == Nat.add(u, Nat.mul(q2, P)) : Nat})
    -> {Nat.add(Nat.mul(c, x), Nat.mul(Nat.mul(c, q1), P)) == Nat.add(Nat.mul(c, u), Nat.mul(Nat.mul(c, q2), P)) : Nat}:
  %Equal.sym(Nat, Nat.mul(Nat.mul(c, q1), P), Nat.mul(c, Nat.mul(q1, P)), L.mul_assoc(c, q1, P)) : {Nat.add(Nat.mul(c, x), _) == Nat.add(Nat.mul(c, u), Nat.mul(Nat.mul(c, q2), P)) : Nat}
  %Equal.sym(Nat, Nat.mul(Nat.mul(c, q2), P), Nat.mul(c, Nat.mul(q2, P)), L.mul_assoc(c, q2, P)) : {Nat.add(Nat.mul(c, x), Nat.mul(c, Nat.mul(q1, P))) == Nat.add(Nat.mul(c, u), _) : Nat}
  %L.mul_add_l(c, x, Nat.mul(q1, P)) : {_ == Nat.add(Nat.mul(c, u), Nat.mul(c, Nat.mul(q2, P))) : Nat}
  %L.mul_add_l(c, u, Nat.mul(q2, P)) : {Nat.mul(c, Nat.add(x, Nat.mul(q1, P))) == _ : Nat}
  Equal.cong(Nat, Nat, w => Nat.mul(c, w), Nat.add(x, Nat.mul(q1, P)), Nat.add(u, Nat.mul(q2, P)), h)

def cg_mul(+P: Nat, +c: Nat, +x: Nat, +u: Nat, +c1: Cg(P, x, u)) -> Cg(P, Nat.mul(c, x), Nat.mul(c, u)):
  (+q1, +r) = c1
  (+q2, h) = r
  (Nat.mul(c, q1), (Nat.mul(c, q2), cg_mul_go(P, c, x, u, q1, q2, h)))

def cg_mod_go(+bp: Nat, +x: Nat, +y: Nat, +q1: Nat, +q2: Nat,
    h: {Nat.add(x, Nat.mul(q1, 1n+bp)) == Nat.add(y, Nat.mul(q2, 1n+bp)) : Nat})
    -> {Nat.add(x, Nat.mul(q1, 1n+bp)) == Nat.add(Nat.mod(y, 1n+bp), Nat.mul(Nat.add(Nat.div(y, 1n+bp), q2), 1n+bp)) : Nat}:
  %Equal.sym(Nat, Nat.mul(Nat.add(Nat.div(y, 1n+bp), q2), 1n+bp), Nat.add(Nat.mul(Nat.div(y, 1n+bp), 1n+bp), Nat.mul(q2, 1n+bp)), L.mul_add_r(Nat.div(y, 1n+bp), q2, 1n+bp)) : {Nat.add(x, Nat.mul(q1, 1n+bp)) == Nat.add(Nat.mod(y, 1n+bp), _) : Nat}
  %N.add_assoc(Nat.mod(y, 1n+bp), Nat.mul(Nat.div(y, 1n+bp), 1n+bp), Nat.mul(q2, 1n+bp)) : {Nat.add(x, Nat.mul(q1, 1n+bp)) == _ : Nat}
  %Equal.sym(Nat, Nat.add(Nat.mod(y, 1n+bp), Nat.mul(Nat.div(y, 1n+bp), 1n+bp)), y, L.div_mod(y, bp)) : {Nat.add(x, Nat.mul(q1, 1n+bp)) == Nat.add(_, Nat.mul(q2, 1n+bp)) : Nat}
  h

# A canonical representative is the remainder: x ~ y and x < M give x == y mod M.
def cg_mod(+bp: Nat, +x: Nat, +y: Nat, +lx: L.Le(x, bp), +c: Cg(1n+bp, x, y)) -> {x == Nat.mod(y, 1n+bp) : Nat}:
  (+q1, +r) = c
  (+q2, h) = r
  L.uniq(bp, x, q1, Nat.mod(y, 1n+bp), Nat.add(Nat.div(y, 1n+bp), q2), lx, L.mod_le(y, bp), cg_mod_go(bp, x, y, q1, q2, h))
