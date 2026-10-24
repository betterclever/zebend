import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L

# Fp modelled as canonical Nats below p = 1 + pp, with exactly the operations the
# generated Orchard gate code (halo2/gen/orchard_cs.bend) uses: Z.fadd, Z.fsub,
# Z.fmul and Z.FZERO. Z.fsub(x, y) = x - y mod p = (x + (p - y)) mod p for y <= p.
# gates.py checks that the decoded gate trees reproduce halo2's gate values.

def fadd(+p: Nat, x: Nat, y: Nat) -> Nat:
  Nat.mod(Nat.add(x, y), p)

def fsub(+p: Nat, x: Nat, +y: Nat) -> Nat:
  Nat.mod(Nat.add(x, Nat.sub(p, y)), p)

def fmul(+p: Nat, x: Nat, +y: Nat) -> Nat:
  Nat.mod(Nat.mul(x, y), p)

# Z/p has no zero divisors on canonical elements: exactly the case when p is prime.
# This is the only property of p the gadget proofs use; it is a hypothesis.
def NZD(+pp: Nat) -> Type:
  @x: Nat -> @y: Nat -> L.Le(x, pp) -> L.Le(y, pp) -> {fmul(1n+pp, x, y) == 0n : Nat} -> Either<&1, &1, {x == 0n : Nat}, {y == 0n : Nat}>

def le_succ(+y: Nat, +pp: Nat, l: L.Le(y, pp)) -> L.Le(y, 1n+pp):
  (+e, he) = l
  (1n+e, Equal.trans(Nat, Nat.add(y, 1n+e), 1n+Nat.add(y, e), 1n+pp, N.add_succ_r(y, e), Equal.cong(Nat, Nat, w => 1n+w, Nat.add(y, e), pp, he)))

# x + (-y) == k  ==>  x == y + k, for canonical x, y.
law neg_eq:
  for +pp: Nat
  for +x: Nat
  for +y: Nat
  for +k: Nat
  for +lx: L.Le(x, pp)
  for +ly: L.Le(y, pp)
  for h: {fadd(1n+pp, x, fsub(1n+pp, 0n, y)) == k : Nat}
  {x == fadd(1n+pp, y, k) : Nat}

def neg_eq(pp, x, y, k, lx, ly, h):
  Equal.trans(Nat, x, Nat.mod(x, 1n+pp), Nat.mod(Nat.add(y, k), 1n+pp),
    Equal.sym(Nat, Nat.mod(x, 1n+pp), x, L.mod_small(x, pp, lx)),
  Equal.trans(Nat, Nat.mod(x, 1n+pp), Nat.mod(Nat.add(x, 1n+pp), 1n+pp), Nat.mod(Nat.add(y, k), 1n+pp),
    Equal.sym(Nat, Nat.mod(Nat.add(x, 1n+pp), 1n+pp), Nat.mod(x, 1n+pp), L.mod_add_self(x, pp)),
  Equal.trans(Nat, Nat.mod(Nat.add(x, 1n+pp), 1n+pp), Nat.mod(Nat.add(x, Nat.add(y, Nat.sub(1n+pp, y))), 1n+pp), Nat.mod(Nat.add(y, k), 1n+pp),
    Equal.cong(Nat, Nat, w => Nat.mod(Nat.add(x, w), 1n+pp), 1n+pp, Nat.add(y, Nat.sub(1n+pp, y)), Equal.sym(Nat, Nat.add(y, Nat.sub(1n+pp, y)), 1n+pp, L.sub_add(1n+pp, y, le_succ(y, pp, ly)))),
  Equal.trans(Nat, Nat.mod(Nat.add(x, Nat.add(y, Nat.sub(1n+pp, y))), 1n+pp), Nat.mod(Nat.add(y, Nat.add(x, Nat.sub(1n+pp, y))), 1n+pp), Nat.mod(Nat.add(y, k), 1n+pp),
    Equal.cong(Nat, Nat, w => Nat.mod(w, 1n+pp), Nat.add(x, Nat.add(y, Nat.sub(1n+pp, y))), Nat.add(y, Nat.add(x, Nat.sub(1n+pp, y))), L.add_left_comm(y, x, Nat.sub(1n+pp, y))),
  Equal.trans(Nat, Nat.mod(Nat.add(y, Nat.add(x, Nat.sub(1n+pp, y))), 1n+pp), Nat.mod(Nat.add(y, Nat.mod(Nat.add(x, Nat.sub(1n+pp, y)), 1n+pp)), 1n+pp), Nat.mod(Nat.add(y, k), 1n+pp),
    Equal.sym(Nat, Nat.mod(Nat.add(y, Nat.mod(Nat.add(x, Nat.sub(1n+pp, y)), 1n+pp)), 1n+pp), Nat.mod(Nat.add(y, Nat.add(x, Nat.sub(1n+pp, y))), 1n+pp), L.mod_add_mod_r(y, Nat.add(x, Nat.sub(1n+pp, y)), pp)),
  Equal.trans(Nat, Nat.mod(Nat.add(y, Nat.mod(Nat.add(x, Nat.sub(1n+pp, y)), 1n+pp)), 1n+pp), Nat.mod(Nat.add(y, Nat.mod(Nat.add(x, Nat.mod(Nat.sub(1n+pp, y), 1n+pp)), 1n+pp)), 1n+pp), Nat.mod(Nat.add(y, k), 1n+pp),
    Equal.cong(Nat, Nat, w => Nat.mod(Nat.add(y, w), 1n+pp), Nat.mod(Nat.add(x, Nat.sub(1n+pp, y)), 1n+pp), Nat.mod(Nat.add(x, Nat.mod(Nat.sub(1n+pp, y), 1n+pp)), 1n+pp), Equal.sym(Nat, Nat.mod(Nat.add(x, Nat.mod(Nat.sub(1n+pp, y), 1n+pp)), 1n+pp), Nat.mod(Nat.add(x, Nat.sub(1n+pp, y)), 1n+pp), L.mod_add_mod_r(x, Nat.sub(1n+pp, y), pp))),
    Equal.cong(Nat, Nat, w => Nat.mod(Nat.add(y, w), 1n+pp), Nat.mod(Nat.add(x, Nat.mod(Nat.sub(1n+pp, y), 1n+pp)), 1n+pp), k, h)))))))

# x + (-y) == 0  ==>  x == y, for canonical x, y.
law neg_zero:
  for +pp: Nat
  for +x: Nat
  for +y: Nat
  for +lx: L.Le(x, pp)
  for +ly: L.Le(y, pp)
  for h: {fadd(1n+pp, x, fsub(1n+pp, 0n, y)) == 0n : Nat}
  {x == y : Nat}

def neg_zero(pp, x, y, lx, ly, h):
  %L.mod_small(y, pp, ly) : {x == _ : Nat}
  %N.add_zero_r(y) : {x == Nat.mod(_, 1n+pp) : Nat}
  neg_eq(pp, x, y, 0n, lx, ly, h)
