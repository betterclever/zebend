import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L
import ./acu.bend as A
import ./model.bend as M

# Bucket reduction (msm_ba.reduce over the reversed bucket list) and the pairwise rounds.

def len(xs: +List<Nat>) -> Nat:
  List.length(&2, Nat, xs)

def blen(xs: +List<+List<Nat>>) -> Nat:
  List.length(&2, +List<Nat>, xs)

def sum(l: +List<Nat>) -> Nat:
  match l:
    case Nil{}:
      0n
    case Con{+x, t}:
      Nat.add(x, sum(t))

# W(bs) = sum over positions of (number of buckets from here to the end) * head
def W(bs: +List<+List<Nat>>) -> Nat:
  match bs:
    case Nil{}:
      0n
    case Con{+l, +t}:
      Nat.add(Nat.mul(1n+blen(t), M.hd(l)), W(t))

# F(L, a) = sum_k (1 + a + k) * head(L_k)    (index order)
def Fh(bs: +List<+List<Nat>>, +a: Nat) -> Nat:
  match bs:
    case Nil{}:
      0n
    case Con{+l, t}:
      Nat.add(Nat.mul(1n+a, M.hd(l)), Fh(t, 1n+a))

# the same with the whole bucket's sum
def Fs(bs: +List<+List<Nat>>, +a: Nat) -> Nat:
  match bs:
    case Nil{}:
      0n
    case Con{+l, t}:
      Nat.add(Nat.mul(1n+a, sum(l)), Fs(t, 1n+a))

def cadd(+x: Nat, +x2: Nat, +y: Nat, +y2: Nat, hx: {x == x2 : Nat}, hy: {y == y2 : Nat}) -> {Nat.add(x, y) == Nat.add(x2, y2) : Nat}:
  %hx : {Nat.add(x, y) == Nat.add(_, y2) : Nat}
  %hy : {Nat.add(x, y) == Nat.add(x, _) : Nat}
  {==}

# reduce's closed form
def red_ok(+bs: +List<+List<Nat>>, +run: Nat, +acc: Nat) -> {M.rs_acc(M.reduce(bs, M.RS{run, acc})) == Nat.add(acc, Nat.add(Nat.mul(blen(bs), run), W(bs))) : Nat}:
  match bs:
    case Nil{}:
      Equal.sym(Nat, Nat.add(acc, 0n), acc, N.add_zero_r(acc))
    case Con{+l, +t}:
      +h = M.hd(l)
      +n = blen(t)
      +r2 = Nat.add(run, h)
      +env = {[acc, run, h, Nat.mul(n, run), Nat.mul(n, h), W(t)] : +List<Nat>}
      Equal.trans(Nat, M.rs_acc(M.reduce(t, M.RS{r2, Nat.add(acc, r2)})), Nat.add(Nat.add(acc, r2), Nat.add(Nat.mul(n, r2), W(t))), Nat.add(acc, Nat.add(Nat.mul(1n+n, run), Nat.add(Nat.mul(1n+n, h), W(t)))), red_ok(t, r2, Nat.add(acc, r2)), Equal.trans(Nat, Nat.add(Nat.add(acc, r2), Nat.add(Nat.mul(n, r2), W(t))), Nat.add(Nat.add(acc, r2), Nat.add(Nat.add(Nat.mul(n, run), Nat.mul(n, h)), W(t))), Nat.add(acc, Nat.add(Nat.mul(1n+n, run), Nat.add(Nat.mul(1n+n, h), W(t)))), Equal.cong(Nat, Nat, w => Nat.add(Nat.add(acc, r2), Nat.add(w, W(t))), Nat.mul(n, r2), Nat.add(Nat.mul(n, run), Nat.mul(n, h)), L.mul_add_l(n, run, h)), A.acu(env, A.P{A.P{A.V{0n}, A.P{A.V{1n}, A.V{2n}}}, A.P{A.P{A.V{3n}, A.V{4n}}, A.V{5n}}}, A.P{A.V{0n}, A.P{A.P{A.V{1n}, A.V{3n}}, A.P{A.P{A.V{2n}, A.V{4n}}, A.V{5n}}}}, {==})))

def go(xs: +List<+List<Nat>>, acc: +List<+List<Nat>>) -> +List<+List<Nat>>:
  List.reverse.go(&2, +List<Nat>, xs, acc)

def blen_go(+xs: +List<+List<Nat>>, +acc: +List<+List<Nat>>) -> {blen(go(xs, acc)) == Nat.add(blen(xs), blen(acc)) : Nat}:
  match xs:
    case Nil{}:
      {==}
    case Con{+l, +t}:
      Equal.trans(Nat, blen(go(t, l <> acc)), Nat.add(blen(t), 1n+blen(acc)), 1n+Nat.add(blen(t), blen(acc)), blen_go(t, l <> acc), N.add_succ_r(blen(t), blen(acc)))

# W over a reversed list is F in index order.
def W_go(+xs: +List<+List<Nat>>, +acc: +List<+List<Nat>>) -> {W(go(xs, acc)) == Nat.add(Fh(xs, blen(acc)), W(acc)) : Nat}:
  match xs:
    case Nil{}:
      {==}
    case Con{+l, +t}:
      +a = blen(acc)
      Equal.trans(Nat, W(go(t, l <> acc)), Nat.add(Fh(t, 1n+a), Nat.add(Nat.mul(1n+a, M.hd(l)), W(acc))), Nat.add(Nat.add(Nat.mul(1n+a, M.hd(l)), Fh(t, 1n+a)), W(acc)), W_go(t, l <> acc), A.acu([Fh(t, 1n+a), Nat.mul(1n+a, M.hd(l)), W(acc)], A.P{A.V{0n}, A.P{A.V{1n}, A.V{2n}}}, A.P{A.P{A.V{1n}, A.V{0n}}, A.V{2n}}, {==}))

def mul_zero(+n: Nat) -> {Nat.mul(n, 0n) == 0n : Nat}:
  L.mul_zero_r(n)

# the window's reduction: reduce(reverse(L)) from zero gives F(L, 0)
law reduce_rev:
  for +bs: +List<+List<Nat>>
  {M.rs_acc(M.reduce(M.rev(bs), M.RS{0n, 0n})) == Fh(bs, 0n) : Nat}

def reduce_rev(bs):
  Equal.trans(Nat, M.rs_acc(M.reduce(go(bs, Nil{}), M.RS{0n, 0n})), Nat.add(0n, Nat.add(Nat.mul(blen(go(bs, Nil{})), 0n), W(go(bs, Nil{})))), Fh(bs, 0n), red_ok(go(bs, Nil{}), 0n, 0n), Equal.trans(Nat, Nat.add(Nat.mul(blen(go(bs, Nil{})), 0n), W(go(bs, Nil{}))), W(go(bs, Nil{})), Fh(bs, 0n), Equal.cong(Nat, Nat, w => Nat.add(w, W(go(bs, Nil{}))), Nat.mul(blen(go(bs, Nil{})), 0n), 0n, mul_zero(blen(go(bs, Nil{})))), Equal.trans(Nat, W(go(bs, Nil{})), Nat.add(Fh(bs, 0n), 0n), Fh(bs, 0n), W_go(bs, Nil{}), N.add_zero_r(Fh(bs, 0n)))))

# --- rounds ----------------------------------------------------------------------------------

def sum_rb(+l: +List<Nat>) -> {sum(M.rb(l)) == sum(l) : Nat}:
  match l:
    case Nil{}:
      {==}
    case Con{+a, +t}:
      match t:
        case Nil{}:
          {==}
        case Con{+b, +r}:
          Equal.trans(Nat, Nat.add(Nat.add(a, b), sum(M.rb(r))), Nat.add(Nat.add(a, b), sum(r)), Nat.add(a, Nat.add(b, sum(r))), Equal.cong(Nat, Nat, w => Nat.add(Nat.add(a, b), w), sum(M.rb(r)), sum(r), sum_rb(r)), N.add_assoc(a, b, sum(r)))

def Fs_rebuild(+bs: +List<+List<Nat>>, +a: Nat) -> {Fs(M.rebuild(bs), a) == Fs(bs, a) : Nat}:
  match bs:
    case Nil{}:
      {==}
    case Con{+l, +t}:
      cadd(Nat.mul(1n+a, sum(M.rb(l))), Nat.mul(1n+a, sum(l)), Fs(M.rebuild(t), 1n+a), Fs(t, 1n+a), Equal.cong(Nat, Nat, w => Nat.mul(1n+a, w), sum(M.rb(l)), sum(l), sum_rb(l)), Fs_rebuild(t, 1n+a))

# every bucket has at most k points
def AllLe(bs: +List<+List<Nat>>, +k: Nat) -> Data:
  match bs:
    case Nil{}:
      Unit
    case Con{+l, t}:
      Sigma<&2, &2, M.Le(len(l), k), _ => AllLe(t, k)>

def le_absurd(+n: Nat, +e: Nat, h: {Nat.add(1n+n, e) == 0n : Nat}) -> Empty:
  L.succ_ne_zero(Nat.add(n, e), h)

def le_succ(+x: Nat, +j: Nat, +h: M.Le(x, j)) -> M.Le(1n+x, 1n+j):
  (f, hf) = h
  (f, Equal.cong(Nat, Nat, w => 1n+w, Nat.add(x, f), j, hf))

# one round halves every bucket (rounding up)
def len_rb(+l: +List<Nat>, +k: Nat, +h: M.Le(len(l), Nat.add(k, k))) -> M.Le(len(M.rb(l)), k):
  match l:
    case Nil{}:
      (k, {==})
    case Con{+a, +t}:
      match t:
        case Nil{}:
          match k:
            case 0n:
              (e, he) = h
              Empty.absurd(M.Le(1n, 0n), le_absurd(0n, e, he))
            case 1n+j:
              (j, {==})
        case Con{+b, +r}:
          match k:
            case 0n:
              (e, he) = h
              Empty.absurd(M.Le(1n+len(M.rb(r)), 0n), le_absurd(1n+len(r), e, he))
            case 1n+j:
              (e, he) = h
              +h2 = L.succ_inj(Nat.add(1n+len(r), e), Nat.add(j, 1n+j), he)
              +h3 = L.succ_inj(Nat.add(len(r), e), Nat.add(j, j), Equal.trans(Nat, 1n+Nat.add(len(r), e), Nat.add(j, 1n+j), 1n+Nat.add(j, j), h2, N.add_succ_r(j, j)))
              le_succ(len(M.rb(r)), j, len_rb(r, j, (e, h3)))

def all_rebuild(+bs: +List<+List<Nat>>, +k: Nat, +h: AllLe(bs, Nat.add(k, k))) -> AllLe(M.rebuild(bs), k):
  match bs:
    case Nil{}:
      Unit{}
    case Con{+l, +t}:
      (hl, ht) = h
      (len_rb(l, k, hl), all_rebuild(t, k, ht))

def isT(b: Bool) -> Type:
  match b:
    case True{}:
      Unit
    case False{}:
      Empty

def bool_ne(h: {False{} == True{} : Bool}) -> Empty:
  %Equal.sym(Bool, False{}, True{}, h) : isT(_)
  Unit{}

# small(bs) == True: every bucket has at most one point
def small_le(+bs: +List<+List<Nat>>, h: {M.small(bs) == True{} : Bool}) -> AllLe(bs, 1n):
  match bs:
    case Nil{}:
      Unit{}
    case Con{+l, +t}:
      match l:
        case Nil{}:
          ((1n, {==}), small_le(t, h))
        case Con{+a, +r}:
          match r:
            case Nil{}:
              ((0n, {==}), small_le(t, h))
            case Con{+b, +q}:
              Empty.absurd(AllLe(Con{Con{a, Con{b, q}}, t}, 1n), bool_ne(h))

def hd_sum(+l: +List<Nat>, +h: M.Le(len(l), 1n)) -> {M.hd(l) == sum(l) : Nat}:
  match l:
    case Nil{}:
      {==}
    case Con{+x, +t}:
      match t:
        case Nil{}:
          Equal.sym(Nat, Nat.add(x, 0n), x, N.add_zero_r(x))
        case Con{+y, +r}:
          (e, he) = h
          Empty.absurd({x == Nat.add(x, Nat.add(y, sum(r))) : Nat}, le_absurd(0n, Nat.add(len(r), e), L.succ_inj(Nat.add(1n+len(r), e), 0n, he)))

def Fh_Fs(+bs: +List<+List<Nat>>, +a: Nat, +h: AllLe(bs, 1n)) -> {Fh(bs, a) == Fs(bs, a) : Nat}:
  match bs:
    case Nil{}:
      {==}
    case Con{+l, +t}:
      (hl, ht) = h
      cadd(Nat.mul(1n+a, M.hd(l)), Nat.mul(1n+a, sum(l)), Fh(t, 1n+a), Fs(t, 1n+a), Equal.cong(Nat, Nat, w => Nat.mul(1n+a, w), M.hd(l), sum(l), hd_sum(l, hl)), Fh_Fs(t, 1n+a, ht))

def pow2s(+f: Nat) -> {Nat.pow(2n, 1n+f) == Nat.add(Nat.pow(2n, f), Nat.pow(2n, f)) : Nat}:
  Equal.cong(Nat, Nat, w => Nat.add(Nat.pow(2n, f), w), Nat.add(Nat.pow(2n, f), 0n), Nat.pow(2n, f), N.add_zero_r(Nat.pow(2n, f)))

def all_cast(+bs: +List<+List<Nat>>, +k: Nat, +k2: Nat, e: {k == k2 : Nat}, +h: AllLe(bs, k)) -> AllLe(bs, k2):
  %e : AllLe(bs, _)
  h

# rounds(f) leaves the bucket sums unchanged and, if no bucket has more than 2^f points, ends
# with at most one point per bucket, so the heads are the bucket sums.
def rounds_ok(+f: Nat, b: Bool, +bs: +List<+List<Nat>>, +a: Nat, hb: {M.small(bs) == b : Bool}, +h: AllLe(bs, Nat.pow(2n, f))) -> {Fh(M.rounds(f, b, bs), a) == Fs(bs, a) : Nat}:
  match f:
    case 0n:
      Fh_Fs(bs, a, h)
    case 1n+g:
      match b:
        case True{}:
          Fh_Fs(bs, a, small_le(bs, hb))
        case False{}:
          +nb = M.rebuild(bs)
          Equal.trans(Nat, Fh(M.rounds(g, M.small(nb), nb), a), Fs(nb, a), Fs(bs, a), rounds_ok(g, M.small(nb), nb, a, {==}, all_rebuild(bs, Nat.pow(2n, g), all_cast(bs, Nat.pow(2n, 1n+g), Nat.add(Nat.pow(2n, g), Nat.pow(2n, g)), pow2s(g), h))), Fs_rebuild(bs, a))
