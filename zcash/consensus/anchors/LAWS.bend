# Laws about the anchor-validity check (claims; proofs in PROOF.bend).
import Base
import ../../halo2/lib/words.bend as Wd
import ./hist.bend as H

# Soundness of the anchor search: whatever `find` returns is in the history and is a real
# witness: its root equals the anchor and its block precedes the transaction's block.
# For every history, anchor, block height and entry.
law find_sound:
  for +xs: +List<H.HE>
  for +a: Wd.W
  for +b: Nat
  for +e: H.HE
  for h: {H.find(xs, a, b) == Some{e} : Maybe<&2, H.HE>}
  {H.hits(a, b, e) == True{} : Bool} & H.Mem(e, xs)

# The history is append-only: adding a new block's root keeps every earlier witness.
law snoc_keeps:
  for +xs: +List<H.HE>
  for +n: H.HE
  for +e: H.HE
  for m: H.Mem(e, xs)
  H.Mem(e, H.snoc(xs, n))

# ...and the new root is itself in the history.
law snoc_has:
  for +xs: +List<H.HE>
  for +n: H.HE
  H.Mem(n, H.snoc(xs, n))
