import Base

# A model of research/perf4/lib/fixb.bend (fixed-base comb tables) over the free commutative
# monoid on {P, -P}: SP{a, b} is a P + b (-P), point addition (VL.add, VL.add_aff, VL.double)
# is componentwise +, BA.signed_pt negates by swapping. As in msm_bucket, an identity between
# such points that holds here holds in every abelian group (map SP{a, b} to a P - b P).
# Each def copies the fixb def named in its comment, with these substitutions:
#   * BA.normalize (projective to affine, with batch inversion) is the identity: it does not
#     change the group element (batchinv/ and curve/ prove the arithmetic it relies on);
#   * BA.ANone (only head_ap of an empty list and a tget past the tree produce it) is the
#     identity SP{0, 0}, and add_d(acc, ANone) == acc is acc + 0;
#   * tget's index i = m - 1 is given by its bits bs, most significant first: the bit
#     tested at depth 1 + k, (U32.shrn(i, k) .&. 1), is the k-th bit of i. That U32 shifts
#     and masks extract bits is not proven (prims/README.md, "Not proven").

type SP is Data:
  SP{a: Nat, b: Nat}

def padd(p: SP, q: SP) -> SP:
  SP{a1, b1} = p
  SP{a2, b2} = q
  SP{Nat.add(a1, a2), Nat.add(b1, b2)}

def pzero() -> SP:
  SP{0n, 0n}

# k * p
def smul(+k: Nat, p: SP) -> SP:
  SP{a, b} = p
  SP{Nat.mul(k, a), Nat.mul(k, b)}

# BA.signed_pt: the point, or its negation when neg == 1
def signed(+neg: Nat, p: SP) -> SP:
  match neg:
    case 0n:
      p
    case 1n+k:
      match k:
        case 0n:
          SP{a, b} = p
          SP{b, a}
        case 1n+q:
          p

def nthp(xs: +List<SP>, i: Nat) -> SP:
  match xs:
    case Nil{}:
      pzero()
    case Con{+h, t}:
      match i:
        case 0n:
          h
        case 1n+j:
          nthp(t, j)

# --- fixb.bend ---------------------------------------------------------------------------

type T is Data:
  TL{a: SP}
  TN{l: T, r: T}

def head_ap(xs: +List<SP>) -> SP:
  match xs:
    case Con{+h, _}:
      h
    case Nil{}:
      pzero()

def pow2(n: Nat) -> Nat:
  match n:
    case 0n:
      1n
    case 1n+k:
      Nat.mul(2n, pow2(k))

def tbuild(+d: Nat, +xs: +List<SP>) -> T:
  match d:
    case 0n:
      TL{head_ap(xs)}
    case 1n+k:
      +h = pow2(k)
      TN{tbuild(k, List.take(&2, SP, xs, h)), tbuild(k, List.drop(&2, SP, xs, h))}

def child(lo: Bool, +l: T, +r: T) -> T:
  match lo:
    case True{}:
      l
    case False{}:
      r

# fixb.tget, the index given by its bits (True = 1, most significant first), passed last
def tget(+d: Nat, +t: T, bs: +List<Bool>) -> SP:
  match d t:
    case _ TL{+a}:
      a
    case 1n+k TN{+l, +r}:
      match bs:
        case Con{+bit, bt}:
          tget(k, child(Bool.not(bit), l, r), bt)
        case Nil{}:
          pzero()
    case _ _:
      pzero()

# [acc, acc + p, ..., acc + (m - 1) p]
def mults(m: Nat, +p: SP, +acc: SP) -> +List<SP>:
  match m:
    case 0n:
      Nil{}
    case 1n+k:
      acc <> mults(k, p, padd(acc, p))

def dbl_n(n: Nat, +p: SP) -> SP:
  match n:
    case 0n:
      p
    case 1n+k:
      dbl_n(k, padd(p, p))

# the window bases 2^(c j) P for j = 0 .. nw-1
def wbases(nw: Nat, +c: Nat, +p: SP) -> +List<SP>:
  match nw:
    case 0n:
      Nil{}
    case 1n+k:
      p <> wbases(k, c, dbl_n(c, p))

def window(+c: Nat, +b: SP) -> T:
  +m = pow2(Nat.sub(c, 1n))
  tbuild(Nat.sub(c, 1n), mults(m, b, b))

# one window per base (fixb.table builds them with wpar, a parallel split of this map)
def windows(+c: Nat, bs: +List<SP>) -> +List<T>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{+b, t}:
      window(c, b) <> windows(c, t)

# a signed digit SD{m, neg}, with the bits of m - 1 (what tget reads)
type Dg is Data:
  Dg{m: Nat, neg: Nat, bs: +List<Bool>}

# fixb.step and add_d
def step(z: Bool, +d: Nat, +bs: +List<Bool>, +neg: Nat, +t: T, +acc: SP) -> SP:
  match z:
    case True{}:
      acc
    case False{}:
      padd(acc, signed(neg, tget(d, t, bs)))

# fixb.walk
def walk(+d: Nat, ws: +List<T>, ds: +List<Dg>, +acc: SP) -> SP:
  match ws ds:
    case Con{+t, wt} Con{Dg{+m, +neg, +bs}, dt}:
      walk(d, wt, dt, step(Nat.is_eq(m, 0n), d, bs, neg, t, acc))
    case _ _:
      acc

# --- the specification ---------------------------------------------------------------------

# sum over the windows j of digit_j 2^(c j) P, signed
def comb_sum(ds: +List<Dg>, +c: Nat, +j: Nat, +p: SP) -> SP:
  match ds:
    case Nil{}:
      pzero()
    case Con{Dg{+m, +neg, _}, dt}:
      padd(signed(neg, smul(Nat.mul(m, pow2(Nat.mul(c, j))), p)), comb_sum(dt, c, 1n+j, p))

# sum over the windows of digit_j * base_j, signed (with base_j = 2^(c j) P: wbases_pow)
def wsum(bases: +List<SP>, ds: +List<Dg>) -> SP:
  match bases ds:
    case Con{+b, bt} Con{Dg{+m, +neg, _}, dt}:
      padd(signed(neg, smul(m, b)), wsum(bt, dt))
    case _ _:
      pzero()

# the value of a bit list, most significant first
def valb(+bs: +List<Bool>) -> Nat:
  match bs:
    case Nil{}:
      0n
    case Con{+bit, t}:
      match bit:
        case True{}:
          Nat.add(pow2(List.length(&2, Bool, t)), valb(t))
        case False{}:
          valb(t)

# digit m is 0, or bs is the (c - 1)-bit expansion of m - 1
def DigOk(+d: Nat, ds: +List<Dg>) -> Data:
  match ds:
    case Nil{}:
      Unit
    case Con{Dg{+m, +neg, +bs}, dt}:
      Sigma<&2, &2, Either<&2, &2, {m == 0n : Nat}, Sigma<&2, &2, {List.length(&2, Bool, bs) == d : Nat}, _ => {1n+valb(bs) == m : Nat}>>, _ => DigOk(d, dt)>
