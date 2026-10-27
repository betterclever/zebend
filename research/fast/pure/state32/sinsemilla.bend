# Sinsemilla and the Orchard/Ironwood note commitment tree, in Bend.
#
# MerkleCRH^Orchard(l, left, right) = SinsemillaHash("z.cash:Orchard-MerkleCRH",
#     I2LEBSP_10(l) || I2LEBSP_255(left) || I2LEBSP_255(right))      (protocol spec 5.4.1.3)
# SinsemillaHashToPoint: acc = Q; for each 10-bit chunk m_j: acc = (acc ⸭ S(m_j)) ⸭ acc,
# where ⸭ is incomplete addition: ⊥ if an operand is the identity or both share an x
# coordinate (P = ±Q). SinsemillaHash = Extract_P (x coordinate, identity -> 0).
# Consensus (orchard's MerkleHashOrchard::combine) maps ⊥ to 0, and so do we.
# Generators Q and S come from consts.bend (exported by the oracle; checked on-curve below).
import Base
import ../../../../zcash/halo2/lib/words.bend as Wd
import ../fp32.bend as B
import ../lib32/pallas.bend as P
import ./consts.bend as C

# --- generators -------------------------------------------------------------------

def aff_of(c: C.XY) -> P.Aff:
  C.XY{x, y} = c
  P.Aff{B.from_words(x), B.from_words(y)}

# y^2 == x^3 + 5
def on_curve(a: P.Aff) -> Bool:
  P.Aff{+x, +y} = a
  B.is_eq(B.sqr(y), B.add(B.mul(B.sqr(x), x), B.from_u32(5)))

# The 1024 S generators as a balanced tree, walked by chunk bits MSB first.
type STab is Data:
  SLeaf{p: P.Aff}
  SNode{l: STab, r: STab}

def stab_leaf(xs: +List<C.XY>) -> STab:
  match xs:
    case Con{h, _}:
      SLeaf{aff_of(h)}
    case Nil{}:
      SLeaf{P.Aff{B.zero(), B.zero()}}

def stab(+d: Nat, +xs: +List<C.XY>) -> STab:
  match d:
    case 0n:
      stab_leaf(xs)
    case 1n+k:
      +half = Nat.pow(2n, k)
      SNode{stab(k, List.take(&2, C.XY, xs, half)), stab(k, List.drop(&2, C.XY, xs, half))}

def look(t: STab, bits: +List<Bool>) -> P.Aff:
  match t bits:
    case SNode{l, r} Con{b, rest}:
      match b:
        case True{}:
          look(r, rest)
        case False{}:
          look(l, rest)
    case SLeaf{p} _:
      p
    case SNode{_, _} Nil{}:
      P.Aff{B.zero(), B.zero()}

type Gens is Data:
  Gens{q: P.Aff, tab: STab}

def gens() -> Gens:
  Gens{aff_of(C.q()), stab(10n, C.s_list())}

def b2n(b: Bool) -> Nat:
  match b:
    case True{}:
      1n
    case False{}:
      0n

def count_on_curve(xs: +List<C.XY>, acc: Nat) -> Nat:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      count_on_curve(t, Nat.add(acc, b2n(on_curve(aff_of(h)))))

# --- message bits -----------------------------------------------------------------

def bit(+x: U32, k: Nat) -> Bool:
  U32.is_eq(U32.and(U32.shrn(x, k), 1), 1)

# n bits of x, LSB first, starting at bit k.
def bits_lsb(n: Nat, +x: U32, +k: Nat) -> +List<Bool>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      bit(x, k) <> bits_lsb(p, x, 1n+k)

def word_bits(+x: U32) -> +List<Bool>:
  bits_lsb(32n, x, 0n)

def w_bits(w: Wd.W) -> +List<Bool>:
  Wd.W{a, b, c, d, e, f, g, h} = w
  List.append(&2, Bool, word_bits(a), List.append(&2, Bool, word_bits(b), List.append(&2, Bool, word_bits(c), List.append(&2, Bool, word_bits(d), List.append(&2, Bool, word_bits(e), List.append(&2, Bool, word_bits(f), List.append(&2, Bool, word_bits(g), word_bits(h))))))))

# I2LEBSP_10(l) || I2LEBSP_255(left) || I2LEBSP_255(right): 520 bits = 52 chunks.
def crh_msg(+level: U32, left: Wd.W, right: Wd.W) -> +List<Bool>:
  List.append(&2, Bool, bits_lsb(10n, level, 0n), List.append(&2, Bool, List.take(&2, Bool, w_bits(left), 255n), List.take(&2, Bool, w_bits(right), 255n)))

# Split into 10-bit chunks, each reversed so the S-table walk reads its MSB first.
def chunks(fuel: Nat, +xs: +List<Bool>) -> List<+List<Bool>>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+p:
      List.reverse(&2, Bool, List.take(&2, Bool, xs, 10n)) <> chunks(p, List.drop(&2, Bool, xs, 10n))

# --- incomplete addition and HashToPoint -------------------------------------------

type Acc is Data:
  Bot{}
  Ok{p: P.Pt}

# Same x coordinate (projective vs affine): X1 == x2 * Z1.
def same_x_aff(p: P.Pt, a: P.Aff) -> Bool:
  P.Pt{x1, _, z1} = p
  P.Aff{x2, _} = a
  B.is_eq(x1, B.mul(x2, z1))

def same_x(p: P.Pt, q: P.Pt) -> Bool:
  P.Pt{x1, _, z1} = p
  P.Pt{x2, _, z2} = q
  B.is_eq(B.mul(x1, z2), B.mul(x2, z1))

def inc_add_aff(bad: Bool, p: P.Pt, s: P.Aff) -> Acc:
  match bad:
    case True{}:
      Bot{}
    case False{}:
      Ok{P.add_aff(p, s)}

def inc_add(bad: Bool, p: P.Pt, q: P.Pt) -> Acc:
  match bad:
    case True{}:
      Bot{}
    case False{}:
      Ok{P.add(p, q)}

# (t ⸭ p), given t = p ⸭ S
def second(t: Acc, +p: P.Pt) -> Acc:
  match t:
    case Bot{}:
      Bot{}
    case Ok{+tp}:
      inc_add(P.is_identity(tp) || same_x(tp, p), tp, p)

def chunk_step(acc: Acc, +s: P.Aff) -> Acc:
  match acc:
    case Bot{}:
      Bot{}
    case Ok{+p}:
      second(inc_add_aff(P.is_identity(p) || same_x_aff(p, s), p, s), p)

def fold(cs: List<+List<Bool>>, acc: Acc, +tab: STab) -> Acc:
  match cs:
    case Nil{}:
      acc
    case Con{c, rest}:
      fold(rest, chunk_step(acc, look(tab, c)), tab)

def aff_x(a: P.Aff) -> Wd.W:
  P.Aff{x, _} = a
  B.to_words(x)

# MerkleCRH^Orchard(level, left, right); ⊥ -> 0 as in consensus.
def extract(acc: Acc) -> Wd.W:
  match acc:
    case Bot{}:
      Wd.zero()
    case Ok{p}:
      aff_x(P.to_aff(p))

def crh(+g: Gens, level: U32, left: Wd.W, right: Wd.W) -> Wd.W:
  Gens{q, tab} = g
  extract(fold(chunks(52n, crh_msg(level, left, right)), Ok{P.from_aff(q)}, tab))

# --- empty roots ------------------------------------------------------------------

# Uncommitted^Orchard = 2.
def uncommitted() -> Wd.W:
  Wd.W{2, 0, 0, 0, 0, 0, 0, 0}

# [empty_0 .. empty_n], empty_{l+1} = MerkleCRH(l, empty_l, empty_l).
def empties_go(n: Nat, +l: Nat, +e: Wd.W, +g: Gens) -> +List<Wd.W>:
  match n:
    case 0n:
      [e]
    case 1n+p:
      e <> empties_go(p, 1n+l, crh(g, U32.from_nat(l), e, e), g)

def empties(+g: Gens) -> +List<Wd.W>:
  empties_go(32n, 0n, uncommitted(), g)

def nth(+xs: +List<Wd.W>, n: Nat) -> Wd.W:
  match xs n:
    case Nil{} _:
      Wd.zero()
    case Con{h, _} 0n:
      h
    case Con{_, t} 1n+k:
      nth(t, k)

# --- the tree ---------------------------------------------------------------------

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

# Root of a subtree of height h. The two halves are a parallel call: on the GPU
# (`subroot!`) or across CPU threads, every node of a level is hashed at once.
def subroot(+h: Nat, t: LTree, +g: Gens, +es: +List<Wd.W>) -> Wd.W:
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

# Lift a root of height h to height 32 by pairing with empty subtrees on the right.
def lift(n: Nat, +h: Nat, r: Wd.W, +g: Gens, +es: +List<Wd.W>) -> Wd.W:
  match n:
    case 0n:
      r
    case 1n+p:
      lift(p, 1n+h, crh(g, U32.from_nat(h), r, nth(es, h)), g, es)

# Root of the depth-32 tree whose first leaves are `xs`, built as a depth-d subtree.
def root(+d: Nat, xs: +List<Wd.W>, +g: Gens, +es: +List<Wd.W>) -> Wd.W:
  lift(Nat.sub(32n, d), d, subroot(d, ltree(d, xs), g, es), g, es)

def root_gpu(+d: Nat, xs: +List<Wd.W>, +g: Gens, +es: +List<Wd.W>) -> Wd.W:
  lift(Nat.sub(32n, d), d, subroot!(d, ltree(d, xs), g, es), g, es)

# --- incremental frontier (what a node keeps between blocks) -----------------------

# One pending left sibling per level 0..31; append is amortised O(1) hashes.
def push(lv: +List<Maybe<&2, Wd.W>>, +l: Nat, carry: Wd.W, +g: Gens) -> +List<Maybe<&2, Wd.W>>:
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

def fright(acc: Maybe<&2, Wd.W>, +l: Nat, +g: Gens, +es: +List<Wd.W>) -> Maybe<&2, Wd.W>:
  match acc:
    case None{}:
      None{}
    case Some{a}:
      Some{crh(g, U32.from_nat(l), a, nth(es, l))}
def fstep(m: Maybe<&2, Wd.W>, acc: Maybe<&2, Wd.W>, +l: Nat, +g: Gens, +es: +List<Wd.W>) -> Maybe<&2, Wd.W>:
  match m:
    case Some{left}:
      Some{crh(g, U32.from_nat(l), left, Maybe.default(&2, Wd.W, acc, nth(es, l)))}
    case None{}:
      fright(acc, l, g, es)

# Root of the frontier: fold levels bottom-up; a missing right side is the empty root.
def froot(lv: +List<Maybe<&2, Wd.W>>, +l: Nat, acc: Maybe<&2, Wd.W>, +g: Gens, +es: +List<Wd.W>) -> Wd.W:
  match lv:
    case Nil{}:
      Maybe.default(&2, Wd.W, acc, nth(es, 32n))
    case Con{m, rest}:
      froot(rest, 1n+l, fstep(m, acc, l, g, es), g, es)

