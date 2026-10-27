import Base

# The incremental note-commitment-tree frontier from zcash/state/sinsemilla.bend
# (push, fright, fstep, froot), copied with one change: the node hash
# `crh(g, l, a, b)` is the free constructor Hn{l, a, b}, and the empty subtree root
# `nth(es, l)` is Em{l}. A theorem that two expressions are equal as free terms
# holds for every hash function and every table of empty roots, because any
# interpretation of Hn and Em maps equal terms to equal values.

type HT is Data:
  Lf{x: Nat}
  Em{k: Nat}
  Hn{k: Nat, l: HT, r: HT}

# --- frontier (one pending left sibling per level) -------------------------------

def push(lv: +List<Maybe<&2, HT>>, +l: Nat, carry: HT) -> +List<Maybe<&2, HT>>:
  match lv:
    case Nil{}:
      Nil{}
    case Con{m, rest}:
      match m:
        case None{}:
          Some{carry} <> rest
        case Some{left}:
          None{} <> push(rest, 1n+l, Hn{l, left, carry})

def nones(n: Nat) -> +List<Maybe<&2, HT>>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      None{} <> nones(p)

# Append leaves one at a time, as a node does block by block.
def push_all(xs: +List<HT>, lv: +List<Maybe<&2, HT>>) -> +List<Maybe<&2, HT>>:
  match xs:
    case Nil{}:
      lv
    case Con{h, t}:
      push_all(t, push(lv, 0n, h))

def fright(acc: Maybe<&2, HT>, +l: Nat) -> Maybe<&2, HT>:
  match acc:
    case None{}:
      None{}
    case Some{a}:
      Some{Hn{l, a, Em{l}}}

def fstep(m: Maybe<&2, HT>, acc: Maybe<&2, HT>, +l: Nat) -> Maybe<&2, HT>:
  match m:
    case Some{left}:
      Some{Hn{l, left, Maybe.default(&2, HT, acc, Em{l})}}
    case None{}:
      fright(acc, l)

# Root of the frontier: fold levels bottom-up; a missing right side is the empty root.
# (zcash/state ends with nth(es, 32n); for its 32-level frontier that is Em{l} here.)
def froot(lv: +List<Maybe<&2, HT>>, +l: Nat, acc: Maybe<&2, HT>) -> HT:
  match lv:
    case Nil{}:
      Maybe.default(&2, HT, acc, Em{l})
    case Con{m, rest}:
      froot(rest, 1n+l, fstep(m, acc, l))

# --- the tree the frontier must agree with ---------------------------------------

# A perfect binary tree of leaves.
type Tr is Data:
  TL{x: HT}
  TN{l: Tr, r: Tr}

def Perf(+k: Nat, t: Tr) -> Data:
  match k t:
    case 0n TL{x}:
      Unit
    case 0n TN{l, r}:
      Empty
    case 1n+p TL{x}:
      Empty
    case 1n+p TN{l, r}:
      Sigma<&2, &2, Perf(p, l), _ => Perf(p, r)>

def troot(+k: Nat, t: Tr) -> HT:
  match k t:
    case 0n TL{x}:
      x
    case 1n+p TN{l, r}:
      Hn{p, troot(p, l), troot(p, r)}
    case _ _:
      Em{0n}

def tleaves(t: Tr) -> +List<HT>:
  match t:
    case TL{x}:
      x <> Nil{}
    case TN{l, r}:
      List.append(&2, HT, tleaves(l), tleaves(r))

# A tree of height k filled from the left, with empty subtrees on the right:
#   PE      no leaves
#   PF t    every leaf present (t is perfect of height k)
#   PLo q   left child q (height k-1, non-empty), right child empty
#   PB t q  left child full (t perfect, height k-1), right child q (height k-1, not full)
type PT is Data:
  PE{}
  PF{t: Tr}
  PLo{q: PT}
  PB{t: Tr, q: PT}

def IsFull(p: PT) -> Bool:
  match p:
    case PF{t}:
      True{}
    case _:
      False{}

def IsEmpty(p: PT) -> Bool:
  match p:
    case PE{}:
      True{}
    case _:
      False{}

def NotB(b: Bool) -> Data:
  match b:
    case True{}:
      Empty
    case False{}:
      Unit

# Well-formed partial tree of height k.
def WF(p: PT, +k: Nat) -> Data:
  match p:
    case PE{}:
      Unit
    case PF{t}:
      Perf(k, t)
    case PLo{+q}:
      match k:
        case 0n:
          Empty
        case 1n+j:
          Sigma<&2, &2, WF(q, j), _ => NotB(IsEmpty(q))>
    case PB{t, +q}:
      match k:
        case 0n:
          Empty
        case 1n+j:
          Sigma<&2, &2, Perf(j, t), _ => Sigma<&2, &2, WF(q, j), _ => NotB(IsFull(q))>>

def proot(p: PT, +k: Nat) -> HT:
  match p:
    case PE{}:
      Em{k}
    case PF{t}:
      troot(k, t)
    case PLo{q}:
      match k:
        case 0n:
          Em{0n}
        case 1n+j:
          Hn{j, proot(q, j), Em{j}}
    case PB{t, q}:
      match k:
        case 0n:
          Em{0n}
        case 1n+j:
          Hn{j, troot(j, t), proot(q, j)}

def pleaves(p: PT) -> +List<HT>:
  match p:
    case PE{}:
      Nil{}
    case PF{t}:
      tleaves(t)
    case PLo{q}:
      pleaves(q)
    case PB{t, q}:
      List.append(&2, HT, tleaves(t), pleaves(q))

# --- specification helpers (used only to state the laws) -------------------------

# The frontier a well-formed, not-full partial tree of height k leaves behind
# (levels 0..k-1), before whatever sits above it.
def fr(+p: PT, +k: Nat) -> +List<Maybe<&2, HT>>:
  match p:
    case PE{}:
      nones(k)
    case PF{t}:
      Nil{}
    case PLo{+q}:
      match q:
        case PF{t}:
          match k:
            case 0n:
              Nil{}
            case 1n+j:
              List.append(&2, Maybe<&2, HT>, nones(j), Some{troot(j, t)} <> Nil{})
        case _:
          match k:
            case 0n:
              Nil{}
            case 1n+j:
              List.append(&2, Maybe<&2, HT>, fr(q, j), None{} <> Nil{})
    case PB{t, q}:
      match k:
        case 0n:
          Nil{}
        case 1n+j:
          List.append(&2, Maybe<&2, HT>, fr(q, j), Some{troot(j, t)} <> Nil{})

def pacc(+k: Nat, p: PT) -> Maybe<&2, HT>:
  match p:
    case PE{}:
      None{}
    case _:
      Some{proot(p, k)}

# --- authentication paths ---------------------------------------------------------

# ds: one direction bit per level, root first (False = left child, True = right).
# Typing ds as Word(k) makes its length the tree height by construction.

def leaf_at(+k: Nat, t: Tr, ds: Word(k)) -> HT:
  match k t:
    case 0n TL{x}:
      x
    case 1n+j TN{l, r}:
      match ds:
        case WCon{d, dr}:
          match d:
            case False{}:
              leaf_at(j, l, dr)
            case True{}:
              leaf_at(j, r, dr)
    case _ _:
      Em{0n}

# Sibling roots along the path, root level first.
def auth(+k: Nat, t: Tr, ds: Word(k)) -> +List<HT>:
  match k t:
    case 1n+j TN{l, r}:
      match ds:
        case WCon{d, dr}:
          match d:
            case False{}:
              troot(j, r) <> auth(j, l, dr)
            case True{}:
              troot(j, l) <> auth(j, r, dr)
    case _ _:
      Nil{}

# Recompute a root from a claimed leaf x, its directions and sibling roots.
def recompute(+k: Nat, x: HT, ds: Word(k), ss: +List<HT>) -> HT:
  match k:
    case 0n:
      x
    case 1n+j:
      match ds:
        case WCon{d, dr}:
          match d:
            case False{}:
              match ss:
                case Con{s, sr}:
                  Hn{j, recompute(j, x, dr, sr), s}
                case Nil{}:
                  Em{0n}
            case True{}:
              match ss:
                case Con{s, sr}:
                  Hn{j, s, recompute(j, x, dr, sr)}
                case Nil{}:
                  Em{0n}

def hn_l(h: HT) -> HT:
  match h:
    case Hn{k, l, r}:
      l
    case _:
      Em{0n}

def hn_r(h: HT) -> HT:
  match h:
    case Hn{k, l, r}:
      r
    case _:
      Em{0n}

def IsHn(h: HT) -> Type:
  match h:
    case Hn{k, l, r}:
      Unit
    case _:
      Empty
