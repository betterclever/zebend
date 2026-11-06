import Base
import ../field/natlemmas.bend as N
import ../field/wordadd.bend as W
import ../prims/natlib.bend as L
import ../prims/words.bend as Ws
import ./bits.bend as Bt

# Step 1 on U32: masking with the low-k-bits word is "mod 2^k", shifting right by k
# (U32.shrn, i.e. `>>`) is "div 2^k", for every k; and the 16-bit instance the field
# code uses (x .&. 65535, x >> 16n).

law shrn_eq:
  for +w: Word(32n)
  for +k: Nat
  {U32.shrn(U32{w}, k) == U32{Bt.shrk(32n, w, k)} : U32}

def shrn_eq(w, k):
  match k:
    case 0n:
      {==}
    case 1n+q:
      %Equal.sym(U32, U32.shrn(U32{w}, q), U32{Bt.shrk(32n, w, q)}, shrn_eq(w, q)) : {U32.shr(_) == U32{Word.shr(32n, Bt.shrk(32n, w, q))} : U32}
      {==}

# (x & lowmask(k)) + (x >> k) * 2^k == x, for every k.
law u32_split:
  for +x: U32
  for +k: Nat
  {Nat.add(U32.to_nat(U32.and(x, U32{Bt.lowmask(32n, k)})), Nat.mul(U32.to_nat(U32.shrn(x, k)), W.pow2(k))) == U32.to_nat(x) : Nat}

def u32_split(x, k):
  match x:
    case U32{w}:
      %Equal.sym(U32, U32.shrn(U32{w}, k), U32{Bt.shrk(32n, w, k)}, shrn_eq(w, k)) : {Nat.add(U32.to_nat(U32.and(U32{w}, U32{Bt.lowmask(32n, k)})), Nat.mul(U32.to_nat(_), W.pow2(k))) == U32.to_nat(U32{w}) : Nat}
      Bt.split(k, 32n, w)

law u32_low_le:
  for +x: U32
  for +k: Nat
  L.Le(U32.to_nat(U32.and(x, U32{Bt.lowmask(32n, k)})), Ws.mask(k))

def u32_low_le(x, k):
  match x:
    case U32{w}:
      Bt.low_le(k, 32n, w)

# q1 * M == q2 * M  ==>  q1 == q2, for M = 1 + bp.
law mul_cancel_r:
  for +q1: Nat
  for +q2: Nat
  for +bp: Nat
  for h: {Nat.mul(q1, 1n+bp) == Nat.mul(q2, 1n+bp) : Nat}
  {q1 == q2 : Nat}

def mul_cancel_r(q1, q2, bp, h):
  match q1 q2:
    case 0n 0n:
      {==}
    case 0n 1n+b:
      Empty.absurd({0n == 1n+b : Nat}, L.succ_ne_zero(Nat.add(bp, Nat.mul(b, 1n+bp)), Equal.sym(Nat, 0n, 1n+Nat.add(bp, Nat.mul(b, 1n+bp)), h)))
    case 1n+a 0n:
      Empty.absurd({1n+a == 0n : Nat}, L.succ_ne_zero(Nat.add(bp, Nat.mul(a, 1n+bp)), h))
    case 1n+a 1n+b:
      Equal.cong(Nat, Nat, v => 1n+v, a, b, mul_cancel_r(a, b, bp, L.add_cancel_l(1n+bp, Nat.mul(a, 1n+bp), Nat.mul(b, 1n+bp), h)))

def split_eq(+x: U32, +k: Nat) -> {Nat.add(U32.to_nat(U32.and(x, U32{Bt.lowmask(32n, k)})), Nat.mul(U32.to_nat(U32.shrn(x, k)), 1n+Ws.mask(k))) == Nat.add(Nat.mod(U32.to_nat(x), 1n+Ws.mask(k)), Nat.mul(Nat.div(U32.to_nat(x), 1n+Ws.mask(k)), 1n+Ws.mask(k))) : Nat}:
  %Ws.pow2_mask(k) : {Nat.add(U32.to_nat(U32.and(x, U32{Bt.lowmask(32n, k)})), Nat.mul(U32.to_nat(U32.shrn(x, k)), _)) == Nat.add(Nat.mod(U32.to_nat(x), 1n+Ws.mask(k)), Nat.mul(Nat.div(U32.to_nat(x), 1n+Ws.mask(k)), 1n+Ws.mask(k))) : Nat}
  Equal.trans(Nat, Nat.add(U32.to_nat(U32.and(x, U32{Bt.lowmask(32n, k)})), Nat.mul(U32.to_nat(U32.shrn(x, k)), W.pow2(k))), U32.to_nat(x), Nat.add(Nat.mod(U32.to_nat(x), 1n+Ws.mask(k)), Nat.mul(Nat.div(U32.to_nat(x), 1n+Ws.mask(k)), 1n+Ws.mask(k))),
    u32_split(x, k), Equal.sym(Nat, Nat.add(Nat.mod(U32.to_nat(x), 1n+Ws.mask(k)), Nat.mul(Nat.div(U32.to_nat(x), 1n+Ws.mask(k)), 1n+Ws.mask(k))), U32.to_nat(x), L.div_mod(U32.to_nat(x), Ws.mask(k))))

def mm(+x: U32, +k: Nat) -> {U32.to_nat(U32.and(x, U32{Bt.lowmask(32n, k)})) == Nat.mod(U32.to_nat(x), 1n+Ws.mask(k)) : Nat}:
  L.uniq(Ws.mask(k), U32.to_nat(U32.and(x, U32{Bt.lowmask(32n, k)})), U32.to_nat(U32.shrn(x, k)), Nat.mod(U32.to_nat(x), 1n+Ws.mask(k)), Nat.div(U32.to_nat(x), 1n+Ws.mask(k)),
    u32_low_le(x, k), L.mod_le(U32.to_nat(x), Ws.mask(k)),
    split_eq(x, k))

# Step 1 as mod / div: the low k bits are x mod 2^k, the shifted word is x div 2^k.
law u32_mask_mod:
  for +x: U32
  for +k: Nat
  {U32.to_nat(U32.and(x, U32{Bt.lowmask(32n, k)})) == Nat.mod(U32.to_nat(x), W.pow2(k)) : Nat}

def u32_mask_mod(x, k):
  %Equal.sym(Nat, W.pow2(k), 1n+Ws.mask(k), Ws.pow2_mask(k)) : {U32.to_nat(U32.and(x, U32{Bt.lowmask(32n, k)})) == Nat.mod(U32.to_nat(x), _) : Nat}
  mm(x, k)

def lo_swap(+x: U32, +k: Nat) -> {Nat.add(Nat.mod(U32.to_nat(x), 1n+Ws.mask(k)), Nat.mul(U32.to_nat(U32.shrn(x, k)), 1n+Ws.mask(k))) == Nat.add(Nat.mod(U32.to_nat(x), 1n+Ws.mask(k)), Nat.mul(Nat.div(U32.to_nat(x), 1n+Ws.mask(k)), 1n+Ws.mask(k))) : Nat}:
  %mm(x, k) : {Nat.add(_, Nat.mul(U32.to_nat(U32.shrn(x, k)), 1n+Ws.mask(k))) == Nat.add(Nat.mod(U32.to_nat(x), 1n+Ws.mask(k)), Nat.mul(Nat.div(U32.to_nat(x), 1n+Ws.mask(k)), 1n+Ws.mask(k))) : Nat}
  split_eq(x, k)

law u32_shr_div:
  for +x: U32
  for +k: Nat
  {U32.to_nat(U32.shrn(x, k)) == Nat.div(U32.to_nat(x), W.pow2(k)) : Nat}

def u32_shr_div(x, k):
  %Equal.sym(Nat, W.pow2(k), 1n+Ws.mask(k), Ws.pow2_mask(k)) : {U32.to_nat(U32.shrn(x, k)) == Nat.div(U32.to_nat(x), _) : Nat}
  mul_cancel_r(U32.to_nat(U32.shrn(x, k)), Nat.div(U32.to_nat(x), 1n+Ws.mask(k)), Ws.mask(k),
    L.add_cancel_l(Nat.mod(U32.to_nat(x), 1n+Ws.mask(k)), Nat.mul(U32.to_nat(U32.shrn(x, k)), 1n+Ws.mask(k)), Nat.mul(Nat.div(U32.to_nat(x), 1n+Ws.mask(k)), 1n+Ws.mask(k)),
      lo_swap(x, k)))

# --- the 16-bit instance used by the field code (x .&. 65535, x >> 16n) -------

def lit65535() -> {U32{Bt.lowmask(32n, 16n)} == 65535 : U32}:
  {==}

def mask16() -> {Ws.mask(16n) == 65535n : Nat}:
  L.succ_inj(Ws.mask(16n), 65535n, Equal.sym(Nat, 65536n, 1n+Ws.mask(16n), Equal.trans(Nat, 65536n, W.pow2(16n), 1n+Ws.mask(16n), Ws.e16(), Ws.pow2_mask(16n))))

law split16:
  for +x: U32
  {Nat.add(U32.to_nat(U32.and(x, 65535)), Nat.mul(U32.to_nat(U32.shrn(x, 16n)), 65536n)) == U32.to_nat(x) : Nat}

def split16(x):
  %lit65535() : {Nat.add(U32.to_nat(U32.and(x, _)), Nat.mul(U32.to_nat(U32.shrn(x, 16n)), 65536n)) == U32.to_nat(x) : Nat}
  %Equal.sym(Nat, 65536n, W.pow2(16n), Ws.e16()) : {Nat.add(U32.to_nat(U32.and(x, U32{Bt.lowmask(32n, 16n)})), Nat.mul(U32.to_nat(U32.shrn(x, 16n)), _)) == U32.to_nat(x) : Nat}
  u32_split(x, 16n)

law low16_le:
  for +x: U32
  L.Le(U32.to_nat(U32.and(x, 65535)), 65535n)

def low16_le(x):
  %lit65535() : L.Le(U32.to_nat(U32.and(x, _)), 65535n)
  %mask16() : L.Le(U32.to_nat(U32.and(x, U32{Bt.lowmask(32n, 16n)})), _)
  u32_low_le(x, 16n)

law mask16_mod:
  for +x: U32
  {U32.to_nat(U32.and(x, 65535)) == Nat.mod(U32.to_nat(x), 65536n) : Nat}

def mask16_mod(x):
  %lit65535() : {U32.to_nat(U32.and(x, _)) == Nat.mod(U32.to_nat(x), 65536n) : Nat}
  %Equal.sym(Nat, 65536n, W.pow2(16n), Ws.e16()) : {U32.to_nat(U32.and(x, U32{Bt.lowmask(32n, 16n)})) == Nat.mod(U32.to_nat(x), _) : Nat}
  u32_mask_mod(x, 16n)

law shr16_div:
  for +x: U32
  {U32.to_nat(U32.shrn(x, 16n)) == Nat.div(U32.to_nat(x), 65536n) : Nat}

def shr16_div(x):
  %Equal.sym(Nat, 65536n, W.pow2(16n), Ws.e16()) : {U32.to_nat(U32.shrn(x, 16n)) == Nat.div(U32.to_nat(x), _) : Nat}
  u32_shr_div(x, 16n)
