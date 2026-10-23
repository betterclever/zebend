# Proofs for LAWS.bend.
import Base
import ../../halo2/lib/words.bend as Wd
import ./nfset.bend as N
import ./LAWS.bend as Laws

# Induction on the key path; in every case both sides compute to the same term once the
# induction hypothesis on the child is used.
def Laws.get_ins(bits, t, v):
  match bits t:
    case Nil{} N.NE{}:
      {==}
    case Nil{} N.NN{ws, z, o}:
      {==}
    case Con{True{}, rest} N.NE{}:
      Laws.get_ins(rest, N.NE{}, v)
    case Con{False{}, rest} N.NE{}:
      Laws.get_ins(rest, N.NE{}, v)
    case Con{True{}, rest} N.NN{ws, z, o}:
      Laws.get_ins(rest, o, v)
    case Con{False{}, rest} N.NN{ws, z, o}:
      Laws.get_ins(rest, z, v)
