import Base
import ../prims/natlib.bend as L
import ../orchard/fieldmodel.bend as F

# Soundness of the running-sum range check (halo2_gadgets' LookupRangeCheck, used by every
# Orchard decomposition: K = 10, r = 2^10) and the canonicity of a field element's
# decomposition. Fp = Z/p, p = 1 + pp. These laws reason about canonical field elements as
# integers (Nat), which is where canonicity lives.
#
# The lookup argument itself (that a looked-up value is in the table) is a property of the
# proof system, not of the gates: here it is a HYPOTHESIS, `the word is < r`.

# One step of the running sum: the word halo2 looks up, z_cur - z_next * r.
def word(+pp: Nat, +r: Nat, +z: Nat, +z1: Nat) -> Nat:
  F.fadd(1n+pp, z, F.fsub(1n+pp, 0n, F.fmul(1n+pp, z1, r)))

# r^n, as (...((1 r) r)...) r.
def pw(+r: Nat, n: Nat) -> Nat:
  match n:
    case 0n:
      1n
    case 1n+m:
      Nat.mul(pw(r, m), r)

def len(zs: List<&2, Nat>) -> Nat:
  match zs:
    case Nil{}:
      0n
    case Con{_, t}:
      1n+len(t)

def last(zs: List<&2, Nat>, +z: Nat) -> Nat:
  match zs:
    case Nil{}:
      z
    case Con{+z1, t}:
      last(t, z1)

# The running sum z_0 = z, z_1, ..., z_n = zs: every z_i canonical and every looked-up word
# z_i - z_{i+1} r in the table [0, r) (the lookup's guarantee, assumed).
def Steps(+pp: Nat, +r: Nat, zs: List<&2, Nat>, +z: Nat) -> Type:
  match zs:
    case Nil{}:
      Unit
    case Con{+z1, t}:
      L.Le(1n+word(pp, r, z, z1), r) & L.Le(z1, pp) & Steps(pp, r, t, z1)

# THEOREM (strict running-sum range check). If z_0 is canonical, every word of an n-step
# running sum is looked up in [0, r), the last running sum z_n is 0 (the strict check
# copy-constrains it to zero), and r^n <= p, then z_0 < r^n as an integer.
# For Orchard: r = 2^10 and n = 25 (a 250-bit piece) or 13 (z_13 = 0: a 130-bit bound),
# and 2^250 <= p. No primality is used.
law running_sum_range:
  for +pp: Nat
  for +r: Nat
  for +z0: Nat
  for +lz0: L.Le(z0, pp)
  for zs: List<&2, Nat>
  for h: Steps(pp, r, zs, z0)
  for +hz: {last(zs, z0) == 0n : Nat}
  for +hp: L.Le(pw(r, len(zs)), 1n+pp)
  L.Le(1n+z0, pw(r, len(zs)))

# NON-VACUITY (1): for every p, every r >= 1 and every n, the all-zero running sum
# satisfies Steps and ends in 0.
def zeros(n: Nat) -> List<&2, Nat>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      0n <> zeros(m)

law running_sum_zero_satisfiable:
  for +pp: Nat
  for +r: Nat
  for +lr: L.Le(1n, r)
  for +n: Nat
  L.Le(0n, pp) & Steps(pp, r, zeros(n), 0n) & {last(zeros(n), 0n) == 0n : Nat}

# NON-VACUITY (2): every hypothesis at once, with a non-zero value: p = 11, r = 3, n = 2,
# z = 5, 1, 0 (5 = 2 + 3 * 1, words 2 and 1).
law running_sum_range_satisfiable:
  L.Le(5n, 10n) & Steps(10n, 3n, [1n, 0n], 5n) & {last([1n, 0n], 5n) == 0n : Nat} & L.Le(pw(3n, 2n), 11n)

# COUNTEREXAMPLE: without the strict check (z_n == 0) the bound fails: at p = 11, r = 3,
# n = 1, the running sum z_0 = 10, z_1 = 3 has its one word 10 - 9 = 1 in the table, yet
# z_0 = 10 >= 3^1.
law running_sum_nonstrict_counterexample:
  L.Le(10n, 10n) & Steps(10n, 3n, [3n], 10n) & L.Le(pw(3n, 1n), 11n) & (L.Le(11n, pw(3n, 1n)) -> Empty)
