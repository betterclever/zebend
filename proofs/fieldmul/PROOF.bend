# Proofs of LAWS.bend: an invariant proof of Base's Nat.divmod.go loop.
#   go(n, m, q, r): n input left, m countdown to the next quotient step, q quotient,
#   r remainder. Invariant: m + r == d (the divisor minus one).
import Base
import ./LAWS.bend as L
import ../field/natlemmas.bend as N

def succ(n: Nat) -> Nat:
  1n+n

def addl(+n: Nat, x: Nat) -> Nat:
  Nat.add(n, x)

def addr(+y: Nat, x: Nat) -> Nat:
  Nat.add(x, y)

def gq(n: Nat, m: Nat, q: Nat, r: Nat) -> Nat:
  Pair.fst(Nat, Nat, Nat.divmod.go(n, m, q, r))

def gr(n: Nat, m: Nat, q: Nat, r: Nat) -> Nat:
  Pair.snd(Nat, Nat, Nat.divmod.go(n, m, q, r))

# q-step: n + ((1 + d + M) + 0) == 1 + n + (M + r), given r == d.
def step_q(+np: Nat, +d: Nat, +mm: Nat, +r: Nat, +h0: {Nat.add(r, 0n) == d : Nat}) -> {Nat.add(np, Nat.add(Nat.add(1n+d, mm), 0n)) == Nat.add(1n+np, Nat.add(mm, r)) : Nat}:
  +h = Equal.trans(Nat, r, Nat.add(r, 0n), d, Equal.sym(Nat, Nat.add(r, 0n), r, N.add_zero_r(r)), h0)
  +e1 = Equal.cong(Nat, Nat, addl(np), Nat.add(Nat.add(1n+d, mm), 0n), Nat.add(1n+d, mm), N.add_zero_r(Nat.add(1n+d, mm)))
  +e2 = N.add_succ_r(np, Nat.add(d, mm))
  +e3 = Equal.cong(Nat, Nat, succ, Nat.add(np, Nat.add(d, mm)), Nat.add(np, Nat.add(mm, d)), Equal.cong(Nat, Nat, addl(np), Nat.add(d, mm), Nat.add(mm, d), N.add_comm(d, mm)))
  +e4 = Equal.cong(Nat, Nat, succ, Nat.add(np, Nat.add(mm, d)), Nat.add(np, Nat.add(mm, r)), Equal.cong(Nat, Nat, addl(np), Nat.add(mm, d), Nat.add(mm, r), Equal.cong(Nat, Nat, addl(mm), d, r, Equal.sym(Nat, r, d, h))))
  Equal.trans(Nat, Nat.add(np, Nat.add(Nat.add(1n+d, mm), 0n)), Nat.add(np, Nat.add(1n+d, mm)), Nat.add(1n+np, Nat.add(mm, r)), e1,
    Equal.trans(Nat, Nat.add(np, 1n+Nat.add(d, mm)), 1n+Nat.add(np, Nat.add(d, mm)), Nat.add(1n+np, Nat.add(mm, r)), e2,
      Equal.trans(Nat, 1n+Nat.add(np, Nat.add(d, mm)), 1n+Nat.add(np, Nat.add(mm, d)), Nat.add(1n+np, Nat.add(mm, r)), e3, e4)))

# r-step: n + (M + (1 + r)) == 1 + n + (M + r).
def step_r(+np: Nat, +mm: Nat, +r: Nat) -> {Nat.add(np, Nat.add(mm, 1n+r)) == Nat.add(1n+np, Nat.add(mm, r)) : Nat}:
  Equal.trans(Nat, Nat.add(np, Nat.add(mm, 1n+r)), Nat.add(np, 1n+Nat.add(mm, r)), Nat.add(1n+np, Nat.add(mm, r)),
    Equal.cong(Nat, Nat, addl(np), Nat.add(mm, 1n+r), 1n+Nat.add(mm, r), N.add_succ_r(mm, r)),
    N.add_succ_r(np, Nat.add(mm, r)))

def go_spec(+n: Nat, +m: Nat, +q: Nat, +r: Nat, +d: Nat) -> {Nat.add(m, r) == d : Nat} -> {Nat.add(Nat.mul(gq(n, m, q, r), 1n+d), gr(n, m, q, r)) == Nat.add(n, Nat.add(Nat.mul(q, 1n+d), r)) : Nat}:
  match n:
    case 0n:
      h => {==}
    case 1n+np:
      match m:
        case 0n:
          h =>
            +h0 = Equal.trans(Nat, Nat.add(r, 0n), r, d, N.add_zero_r(r), h)
            Equal.trans(Nat,
              Nat.add(Nat.mul(gq(np, r, 1n+q, 0n), 1n+d), gr(np, r, 1n+q, 0n)),
              Nat.add(np, Nat.add(Nat.mul(1n+q, 1n+d), 0n)),
              Nat.add(1n+np, Nat.add(Nat.mul(q, 1n+d), r)),
              go_spec(np, r, 1n+q, 0n, d, h0),
              step_q(np, d, Nat.mul(q, 1n+d), r, h0))
        case 1n+mp:
          h =>
            +h1 = Equal.trans(Nat, Nat.add(mp, 1n+r), 1n+Nat.add(mp, r), d, N.add_succ_r(mp, r), h)
            Equal.trans(Nat,
              Nat.add(Nat.mul(gq(np, mp, q, 1n+r), 1n+d), gr(np, mp, q, 1n+r)),
              Nat.add(np, Nat.add(Nat.mul(q, 1n+d), 1n+r)),
              Nat.add(1n+np, Nat.add(Nat.mul(q, 1n+d), r)),
              go_spec(np, mp, q, 1n+r, d, h1),
              step_r(np, Nat.mul(q, 1n+d), r))

def go_bound(+n: Nat, +m: Nat, +q: Nat, +r: Nat, +d: Nat) -> {Nat.add(m, r) == d : Nat} -> &k: Nat -> {Nat.add(gr(n, m, q, r), k) == d : Nat}:
  match n:
    case 0n:
      h => (m, Equal.trans(Nat, Nat.add(r, m), Nat.add(m, r), d, N.add_comm(r, m), h))
    case 1n+np:
      match m:
        case 0n:
          h => go_bound(np, r, 1n+q, 0n, d, Equal.trans(Nat, Nat.add(r, 0n), r, d, N.add_zero_r(r), h))
        case 1n+mp:
          h => go_bound(np, mp, q, 1n+r, d, Equal.trans(Nat, Nat.add(mp, 1n+r), 1n+Nat.add(mp, r), d, N.add_succ_r(mp, r), h))

def L.divmod_spec(a, bp):
  Equal.trans(Nat, Nat.add(Nat.mul(gq(a, bp, 0n, 0n), 1n+bp), gr(a, bp, 0n, 0n)), Nat.add(a, 0n), a,
    go_spec(a, bp, 0n, 0n, bp, N.add_zero_r(bp)), N.add_zero_r(a))

def L.mod_bound(a, bp):
  go_bound(a, bp, 0n, 0n, bp, N.add_zero_r(bp))
