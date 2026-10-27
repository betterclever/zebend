import Base
import ./pools.bend as P

# Laws of the Zcash value pools (ZIP 209 turnstile, ZIP 211, ZIP 258 / NU6.3,
# ZIP 2003 / NU7, ZIP 235). Each law is about the executable `P.apply`, the
# same function the demo runs; PROOF.bend proves every one of them.

# Per-pool accounting: for every pool, out + new == old + in. Balances are Nat,
# so this says exactly that the pool moved by (in - out) and never went below
# zero: the ZIP 209 turnstile.
def Accounted(+s: P.Pools, +x: P.Tx, -s2: P.Pools) -> Type:
  {Nat.add(P.Flow.out(P.Tx.t(x)), P.Pools.t(s2)) == Nat.add(P.Pools.t(s), P.Flow.inp(P.Tx.t(x))) : Nat} &
  {Nat.add(P.Flow.out(P.Tx.sp(x)), P.Pools.sp(s2)) == Nat.add(P.Pools.sp(s), P.Flow.inp(P.Tx.sp(x))) : Nat} &
  {Nat.add(P.Flow.out(P.Tx.sa(x)), P.Pools.sa(s2)) == Nat.add(P.Pools.sa(s), P.Flow.inp(P.Tx.sa(x))) : Nat} &
  {Nat.add(P.Flow.out(P.Tx.orc(x)), P.Pools.orc(s2)) == Nat.add(P.Pools.orc(s), P.Flow.inp(P.Tx.orc(x))) : Nat} &
  {Nat.add(P.Flow.out(P.Tx.iw(x)), P.Pools.iw(s2)) == Nat.add(P.Pools.iw(s), P.Flow.inp(P.Tx.iw(x))) : Nat}

def PostNU63(e: P.Era) -> Bool:
  match e:
    case P.PreNU63{}:
      False{}
    case P.NU63{}:
      True{}
    case P.NU7{}:
      True{}

def Sum.issue(xs: +List<P.Tx>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{x, rest}:
      Nat.add(P.Tx.issue(x), Sum.issue(rest))

def Sum.burn(xs: +List<P.Tx>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{x, rest}:
      Nat.add(P.Tx.burn(x), Sum.burn(rest))

# (a) Turnstile: an accepted transaction moves every pool by exactly its flows
# and never below zero.
law turnstile:
  for +e: P.Era
  for +s: P.Pools
  for +x: P.Tx
  for +s2: P.Pools
  for h: {P.apply(e, s, x) == Some{s2} : Maybe<P.Pools>}
  Accounted(s, x, s2)

# (a') No counterfeit exit: a transaction that withdraws more from Ironwood than
# the pool holds (plus what it deposits) is rejected. This is the backstop
# ZIP 2005 relies on: forged shielded value cannot leave the pool it was forged in.
law no_counterfeit_exit:
  for +e: P.Era
  for +s: P.Pools
  for +x: P.Tx
  for h: {Nat.is_lt(Nat.add(P.Pools.iw(s), P.Flow.inp(P.Tx.iw(x))), P.Flow.out(P.Tx.iw(x))) == True{} : Bool}
  {P.apply(e, s, x) == None{} : Maybe<P.Pools>}

# (b) Supply conservation: total after + burned == total before + issued.
law conservation:
  for +e: P.Era
  for +s: P.Pools
  for +x: P.Tx
  for +s2: P.Pools
  for +h: {P.apply(e, s, x) == Some{s2} : Maybe<P.Pools>}
  {Nat.add(P.Pools.total(s2), P.Tx.burn(x)) == Nat.add(P.Pools.total(s), P.Tx.issue(x)) : Nat}

# (c) NU6.3 (ZIP 258): Orchard is withdraw-only. It shrinks by exactly what
# leaves it, and nothing enters.
law orchard_withdraw_only:
  for +e: P.Era
  for +s: P.Pools
  for +x: P.Tx
  for +s2: P.Pools
  for post: {PostNU63(e) == True{} : Bool}
  for +h: {P.apply(e, s, x) == Some{s2} : Maybe<P.Pools>}
  {Nat.add(P.Flow.out(P.Tx.orc(x)), P.Pools.orc(s2)) == P.Pools.orc(s) : Nat}

# (d) NU7 (ZIP 2003): Sprout is frozen.
law sprout_frozen:
  for +s: P.Pools
  for +x: P.Tx
  for +s2: P.Pools
  for +h: {P.apply(P.NU7{}, s, x) == Some{s2} : Maybe<P.Pools>}
  {P.Pools.sp(s2) == P.Pools.sp(s) : Nat}

# (d') ZIP 211, every era: Sprout never grows.
law sprout_never_grows:
  for +e: P.Era
  for +s: P.Pools
  for +x: P.Tx
  for +s2: P.Pools
  for +h: {P.apply(e, s, x) == Some{s2} : Maybe<P.Pools>}
  {Nat.add(P.Flow.out(P.Tx.sp(x)), P.Pools.sp(s2)) == P.Pools.sp(s) : Nat}

# (d'') Before NU6.3 there is no Ironwood pool to move value through.
law ironwood_dormant_before_nu63:
  for +s: P.Pools
  for +x: P.Tx
  for +s2: P.Pools
  for +h: {P.apply(P.PreNU63{}, s, x) == Some{s2} : Maybe<P.Pools>}
  {P.Pools.iw(s2) == P.Pools.iw(s) : Nat}

# (e) Whole histories: conservation over any accepted sequence of transactions.
law chain_conservation:
  for +e: P.Era
  for xs: +List<P.Tx>
  for +s: P.Pools
  for +s2: P.Pools
  for h: {P.apply_all(e, xs, Some{s}) == Some{s2} : Maybe<P.Pools>}
  {Nat.add(P.Pools.total(s2), Sum.burn(xs)) == Nat.add(P.Pools.total(s), Sum.issue(xs)) : Nat}

# (e') Whole histories after NU6.3: Orchard only ever shrinks.
law chain_orchard_shrinks:
  for +e: P.Era
  for xs: +List<P.Tx>
  for +s: P.Pools
  for +s2: P.Pools
  for +post: {PostNU63(e) == True{} : Bool}
  for h: {P.apply_all(e, xs, Some{s}) == Some{s2} : Maybe<P.Pools>}
  exs k: Nat
  {Nat.add(k, P.Pools.orc(s2)) == P.Pools.orc(s) : Nat}
