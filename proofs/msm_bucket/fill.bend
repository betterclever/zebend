import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L
import ./acu.bend as A
import ./model.bend as M
import ./red.bend as R

# Filling the buckets (msm_ba.fill9 / put) and one window's sum (window_sum9).

def plen(xs: +List<M.AP>) -> Nat:
  List.length(&2, M.AP, xs)

def sd_m(sd: M.SD) -> Nat:
  M.SD{+m, _} = sd
  m

def blen_ins(+bs: +List<+List<Nat>>, +k: Nat, +x: Nat) -> {R.blen(M.ins(bs, k, x)) == R.blen(bs) : Nat}:
  match bs:
    case Nil{}:
      {==}
    case Con{+l, +t}:
      match k:
        case 0n:
          {==}
        case 1n+j:
          Equal.cong(Nat, Nat, w => 1n+w, R.blen(M.ins(t, j, x)), R.blen(t), blen_ins(t, j, x))

def le_pred(+x: Nat, +y: Nat, +h: M.Le(1n+x, 1n+y)) -> M.Le(x, y):
  (e, he) = h
  (e, L.succ_inj(Nat.add(x, e), y, he))

# inserting x into bucket k (k < number of buckets) adds (1 + k + a) * x
def Fs_ins(+bs: +List<+List<Nat>>, +k: Nat, +x: Nat, +a: Nat, +h: M.Le(1n+k, R.blen(bs))) -> {R.Fs(M.ins(bs, k, x), a) == Nat.add(R.Fs(bs, a), Nat.mul(1n+Nat.add(k, a), x)) : Nat}:
  match bs:
    case Nil{}:
      (e, he) = h
      Empty.absurd({R.Fs(M.ins(Nil{}, k, x), a) == Nat.add(R.Fs(Nil{}, a), Nat.mul(1n+Nat.add(k, a), x)) : Nat}, R.le_absurd(k, e, he))
    case Con{+l, +t}:
      match k:
        case 0n:
          +ma = Nat.mul(1n+a, x)
          +mb = Nat.mul(1n+a, R.sum(l))
          +ft = R.Fs(t, 1n+a)
          Equal.trans(Nat, Nat.add(Nat.mul(1n+a, Nat.add(x, R.sum(l))), ft), Nat.add(Nat.add(ma, mb), ft), Nat.add(Nat.add(mb, ft), ma), Equal.cong(Nat, Nat, w => Nat.add(w, ft), Nat.mul(1n+a, Nat.add(x, R.sum(l))), Nat.add(ma, mb), L.mul_add_l(1n+a, x, R.sum(l))), A.acu({[ma, mb, ft] : +List<Nat>}, A.P{A.P{A.V{0n}, A.V{1n}}, A.V{2n}}, A.P{A.P{A.V{1n}, A.V{2n}}, A.V{0n}}, {==}))
        case 1n+j:
          +mb = Nat.mul(1n+a, R.sum(l))
          +ft = R.Fs(t, 1n+a)
          +mx = Nat.mul(1n+Nat.add(j, 1n+a), x)
          +my = Nat.mul(1n+(1n+Nat.add(j, a)), x)
          Equal.trans(Nat, Nat.add(mb, R.Fs(M.ins(t, j, x), 1n+a)), Nat.add(mb, Nat.add(ft, mx)), Nat.add(Nat.add(mb, ft), my), Equal.cong(Nat, Nat, w => Nat.add(mb, w), R.Fs(M.ins(t, j, x), 1n+a), Nat.add(ft, mx), Fs_ins(t, j, x, 1n+a, le_pred(1n+j, R.blen(t), h))), Equal.trans(Nat, Nat.add(mb, Nat.add(ft, mx)), Nat.add(Nat.add(mb, ft), mx), Nat.add(Nat.add(mb, ft), my), Equal.sym(Nat, Nat.add(Nat.add(mb, ft), mx), Nat.add(mb, Nat.add(ft, mx)), N.add_assoc(mb, ft, mx)), Equal.cong(Nat, Nat, w => Nat.add(Nat.add(mb, ft), Nat.mul(1n+w, x)), Nat.add(j, 1n+a), 1n+Nat.add(j, a), N.add_succ_r(j, a))))

def Fs_put(+p: M.AP, +sd: M.SD, +bs: +List<+List<Nat>>, +h: M.Le(sd_m(sd), R.blen(bs))) -> {R.Fs(M.put(p, sd, bs), 0n) == Nat.add(R.Fs(bs, 0n), M.sdval(sd, p)) : Nat}:
  match sd:
    case M.SD{+m, +neg}:
      match m:
        case 0n:
          Equal.sym(Nat, Nat.add(R.Fs(bs, 0n), 0n), R.Fs(bs, 0n), N.add_zero_r(R.Fs(bs, 0n)))
        case 1n+k:
          Equal.trans(Nat, R.Fs(M.ins(bs, k, M.signed_pt(neg, p)), 0n), Nat.add(R.Fs(bs, 0n), Nat.mul(1n+Nat.add(k, 0n), M.signed_pt(neg, p))), Nat.add(R.Fs(bs, 0n), Nat.mul(1n+k, M.signed_pt(neg, p))), Fs_ins(bs, k, M.signed_pt(neg, p), 0n, h), Equal.cong(Nat, Nat, w => Nat.add(R.Fs(bs, 0n), Nat.mul(1n+w, M.signed_pt(neg, p))), Nat.add(k, 0n), k, N.add_zero_r(k)))

def blen_put(+p: M.AP, +sd: M.SD, +bs: +List<+List<Nat>>) -> {R.blen(M.put(p, sd, bs)) == R.blen(bs) : Nat}:
  match sd:
    case M.SD{+m, +neg}:
      match m:
        case 0n:
          {==}
        case 1n+k:
          blen_ins(bs, k, M.signed_pt(neg, p))

# --- digit magnitudes stay within the buckets -------------------------------------------------

def le_refl(+x: Nat) -> M.Le(x, x):
  (0n, N.add_zero_r(x))

def le_up(+x: Nat, +y: Nat, +h: M.Le(x, y)) -> M.Le(x, 1n+y):
  (e, he) = h
  (1n+e, Equal.trans(Nat, Nat.add(x, 1n+e), 1n+Nat.add(x, e), 1n+y, N.add_succ_r(x, e), Equal.cong(Nat, Nat, w => 1n+w, Nat.add(x, e), y, he)))

def le_sub(+a: Nat, +b: Nat) -> M.Le(Nat.sub(a, b), a):
  match a:
    case 0n:
      (0n, {==})
    case 1n+ap:
      match b:
        case 0n:
          le_refl(1n+ap)
        case 1n+bq:
          le_up(Nat.sub(ap, bq), ap, le_sub(ap, bq))

def le_sub_add(+h: Nat, +u: Nat, +x: Nat, +hl: M.Le(u, Nat.add(h, x))) -> M.Le(Nat.sub(u, h), x):
  match h:
    case 0n:
      match u:
        case 0n:
          (x, {==})
        case 1n+up:
          hl
    case 1n+hp:
      match u:
        case 0n:
          (x, {==})
        case 1n+up:
          le_sub_add(hp, up, x, le_pred(up, Nat.add(hp, x), hl))

def sd_bound(b: Bool, +u: Nat, +half: Nat, +hl: M.Le(u, Nat.add(half, half))) -> M.Le(sd_m(M.sd_u(b, u, half)), half):
  match b:
    case True{}:
      le_sub_add(half, u, half, hl)
    case False{}:
      le_sub(half, u)

def win1_nth(+half: Nat, +u: +List<Nat>, +j: Nat, +h: M.Win1(half, u)) -> M.Le(M.nth(u, j), Nat.add(half, half)):
  match u:
    case Nil{}:
      (Nat.add(half, half), {==})
    case Con{+x, +t}:
      match j:
        case 0n:
          (hx, ht) = h
          hx
        case 1n+k:
          (hx, ht) = h
          win1_nth(half, t, k, ht)

def le_cast(+x: Nat, +k: Nat, +k2: Nat, e: {k == k2 : Nat}, +h: M.Le(x, k)) -> M.Le(x, k2):
  %e : M.Le(x, _)
  h

# filling adds every point times its signed digit, bucket d weighing d
def Fs_fill(+ps: +List<M.AP>, +us: +List<+List<Nat>>, +j: Nat, +half: Nat, +bs: +List<+List<Nat>>, +hw: M.Win(half, us), +hb: {R.blen(bs) == half : Nat}) -> {R.Fs(M.fill(ps, us, j, half, bs), 0n) == Nat.add(R.Fs(bs, 0n), M.wsum(ps, us, j, half)) : Nat}:
  match ps:
    case Nil{}:
      Equal.sym(Nat, Nat.add(R.Fs(bs, 0n), 0n), R.Fs(bs, 0n), N.add_zero_r(R.Fs(bs, 0n)))
    case Con{+p, +pt}:
      match us:
        case Nil{}:
          Equal.sym(Nat, Nat.add(R.Fs(bs, 0n), 0n), R.Fs(bs, 0n), N.add_zero_r(R.Fs(bs, 0n)))
        case Con{+u, +ut}:
          (h1, ht) = hw
          +d = M.digit(M.nth(u, j), half)
          +b2 = M.put(p, d, bs)
          +hb2 = Equal.trans(Nat, R.blen(b2), R.blen(bs), half, blen_put(p, d, bs), hb)
          +bound = le_cast(sd_m(d), half, R.blen(bs), Equal.sym(Nat, R.blen(bs), half, hb), sd_bound(Nat.is_ge(M.nth(u, j), half), M.nth(u, j), half, win1_nth(half, u, j, h1)))
          +sv = M.sdval(d, p)
          +ws = M.wsum(pt, ut, j, half)
          Equal.trans(Nat, R.Fs(M.fill(pt, ut, j, half, b2), 0n), Nat.add(R.Fs(b2, 0n), ws), Nat.add(R.Fs(bs, 0n), Nat.add(sv, ws)), Fs_fill(pt, ut, j, half, b2, ht, hb2), Equal.trans(Nat, Nat.add(R.Fs(b2, 0n), ws), Nat.add(Nat.add(R.Fs(bs, 0n), sv), ws), Nat.add(R.Fs(bs, 0n), Nat.add(sv, ws)), Equal.cong(Nat, Nat, w => Nat.add(w, ws), R.Fs(b2, 0n), Nat.add(R.Fs(bs, 0n), sv), Fs_put(p, d, bs, bound)), N.add_assoc(R.Fs(bs, 0n), sv, ws)))

def Fs_empty(+n: Nat, +a: Nat) -> {R.Fs(M.empty(n), a) == 0n : Nat}:
  match n:
    case 0n:
      {==}
    case 1n+k:
      Equal.trans(Nat, Nat.add(Nat.mul(1n+a, 0n), R.Fs(M.empty(k), 1n+a)), Nat.add(0n, 0n), 0n, R.cadd(Nat.mul(1n+a, 0n), 0n, R.Fs(M.empty(k), 1n+a), 0n, L.mul_zero_r(1n+a), Fs_empty(k, 1n+a)), {==})

def blen_empty(+n: Nat) -> {R.blen(M.empty(n)) == n : Nat}:
  match n:
    case 0n:
      {==}
    case 1n+k:
      Equal.cong(Nat, Nat, w => 1n+w, R.blen(M.empty(k)), k, blen_empty(k))

# --- bucket sizes: no bucket gets more points than there are --------------------------------

def all_up(+bs: +List<+List<Nat>>, +k: Nat, +h: R.AllLe(bs, k)) -> R.AllLe(bs, 1n+k):
  match bs:
    case Nil{}:
      Unit{}
    case Con{+l, +t}:
      (hl, ht) = h
      (le_up(R.len(l), k, hl), all_up(t, k, ht))

def all_ins(+bs: +List<+List<Nat>>, +k: Nat, +i: Nat, +x: Nat, +h: R.AllLe(bs, k)) -> R.AllLe(M.ins(bs, i, x), 1n+k):
  match bs:
    case Nil{}:
      Unit{}
    case Con{+l, +t}:
      match i:
        case 0n:
          (hl, ht) = h
          (R.le_succ(R.len(l), k, hl), all_up(t, k, ht))
        case 1n+j:
          (hl, ht) = h
          (le_up(R.len(l), k, hl), all_ins(t, k, j, x, ht))

def all_put(+p: M.AP, +sd: M.SD, +bs: +List<+List<Nat>>, +k: Nat, +h: R.AllLe(bs, k)) -> R.AllLe(M.put(p, sd, bs), 1n+k):
  match sd:
    case M.SD{+m, +neg}:
      match m:
        case 0n:
          all_up(bs, k, h)
        case 1n+i:
          all_ins(bs, k, i, M.signed_pt(neg, p), h)

def all_cast(+bs: +List<+List<Nat>>, +k: Nat, +k2: Nat, e: {k == k2 : Nat}, +h: R.AllLe(bs, k)) -> R.AllLe(bs, k2):
  %e : R.AllLe(bs, _)
  h

def all_mono(+bs: +List<+List<Nat>>, +d: Nat, +k: Nat, +h: R.AllLe(bs, k)) -> R.AllLe(bs, Nat.add(d, k)):
  match d:
    case 0n:
      h
    case 1n+e:
      all_up(bs, Nat.add(e, k), all_mono(bs, e, k, h))

def all_fill(+ps: +List<M.AP>, +us: +List<+List<Nat>>, +j: Nat, +half: Nat, +bs: +List<+List<Nat>>, +k: Nat, +h: R.AllLe(bs, k)) -> R.AllLe(M.fill(ps, us, j, half, bs), Nat.add(plen(ps), k)):
  match ps:
    case Nil{}:
      h
    case Con{+p, +pt}:
      match us:
        case Nil{}:
          all_mono(bs, plen(Con{p, pt}), k, h)
        case Con{+u, +ut}:
          +b2 = M.put(p, M.digit(M.nth(u, j), half), bs)
          all_cast(M.fill(pt, ut, j, half, b2), Nat.add(plen(pt), 1n+k), 1n+Nat.add(plen(pt), k), N.add_succ_r(plen(pt), k), all_fill(pt, ut, j, half, b2, 1n+k, all_put(p, M.digit(M.nth(u, j), half), bs, k, h)))

def all_empty(+n: Nat) -> R.AllLe(M.empty(n), 0n):
  match n:
    case 0n:
      Unit{}
    case 1n+k:
      ((0n, {==}), all_empty(k))

def le_trans(+x: Nat, +y: Nat, +z: Nat, +h1: M.Le(x, y), +h2: M.Le(y, z)) -> M.Le(x, z):
  (e1, he1) = h1
  (e2, he2) = h2
  (Nat.add(e1, e2), Equal.trans(Nat, Nat.add(x, Nat.add(e1, e2)), Nat.add(Nat.add(x, e1), e2), z, Equal.sym(Nat, Nat.add(Nat.add(x, e1), e2), Nat.add(x, Nat.add(e1, e2)), N.add_assoc(x, e1, e2)), Equal.trans(Nat, Nat.add(Nat.add(x, e1), e2), Nat.add(y, e2), z, Equal.cong(Nat, Nat, w => Nat.add(w, e2), Nat.add(x, e1), y, he1), he2)))

def all_trans(+bs: +List<+List<Nat>>, +k: Nat, +k2: Nat, +hk: M.Le(k, k2), +h: R.AllLe(bs, k)) -> R.AllLe(bs, k2):
  match bs:
    case Nil{}:
      Unit{}
    case Con{+l, +t}:
      (hl, ht) = h
      (le_trans(R.len(l), k, k2, hl, hk), all_trans(t, k, k2, hk, ht))

# ONE WINDOW: msm_ba.window_sum9 computes sum_i digit_ij * P_i, provided every window value is
# at most 2^c and there are at most 2^rf points (rf = rounds' fuel, 32 in the code).
law window_ok:
  for +half: Nat
  for +rf: Nat
  for +ps: +List<M.AP>
  for +us: +List<+List<Nat>>
  for +j: Nat
  for +hw: M.Win(half, us)
  for +hn: M.Le(plen(ps), Nat.pow(2n, rf))
  {M.window_sum(half, rf, ps, us, j) == M.wsum(ps, us, j, half) : Nat}

def window_ok(half, rf, ps, us, j, hw, hn):
  +bs = M.fill(ps, us, j, half, M.empty(half))
  +summed = M.rounds(rf, M.small(bs), bs)
  +sizes = all_trans(bs, plen(ps), Nat.pow(2n, rf), hn, all_cast(bs, Nat.add(plen(ps), 0n), plen(ps), N.add_zero_r(plen(ps)), all_fill(ps, us, j, half, M.empty(half), 0n, all_empty(half))))
  Equal.trans(Nat, M.rs_acc(M.reduce(M.rev(summed), M.RS{0n, 0n})), R.Fh(summed, 0n), M.wsum(ps, us, j, half), R.reduce_rev(summed), Equal.trans(Nat, R.Fh(summed, 0n), R.Fs(bs, 0n), M.wsum(ps, us, j, half), R.rounds_ok(rf, M.small(bs), bs, 0n, {==}, sizes), Equal.trans(Nat, R.Fs(bs, 0n), Nat.add(R.Fs(M.empty(half), 0n), M.wsum(ps, us, j, half)), M.wsum(ps, us, j, half), Fs_fill(ps, us, j, half, M.empty(half), hw, blen_empty(half)), Equal.cong(Nat, Nat, w => Nat.add(w, M.wsum(ps, us, j, half)), R.Fs(M.empty(half), 0n), 0n, Fs_empty(half, 0n)))))
