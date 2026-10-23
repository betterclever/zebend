import Base
import ./planner.bend as P

# The laws a ZIP 318 (Orchard → Ironwood) migration planner must obey.
# Written as the specification; PROOF.bend proves each one.

# What a returned plan must satisfy (None, "notes too small", is vacuous).

def NoTransparent(m: Maybe<P.Plan>) -> Type:
  match m:
    case None{}:
      Unit
    case Some{p}:
      match p:
        case P.Plan{s, o, c, f, b, sh, ca, fo}:
          P.AllIronwood(P.Output{P.Ironwood{}, c} <> o)

def Canonical(m: Maybe<P.Plan>) -> Type:
  match m:
    case None{}:
      Unit
    case Some{p}:
      match p:
        case P.Plan{s, o, c, f, b, sh, ca, fo}:
          P.AllCanon(o)

def Balanced(m: Maybe<P.Plan>) -> Type:
  match m:
    case None{}:
      Unit
    case Some{p}:
      match p:
        case P.Plan{s, o, c, f, b, sh, ca, fo}:
          {P.notes_total(s) == Nat.add(P.outs_total(P.Output{P.Ironwood{}, c} <> o), f) : Nat}

def FeeIsZip317(m: Maybe<P.Plan>) -> Type:
  match m:
    case None{}:
      Unit
    case Some{p}:
      match p:
        case P.Plan{s, o, c, f, b, sh, ca, fo}:
          {f == P.zip317_fee(P.n_spent(s), 1n+P.n_outputs(o)) : Nat}

# (a) Conservation: the denominations of an amount sum back to the amount.
law conservation:
  for ds: +List<P.Digit>
  {P.total(P.denominate(ds)) == P.amount(ds) : Nat}

# (a') The migration outputs carry exactly the requested amount.
law exact_migration:
  for +ds: +List<P.Digit>
  {P.outs_total(P.to_outputs(P.denominate(ds))) == P.amount(ds) : Nat}

# (b) Every migration output is a ZIP 318 canonical denomination {1,2,5}×10^k.
law canonical:
  for +spent: +List<P.Note>
  for +ds: +List<P.Digit>
  Canonical(P.plan(spent, ds))

# (c) Privacy: no output of any plan (change included) is transparent.
law no_transparent:
  for +spent: +List<P.Note>
  for +ds: +List<P.Digit>
  NoTransparent(P.plan(spent, ds))

# (d) Value balance: inputs = outputs (including change) + fee.
law balanced:
  for +spent: +List<P.Note>
  for +ds: +List<P.Digit>
  Balanced(P.plan(spent, ds))

# (e) The fee is exactly the ZIP 317 conventional fee for the plan's shape.
law fee_is_zip317:
  for +spent: +List<P.Note>
  for +ds: +List<P.Digit>
  FeeIsZip317(P.plan(spent, ds))
