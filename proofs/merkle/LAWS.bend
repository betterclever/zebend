import Base
import ./merkle.bend as M

# The incremental frontier is the whole tree.
#
# For every well-formed tree p of height D that is filled from the left and not
# completely full (so it fits in a D-level frontier), pushing p's leaves one by one
# into an empty D-level frontier (`push`, as node/state does block by block) and
# taking the frontier's root (`froot`) gives exactly the root of the tree.
#
# Hn and Em are free constructors standing for the node hash and the empty-subtree
# roots, so the equality holds for every hash function, Sinsemilla included.
law frontier_root:
  for +D: Nat
  for +p: M.PT
  for +w: M.WF(p, D)
  for +nf: M.NotB(M.IsFull(p))
  {M.froot(M.push_all(M.pleaves(p), M.nones(D)), 0n, None{}) == M.proot(p, D) : M.HT}

# Path soundness: the authentication path of any leaf recomputes the tree's root.
law path_sound:
  for +k: Nat
  for +t: M.Tr
  for +pf: M.Perf(k, t)
  for +ds: Word(k)
  {M.recompute(k, M.leaf_at(k, t, ds), ds, M.auth(k, t, ds)) == M.troot(k, t) : M.HT}

# Path binding: if any claimed leaf x with any sibling list verifies against the
# tree's root, x IS the tree's leaf at that position. With Hn a free constructor
# (an injective, collision-free hash), no forged leaf verifies; for a real hash,
# a forged path that verifies yields a hash collision.
law path_binding:
  for +k: Nat
  for +t: M.Tr
  for +pf: M.Perf(k, t)
  for +ds: Word(k)
  for -x: M.HT
  for +ss: List<&2, M.HT>
  for e: {M.recompute(k, x, ds, ss) == M.troot(k, t) : M.HT}
  {x == M.leaf_at(k, t, ds) : M.HT}
