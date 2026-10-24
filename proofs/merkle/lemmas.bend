import Base
import ./merkle.bend as M

# List and Nat lemmas for the frontier proof. Each is stated in the orientation the
# rewrites in PROOF.bend need: `%e : P` with e : {a == b} replaces b by a.

law append_nil:
  for -A: Data
  for xs: List<&2, A>
  {List.append(&2, A, xs, Nil{}) == xs : List<&2, A>}

def append_nil(A, xs):
  match xs:
    case Nil{}:
      {==}
    case Con{h, t}:
      %append_nil(A, t) : {h <> List.append(&2, A, t, Nil{}) == h <> _ : List<&2, A>}
      {==}

# append(xs, y :: r) == append(append(xs, [y]), r)
law snoc:
  for -A: Data
  for xs: List<&2, A>
  for -y: A
  for -r: List<&2, A>
  {List.append(&2, A, xs, y <> r) == List.append(&2, A, List.append(&2, A, xs, y <> Nil{}), r) : List<&2, A>}

def snoc(A, xs, y, r):
  match xs:
    case Nil{}:
      {==}
    case Con{h, t}:
      %snoc(A, t, y, r) : {h <> List.append(&2, A, t, y <> r) == h <> _ : List<&2, A>}
      {==}

# append(nones j, None :: r) == None :: append(nones j, r)
law nones_shift:
  for j: Nat
  for -r: List<&2, Maybe<&2, M.HT>>
  {List.append(&2, Maybe<&2, M.HT>, M.nones(j), None{} <> r) == None{} <> List.append(&2, Maybe<&2, M.HT>, M.nones(j), r) : List<&2, Maybe<&2, M.HT>>}

def nones_shift(j, r):
  match j:
    case 0n:
      {==}
    case 1n+p:
      %nones_shift(p, r) : {None{} <> List.append(&2, Maybe<&2, M.HT>, M.nones(p), None{} <> r) == None{} <> _ : List<&2, Maybe<&2, M.HT>>}
      {==}

# push_all(ys, push_all(xs, lv)) == push_all(append(xs, ys), lv)
law push_all_append:
  for xs: List<&2, M.HT>
  for -ys: List<&2, M.HT>
  for -lv: List<&2, Maybe<&2, M.HT>>
  {M.push_all(ys, M.push_all(xs, lv)) == M.push_all(List.append(&2, M.HT, xs, ys), lv) : List<&2, Maybe<&2, M.HT>>}

def push_all_append(xs, ys, lv):
  match xs:
    case Nil{}:
      {==}
    case Con{h, t}:
      push_all_append(t, ys, M.push(lv, 0n, h))

law add_zero:
  for j: Nat
  {Nat.add(j, 0n) == j : Nat}

def add_zero(j):
  match j:
    case 0n:
      {==}
    case 1n+p:
      %add_zero(p) : {1n+Nat.add(p, 0n) == 1n+_ : Nat}
      {==}

law add_succ_r:
  for p: Nat
  for -l: Nat
  {Nat.add(p, 1n+l) == 1n+Nat.add(p, l) : Nat}

def add_succ_r(p, l):
  match p:
    case 0n:
      {==}
    case 1n+q:
      %add_succ_r(q, l) : {1n+Nat.add(q, 1n+l) == 1n+_ : Nat}
      {==}

# Levels that hold no pending sibling pass an empty accumulator straight through.
law froot_nones:
  for +j: Nat
  for -l: Nat
  for -rest: List<&2, Maybe<&2, M.HT>>
  {M.froot(List.append(&2, Maybe<&2, M.HT>, M.nones(j), rest), l, None{}) == M.froot(rest, Nat.add(j, l), None{}) : M.HT}

def froot_nones(j, l, rest):
  match j:
    case 0n:
      {==}
    case 1n+p:
      %add_succ_r(p, l) : {M.froot(List.append(&2, Maybe<&2, M.HT>, M.nones(p), rest), 1n+l, None{}) == M.froot(rest, _, None{}) : M.HT}
      froot_nones(p, 1n+l, rest)

# default(pacc(k, p), Em k) == proot(k, p)
law acc_default:
  for -k: Nat
  for p: M.PT
  {Maybe.default(&2, M.HT, M.pacc(k, p), M.Em{k}) == M.proot(p, k) : M.HT}

def acc_default(k, p):
  match p:
    case M.PE{}:
      {==}
    case M.PF{t}:
      {==}
    case M.PLo{q}:
      {==}
    case M.PB{t, q}:
      {==}
