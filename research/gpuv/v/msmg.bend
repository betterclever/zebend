# GPU multi-scalar multiplication for batch verification: one scalar multiplication per
# lane, then a balanced parallel tree of point additions. `sum!` runs the whole tree on the
# Metal GPU; every lane does the same uniform work, which is the shape a GPU wants. Inputs
# are public (proof commitments, generators, verifier scalars), so variable-time is fine.
import Base
import ../../../zcash/halo2/lib/words.bend as Wd
import ../../../crypto/field3/lib64/vesta.bend as V

type T is Data:
  Leaf{p: V.Pt, k: Wd.W}
  Node{l: T, r: T}
  Empty{}

# Leaves in input order. Each list is consumed once (no take/drop copies of the inputs).
def leaves(+ps: +List<V.Pt>, +ss: +List<Wd.W>) -> List<T>:
  match ps ss:
    case Con{+p, pt} Con{+k, st}:
      Leaf{p, k} <> leaves(pt, st)
    case _ _:
      Nil{}

# One level up: pair neighbours, so the tree stays balanced.
def pairs(ts: List<T>) -> List<T>:
  match ts:
    case Con{a, Con{b, r}}:
      Node{a, b} <> pairs(r)
    case Con{a, Nil{}}:
      a <> Nil{}
    case Nil{}:
      Nil{}

def reduce(fuel: Nat, ts: List<T>) -> T:
  match fuel ts:
    case _ Nil{}:
      Empty{}
    case _ Con{t, Nil{}}:
      t
    case 1n+f _:
      reduce(f, pairs(ts))
    case _ _:
      Empty{}

# Bit i of a 256-bit scalar (8 little-endian words).
def word(+j: U32, w: Wd.W) -> U32:
  match j w:
    case 0 Wd.W{w0, _, _, _, _, _, _, _}:
      w0
    case 1 Wd.W{_, w1, _, _, _, _, _, _}:
      w1
    case 2 Wd.W{_, _, w2, _, _, _, _, _}:
      w2
    case 3 Wd.W{_, _, _, w3, _, _, _, _}:
      w3
    case 4 Wd.W{_, _, _, _, w4, _, _, _}:
      w4
    case 5 Wd.W{_, _, _, _, _, w5, _, _}:
      w5
    case 6 Wd.W{_, _, _, _, _, _, w6, _}:
      w6
    case _ Wd.W{_, _, _, _, _, _, _, w7}:
      w7

def bit(+i: Nat, +k: Wd.W) -> U32:
  +ii = U32.from_nat(i)
  ((word((ii >> 5n : U32), k) >> U32.to_nat((ii .&. 31 : U32))) .&. 1 : U32)

def pick(+b: U32, +p: V.Pt) -> V.Pt:
  match b:
    case 0:
      V.identity()
    case _:
      p

# Left-to-right double-and-add with the complete addition law doing the doubling too
# (acc + acc), so the GPU kernel holds only two copies of the point addition. Metal
# builds inline every helper (METAL_INLINE.md); GLV's tables and ladders inline into a
# kernel Apple's compiler fails on, this one stays small.
def smul(+n: Nat, +acc: V.Pt, +p: V.Pt, +k: Wd.W) -> V.Pt:
  match n:
    case 0n:
      acc
    case 1n+i:
      smul(i, V.add(V.add(acc, acc), pick(bit(i, k), p)), p, k)

def sum(t: T) -> V.Pt:
  match t:
    case Leaf{p, k}:
      smul(255n, V.identity(), p, k)
    case Node{l, r}:
      a b = sum(l) sum(r)
      V.add(a, b)
    case Empty{}:
      V.identity()

# Rebuild the tree while folding a digest over every leaf, so an IO step can print the
# digest and leave the tree fully evaluated on the host before `sum!` ships it.
type Touched is Data:
  Touched{t: T, d: U32}

def join(a: Touched, b: Touched) -> Touched:
  Touched{+lt, +ld} = a
  Touched{+rt, +rd} = b
  Touched{Node{lt, rt}, (ld .^. (rd << 1n) .^. (rd >> 31n) : U32)}

def touch(t: T) -> Touched:
  match t:
    case Leaf{+p, +k}:
      Touched{Leaf{p, k}, (Bool.to_u32(V.is_identity(p)) + Wd.low_bit(k) : U32)}
    case Node{l, r}:
      a b = touch(l) touch(r)
      join(a, b)
    case Empty{}:
      Touched{Empty{}, 0}

def tree(+ps: +List<V.Pt>, +ss: +List<Wd.W>) -> T:
  reduce(32n, leaves(ps, ss))

# Σ k_i·P_i on the GPU.
def msm_gpu(+ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  sum!(tree(ps, ss))

# Σ k_i·P_i on CPU threads (same tree, for comparison).
def msm_cpu(+ps: +List<V.Pt>, +ss: +List<Wd.W>) -> V.Pt:
  sum(tree(ps, ss))
