import Base
import ./planner.bend as P
import ./LAWS.bend as Laws

# Abbreviations for the terms `P.plan` unfolds to (definitional, so the
# checker sees through them).

def outs(ps: +List<P.Piece>) -> +List<P.Output>:
  P.to_outputs(ps)

def fee(+spent: +List<P.Note>, +ps: +List<P.Piece>) -> Nat:
  P.zip317_fee(P.n_spent(spent), 1n+P.n_outputs(P.to_outputs(ps)))

def need(+spent: +List<P.Note>, +ps: +List<P.Piece>) -> Nat:
  Nat.add(P.outs_total(P.to_outputs(ps)), fee(spent, ps))

def have(+spent: +List<P.Note>) -> Nat:
  P.notes_total(spent)

# The plan for given pieces, with the branch taken by `split` exposed as `b`.
def planned(+spent: +List<P.Note>, +ps: +List<P.Piece>, b: Bool, -e: {Nat.is_ge(have(spent), need(spent, ps)) == b : Bool}) -> Maybe<P.Plan>:
  P.plan.mk(spent, outs(ps), fee(spent, ps), P.iron_outs(ps), P.canon_outs(ps), {==}, P.split.if(need(spent, ps), have(spent), b, e))

# (a), (a')

def Laws.conservation(ds):
  P.conservation_at(ds, 0n)

def Laws.exact_migration(ds):
  %Equal.sym(Nat, P.outs_total(P.to_outputs(P.denominate(ds))), P.total(P.denominate(ds)), P.outs_conserve(P.denominate(ds))) : {_ == P.amount(ds) : Nat}
  Laws.conservation(ds)

# (b)

def canonical.if(+spent: +List<P.Note>, +ps: +List<P.Piece>, b: Bool, -e: {Nat.is_ge(have(spent), need(spent, ps)) == b : Bool}) -> Laws.Canonical(planned(spent, ps, b, e)):
  match b:
    case True{}:
      P.canon_outs(ps)
    case False{}:
      Unit{}

def Laws.canonical(spent, ds):
  canonical.if(spent, P.denominate(ds), Nat.is_ge(have(spent), need(spent, P.denominate(ds))), {==})

# (c)

def no_transparent.if(+spent: +List<P.Note>, +ps: +List<P.Piece>, b: Bool, -e: {Nat.is_ge(have(spent), need(spent, ps)) == b : Bool}) -> Laws.NoTransparent(planned(spent, ps, b, e)):
  match b:
    case True{}:
      ({==}, P.iron_outs(ps))
    case False{}:
      Unit{}

def Laws.no_transparent(spent, ds):
  no_transparent.if(spent, P.denominate(ds), Nat.is_ge(have(spent), need(spent, P.denominate(ds))), {==})

# (d)

def balanced.if(+spent: +List<P.Note>, +ps: +List<P.Piece>, b: Bool, e: {Nat.is_ge(have(spent), need(spent, ps)) == b : Bool}) -> Laws.Balanced(planned(spent, ps, b, e)):
  match b:
    case True{}:
      P.balance_of(Nat.sub(have(spent), need(spent, ps)), P.outs_total(outs(ps)), fee(spent, ps), have(spent), P.sub_add(have(spent), need(spent, ps), e))
    case False{}:
      Unit{}

def Laws.balanced(spent, ds):
  balanced.if(spent, P.denominate(ds), Nat.is_ge(have(spent), need(spent, P.denominate(ds))), {==})

# (e)

def fee.if(+spent: +List<P.Note>, +ps: +List<P.Piece>, b: Bool, -e: {Nat.is_ge(have(spent), need(spent, ps)) == b : Bool}) -> Laws.FeeIsZip317(planned(spent, ps, b, e)):
  match b:
    case True{}:
      {==}
    case False{}:
      Unit{}

def Laws.fee_is_zip317(spent, ds):
  fee.if(spent, P.denominate(ds), Nat.is_ge(have(spent), need(spent, P.denominate(ds))), {==})
