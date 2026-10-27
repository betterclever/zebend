# Zcash mainnet block subsidy, founders' reward and funding streams (protocol spec §7.8,
# §7.9, §7.10; ZIP 207, ZIP 214 revisions 0–2, ZIP 1015, ZIP 2001, ZIP 271). NU7 is not
# active on mainnet at the time of writing, so its changes (ZIP 214 rev. 3, ZIP 235) are
# not modelled.
import Base
import ./params.bend as P

def max_subsidy() -> Nat:
  U32.to_nat(1250000000)

def slow_start_interval() -> Nat:
  U32.to_nat(20000)

def slow_start_shift() -> Nat:
  U32.to_nat(10000)

def pre_blossom_halving_interval() -> Nat:
  U32.to_nat(840000)

def post_blossom_halving_interval() -> Nat:
  U32.to_nat(1680000)

def blossom() -> Nat:
  U32.to_nat(653600)

def canopy() -> Nat:
  U32.to_nat(1046400)

# S(k, m): the subsidy m halved k times, one floor-halving at a time. Equal to
# floor(m / 2^k); written this way so the laws in LAWS.bend are about this exact code.
def halve(k: Nat, m: Nat) -> Nat:
  match k:
    case 0n:
      m
    case 1n+p:
      halve(p, Nat.div(m, 2n))

def halving_pre(+h: Nat) -> Nat:
  Nat.div(Nat.sub(h, slow_start_shift()), pre_blossom_halving_interval())

# floor((B - S)/PreInterval + (h - B)/PostInterval) with PreInterval = PostInterval / 2.
def halving_post(+h: Nat) -> Nat:
  Nat.div(Nat.add(Nat.mul(2n, Nat.sub(blossom(), slow_start_shift())), Nat.sub(h, blossom())), post_blossom_halving_interval())

def halving_ge_shift(pre: Bool, +h: Nat) -> Nat:
  match pre:
    case True{}:
      halving_pre(h)
    case False{}:
      halving_post(h)

def halving_of(lt_shift: Bool, +h: Nat) -> Nat:
  match lt_shift:
    case True{}:
      0n
    case False{}:
      halving_ge_shift(Nat.is_lt(h, blossom()), h)

def halving(+h: Nat) -> Nat:
  halving_of(Nat.is_lt(h, slow_start_shift()), h)

def sub_after_slow(pre: Bool, +h: Nat) -> Nat:
  match pre:
    case True{}:
      halve(halving(h), max_subsidy())
    case False{}:
      halve(halving(h), Nat.div(max_subsidy(), 2n))

def sub_slow2(lt_ssi: Bool, +h: Nat) -> Nat:
  match lt_ssi:
    case True{}:
      Nat.mul(Nat.div(max_subsidy(), slow_start_interval()), 1n+h)
    case False{}:
      sub_after_slow(Nat.is_lt(h, blossom()), h)

def sub_slow1(lt_shift: Bool, +h: Nat) -> Nat:
  match lt_shift:
    case True{}:
      Nat.mul(Nat.div(max_subsidy(), slow_start_interval()), h)
    case False{}:
      sub_slow2(Nat.is_lt(h, slow_start_interval()), h)

def block_subsidy(+h: Nat) -> Nat:
  sub_slow1(Nat.is_lt(h, slow_start_shift()), h)

# --- founders' reward (heights < Canopy) ---------------------------------------------

def founders_adjusted(pre: Bool, +h: Nat) -> Nat:
  match pre:
    case True{}:
      h
    case False{}:
      Nat.add(blossom(), Nat.div(Nat.sub(h, blossom()), 2n))

# ceil((SlowStartShift + PreBlossomHalvingInterval) / 48) = ceil(850000 / 48) = 17709
def founders_index(+h: Nat) -> Nat:
  Nat.div(founders_adjusted(Nat.is_lt(h, blossom()), h), U32.to_nat(17709))

# --- funding streams (ZIP 207 address periods) -------------------------------------

def address_period(+h: Nat) -> Nat:
  Nat.div(Nat.sub(Nat.add(h, post_blossom_halving_interval()), canopy()), U32.to_nat(35000))

def address_index(+start: Nat, +h: Nat) -> Nat:
  Nat.sub(address_period(h), address_period(start))

def fs_value(+subsidy: Nat, +num: Nat) -> Nat:
  Nat.div(Nat.mul(subsidy, num), 100n)

# --- the issuance schedule as a sum ---------------------------------------------------

# Total over K halving eras of one block each, starting from subsidy m:
# total(K, m) = halve(0, m) + halve(1, m) + ... + halve(K-1, m).
def total(K: Nat, +m: Nat) -> Nat:
  match K:
    case 0n:
      0n
    case 1n+p:
      Nat.add(m, total(p, Nat.div(m, 2n)))
