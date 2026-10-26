# The Sapling note commitment tree (depth 32) over MerkleCRH^Sapling (pedersen.bend).
# Same shape as node/state/sinsemilla.bend: leaves are cmu values (LE words), the empty
# leaf is Uncommitted^Sapling = 1, and a subtree's two halves are hashed in parallel
# (CPU threads, or the GPU with `subroot!`).
import Base
import ../../halo2/lib/words.bend as Wd
import ./pedersen.bend as PH
import ../jubjub/jubjub.bend as J
import ../jubjub/fr.bend as F

def crh(+g: PH.Tab, +l: U32, a: Wd.W, b: Wd.W) -> Wd.W:
  PH.merkle(g, l, a, b)

# Uncommitted^Sapling = I2LEBSP_255(1).
def uncommitted() -> Wd.W:
  Wd.W{1, 0, 0, 0, 0, 0, 0, 0}

# [empty_0 .. empty_n], empty_{l+1} = MerkleCRH(l, empty_l, empty_l).
def empties_go(n: Nat, +l: Nat, +e: Wd.W, +g: PH.Tab) -> +List<Wd.W>:
  match n:
    case 0n:
      [e]
    case 1n+p:
      e <> empties_go(p, 1n+l, crh(g, U32.from_nat(l), e, e), g)

def empties(+g: PH.Tab) -> +List<Wd.W>:
  empties_go(32n, 0n, uncommitted(), g)

def nth(+xs: +List<Wd.W>, n: Nat) -> Wd.W:
  match xs n:
    case Nil{} _:
      Wd.zero()
    case Con{h, _} 0n:
      h
    case Con{_, t} 1n+k:
      nth(t, k)

type LTree is Data:
  LEmpty{}
  LOne{w: Wd.W}
  LNode{l: LTree, r: LTree}

# Leaves (in order) into a complete tree of depth d; missing leaves are LEmpty.
def ltree(+d: Nat, xs: +List<Wd.W>) -> LTree:
  match d xs:
    case _ Nil{}:
      LEmpty{}
    case 0n Con{h, _}:
      LOne{h}
    case 1n+k Con{h, t}:
      +ys = {h <> t : +List<Wd.W>}
      +half = Nat.pow(2n, k)
      LNode{ltree(k, List.take(&2, Wd.W, ys, half)), ltree(k, List.drop(&2, Wd.W, ys, half))}

# Sequential subtree root (no fork), for the small subtrees at the bottom.
def subroot_seq(+h: Nat, t: LTree, +g: PH.Tab, +es: +List<Wd.W>) -> Wd.W:
  match h t:
    case _ LEmpty{}:
      nth(es, h)
    case 0n LOne{w}:
      w
    case 1n+k LNode{l, r}:
      +a = subroot_seq(k, l, g, es)
      +b = subroot_seq(k, r, g, es)
      crh(g, U32.from_nat(k), a, b)
    case _ _:
      Wd.zero()

def is_small(+h: Nat) -> Bool:
  Nat.is_lt(h, 9n)

# Root of a subtree of height h; the halves are a parallel call (subtrees of height <= 8
# are hashed sequentially, so each parallel task is at least 255 hashes).
def subroot_c(+h: Nat, small: Bool, t: LTree, +g: PH.Tab, +es: +List<Wd.W>) -> Wd.W:
  match h small t:
    case _ True{} _:
      subroot_seq(h, t, g, es)
    case _ False{} LEmpty{}:
      nth(es, h)
    case 1n+k False{} LNode{l, r}:
      a b = subroot_c(k, is_small(k), l, g, es) subroot_c(k, is_small(k), r, g, es)
      crh(g, U32.from_nat(k), a, b)
    case _ _ _:
      Wd.zero()

def subroot_par(+h: Nat, t: LTree, +g: PH.Tab, +es: +List<Wd.W>) -> Wd.W:
  subroot_c(h, is_small(h), t, g, es)

# Root of a subtree of height h; the halves are a parallel call.
def subroot(+h: Nat, t: LTree, +g: PH.Tab, +es: +List<Wd.W>) -> Wd.W:
  match h t:
    case _ LEmpty{}:
      nth(es, h)
    case 0n LOne{w}:
      w
    case 1n+k LNode{l, r}:
      a b = subroot(k, l, g, es) subroot(k, r, g, es)
      crh(g, U32.from_nat(k), a, b)
    case _ _:
      Wd.zero()

# Lift a root of height h to height h + n by pairing with empty subtrees on the right.
def lift(n: Nat, +h: Nat, r: Wd.W, +g: PH.Tab, +es: +List<Wd.W>) -> Wd.W:
  match n:
    case 0n:
      r
    case 1n+p:
      lift(p, 1n+h, crh(g, U32.from_nat(h), r, nth(es, h)), g, es)

# Root of the depth-32 tree whose first leaves are `xs`, built as a depth-d subtree.
def root(+d: Nat, xs: +List<Wd.W>, +g: PH.Tab, +es: +List<Wd.W>) -> Wd.W:
  lift(Nat.sub(32n, d), d, subroot(d, ltree(d, xs), g, es), g, es)

# Upper tree: level-16 chunk roots as leaves, levels 16..31.
def usub(+h: Nat, t: LTree, +g: PH.Tab, +es: +List<Wd.W>) -> Wd.W:
  match h t:
    case _ LEmpty{}:
      nth(es, Nat.add(16n, h))
    case 0n LOne{w}:
      w
    case 1n+k LNode{l, r}:
      a b = usub(k, l, g, es) usub(k, r, g, es)
      crh(g, U32.from_nat(Nat.add(16n, k)), a, b)
    case _ _:
      Wd.zero()

def root_from_chunks(roots: +List<Wd.W>, +g: PH.Tab, +es: +List<Wd.W>) -> Wd.W:
  usub(16n, ltree(16n, roots), g, es)

# --- incremental frontier (a node's view: append one leaf at a time) ---------------

def push(lv: +List<Maybe<&2, Wd.W>>, +l: Nat, carry: Wd.W, +g: PH.Tab) -> +List<Maybe<&2, Wd.W>>:
  match lv:
    case Nil{}:
      Nil{}
    case Con{m, rest}:
      match m:
        case None{}:
          Some{carry} <> rest
        case Some{left}:
          None{} <> push(rest, 1n+l, crh(g, U32.from_nat(l), left, carry), g)

def nones(n: Nat) -> +List<Maybe<&2, Wd.W>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      None{} <> nones(p)

def frontier_new() -> +List<Maybe<&2, Wd.W>>:
  nones(32n)

def fright(acc: Maybe<&2, Wd.W>, +l: Nat, +g: PH.Tab, +es: +List<Wd.W>) -> Maybe<&2, Wd.W>:
  match acc:
    case None{}:
      None{}
    case Some{a}:
      Some{crh(g, U32.from_nat(l), a, nth(es, l))}

def fstep(m: Maybe<&2, Wd.W>, acc: Maybe<&2, Wd.W>, +l: Nat, +g: PH.Tab, +es: +List<Wd.W>) -> Maybe<&2, Wd.W>:
  match m:
    case Some{left}:
      Some{crh(g, U32.from_nat(l), left, Maybe.default(&2, Wd.W, acc, nth(es, l)))}
    case None{}:
      fright(acc, l, g, es)

def froot(lv: +List<Maybe<&2, Wd.W>>, +l: Nat, acc: Maybe<&2, Wd.W>, +g: PH.Tab, +es: +List<Wd.W>) -> Wd.W:
  match lv:
    case Nil{}:
      Maybe.default(&2, Wd.W, acc, nth(es, 32n))
    case Con{m, rest}:
      froot(rest, 1n+l, fstep(m, acc, l, g, es), g, es)

# --- complete chunks, level by level with batched inversion ------------------------------

# Extract_J needs u = X/Z for every hash. Hashing a whole level first and inverting all the
# Z coordinates at once (Montgomery's trick: 3 multiplications each plus one inversion per
# level) removes the per-hash inversion, about a third of a hash's cost.

def pairs_pt(xs: +List<Wd.W>, +layer: U32, +g: PH.Tab) -> +List<J.Pt>:
  match xs:
    case Con{a, Con{b, rest}}:
      PH.hash_pt(g, layer, a, b) <> pairs_pt(rest, layer, g)
    case _:
      Nil{}

def pt_z(p: J.Pt) -> F.Fr:
  J.Pt{_, _, z, _} = p
  z

def zs_of(ps: +List<J.Pt>) -> +List<F.Fr>:
  match ps:
    case Con{p, t}:
      pt_z(p) <> zs_of(t)
    case Nil{}:
      Nil{}

def us_of(ps: +List<J.Pt>, invs: +List<F.Fr>) -> +List<Wd.W>:
  match ps invs:
    case Con{J.Pt{x, _, _, _}, pt} Con{i, it}:
      F.to_words(F.mul(x, i)) <> us_of(pt, it)
    case _ _:
      Nil{}

# One level: n nodes -> n/2 parents (n even).
def level_up(+xs: +List<Wd.W>, +layer: U32, +g: PH.Tab) -> +List<Wd.W>:
  +ps = pairs_pt(xs, layer, g)
  us_of(ps, F.batch_inv(zs_of(ps)))

# Root of 2^k nodes at layer `layer` (k levels, sequential).
def levels(k: Nat, +layer: U32, +xs: +List<Wd.W>, +g: PH.Tab) -> Wd.W:
  match k xs:
    case 0n Con{h, _}:
      h
    case 1n+j _:
      levels(j, (layer + 1 : U32), level_up(xs, layer, g), g)
    case _ _:
      Wd.zero()

# Blocks of 256 leaves (complete chunk: 65536 leaves -> 256 blocks).
def blocks_of(n: Nat, +xs: +List<Wd.W>) -> +List<+List<Wd.W>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      List.take(&2, Wd.W, xs, 256n) <> blocks_of(p, List.drop(&2, Wd.W, xs, 256n))

def blocks_par(+fuel: Nat, +cnt: Nat, +bs: +List<+List<Wd.W>>, +g: PH.Tab) -> +List<Wd.W>:
  match fuel cnt bs:
    case _ 0n _:
      Nil{}
    case _ 1n Con{+b, _}:
      levels(8n, 0, b, g) <> Nil{}
    case 1n+f _ _:
      +h = Nat.div(cnt, 2n)
      a c = blocks_par(f, h, List.take(&2, +List<Wd.W>, bs, h), g) blocks_par(f, Nat.sub(cnt, h), List.drop(&2, +List<Wd.W>, bs, h), g)
      List.append(&2, Wd.W, a, c)
    case _ _ _:
      Nil{}

# Root of a COMPLETE chunk of 2^16 leaves: 256 blocks of 256 in parallel (8 levels each),
# then the top 8 levels over the 256 block roots.
def chunk_root(+xs: +List<Wd.W>, +g: PH.Tab) -> Wd.W:
  levels(8n, 8, blocks_par(16n, 256n, blocks_of(256n, xs), g), g)
