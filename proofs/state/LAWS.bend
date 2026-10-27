# The Merkle theorems of proofs/merkle, transferred to zcash/state's running code:
# its frontier (S.push / S.froot with Sinsemilla MerkleCRH), which rebuilt the real
# mainnet Ironwood tree and matched the chain's roots at 6/6 checkpoints.
import Base
import ../../zcash/halo2/lib/words.bend as Wd
import ../../zcash/state/sinsemilla.bend as S
import ../merkle/merkle.bend as M
import ./refine.bend as R

# zcash/state's S.push commutes with interpretation.
law push_refines:
  for +g: S.Gens
  for +es: +List<Wd.W>
  for +ls: +List<Wd.W>
  for +lv: +List<Maybe<&2, M.HT>>
  for +l: Nat
  for +c: M.HT
  {S.push(R.imap(g, es, ls, lv), l, R.interp(g, es, ls, c), g) == R.imap(g, es, ls, M.push(lv, l, c)) : +List<Maybe<&2, Wd.W>>}

# zcash/state's S.froot commutes with interpretation (for a 32-level frontier).
law froot_refines:
  for +g: S.Gens
  for +es: +List<Wd.W>
  for +ls: +List<Wd.W>
  for +lv: +List<Maybe<&2, M.HT>>
  for +l: Nat
  for +acc: Maybe<&2, M.HT>
  for h: {Nat.add(l, List.length(&2, Maybe<&2, M.HT>, lv)) == 32n : Nat}
  {S.froot(R.imap(g, es, ls, lv), l, R.imaybe(g, es, ls, acc), g, es) == R.interp(g, es, ls, M.froot(lv, l, acc)) : Wd.W}

# frontier_root for the RUNNING code: appending the leaves of any well-formed,
# left-filled, not-full 32-level tree p one by one with zcash/state's S.push, starting
# from S.frontier_new(), and taking S.froot gives the Sinsemilla interpretation of
# the full tree's root.
law frontier_root_running:
  for +g: S.Gens
  for +es: +List<Wd.W>
  for +ls: +List<Wd.W>
  for +p: M.PT
  for +w: M.WF(p, 32n)
  for +nf: M.NotB(M.IsFull(p))
  {S.froot(R.spush_all(R.imapl(g, es, ls, M.pleaves(p)), S.frontier_new(), g), 0n, None{}, g, es) == R.interp(g, es, ls, M.proot(p, 32n)) : Wd.W}

# Path recomputation with the real hash commutes with interpretation ...
law path_refines:
  for +g: S.Gens
  for +es: +List<Wd.W>
  for +ls: +List<Wd.W>
  for +k: Nat
  for +x: M.HT
  for +ds: Word(k)
  for +ss: +List<M.HT>
  {R.srecompute(g, es, k, R.interp(g, es, ls, x), ds, R.imapl(g, es, ls, ss)) == R.interp(g, es, ls, M.recompute(k, x, ds, ss)) : Wd.W}

# ... so path soundness holds with Sinsemilla: the authentication path of any leaf of
# any perfect tree recomputes (the interpretation of) the tree's root.
law path_sound_running:
  for +g: S.Gens
  for +es: +List<Wd.W>
  for +ls: +List<Wd.W>
  for +k: Nat
  for +t: M.Tr
  for +pf: M.Perf(k, t)
  for +ds: Word(k)
  {R.srecompute(g, es, k, R.interp(g, es, ls, M.leaf_at(k, t, ds)), ds, R.imapl(g, es, ls, M.auth(k, t, ds))) == R.interp(g, es, ls, M.troot(k, t)) : Wd.W}
