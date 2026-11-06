import Base
import ../../zcash/halo2/lib/fp.bend as Fp
import ../prims/natlib.bend as L
import ../field/natlemmas.bend as N
import ../prims/words.bend as Ws
import ./u32bits.bend as UB
import ./u32sem.bend as S
import ./defs.bend as D
import ./addproof.bend as AP
import ./canon.bend as CN
import ./subproof.bend as SP
import ./LAWS.bend as Laws

def Laws.u32_mask_mod(x, k):
  UB.u32_mask_mod(x, k)

def Laws.u32_shr_div(x, k):
  UB.u32_shr_div(x, k)

def Laws.mask16_mod(x):
  UB.mask16_mod(x)

def Laws.shr16_div(x):
  UB.shr16_div(x)

def Laws.add_exact(a, b, l):
  S.add_exact(a, b, l)

def zero_add(+x: Nat) -> {Nat.add(0n, x) == x : Nat}:
  {==}

def za(+x: Nat, +y: Nat, +h: {y == 0n : Nat}) -> {Nat.add(y, x) == x : Nat}:
  %Equal.sym(Nat, y, 0n, h) : {Nat.add(_, x) == x : Nat}
  zero_add(x)

def Laws.add_exact_sat():
  (Ws.mask(32n), za(Ws.mask(32n), Nat.add(U32.to_nat(0), U32.to_nat(0)), {==}))

def Laws.sub_exact(a, b, l):
  S.sub_exact(a, b, l)

def Laws.sub_exact_sat(x):
  (0n, N.add_zero_r(U32.to_nat(x)))

def Laws.add_ok(a, b, ca, cb):
  AP.add_ok_proof(a, b, ca, cb)

def ltof(+a: Fp.Fp, +c: D.Canon(a)) -> L.Le(1n+D.val(65536n, a), D.val(65536n, Fp.Fp{1, 0, 12525, 39213, 63771, 2380, 39164, 8774, 0, 0, 0, 0, 0, 0, 0, 16384})):
  (+l, +t) = c
  t

def Laws.add_lt(a, b, ca, cb):
  %Equal.sym(Nat, D.val(65536n, Fp.add(a, b)), Nat.mod(Nat.add(D.val(65536n, a), D.val(65536n, b)), D.val(65536n, Fp.Fp{1, 0, 12525, 39213, 63771, 2380, 39164, 8774, 0, 0, 0, 0, 0, 0, 0, 16384})), AP.add_ok_proof(a, b, ca, cb)) : L.Le(1n+_, D.val(65536n, Fp.Fp{1, 0, 12525, 39213, 63771, 2380, 39164, 8774, 0, 0, 0, 0, 0, 0, 0, 16384}))
  CN.mod_lt(Nat.add(D.val(65536n, a), D.val(65536n, b)), D.val(65536n, Fp.Fp{1, 0, 12525, 39213, 63771, 2380, 39164, 8774, 0, 0, 0, 0, 0, 0, 0, 16384}), D.val(65536n, a), ltof(a, ca))

def Laws.sub_ok(a, b, ca, cb):
  SP.sub_ok_proof(a, b, ca, cb)

def Laws.sub_lt(a, b, ca, cb):
  %Equal.sym(Nat, D.val(65536n, Fp.sub(a, b)), Nat.mod(Nat.add(D.val(65536n, a), Nat.sub(D.val(65536n, Fp.Fp{1, 0, 12525, 39213, 63771, 2380, 39164, 8774, 0, 0, 0, 0, 0, 0, 0, 16384}), D.val(65536n, b))), D.val(65536n, Fp.Fp{1, 0, 12525, 39213, 63771, 2380, 39164, 8774, 0, 0, 0, 0, 0, 0, 0, 16384})), SP.sub_ok_proof(a, b, ca, cb)) : L.Le(1n+_, D.val(65536n, Fp.Fp{1, 0, 12525, 39213, 63771, 2380, 39164, 8774, 0, 0, 0, 0, 0, 0, 0, 16384}))
  CN.mod_lt(Nat.add(D.val(65536n, a), Nat.sub(D.val(65536n, Fp.Fp{1, 0, 12525, 39213, 63771, 2380, 39164, 8774, 0, 0, 0, 0, 0, 0, 0, 16384}), D.val(65536n, b))), D.val(65536n, Fp.Fp{1, 0, 12525, 39213, 63771, 2380, 39164, 8774, 0, 0, 0, 0, 0, 0, 0, 16384}), D.val(65536n, a), ltof(a, ca))

def Laws.canon_zero():
  CN.canon_zero()
