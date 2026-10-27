import Base

# Zcash chain value pools and the ZIP 209 turnstile, as a checkable model.
#
# Balances are Nat in a fixed unit (the demo uses 10 zatoshi, because Bend's
# runtime Nat tops out at 2^48-1 and the 21M ZEC supply is 2.1e15 zatoshi).
# Every law is unit-independent.

# Network-upgrade eras that change the pool rules.
#   PreNU63: Canopy..NU6.2. Ironwood does not exist yet.
#   NU63:    Ironwood activates (ZIP 258); Orchard becomes withdraw-only.
#   NU7:     v4 transactions disabled (ZIP 2003), so Sprout is frozen;
#            part of each fee may be burned (ZIP 235).
type Era is Data:
  PreNU63{}
  NU63{}
  NU7{}

# Value a transaction moves into (`inp`) and out of (`out`) one pool.
# For a shielded pool this is its value balance split by sign; for the
# transparent pool, inputs spent are `out` and outputs created are `inp`.
type Flow is Data:
  Flow{inp: Nat, out: Nat}

type Pools is Data:
  Pools{t: Nat, sp: Nat, sa: Nat, orc: Nat, iw: Nat}

# `issue` is new coin from the block subsidy (coinbase). `burn` is value
# destroyed (ZIP 235, NU7 only). Fees are not a separate field: a fee is
# value leaving one pool and entering the miner's coinbase output in the same
# block, so at block granularity it is just another flow.
type Tx is Data:
  Tx{t: Flow, sp: Flow, sa: Flow, orc: Flow, iw: Flow, issue: Nat, burn: Nat}

# Accessors
# ---------

def Flow.inp(f: Flow) -> Nat:
  match f:
    case Flow{i, o}:
      i

def Flow.out(f: Flow) -> Nat:
  match f:
    case Flow{i, o}:
      o

def Pools.t(p: Pools) -> Nat:
  match p:
    case Pools{t, sp, sa, orc, iw}:
      t

def Pools.sp(p: Pools) -> Nat:
  match p:
    case Pools{t, sp, sa, orc, iw}:
      sp

def Pools.sa(p: Pools) -> Nat:
  match p:
    case Pools{t, sp, sa, orc, iw}:
      sa

def Pools.orc(p: Pools) -> Nat:
  match p:
    case Pools{t, sp, sa, orc, iw}:
      orc

def Pools.iw(p: Pools) -> Nat:
  match p:
    case Pools{t, sp, sa, orc, iw}:
      iw

def Tx.t(x: Tx) -> Flow:
  match x:
    case Tx{t, sp, sa, orc, iw, issue, burn}:
      t

def Tx.sp(x: Tx) -> Flow:
  match x:
    case Tx{t, sp, sa, orc, iw, issue, burn}:
      sp

def Tx.sa(x: Tx) -> Flow:
  match x:
    case Tx{t, sp, sa, orc, iw, issue, burn}:
      sa

def Tx.orc(x: Tx) -> Flow:
  match x:
    case Tx{t, sp, sa, orc, iw, issue, burn}:
      orc

def Tx.iw(x: Tx) -> Flow:
  match x:
    case Tx{t, sp, sa, orc, iw, issue, burn}:
      iw

def Tx.issue(x: Tx) -> Nat:
  match x:
    case Tx{t, sp, sa, orc, iw, issue, burn}:
      issue

def Tx.burn(x: Tx) -> Nat:
  match x:
    case Tx{t, sp, sa, orc, iw, issue, burn}:
      burn

# Sums, right-nested so proofs can line them up term by term.
def Pools.total(p: Pools) -> Nat:
  match p:
    case Pools{t, sp, sa, orc, iw}:
      Nat.add(t, Nat.add(sp, Nat.add(sa, Nat.add(orc, iw))))

def Tx.ins(x: Tx) -> Nat:
  match x:
    case Tx{t, sp, sa, orc, iw, issue, burn}:
      Nat.add(Flow.inp(t), Nat.add(Flow.inp(sp), Nat.add(Flow.inp(sa), Nat.add(Flow.inp(orc), Flow.inp(iw)))))

def Tx.outs(x: Tx) -> Nat:
  match x:
    case Tx{t, sp, sa, orc, iw, issue, burn}:
      Nat.add(Flow.out(t), Nat.add(Flow.out(sp), Nat.add(Flow.out(sa), Nat.add(Flow.out(orc), Flow.out(iw)))))

# The turnstile, one pool at a time
# ---------------------------------

# Checked subtraction: Some(a - b) exactly when b <= a. A pool may never be
# drawn below zero; that is the whole of ZIP 209. (Built on Base's Nat.is_le and
# Nat.sub, which Bend runs natively; a hand-written unary recursion would take
# one step per 10 zatoshi.)
def csub.go(ok: Bool, +a: Nat, +b: Nat) -> Maybe<Nat>:
  match ok:
    case False{}:
      None{}
    case True{}:
      Some{Nat.sub(a, b)}

def csub(+a: Nat, +b: Nat) -> Maybe<Nat>:
  csub.go(Nat.is_le(b, a), a, b)

def pool_step(bal: Nat, f: Flow) -> Maybe<Nat>:
  match f:
    case Flow{i, o}:
      csub(Nat.add(bal, i), o)

# All five pools must pass; any underflow rejects the transaction.
def step5(a: Maybe<Nat>, b: Maybe<Nat>, c: Maybe<Nat>, d: Maybe<Nat>, e: Maybe<Nat>) -> Maybe<Pools>:
  match a:
    case None{}:
      None{}
    case Some{x1}:
      match b:
        case None{}:
          None{}
        case Some{x2}:
          match c:
            case None{}:
              None{}
            case Some{x3}:
              match d:
                case None{}:
                  None{}
                case Some{x4}:
                  match e:
                    case None{}:
                      None{}
                    case Some{x5}:
                      Some{Pools{x1, x2, x3, x4, x5}}

def step(s: Pools, x: Tx) -> Maybe<Pools>:
  match s x:
    case Pools{t, sp, sa, orc, iw} Tx{ft, fsp, fsa, forc, fiw, issue, burn}:
      step5(pool_step(t, ft), pool_step(sp, fsp), pool_step(sa, fsa), pool_step(orc, forc), pool_step(iw, fiw))

# Era rules
# ---------

def is_zero(n: Nat) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      False{}

# ZIP 211 (Canopy): no value may enter Sprout. Holds in every modelled era.
# ZIP 258 (NU6.3): no value may enter Orchard; Ironwood only exists from NU6.3.
# ZIP 2003 (NU7): v4 transactions are gone, so Sprout cannot be spent either.
# ZIP 235 (NU7): burning is only possible from NU7.
def Era.rules(e: Era, +x: Tx) -> Bool:
  match e:
    case PreNU63{}:
      is_zero(Flow.inp(Tx.sp(x))) && is_zero(Flow.inp(Tx.iw(x))) && is_zero(Flow.out(Tx.iw(x))) && is_zero(Tx.burn(x))
    case NU63{}:
      is_zero(Flow.inp(Tx.sp(x))) && is_zero(Flow.inp(Tx.orc(x))) && is_zero(Tx.burn(x))
    case NU7{}:
      is_zero(Flow.inp(Tx.sp(x))) && is_zero(Flow.out(Tx.sp(x))) && is_zero(Flow.inp(Tx.orc(x)))

# Value balance: everything that leaves a pool, plus new issuance, lands in a
# pool or is burned. Nothing is created or lost in transit.
def balanced(+x: Tx) -> Bool:
  Nat.is_eq(Nat.add(Tx.ins(x), Tx.burn(x)), Nat.add(Tx.outs(x), Tx.issue(x)))

def apply.go(ok: Bool, s: Pools, x: Tx) -> Maybe<Pools>:
  match ok:
    case False{}:
      None{}
    case True{}:
      step(s, x)

# A transaction is accepted iff it obeys its era's pool rules, balances, and
# leaves every pool non-negative.
def apply(e: Era, s: Pools, +x: Tx) -> Maybe<Pools>:
  apply.go(Era.rules(e, x) && balanced(x), s, x)

# One more transaction on top of a possibly-failed history.
def next(+e: Era, m: Maybe<Pools>, +x: Tx) -> Maybe<Pools>:
  match m:
    case None{}:
      None{}
    case Some{s}:
      apply(e, s, x)

# A sequence of transactions (a block, or a chain segment within one era),
# failing as a whole if any transaction fails.
def apply_all(+e: Era, xs: +List<Tx>, m: Maybe<Pools>) -> Maybe<Pools>:
  match xs:
    case Nil{}:
      m
    case Con{x, rest}:
      apply_all(e, rest, next(e, m, x))
