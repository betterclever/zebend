# The per-block root history of a note commitment tree, and the anchor rule:
# an Orchard/Ironwood anchor is valid iff it equals the tree root at the end of some
# block before the transaction's block (protocol spec §4.6 / ZIP 229 for Ironwood).
import Base
import ../../halo2/lib/words.bend as Wd

# One history entry: the tree root as of the end of block `height`.
type HE is Data:
  HE{height: Nat, root: Wd.W}

# An entry witnesses anchor `a` for a transaction in block `b`.
def hits(+a: Wd.W, +b: Nat, e: HE) -> Bool:
  HE{h, r} = e
  Bool.and(Wd.is_eq(r, a), Nat.is_lt(h, b))

def pick(c: Bool, x: HE, r: Maybe<&2, HE>) -> Maybe<&2, HE>:
  match c:
    case True{}:
      Some{x}
    case False{}:
      r

# The first entry that witnesses `a` for block `b`, if any.
def find(xs: +List<HE>, +a: Wd.W, +b: Nat) -> Maybe<&2, HE>:
  match xs:
    case Nil{}:
      None{}
    case Con{+x, rest}:
      pick(hits(a, b, x), x, find(rest, a, b))

# Membership, as a type.
def Mem(e: HE, xs: +List<HE>) -> Type:
  match xs:
    case Nil{}:
      Empty
    case Con{x, rest}:
      Either<&1, &1, {x == e : HE}, Mem(e, rest)>

# Appending a block's root at the end of the history.
def snoc(xs: +List<HE>, e: HE) -> +List<HE>:
  match xs:
    case Nil{}:
      [e]
    case Con{x, rest}:
      x <> snoc(rest, e)
