import Base
import ../prims/natlib.bend as L
import ../orchard/fieldmodel.bend as F

# Canonicity of a field element's decomposition: NoteCommit's x(g_d) (gate 38 "NoteCommit input
# g_d", the same polynomials as gate 49). The circuit decomposes x = x(g_d) as
#   x = a + 2^250 b_0 + 2^254 b_1      (a: 250 bits, b_0: 4 bits, b_1: 1 bit)
# in Fp. Without more, the pieces could describe x + p instead of x. The canonicity checks
# exist to rule that out; this law proves they do: with them, x equals the INTEGER
# a + 2^250 b_0 + 2^254 b_1, so the decomposition is the unique canonical one.
#
# Every hypothesis is a fact another law or the proof system supplies:
# - e0, e1, i0: law gate_38 ("decomposition", "a_prime_check", "b_1 = 1 => b_0"),
# - bit: law gate_33 ("bool_check b_1"; b_1's cell is copy-constrained between the regions),
# - ra: a < 2^250, law running_sum_range with r = 2^10, n = 25, given the 25 lookups,
# - rb: b_0 < 2^4, the short range check of b_0 (lookup),
# - ra': b_1 = 1 => a' < 2^130, law running_sum_range with n = 13 once "b_1 = 1 => z13_a_prime"
#   (gate_38) has forced z_13(a') = 0,
# - the constants: p = 2^254 + t_P, 2^254 = 16 * 2^250, 1 <= t_P < 2^130 <= 2^250 (checked
#   numerically by gen.py; the law holds for every value satisfying them).
# No primality is used. Fp = Z/p, p = 1 + pp.
law canon_gd:
  for +pp: Nat
  for +t130: Nat
  for +t250: Nat
  for +t254: Nat
  for +tP: Nat
  for +hp: {Nat.add(t254, tP) == 1n+pp : Nat}
  for +h16: {Nat.mul(16n, t250) == t254 : Nat}
  for +htp: L.Le(1n+tP, t130)
  for +htp1: L.Le(1n, tP)
  for +h130: L.Le(t130, t250)
  for +x: Nat
  for +a: Nat
  for +b0: Nat
  for +b1: Nat
  for +ap: Nat
  for +e0: {F.fadd(1n+pp, F.fadd(1n+pp, a, F.fmul(1n+pp, b0, t250)), F.fmul(1n+pp, b1, t254)) == x : Nat}
  for +e1: {F.fadd(1n+pp, a, t130) == F.fadd(1n+pp, tP, ap) : Nat}
  for i0: {b1 == 1n : Nat} -> {b0 == 0n : Nat}
  for bit: Either<&1, &1, {b1 == 0n : Nat}, {b1 == 1n : Nat}>
  for +ra: L.Le(1n+a, t250)
  for +rb: L.Le(1n+b0, 16n)
  for rap: {b1 == 1n : Nat} -> L.Le(1n+ap, t130)
  {x == Nat.add(Nat.add(a, Nat.mul(b0, t250)), Nat.mul(b1, t254)) : Nat}

# NON-VACUITY: every hypothesis at once, with b_1 = 1 (the case the checks are for), on a
# toy instance of the constants: 2^130 -> 2, 2^250 -> 2, 2^254 -> 32, t_P -> 1, p = 33;
# x = 32, a = 0, b_0 = 0, b_1 = 1, a' = 1.
law canon_gd_satisfiable:
  {Nat.add(32n, 1n) == 33n : Nat} & {Nat.mul(16n, 2n) == 32n : Nat} & L.Le(2n, 2n) & L.Le(1n, 1n) & L.Le(2n, 2n)
    & {F.fadd(33n, F.fadd(33n, 0n, F.fmul(33n, 0n, 2n)), F.fmul(33n, 1n, 32n)) == 32n : Nat}
    & {F.fadd(33n, 0n, 2n) == F.fadd(33n, 1n, 1n) : Nat}
    & ({1n == 1n : Nat} -> {0n == 0n : Nat}) & Either<&1, &1, {1n == 0n : Nat}, {1n == 1n : Nat}>
    & L.Le(1n, 2n) & L.Le(1n, 16n) & ({1n == 1n : Nat} -> L.Le(2n, 2n))

# COUNTEREXAMPLE (the a' range check is needed): on the same toy constants, drop rap and keep
# every other hypothesis. Then a = 1 (>= t_P), b_0 = 0, b_1 = 1, a' = 2, x = 0 satisfy them all,
# yet the integer a + 2^254 b_1 = 33 = p is not x: the pieces describe x + p.
law canon_gd_without_aprime_counterexample:
  {Nat.add(32n, 1n) == 33n : Nat} & {Nat.mul(16n, 2n) == 32n : Nat} & L.Le(2n, 2n) & L.Le(1n, 1n) & L.Le(2n, 2n)
    & {F.fadd(33n, F.fadd(33n, 1n, F.fmul(33n, 0n, 2n)), F.fmul(33n, 1n, 32n)) == 0n : Nat}
    & {F.fadd(33n, 1n, 2n) == F.fadd(33n, 1n, 2n) : Nat}
    & ({1n == 1n : Nat} -> {0n == 0n : Nat}) & Either<&1, &1, {1n == 0n : Nat}, {1n == 1n : Nat}>
    & L.Le(2n, 2n) & L.Le(1n, 16n)
    & ({0n == Nat.add(Nat.add(1n, Nat.mul(0n, 2n)), Nat.mul(1n, 32n)) : Nat} -> Empty)
