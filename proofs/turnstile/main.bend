import Base
import ./pools.bend as P

# A scripted history across NU6.2 -> NU6.3 (Ironwood) -> NU7, run through the
# same `P.apply` that PROOF.bend reasons about.
#
# Amounts are in units of 10 zatoshi (1 ZEC = 10,000,000 units), because Bend's
# runtime Nat stops at 2^48-1 and 21M ZEC is 2.1e15 zatoshi.
# Starting balances are ILLUSTRATIVE round numbers, not live chain data.

def zec(n: Nat) -> Nat:
  Nat.mul(n, 10000000n)

def show_zec(+n: Nat) -> String:
  Nat.show(Nat.div(n, 10000000n)) ++ "." ++ String.drop(Nat.show(Nat.add(Nat.mod(n, 10000000n), 10000000n)), 1n)

def show_pools(+s: P.Pools) -> String:
  "t=" ++ show_zec(P.Pools.t(s)) ++ " sprout=" ++ show_zec(P.Pools.sp(s)) ++
  " sapling=" ++ show_zec(P.Pools.sa(s)) ++ " orchard=" ++ show_zec(P.Pools.orc(s)) ++
  " ironwood=" ++ show_zec(P.Pools.iw(s)) ++ "  | total=" ++ show_zec(P.Pools.total(s))

def nothing() -> P.Flow:
  P.Flow{0n, 0n}

# Tx builders: (into-pool, out-of-pool) per pool, then issuance and burn.
def tx(t: P.Flow, sp: P.Flow, sa: P.Flow, orc: P.Flow, iw: P.Flow, issue: Nat, burn: Nat) -> P.Tx:
  P.Tx{t, sp, sa, orc, iw, issue, burn}

def Era.show(e: P.Era) -> String:
  match e:
    case P.PreNU63{}:
      "NU6.2"
    case P.NU63{}:
      "NU6.3"
    case P.NU7{}:
      "NU7  "

# Applies one transaction; keeps the old state if it is rejected.
def step.fin(+s: P.Pools, m: Maybe<P.Pools>) -> (P.Pools & String):
  match m:
    case None{}:
      (s, "REJECTED")
    case Some{+s2}:
      (s2, "accepted")

def step.out(+e: P.Era, label: String, r: P.Pools & String) -> IO(P.Pools):
  (+s2, verdict) = r
  do IO<P.Pools>:
    IO.print("[" ++ Era.show(e) ++ "] " ++ verdict ++ "  " ++ label)
    IO.print("          " ++ show_pools(s2))
    return s2

def step(+e: P.Era, +s: P.Pools, +x: P.Tx, label: String) -> IO(P.Pools):
  step.out(e, label, step.fin(s, P.apply(e, s, x)))

def main() -> IO(Unit):
  do IO<Unit>:
    +s0 : P.Pools = P.Pools{zec(11000000n), zec(25000n), zec(1000000n), zec(4500000n), 0n}
    IO.print("Illustrative starting balances (not live chain data):")
    IO.print("          " ++ show_pools(s0))
    IO.print("")
    s1 : P.Pools <- step(P.PreNU63{}, s0,
      tx(P.Flow{0n, zec(100n)}, nothing(), nothing(), P.Flow{zec(100n), 0n}, nothing(), 0n, 0n),
      "shield 100 ZEC: transparent -> Orchard")
    s2 : P.Pools <- step(P.PreNU63{}, s1,
      tx(P.Flow{0n, zec(50n)}, nothing(), nothing(), nothing(), P.Flow{zec(50n), 0n}, 0n, 0n),
      "deposit into Ironwood before it activates (ZIP 258)")
    s3 : P.Pools <- step(P.NU63{}, s2,
      tx(P.Flow{0n, zec(10n)}, nothing(), nothing(), P.Flow{zec(10n), 0n}, nothing(), 0n, 0n),
      "deposit into Orchard after NU6.3: Orchard is withdraw-only (ZIP 258)")
    s4 : P.Pools <- step(P.NU63{}, s3,
      tx(nothing(), nothing(), nothing(), P.Flow{0n, zec(1000000n)}, P.Flow{zec(1000000n), 0n}, 0n, 0n),
      "migrate 1,000,000 ZEC: Orchard -> Ironwood (ZIP 318)")
    s5 : P.Pools <- step(P.NU63{}, s4,
      tx(P.Flow{zec(1000001n), 0n}, nothing(), nothing(), nothing(), P.Flow{0n, zec(1000001n)}, 0n, 0n),
      "COUNTERFEIT: forged Ironwood notes try to exit 1,000,001 ZEC (pool holds 1,000,000)")
    s6 : P.Pools <- step(P.NU63{}, s5,
      tx(P.Flow{zec(250000n), 0n}, nothing(), nothing(), nothing(), P.Flow{0n, zec(250000n)}, 0n, 0n),
      "unshield 250,000 ZEC: Ironwood -> transparent")
    s7 : P.Pools <- step(P.NU7{}, s6,
      tx(P.Flow{zec(1n), 0n}, P.Flow{0n, zec(1n)}, nothing(), nothing(), nothing(), 0n, 0n),
      "withdraw from Sprout after NU7: v4 transactions are gone (ZIP 2003)")
    s8 : P.Pools <- step(P.NU7{}, s7,
      tx(P.Flow{5208333n, 0n}, nothing(), nothing(), nothing(), P.Flow{0n, 6n}, 5208333n, 6n),
      "coinbase: issue 0.5208333 ZEC; burn 60 zat of fees (ZIP 235)")
    s9 : P.Pools <- step(P.NU7{}, s8,
      tx(P.Flow{0n, zec(5n)}, nothing(), nothing(), nothing(), P.Flow{zec(5n), 0n}, zec(1n), 0n),
      "unbalanced: claims 1 ZEC of issuance it has no right to")
    IO.print("")
    IO.print("Supply check (laws `conservation` / `chain_conservation`):")
    IO.print("  start total + issued - burned = " ++ show_zec(Nat.sub(Nat.add(P.Pools.total(s0), 5208333n), 6n)))
    IO.print("  end total                     = " ++ show_zec(P.Pools.total(s9)))
