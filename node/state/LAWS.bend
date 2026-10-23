# Laws for the shielded-state component (human-written claims; proofs in PROOF.bend).
import Base
import ../../halo2/lib/words.bend as Wd
import ./nfset.bend as N

# Inserting a nullifier puts it at the front of exactly the bucket its key selects,
# leaving that bucket's other contents untouched: get(ins(k, t, v), k) == v :: get(t, k).
# For every trie t, every key path k and every value v.
law get_ins:
  for +bits: +List<Bool>
  for t: N.NSet
  for +v: Wd.W
  {N.get(N.ins(bits, t, v), bits) == v <> N.get(t, bits) : +List<Wd.W>}
