# Foundation for proving field multiplication correct: the division algorithm for
# Base's Nat.div / Nat.mod (which Base defines via an unspecified accumulator loop,
# Nat.divmod.go, and states no laws about). Every limb identity of mul_hi / mac64
# (defined through Nat.div by powers of two) depends on these.
import Base

# a = (a div b) * b + (a mod b), for every divisor b >= 1.
law divmod_spec:
  for +a: Nat
  for +bp: Nat
  {Nat.add(Nat.mul(Nat.div(a, 1n+bp), 1n+bp), Nat.mod(a, 1n+bp)) == a : Nat}

# a mod b < b: the remainder plus some k is b - 1.
law mod_bound:
  for +a: Nat
  for +bp: Nat
  exs k: Nat
  {Nat.add(Nat.mod(a, 1n+bp), k) == bp : Nat}
