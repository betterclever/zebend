# Proofs for LAWS.bend.
import Base
import ../../../proofs/field/natlemmas.bend as N
import ../../../proofs/prims/natlib.bend as L
import ./issuance.bend as I
import ./LAWS.bend as Laws

# --- order helpers -------------------------------------------------------------------

law le_refl:
  for +a: Nat
  L.Le(a, a)

def le_refl(a):
  (0n, N.add_zero_r(a))

law le_trans_eq:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for +e1: Nat
  for +e2: Nat
  for p1: {Nat.add(a, e1) == b : Nat}
  for p2: {Nat.add(b, e2) == c : Nat}
  {Nat.add(a, Nat.add(e1, e2)) == c : Nat}

def le_trans_eq(a, b, c, e1, e2, p1, p2):
  %N.add_assoc(a, e1, e2) : {_ == c : Nat}
  %Equal.sym(Nat, Nat.add(a, e1), b, p1) : {Nat.add(_, e2) == c : Nat}
  p2

law le_trans:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for l1: L.Le(a, b)
  for l2: L.Le(b, c)
  L.Le(a, c)

def le_trans(a, b, c, l1, l2):
  (+e1, p1) = l1
  (+e2, p2) = l2
  (Nat.add(e1, e2), le_trans_eq(a, b, c, e1, e2, p1, p2))

law add_mono_eq:
  for +k: Nat
  for +a: Nat
  for +b: Nat
  for +e: Nat
  for p: {Nat.add(a, e) == b : Nat}
  {Nat.add(Nat.add(k, a), e) == Nat.add(k, b) : Nat}

def add_mono_eq(k, a, b, e, p):
  %Equal.sym(Nat, Nat.add(Nat.add(k, a), e), Nat.add(k, Nat.add(a, e)), N.add_assoc(k, a, e)) : {_ == Nat.add(k, b) : Nat}
  %p : {Nat.add(k, Nat.add(a, e)) == Nat.add(k, _) : Nat}
  {==}

law add_mono_l:
  for +k: Nat
  for +a: Nat
  for +b: Nat
  for l: L.Le(a, b)
  L.Le(Nat.add(k, a), Nat.add(k, b))

def add_mono_l(k, a, b, l):
  (+e, p) = l
  (e, add_mono_eq(k, a, b, e, p))

law mul_mono_eq:
  for +n: Nat
  for +a: Nat
  for +b: Nat
  for +e: Nat
  for p: {Nat.add(a, e) == b : Nat}
  {Nat.add(Nat.mul(n, a), Nat.mul(n, e)) == Nat.mul(n, b) : Nat}

def mul_mono_eq(n, a, b, e, p):
  %L.mul_add_l(n, a, e) : {_ == Nat.mul(n, b) : Nat}
  %p : {Nat.mul(n, Nat.add(a, e)) == Nat.mul(n, _) : Nat}
  {==}

law mul_mono_l:
  for +n: Nat
  for +a: Nat
  for +b: Nat
  for l: L.Le(a, b)
  L.Le(Nat.mul(n, a), Nat.mul(n, b))

def mul_mono_l(n, a, b, l):
  (+e, p) = l
  (Nat.mul(n, e), mul_mono_eq(n, a, b, e, p))

# --- halving -------------------------------------------------------------------------

# mod(x, 2) + (d + d) == x, with d = floor(x / 2).
law half_split:
  for +x: Nat
  {Nat.add(Nat.mod(x, 2n), Nat.add(Nat.div(x, 2n), Nat.div(x, 2n))) == x : Nat}

def half_split(x):
  %Equal.trans(Nat, Nat.mul(Nat.div(x, 2n), 2n), Nat.add(Nat.div(x, 2n), Nat.mul(Nat.div(x, 2n), 1n)), Nat.add(Nat.div(x, 2n), Nat.div(x, 2n)), L.mul_succ_r(Nat.div(x, 2n), 1n), Equal.cong(Nat, Nat, y => Nat.add(Nat.div(x, 2n), y), Nat.mul(Nat.div(x, 2n), 1n), Nat.div(x, 2n), L.mul_one_r(Nat.div(x, 2n)))) : {Nat.add(Nat.mod(x, 2n), _) == x : Nat}
  L.div_mod(x, 1n)

law div2_eq:
  for +x: Nat
  {Nat.add(Nat.div(x, 2n), Nat.add(Nat.div(x, 2n), Nat.mod(x, 2n))) == x : Nat}

def div2_eq(x):
  %N.add_assoc(Nat.div(x, 2n), Nat.div(x, 2n), Nat.mod(x, 2n)) : {_ == x : Nat}
  %Equal.sym(Nat, Nat.add(Nat.add(Nat.div(x, 2n), Nat.div(x, 2n)), Nat.mod(x, 2n)), Nat.add(Nat.mod(x, 2n), Nat.add(Nat.div(x, 2n), Nat.div(x, 2n))), N.add_comm(Nat.add(Nat.div(x, 2n), Nat.div(x, 2n)), Nat.mod(x, 2n))) : {_ == x : Nat}
  half_split(x)

law div2_le:
  for +x: Nat
  L.Le(Nat.div(x, 2n), x)

def div2_le(x):
  (Nat.add(Nat.div(x, 2n), Nat.mod(x, 2n)), div2_eq(x))

law two_half_eq:
  for +x: Nat
  {Nat.add(Nat.add(Nat.div(x, 2n), Nat.div(x, 2n)), Nat.mod(x, 2n)) == x : Nat}

def two_half_eq(x):
  %Equal.sym(Nat, Nat.add(Nat.add(Nat.div(x, 2n), Nat.div(x, 2n)), Nat.mod(x, 2n)), Nat.add(Nat.mod(x, 2n), Nat.add(Nat.div(x, 2n), Nat.div(x, 2n))), N.add_comm(Nat.add(Nat.div(x, 2n), Nat.div(x, 2n)), Nat.mod(x, 2n))) : {_ == x : Nat}
  half_split(x)

law two_half_le:
  for +x: Nat
  L.Le(Nat.add(Nat.div(x, 2n), Nat.div(x, 2n)), x)

def two_half_le(x):
  (Nat.mod(x, 2n), two_half_eq(x))

# --- the laws ------------------------------------------------------------------------

def Laws.halve_succ(k, m):
  match k:
    case 0n:
      {==}
    case 1n+p:
      Laws.halve_succ(p, Nat.div(m, 2n))

def Laws.halve_step_le(k, m):
  %Equal.sym(Nat, I.halve(1n+k, m), Nat.div(I.halve(k, m), 2n), Laws.halve_succ(k, m)) : L.Le(_, I.halve(k, m))
  div2_le(I.halve(k, m))

def Laws.halve_le(k, m):
  match k:
    case 0n:
      le_refl(m)
    case 1n+p:
      le_trans(I.halve(p, Nat.div(m, 2n)), Nat.div(m, 2n), m, Laws.halve_le(p, Nat.div(m, 2n)), div2_le(m))

def Laws.total_le(K, m):
  match K:
    case 0n:
      (Nat.add(m, m), {==})
    case 1n+p:
      add_mono_l(m, I.total(p, Nat.div(m, 2n)), m,
        le_trans(I.total(p, Nat.div(m, 2n)), Nat.add(Nat.div(m, 2n), Nat.div(m, 2n)), m,
          Laws.total_le(p, Nat.div(m, 2n)), two_half_le(m)))

def Laws.cap(n, K, m):
  mul_mono_l(n, I.total(K, m), Nat.add(m, m), Laws.total_le(K, m))
