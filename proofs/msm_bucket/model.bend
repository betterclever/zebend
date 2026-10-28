import Base

# A model of research/perf4/lib/msm_ba.bend's msm9 (carry-free signed-digit bucket MSM) over
# the commutative monoid (Nat, +). Each def copies the control structure of the msm_ba def
# named in its comment. Substitutions (README.md, "Refinement"):
#   * an input point is AP{p, n}: two free generators, p for the point P and n for -P;
#     ap_neg / neg_b / signed_pt pick n instead of p. After normalisation every point the
#     algorithm adds is p or n of some input, or a sum of such, so mapping p |-> P, n |-> -P
#     into any abelian group turns every equation below into the real one;
#   * point addition (psum's affine/complete addition, add_aff, VL.add, VL.double) is +;
#   * a scalar is given by its windows: us_i lists u_ij, the j-th c-bit window of
#     k'_i = k_i + H (what bits9(add9(k_i, hconst(c)), j*c, c) extracts);
#   * the bucket array (Array<+List<AP>>, empty, Array.swap, flat) is a list of bucket lists in
#     index order, bucket b at position b;
#   * the batch inversion that rounds/rbucket use for affine additions is dropped (it only
#     computes the same sums faster).
# Window width c = 1 + cm, half = 2^cm buckets, B = 2^c.

type AP is Data:
  AP{p: Nat, n: Nat}

# Signed digit: magnitude m and sign neg (1 = negative).
type SD is Data:
  SD{m: Nat, neg: Nat}

def nth(xs: +List<Nat>, i: Nat) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{+h, t}:
      match i:
        case 0n:
          h
        case 1n+k:
          nth(t, k)

# msm_ba.sd_u / digit9: the signed digit of window u, u - half as magnitude and sign.
def sd_u(b: Bool, +u: Nat, +half: Nat) -> SD:
  match b:
    case True{}:
      SD{Nat.sub(u, half), 0n}
    case False{}:
      SD{Nat.sub(half, u), 1n}

def digit(+u: Nat, +half: Nat) -> SD:
  sd_u(Nat.is_ge(u, half), u, half)

# msm_ba.signed_pt (neg_b, ap_neg): the point or its negation.
def ap_p(a: AP) -> Nat:
  AP{+p, _} = a
  p

def ap_n(a: AP) -> Nat:
  AP{_, +n} = a
  n

def signed_pt(+neg: Nat, +a: AP) -> Nat:
  match neg:
    case 0n:
      ap_p(a)
    case 1n+k:
      match k:
        case 0n:
          ap_n(a)
        case 1n+q:
          ap_p(a)

# Array.swap into bucket k: prepend x to the k-th bucket list.
def ins(bs: +List<+List<Nat>>, k: Nat, +x: Nat) -> +List<+List<Nat>>:
  match bs:
    case Nil{}:
      Nil{}
    case Con{+l, t}:
      match k:
        case 0n:
          (x <> l) <> t
        case 1n+j:
          l <> ins(t, j, x)

# msm_ba.put: digit 0 adds nothing; digit m goes to bucket m - 1, signed.
def put(+a: AP, +sd: SD, bs: +List<+List<Nat>>) -> +List<+List<Nat>>:
  SD{+m, +neg} = sd
  match m:
    case 0n:
      bs
    case 1n+k:
      ins(bs, k, signed_pt(neg, a))

# msm_ba.fill9
def fill(ps: +List<AP>, us: +List<+List<Nat>>, +j: Nat, +half: Nat, bs: +List<+List<Nat>>) -> +List<+List<Nat>>:
  match ps us:
    case Con{+p, pt} Con{+u, ut}:
      fill(pt, ut, j, half, put(p, digit(nth(u, j), half), bs))
    case _ _:
      bs

# msm_ba.empty + flat: `half` empty buckets.
def empty(n: Nat) -> +List<+List<Nat>>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      Nil{} <> empty(k)

# msm_ba.rbucket / rebuild: one round adds the points of each bucket in pairs.
def rb(l: +List<Nat>) -> +List<Nat>:
  match l:
    case Con{+a, Con{+b, t}}:
      Nat.add(a, b) <> rb(t)
    case _:
      l

def rebuild(bs: +List<+List<Nat>>) -> +List<+List<Nat>>:
  match bs:
    case Con{+l, t}:
      rb(l) <> rebuild(t)
    case Nil{}:
      Nil{}

# msm_ba.small
def small(bs: +List<+List<Nat>>) -> Bool:
  match bs:
    case Con{Con{_, Con{_, _}}, _}:
      False{}
    case Con{_, t}:
      small(t)
    case Nil{}:
      True{}

# msm_ba.rounds
def rounds(fuel: Nat, done: Bool, +bs: +List<+List<Nat>>) -> +List<+List<Nat>>:
  match fuel done:
    case 1n+f False{}:
      +nb = rebuild(bs)
      rounds(f, small(nb), nb)
    case _ _:
      bs

# msm_ba.add_b: the running sum plus the bucket's (first) point.
def hd(l: +List<Nat>) -> Nat:
  match l:
    case Con{+x, _}:
      x
    case Nil{}:
      0n

type RS is Data:
  RS{run: Nat, acc: Nat}

# msm_ba.reduce: buckets highest digit first; run = suffix sum, acc = sum_d d * B_d.
def reduce(bs: +List<+List<Nat>>, st: RS) -> RS:
  match bs:
    case Con{+l, t}:
      RS{+run, +acc} = st
      +r2 = Nat.add(run, hd(l))
      reduce(t, RS{r2, Nat.add(acc, r2)})
    case Nil{}:
      st

def rs_acc(st: RS) -> Nat:
  RS{_, +acc} = st
  acc

def rev(xs: +List<+List<Nat>>) -> +List<+List<Nat>>:
  List.reverse(&2, +List<Nat>, xs)

# msm_ba.window_sum9 (`rf` = the rounds fuel, 32n in msm9)
def window_sum(+half: Nat, +rf: Nat, +ps: +List<AP>, +us: +List<+List<Nat>>, +j: Nat) -> Nat:
  +bs = fill(ps, us, j, half, empty(half))
  +summed = rounds(rf, small(bs), bs)
  rs_acc(reduce(rev(summed), RS{0n, 0n}))

# msm_ba.dbl_n
def dbl_n(n: Nat, +p: Nat) -> Nat:
  match n:
    case 0n:
      p
    case 1n+k:
      dbl_n(k, Nat.add(p, p))

# msm_ba.wrange9: windows lo .. lo+cnt-1, split in halves, b shifted by h*c doublings.
def wrange(+fuel: Nat, one: Bool, +c: Nat, +half: Nat, +rf: Nat, +ps: +List<AP>, +us: +List<+List<Nat>>, +lo: Nat, +cnt: Nat) -> Nat:
  match fuel one:
    case 1n+f False{}:
      +h = Nat.div(cnt, 2n)
      +h2 = Nat.sub(cnt, h)
      Nat.add(wrange(f, Nat.is_lt(h, 2n), c, half, rf, ps, us, lo, h), dbl_n(Nat.mul(h, c), wrange(f, Nat.is_lt(h2, 2n), c, half, rf, ps, us, Nat.add(lo, h), h2)))
    case _ _:
      window_sum(half, rf, ps, us, lo)

# msm_ba.msm9 with c = 1 + cm and cnt windows (windows9(c) in the code).
def msm9(+cm: Nat, +ps: +List<AP>, +us: +List<+List<Nat>>, +cnt: Nat) -> Nat:
  wrange(9n, False{}, 1n+cm, Nat.pow(2n, cm), 32n, ps, us, 0n, cnt)

# --- specification ---------------------------------------------------------------------------

# the value of one signed digit times one input point
def sdval(+sd: SD, +a: AP) -> Nat:
  SD{+m, +neg} = sd
  Nat.mul(m, signed_pt(neg, a))

# window j: sum_i digit_ij * P_i
def wsum(ps: +List<AP>, us: +List<+List<Nat>>, +j: Nat, +half: Nat) -> Nat:
  match ps us:
    case Con{+p, pt} Con{+u, ut}:
      Nat.add(sdval(digit(nth(u, j), half), p), wsum(pt, ut, j, half))
    case _ _:
      0n

# windows lo .. lo+cnt-1: sum_t B^t * window(lo + t), B = 2^c (Horner)
def spec(+c: Nat, +half: Nat, +ps: +List<AP>, +us: +List<+List<Nat>>, cnt: Nat, +lo: Nat) -> Nat:
  match cnt:
    case 0n:
      0n
    case 1n+t:
      Nat.add(wsum(ps, us, lo, half), Nat.mul(Nat.pow(2n, c), spec(c, half, ps, us, t, 1n+lo)))

# --- hypotheses ------------------------------------------------------------------------------

def Le(a: Nat, b: Nat) -> Data:
  Sigma<&2, &2, Nat, e => {Nat.add(a, e) == b : Nat}>

# every window value is at most 2 * half = 2^c (the code's are below it)
def Win1(+half: Nat, u: +List<Nat>) -> Data:
  match u:
    case Nil{}:
      Unit
    case Con{+x, t}:
      Sigma<&2, &2, Le(x, Nat.add(half, half)), _ => Win1(half, t)>

def Win(+half: Nat, us: +List<+List<Nat>>) -> Data:
  match us:
    case Nil{}:
      Unit
    case Con{+u, t}:
      Sigma<&2, &2, Win1(half, u), _ => Win(half, t)>

# wrange's fuel suffices: every leaf of the split tree is exactly one window.
def Fuel(fuel: Nat, one: Bool, +cnt: Nat) -> Data:
  match fuel one:
    case 1n+f False{}:
      +h = Nat.div(cnt, 2n)
      Sigma<&2, &2, Fuel(f, Nat.is_lt(h, 2n), h), _ => Fuel(f, Nat.is_lt(Nat.sub(cnt, h), 2n), Nat.sub(cnt, h))>
    case _ _:
      {cnt == 1n : Nat}

# np points, each with nw zero windows (non-vacuity witness)
def zrow(n: Nat) -> +List<Nat>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      0n <> zrow(k)

def zeros(np: Nat, +nw: Nat) -> +List<+List<Nat>>:
  match np:
    case 0n:
      Nil{}
    case 1n+k:
      zrow(nw) <> zeros(k, nw)
