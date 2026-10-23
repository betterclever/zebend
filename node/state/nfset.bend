# A nullifier set: a binary trie on the first key bits of each nullifier, with a
# bucket of full nullifiers at every node. Every node carries a bucket, so there is no
# malformed shape, and the core law (see LAWS.bend) holds for every trie and every key.
import Base
import ../../halo2/lib/words.bend as Wd

type NSet is Data:
  NE{}
  NN{ws: +List<Wd.W>, z: NSet, o: NSet}

def empty() -> NSet:
  NE{}

# The bucket reached by following `bits` (empty if the path is absent).
def get(t: NSet, bits: +List<Bool>) -> +List<Wd.W>:
  match t bits:
    case NE{} _:
      Nil{}
    case NN{ws, _, _} Nil{}:
      ws
    case NN{_, _, o} Con{True{}, rest}:
      get(o, rest)
    case NN{_, z, _} Con{False{}, rest}:
      get(z, rest)

# Insert v into the bucket at path `bits`, creating the path if needed.
def ins(bits: +List<Bool>, t: NSet, v: Wd.W) -> NSet:
  match bits t:
    case Nil{} NE{}:
      NN{[v], NE{}, NE{}}
    case Nil{} NN{ws, z, o}:
      NN{v <> ws, z, o}
    case Con{True{}, rest} NE{}:
      NN{Nil{}, NE{}, ins(rest, NE{}, v)}
    case Con{False{}, rest} NE{}:
      NN{Nil{}, ins(rest, NE{}, v), NE{}}
    case Con{True{}, rest} NN{ws, z, o}:
      NN{ws, z, ins(rest, o, v)}
    case Con{False{}, rest} NN{ws, z, o}:
      NN{ws, ins(rest, z, v), o}

def any_eq(xs: +List<Wd.W>, +v: Wd.W) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{h, t}:
      Wd.is_eq(h, v) || any_eq(t, v)

def member(+t: NSet, +bits: +List<Bool>, +v: Wd.W) -> Bool:
  any_eq(get(t, bits), v)
