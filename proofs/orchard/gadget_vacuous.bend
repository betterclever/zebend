import Base
import ../prims/natlib.bend as L
import ../gadget/gadget.bend as G

# gadget/'s hypothesis NoZeroDivisors(p) quantifies over all Nats, not just canonical
# elements below p. Then x = p, y = 1 is a zero divisor (p * 1 mod p == 0), so the
# hypothesis is false for every p >= 1 and gadget/'s bool_gate_sound holds vacuously.
# fieldmodel.bend's NZD restricts x, y to canonical elements, which a prime p satisfies.
law nzd_unsatisfiable:
  for +pp: Nat
  for nzd: G.NoZeroDivisors(1n+pp)
  Empty

def nzd_go(+pp: Nat, e: Either<&1, &1, {1n+pp == 0n : Nat}, {1n == 0n : Nat}>) -> Empty:
  match e:
    case Inl{z}:
      L.succ_ne_zero(pp, z)
    case Inr{z}:
      L.succ_ne_zero(0n, z)

def nzd_zero(+pp: Nat) -> {G.fmul(1n+pp, 1n+pp, 1n) == 0n : Nat}:
  %Equal.sym(Nat, Nat.mul(1n+pp, 1n), 1n+pp, L.mul_one_r(1n+pp)) : {Nat.mod(_, 1n+pp) == 0n : Nat}
  L.mod_add_self(0n, pp)

def nzd_unsatisfiable(pp, nzd):
  nzd_go(pp, nzd(1n+pp, 1n, nzd_zero(pp)))

