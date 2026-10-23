import Base

# ZIP 318 migration planner (Orchard → Ironwood), modelled in Bend 2.
#
# Amounts are given as little-endian decimal digit lists so that splitting an
# amount into ZIP 318 canonical denominations {1,2,5}×10^k is digit-local and
# provable by structural recursion.

# Pools
# -----

type Pool is Data:
  Transparent{}
  Orchard{}
  Ironwood{}

# Canonical mantissas: the only three a ZIP 318 denomination may start with.
type Mant is Data:
  One{}
  Two{}
  Five{}

type Digit is Data:
  D0{}
  D1{}
  D2{}
  D3{}
  D4{}
  D5{}
  D6{}
  D7{}
  D8{}
  D9{}

# A piece of value mant × 10^exp zatoshi.
type Piece is Data:
  Piece{mant: Mant, exp: Nat}

# A note being migrated (spent from Orchard).
type Note is Data:
  Note{pool: Pool, value: Nat}

# A transaction output.
type Output is Data:
  Output{pool: Pool, value: Nat}

# Nat lemmas
# ----------

law add_zero_r:
  for x: Nat
  {Nat.add(x, 0n) == x : Nat}

def add_zero_r(x):
  match x:
    case 0n:
      {==}
    case 1n+p:
      %add_zero_r(p) : {1n+Nat.add(p, 0n) == 1n+_ : Nat}
      {==}

law add_succ_r:
  for a: Nat
  for -b: Nat
  {Nat.add(a, 1n+b) == 1n+Nat.add(a, b) : Nat}

def add_succ_r(a, b):
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_succ_r(p, b) : {1n+Nat.add(p, 1n+b) == 1n+_ : Nat}
      {==}

law add_assoc:
  for a: Nat
  for -b: Nat
  for -c: Nat
  {Nat.add(Nat.add(a, b), c) == Nat.add(a, Nat.add(b, c)) : Nat}

def add_assoc(a, b, c):
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_assoc(p, b, c) : {1n+Nat.add(Nat.add(p, b), c) == 1n+_ : Nat}
      {==}

law add_succ_eq:
  for c: Nat
  for -n: Nat
  for -h: Nat
  for e: {Nat.add(c, n) == h : Nat}
  {Nat.add(c, 1n+n) == 1n+h : Nat}

def add_succ_eq(c, n, h, e):
  %Equal.sym(Nat, Nat.add(c, 1n+n), 1n+Nat.add(c, n), add_succ_r(c, n)) : {_ == 1n+h : Nat}
  %e : {1n+Nat.add(c, n) == 1n+_ : Nat}
  {==}

# Arithmetic helpers
# ------------------

def mval(m: Mant) -> Nat:
  match m:
    case One{}:
      1n
    case Two{}:
      2n
    case Five{}:
      5n

def dval(d: Digit) -> Nat:
  match d:
    case D0{}:
      0n
    case D1{}:
      1n
    case D2{}:
      2n
    case D3{}:
      3n
    case D4{}:
      4n
    case D5{}:
      5n
    case D6{}:
      6n
    case D7{}:
      7n
    case D8{}:
      8n
    case D9{}:
      9n

def pow10(k: Nat) -> Nat:
  match k:
    case 0n:
      1n
    case 1n+p:
      Nat.mul(10n, pow10(p))

def pval(p: Piece) -> Nat:
  match p:
    case Piece{m, k}:
      Nat.mul(mval(m), pow10(k))

# Value of a digit list whose head sits at place k.
def amount_at(ds: +List<Digit>, +k: Nat) -> Nat:
  match ds:
    case Nil{}:
      0n
    case Con{d, t}:
      Nat.add(Nat.mul(dval(d), pow10(k)), amount_at(t, 1n+k))

def amount(ds: +List<Digit>) -> Nat:
  amount_at(ds, 0n)

# Denomination
# ------------

# Each decimal digit as at most three canonical mantissas.
def digit_mants(d: Digit) -> +List<Mant>:
  match d:
    case D0{}:
      []
    case D1{}:
      [One{}]
    case D2{}:
      [Two{}]
    case D3{}:
      [One{}, Two{}]
    case D4{}:
      [Two{}, Two{}]
    case D5{}:
      [Five{}]
    case D6{}:
      [One{}, Five{}]
    case D7{}:
      [Two{}, Five{}]
    case D8{}:
      [One{}, Two{}, Five{}]
    case D9{}:
      [Two{}, Two{}, Five{}]

def msum(ms: +List<Mant>) -> Nat:
  match ms:
    case Nil{}:
      0n
    case Con{m, t}:
      Nat.add(mval(m), msum(t))

# Places the mantissas at exponent k in front of `rest`.
def put(ms: +List<Mant>, +k: Nat, rest: +List<Piece>) -> +List<Piece>:
  match ms:
    case Nil{}:
      rest
    case Con{m, t}:
      Piece{m, k} <> put(t, k, rest)

def denom_at(ds: +List<Digit>, +k: Nat) -> +List<Piece>:
  match ds:
    case Nil{}:
      []
    case Con{d, t}:
      put(digit_mants(d), k, denom_at(t, 1n+k))

# Splits an amount into ZIP 318 canonical denominations.
def denominate(ds: +List<Digit>) -> +List<Piece>:
  denom_at(ds, 0n)

def total(ps: +List<Piece>) -> Nat:
  match ps:
    case Nil{}:
      0n
    case Con{p, t}:
      Nat.add(pval(p), total(t))

# Plans
# -----

def notes_total(ns: +List<Note>) -> Nat:
  match ns:
    case Nil{}:
      0n
    case Con{n, t}:
      match n:
        case Note{_, v}:
          Nat.add(v, notes_total(t))

def outs_total(os: +List<Output>) -> Nat:
  match os:
    case Nil{}:
      0n
    case Con{o, t}:
      match o:
        case Output{_, v}:
          Nat.add(v, outs_total(t))

# ZIP 317: fee = 5000 zat × max(2, logical actions); for an Orchard-protocol
# bundle the logical actions are max(spends, outputs).
def zip317_fee(spends: Nat, outputs: Nat) -> Nat:
  Nat.mul(5000n, Nat.max(2n, Nat.max(spends, outputs)))

# Change with an erased proof: change + need == have.
type Change<-need: Nat, -have: Nat> is Data:
  Change{change: Nat, -ok: {Nat.add(change, need) == have : Nat}}

def bool_disc(b: Bool) -> Type:
  match b:
    case False{}:
      Unit
    case True{}:
      Empty

law false_ne_true:
  for e: {False{} == True{} : Bool}
  Empty

def false_ne_true(e):
  %e : bool_disc(_)
  Unit{}

law sub_add:
  for +h: Nat
  for +n: Nat
  for e: {Nat.is_ge(h, n) == True{} : Bool}
  {Nat.add(Nat.sub(h, n), n) == h : Nat}

def sub_add(h, n, e):
  match h n:
    case 0n 0n:
      {==}
    case 0n 1n+np:
      Empty.absurd({Nat.add(Nat.sub(0n, 1n+np), 1n+np) == 0n : Nat}, false_ne_true(e))
    case 1n+hp 0n:
      add_zero_r(1n+hp)
    case 1n+hp 1n+np:
      add_succ_eq(Nat.sub(hp, np), np, hp, sub_add(hp, np, e))

def split.if(+need: Nat, +have: Nat, b: Bool, -e: {Nat.is_ge(have, need) == b : Bool}) -> Maybe<Change<need, have>>:
  match b:
    case True{}:
      Some{Change{Nat.sub(have, need), sub_add(have, need, e)}}
    case False{}:
      None{}

# `split(need, have)`: the change left after paying `need` from `have`, or None.
def split(+need: Nat, +have: Nat) -> Maybe<Change<need, have>>:
  split.if(need, have, Nat.is_ge(have, need), {==})

# Conservation lemmas
# -------------------

law mul_distrib:
  for a: Nat
  for -b: Nat
  for +p: Nat
  {Nat.mul(Nat.add(a, b), p) == Nat.add(Nat.mul(a, p), Nat.mul(b, p)) : Nat}

def mul_distrib(a, b, p):
  match a:
    case 0n:
      {==}
    case 1n+q:
      %Equal.sym(Nat, Nat.mul(Nat.add(q, b), p), Nat.add(Nat.mul(q, p), Nat.mul(b, p)), mul_distrib(q, b, p)) : {Nat.add(p, _) == Nat.add(Nat.add(p, Nat.mul(q, p)), Nat.mul(b, p)) : Nat}
      %add_assoc(p, Nat.mul(q, p), Nat.mul(b, p)) : {_ == Nat.add(Nat.add(p, Nat.mul(q, p)), Nat.mul(b, p)) : Nat}
      {==}

law digit_sum:
  for d: Digit
  {msum(digit_mants(d)) == dval(d) : Nat}

def digit_sum(d):
  match d:
    case D0{}:
      {==}
    case D1{}:
      {==}
    case D2{}:
      {==}
    case D3{}:
      {==}
    case D4{}:
      {==}
    case D5{}:
      {==}
    case D6{}:
      {==}
    case D7{}:
      {==}
    case D8{}:
      {==}
    case D9{}:
      {==}

law put_total:
  for ms: +List<Mant>
  for +k: Nat
  for -rest: +List<Piece>
  {total(put(ms, k, rest)) == Nat.add(Nat.mul(msum(ms), pow10(k)), total(rest)) : Nat}

def put_total(ms, k, rest):
  match ms:
    case Nil{}:
      {==}
    case Con{+m, t}:
      %Equal.sym(Nat, total(put(t, k, rest)), Nat.add(Nat.mul(msum(t), pow10(k)), total(rest)), put_total(t, k, rest)) : {Nat.add(Nat.mul(mval(m), pow10(k)), _) == Nat.add(Nat.mul(Nat.add(mval(m), msum(t)), pow10(k)), total(rest)) : Nat}
      %Equal.sym(Nat, Nat.mul(Nat.add(mval(m), msum(t)), pow10(k)), Nat.add(Nat.mul(mval(m), pow10(k)), Nat.mul(msum(t), pow10(k))), mul_distrib(mval(m), msum(t), pow10(k))) : {Nat.add(Nat.mul(mval(m), pow10(k)), Nat.add(Nat.mul(msum(t), pow10(k)), total(rest))) == Nat.add(_, total(rest)) : Nat}
      %add_assoc(Nat.mul(mval(m), pow10(k)), Nat.mul(msum(t), pow10(k)), total(rest)) : {_ == Nat.add(Nat.add(Nat.mul(mval(m), pow10(k)), Nat.mul(msum(t), pow10(k))), total(rest)) : Nat}
      {==}

law conservation_at:
  for ds: +List<Digit>
  for +k: Nat
  {total(denom_at(ds, k)) == amount_at(ds, k) : Nat}

def conservation_at(ds, k):
  match ds:
    case Nil{}:
      {==}
    case Con{+d, t}:
      %Equal.sym(Nat, total(put(digit_mants(d), k, denom_at(t, 1n+k))), Nat.add(Nat.mul(msum(digit_mants(d)), pow10(k)), total(denom_at(t, 1n+k))), put_total(digit_mants(d), k, denom_at(t, 1n+k))) : {_ == Nat.add(Nat.mul(dval(d), pow10(k)), amount_at(t, 1n+k)) : Nat}
      %Equal.sym(Nat, msum(digit_mants(d)), dval(d), digit_sum(d)) : {Nat.add(Nat.mul(_, pow10(k)), total(denom_at(t, 1n+k))) == Nat.add(Nat.mul(dval(d), pow10(k)), amount_at(t, 1n+k)) : Nat}
      %Equal.sym(Nat, total(denom_at(t, 1n+k)), amount_at(t, 1n+k), conservation_at(t, 1n+k)) : {Nat.add(Nat.mul(dval(d), pow10(k)), _) == Nat.add(Nat.mul(dval(d), pow10(k)), amount_at(t, 1n+k)) : Nat}
      {==}

# Outputs
# -------

# Every denomination becomes its own Ironwood output.
def to_outputs(ps: +List<Piece>) -> +List<Output>:
  match ps:
    case Nil{}:
      []
    case Con{p, t}:
      Output{Ironwood{}, pval(p)} <> to_outputs(t)

law outs_conserve:
  for ps: +List<Piece>
  {outs_total(to_outputs(ps)) == total(ps) : Nat}

def outs_conserve(ps):
  match ps:
    case Nil{}:
      {==}
    case Con{p, t}:
      %Equal.sym(Nat, outs_total(to_outputs(t)), total(t), outs_conserve(t)) : {Nat.add(pval(p), _) == Nat.add(pval(p), total(t)) : Nat}
      {==}

# No output may be transparent: every output must be Ironwood.
def AllIronwood(os: +List<Output>) -> Type:
  match os:
    case Nil{}:
      Unit
    case Con{o, t}:
      match o:
        case Output{pl, v}:
          {pl == Ironwood{} : Pool} & AllIronwood(t)

def iron_outs(ps: +List<Piece>) -> AllIronwood(to_outputs(ps)):
  match ps:
    case Nil{}:
      Unit{}
    case Con{p, t}:
      ({==}, iron_outs(t))

# ZIP 318 canonical denomination: v = m × 10^k with m ∈ {1, 2, 5}.
def IsCanonical(v: Nat) -> Type:
  &m: Mant -> &k: Nat -> {v == Nat.mul(mval(m), pow10(k)) : Nat}

def AllCanon(os: +List<Output>) -> Type:
  match os:
    case Nil{}:
      Unit
    case Con{o, t}:
      match o:
        case Output{pl, v}:
          IsCanonical(v) & AllCanon(t)

def canon_outs(ps: +List<Piece>) -> AllCanon(to_outputs(ps)):
  match ps:
    case Nil{}:
      Unit{}
    case Con{p, t}:
      match p:
        case Piece{m, k}:
          ((m, (k, {==})), canon_outs(t))

# Plans
# -----

def n_spent(ns: +List<Note>) -> Nat:
  List.length(&2, Note, ns)

def n_outputs(os: +List<Output>) -> Nat:
  List.length(&2, Output, os)

# A migration plan. Its type carries its invariants as (erased) proofs, so a
# Plan that leaks to the transparent pool, uses a non-canonical denomination,
# fails to balance, or underpays the ZIP 317 fee cannot even be constructed.
# The change output goes to the wallet's own Ironwood (internal) address.
type Plan is Data:
  Plan{spent: +List<Note>, outputs: +List<Output>, change: Nat, fee: Nat, -balanced: {notes_total(spent) == Nat.add(outs_total(Output{Ironwood{}, change} <> outputs), fee) : Nat}, -shielded: AllIronwood(outputs), -canonical: AllCanon(outputs), -fee_ok: {fee == zip317_fee(n_spent(spent), 1n+n_outputs(outputs)) : Nat}}

law balance_of:
  for +c: Nat
  for -t: Nat
  for -f: Nat
  for -v: Nat
  for e: {Nat.add(c, Nat.add(t, f)) == v : Nat}
  {v == Nat.add(Nat.add(c, t), f) : Nat}

def balance_of(c, t, f, v, e):
  %Equal.sym(Nat, Nat.add(Nat.add(c, t), f), Nat.add(c, Nat.add(t, f)), add_assoc(c, t, f)) : {v == _ : Nat}
  Equal.sym(Nat, Nat.add(c, Nat.add(t, f)), v, e)

def plan.mk(+spent: +List<Note>, +outs: +List<Output>, +fee: Nat, -shielded: AllIronwood(outs), -canonical: AllCanon(outs), -fee_ok: {fee == zip317_fee(n_spent(spent), 1n+n_outputs(outs)) : Nat}, r: Maybe<Change<Nat.add(outs_total(outs), fee), notes_total(spent)>>) -> Maybe<Plan>:
  match r:
    case None{}:
      None{}
    case Some{ch}:
      match ch:
        case Change{+c, ok}:
          Some{Plan{spent, outs, c, fee, balance_of(c, outs_total(outs), fee, notes_total(spent), ok), shielded, canonical, fee_ok}}

# Plans the migration of `amount` (decimal digits, little-endian) from the
# Orchard notes `spent`: one Ironwood output per ZIP 318 denomination, the rest
# (minus the ZIP 317 fee) as Ironwood change. None if the notes are too small.
def plan(+spent: +List<Note>, ds: +List<Digit>) -> Maybe<Plan>:
  +ps = denominate(ds)
  +outs = to_outputs(ps)
  +fee = zip317_fee(n_spent(spent), 1n+n_outputs(outs))
  plan.mk(spent, outs, fee, iron_outs(ps), canon_outs(ps), {==}, split(Nat.add(outs_total(outs), fee), notes_total(spent)))
