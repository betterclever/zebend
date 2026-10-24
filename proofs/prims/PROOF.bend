import Base
import ../field/natlemmas.bend as N2
import ./natlib.bend as L
import ../field/wordadd.bend as W
import ./words.bend as Ws
import ./u32.bend as U
import ./hi.bend as H
import ./LAWS.bend as Laws

# Every proof first rewrites each K = 65536 * 65536 to 1 + mask(32) (Ws.two32), then
# applies the generic lemmas at bp = mask(32) = 2^32 - 1.

def k32() -> {1n+Ws.mask(32n) == Nat.mul(65536n, 65536n) : Nat}:
  Equal.sym(Nat, Nat.mul(65536n, 65536n), 1n+Ws.mask(32n), Ws.two32())

def Laws.u32_mul_lo(a, b):
  %k32() : {U32.to_nat(U32.mul(a, b)) == Nat.mod(Nat.mul(U32.to_nat(a), U32.to_nat(b)), _) : Nat}
  U.u32_mul(a, b)

def Laws.u32_add_lo(a, b):
  %k32() : {U32.to_nat(U32.add(a, b)) == Nat.mod(Nat.add(U32.to_nat(a), U32.to_nat(b)), _) : Nat}
  U.u32_add(a, b)

def Laws.u32_from_nat(y):
  %k32() : {U32.to_nat(U32.from_nat(y)) == Nat.mod(y, _) : Nat}
  U.u32_from_nat(y)

def Laws.mul_hi_split(a, b):
  %k32() : {Nat.add(U32.to_nat(U32.mul(a, b)), Nat.mul(U32.to_nat(U32.from_nat(Nat.div(Nat.mul(U32.to_nat(a), U32.to_nat(b)), _))), Nat.mul(65536n, 65536n))) == Nat.mul(U32.to_nat(a), U32.to_nat(b)) : Nat}
  %k32() : {Nat.add(U32.to_nat(U32.mul(a, b)), Nat.mul(U32.to_nat(U32.from_nat(Nat.div(Nat.mul(U32.to_nat(a), U32.to_nat(b)), 1n+Ws.mask(32n)))), _)) == Nat.mul(U32.to_nat(a), U32.to_nat(b)) : Nat}
  H.hi_split(Ws.mask(32n), Nat.mul(U32.to_nat(a), U32.to_nat(b)), U32.to_nat(U32.mul(a, b)), U32.to_nat(U32.from_nat(Nat.div(Nat.mul(U32.to_nat(a), U32.to_nat(b)), 1n+Ws.mask(32n)))),
    U.u32_mul(a, b), U.u32_from_nat(Nat.div(Nat.mul(U32.to_nat(a), U32.to_nat(b)), 1n+Ws.mask(32n))),
    H.bnd_mul(Ws.mask(32n), U32.to_nat(a), U32.to_nat(b), Ws.u32_le(a), Ws.u32_le(b)))

def Laws.add_hi_split(a, b):
  %k32() : {Nat.add(U32.to_nat(U32.add(a, b)), Nat.mul(U32.to_nat(U32.from_nat(Nat.div(Nat.add(U32.to_nat(a), U32.to_nat(b)), _))), Nat.mul(65536n, 65536n))) == Nat.add(U32.to_nat(a), U32.to_nat(b)) : Nat}
  %k32() : {Nat.add(U32.to_nat(U32.add(a, b)), Nat.mul(U32.to_nat(U32.from_nat(Nat.div(Nat.add(U32.to_nat(a), U32.to_nat(b)), 1n+Ws.mask(32n)))), _)) == Nat.add(U32.to_nat(a), U32.to_nat(b)) : Nat}
  H.hi_split(Ws.mask(32n), Nat.add(U32.to_nat(a), U32.to_nat(b)), U32.to_nat(U32.add(a, b)), U32.to_nat(U32.from_nat(Nat.div(Nat.add(U32.to_nat(a), U32.to_nat(b)), 1n+Ws.mask(32n)))),
    U.u32_add(a, b), U.u32_from_nat(Nat.div(Nat.add(U32.to_nat(a), U32.to_nat(b)), 1n+Ws.mask(32n))),
    H.bnd_add(Ws.mask(32n), U32.to_nat(a), U32.to_nat(b), Ws.u32_le(a), Ws.u32_le(b)))

# The low word of a * b + c + d, reduced step by step, is the whole sum mod M.
def mac_lo(+bp: Nat, +ab: Nat, +c: Nat, +d: Nat, +x1: Nat, +x2: Nat, +x3: Nat,
    h1: {x1 == Nat.mod(ab, 1n+bp) : Nat}, h2: {x2 == Nat.mod(Nat.add(x1, c), 1n+bp) : Nat}, h3: {x3 == Nat.mod(Nat.add(x2, d), 1n+bp) : Nat})
    -> {x3 == Nat.mod(Nat.add(Nat.add(ab, c), d), 1n+bp) : Nat}:
  %Equal.sym(Nat, x3, Nat.mod(Nat.add(x2, d), 1n+bp), h3) : {_ == Nat.mod(Nat.add(Nat.add(ab, c), d), 1n+bp) : Nat}
  %Equal.sym(Nat, x2, Nat.mod(Nat.add(x1, c), 1n+bp), h2) : {Nat.mod(Nat.add(_, d), 1n+bp) == Nat.mod(Nat.add(Nat.add(ab, c), d), 1n+bp) : Nat}
  %Equal.sym(Nat, Nat.mod(Nat.add(Nat.mod(Nat.add(x1, c), 1n+bp), d), 1n+bp), Nat.mod(Nat.add(Nat.add(x1, c), d), 1n+bp), L.mod_add_mod_l(Nat.add(x1, c), d, bp)) : {_ == Nat.mod(Nat.add(Nat.add(ab, c), d), 1n+bp) : Nat}
  %Equal.sym(Nat, x1, Nat.mod(ab, 1n+bp), h1) : {Nat.mod(Nat.add(Nat.add(_, c), d), 1n+bp) == Nat.mod(Nat.add(Nat.add(ab, c), d), 1n+bp) : Nat}
  %Equal.sym(Nat, Nat.add(Nat.add(Nat.mod(ab, 1n+bp), c), d), Nat.add(Nat.mod(ab, 1n+bp), Nat.add(c, d)), N2.add_assoc(Nat.mod(ab, 1n+bp), c, d)) : {Nat.mod(_, 1n+bp) == Nat.mod(Nat.add(Nat.add(ab, c), d), 1n+bp) : Nat}
  %Equal.sym(Nat, Nat.add(Nat.add(ab, c), d), Nat.add(ab, Nat.add(c, d)), N2.add_assoc(ab, c, d)) : {Nat.mod(Nat.add(Nat.mod(ab, 1n+bp), Nat.add(c, d)), 1n+bp) == Nat.mod(_, 1n+bp) : Nat}
  L.mod_add_mod_l(ab, Nat.add(c, d), bp)

def Laws.mac_hi_split(a, b, c, d):
  %k32() : {Nat.add(U32.to_nat(U32.add(U32.add(U32.mul(a, b), c), d)), Nat.mul(U32.to_nat(U32.from_nat(Nat.div(Nat.add(Nat.add(Nat.mul(U32.to_nat(a), U32.to_nat(b)), U32.to_nat(c)), U32.to_nat(d)), _))), Nat.mul(65536n, 65536n))) == Nat.add(Nat.add(Nat.mul(U32.to_nat(a), U32.to_nat(b)), U32.to_nat(c)), U32.to_nat(d)) : Nat}
  %k32() : {Nat.add(U32.to_nat(U32.add(U32.add(U32.mul(a, b), c), d)), Nat.mul(U32.to_nat(U32.from_nat(Nat.div(Nat.add(Nat.add(Nat.mul(U32.to_nat(a), U32.to_nat(b)), U32.to_nat(c)), U32.to_nat(d)), 1n+Ws.mask(32n)))), _)) == Nat.add(Nat.add(Nat.mul(U32.to_nat(a), U32.to_nat(b)), U32.to_nat(c)), U32.to_nat(d)) : Nat}
  H.hi_split(Ws.mask(32n), Nat.add(Nat.add(Nat.mul(U32.to_nat(a), U32.to_nat(b)), U32.to_nat(c)), U32.to_nat(d)), U32.to_nat(U32.add(U32.add(U32.mul(a, b), c), d)), U32.to_nat(U32.from_nat(Nat.div(Nat.add(Nat.add(Nat.mul(U32.to_nat(a), U32.to_nat(b)), U32.to_nat(c)), U32.to_nat(d)), 1n+Ws.mask(32n)))),
    mac_lo(Ws.mask(32n), Nat.mul(U32.to_nat(a), U32.to_nat(b)), U32.to_nat(c), U32.to_nat(d), U32.to_nat(U32.mul(a, b)), U32.to_nat(U32.add(U32.mul(a, b), c)), U32.to_nat(U32.add(U32.add(U32.mul(a, b), c), d)),
      U.u32_mul(a, b), U.u32_add(U32.mul(a, b), c), U.u32_add(U32.add(U32.mul(a, b), c), d)),
    U.u32_from_nat(Nat.div(Nat.add(Nat.add(Nat.mul(U32.to_nat(a), U32.to_nat(b)), U32.to_nat(c)), U32.to_nat(d)), 1n+Ws.mask(32n))),
    H.bnd_mac(Ws.mask(32n), U32.to_nat(a), U32.to_nat(b), U32.to_nat(c), U32.to_nat(d), Ws.u32_le(a), Ws.u32_le(b), Ws.u32_le(c), Ws.u32_le(d)))

def e3232() -> {Nat.add(32n, 32n) == 64n : Nat}:
  {==}

def p_sq() -> {Nat.mul(W.pow2(32n), W.pow2(32n)) == 1n+H.TB(Ws.mask(32n)) : Nat}:
  %Equal.sym(Nat, W.pow2(32n), 1n+Ws.mask(32n), Ws.pow2_mask(32n)) : {Nat.mul(_, W.pow2(32n)) == 1n+H.TB(Ws.mask(32n)) : Nat}
  %Equal.sym(Nat, W.pow2(32n), 1n+Ws.mask(32n), Ws.pow2_mask(32n)) : {Nat.mul(1n+Ws.mask(32n), _) == 1n+H.TB(Ws.mask(32n)) : Nat}
  H.sq_tb(Ws.mask(32n))

# 2^64 == 1 + TB(2^32 - 1)
def p64() -> {Nat.pow(2n, 64n) == 1n+H.TB(Ws.mask(32n)) : Nat}:
  %Equal.sym(Nat, Nat.pow(2n, 64n), W.pow2(64n), Ws.pow_pow2(64n)) : {_ == 1n+H.TB(Ws.mask(32n)) : Nat}
  %e3232() : {W.pow2(_) == 1n+H.TB(Ws.mask(32n)) : Nat}
  Equal.trans(Nat, W.pow2(Nat.add(32n, 32n)), Nat.mul(W.pow2(32n), W.pow2(32n)), 1n+H.TB(Ws.mask(32n)), Ws.pow2_add(32n, 32n), p_sq())

def p0() -> {Nat.pow(2n, Nat.mul(32n, U32.to_nat(0))) == 1n : Nat}:
  {==}

def e_one() -> {1n == U32.to_nat(1) : Nat}:
  {==}

def e_32() -> {32n == Nat.mul(32n, 1n) : Nat}:
  {==}

def p1() -> {Nat.pow(2n, Nat.mul(32n, U32.to_nat(1))) == 1n+Ws.mask(32n) : Nat}:
  %e_one() : {Nat.pow(2n, Nat.mul(32n, _)) == 1n+Ws.mask(32n) : Nat}
  %e_32() : {Nat.pow(2n, _) == 1n+Ws.mask(32n) : Nat}
  %Equal.sym(Nat, Nat.pow(2n, 32n), W.pow2(32n), Ws.pow_pow2(32n)) : {_ == 1n+Ws.mask(32n) : Nat}
  Ws.pow2_mask(32n)

def Laws.lane64_split(x):
  %Equal.sym(Nat, Nat.pow(2n, 64n), 1n+H.TB(Ws.mask(32n)), p64()) : {Nat.add(U32.to_nat(U32.from_nat(Nat.div(Nat.mod(x, _), Nat.pow(2n, Nat.mul(32n, U32.to_nat(0)))))), Nat.mul(U32.to_nat(U32.from_nat(Nat.div(Nat.mod(x, Nat.pow(2n, 64n)), Nat.pow(2n, Nat.mul(32n, U32.to_nat(1)))))), Nat.mul(65536n, 65536n))) == Nat.mod(x, Nat.pow(2n, 64n)) : Nat}
  %Equal.sym(Nat, Nat.pow(2n, 64n), 1n+H.TB(Ws.mask(32n)), p64()) : {Nat.add(U32.to_nat(U32.from_nat(Nat.div(Nat.mod(x, 1n+H.TB(Ws.mask(32n))), Nat.pow(2n, Nat.mul(32n, U32.to_nat(0)))))), Nat.mul(U32.to_nat(U32.from_nat(Nat.div(Nat.mod(x, _), Nat.pow(2n, Nat.mul(32n, U32.to_nat(1)))))), Nat.mul(65536n, 65536n))) == Nat.mod(x, Nat.pow(2n, 64n)) : Nat}
  %Equal.sym(Nat, Nat.pow(2n, 64n), 1n+H.TB(Ws.mask(32n)), p64()) : {Nat.add(U32.to_nat(U32.from_nat(Nat.div(Nat.mod(x, 1n+H.TB(Ws.mask(32n))), Nat.pow(2n, Nat.mul(32n, U32.to_nat(0)))))), Nat.mul(U32.to_nat(U32.from_nat(Nat.div(Nat.mod(x, 1n+H.TB(Ws.mask(32n))), Nat.pow(2n, Nat.mul(32n, U32.to_nat(1)))))), Nat.mul(65536n, 65536n))) == Nat.mod(x, _) : Nat}
  %Equal.sym(Nat, Nat.pow(2n, Nat.mul(32n, U32.to_nat(0))), 1n, p0()) : {Nat.add(U32.to_nat(U32.from_nat(Nat.div(Nat.mod(x, 1n+H.TB(Ws.mask(32n))), _))), Nat.mul(U32.to_nat(U32.from_nat(Nat.div(Nat.mod(x, 1n+H.TB(Ws.mask(32n))), Nat.pow(2n, Nat.mul(32n, U32.to_nat(1)))))), Nat.mul(65536n, 65536n))) == Nat.mod(x, 1n+H.TB(Ws.mask(32n))) : Nat}
  %Equal.sym(Nat, Nat.pow(2n, Nat.mul(32n, U32.to_nat(1))), 1n+Ws.mask(32n), p1()) : {Nat.add(U32.to_nat(U32.from_nat(Nat.div(Nat.mod(x, 1n+H.TB(Ws.mask(32n))), 1n))), Nat.mul(U32.to_nat(U32.from_nat(Nat.div(Nat.mod(x, 1n+H.TB(Ws.mask(32n))), _))), Nat.mul(65536n, 65536n))) == Nat.mod(x, 1n+H.TB(Ws.mask(32n))) : Nat}
  %k32() : {Nat.add(U32.to_nat(U32.from_nat(Nat.div(Nat.mod(x, 1n+H.TB(Ws.mask(32n))), 1n))), Nat.mul(U32.to_nat(U32.from_nat(Nat.div(Nat.mod(x, 1n+H.TB(Ws.mask(32n))), 1n+Ws.mask(32n)))), _)) == Nat.mod(x, 1n+H.TB(Ws.mask(32n))) : Nat}
  %Equal.sym(Nat, Nat.div(Nat.mod(x, 1n+H.TB(Ws.mask(32n))), 1n), Nat.mod(x, 1n+H.TB(Ws.mask(32n))), H.div_one(Nat.mod(x, 1n+H.TB(Ws.mask(32n))))) : {Nat.add(U32.to_nat(U32.from_nat(_)), Nat.mul(U32.to_nat(U32.from_nat(Nat.div(Nat.mod(x, 1n+H.TB(Ws.mask(32n))), 1n+Ws.mask(32n)))), 1n+Ws.mask(32n))) == Nat.mod(x, 1n+H.TB(Ws.mask(32n))) : Nat}
  H.hi_split(Ws.mask(32n), Nat.mod(x, 1n+H.TB(Ws.mask(32n))), U32.to_nat(U32.from_nat(Nat.mod(x, 1n+H.TB(Ws.mask(32n))))), U32.to_nat(U32.from_nat(Nat.div(Nat.mod(x, 1n+H.TB(Ws.mask(32n))), 1n+Ws.mask(32n)))),
    U.u32_from_nat(Nat.mod(x, 1n+H.TB(Ws.mask(32n)))), U.u32_from_nat(Nat.div(Nat.mod(x, 1n+H.TB(Ws.mask(32n))), 1n+Ws.mask(32n))),
    L.mod_le(x, H.TB(Ws.mask(32n))))
