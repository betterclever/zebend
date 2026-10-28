import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L
import ./model.bend as M
import ./red.bend as R
import ./fill.bend as F

# Combining the windows (msm_ba.wrange9, dbl_n) and the whole msm9.

def dbl_ok(+n: Nat, +p: Nat) -> {M.dbl_n(n, p) == Nat.mul(Nat.pow(2n, n), p) : Nat}:
  match n:
    case 0n:
      Equal.sym(Nat, Nat.mul(1n, p), p, L.mul_one_l(p))
    case 1n+k:
      +q = Nat.pow(2n, k)
      Equal.trans(Nat, M.dbl_n(k, Nat.add(p, p)), Nat.mul(q, Nat.add(p, p)), Nat.mul(Nat.add(q, Nat.add(q, 0n)), p), dbl_ok(k, Nat.add(p, p)), Equal.trans(Nat, Nat.mul(q, Nat.add(p, p)), Nat.add(Nat.mul(q, p), Nat.mul(q, p)), Nat.mul(Nat.add(q, Nat.add(q, 0n)), p), L.mul_add_l(q, p, p), Equal.trans(Nat, Nat.add(Nat.mul(q, p), Nat.mul(q, p)), Nat.mul(Nat.add(q, q), p), Nat.mul(Nat.add(q, Nat.add(q, 0n)), p), Equal.sym(Nat, Nat.mul(Nat.add(q, q), p), Nat.add(Nat.mul(q, p), Nat.mul(q, p)), L.mul_add_r(q, q, p)), Equal.cong(Nat, Nat, w => Nat.mul(Nat.add(q, w), p), q, Nat.add(q, 0n), Equal.sym(Nat, Nat.add(q, 0n), q, N.add_zero_r(q))))))

def pow_add(+c: Nat, +x: Nat) -> {Nat.pow(2n, Nat.add(c, x)) == Nat.mul(Nat.pow(2n, c), Nat.pow(2n, x)) : Nat}:
  match c:
    case 0n:
      Equal.sym(Nat, Nat.mul(1n, Nat.pow(2n, x)), Nat.pow(2n, x), L.mul_one_l(Nat.pow(2n, x)))
    case 1n+k:
      Equal.trans(Nat, Nat.mul(2n, Nat.pow(2n, Nat.add(k, x))), Nat.mul(2n, Nat.mul(Nat.pow(2n, k), Nat.pow(2n, x))), Nat.mul(Nat.mul(2n, Nat.pow(2n, k)), Nat.pow(2n, x)), Equal.cong(Nat, Nat, w => Nat.mul(2n, w), Nat.pow(2n, Nat.add(k, x)), Nat.mul(Nat.pow(2n, k), Nat.pow(2n, x)), pow_add(k, x)), Equal.sym(Nat, Nat.mul(Nat.mul(2n, Nat.pow(2n, k)), Nat.pow(2n, x)), Nat.mul(2n, Nat.mul(Nat.pow(2n, k), Nat.pow(2n, x))), L.mul_assoc(2n, Nat.pow(2n, k), Nat.pow(2n, x))))

def pow_mul(+h: Nat, +c: Nat) -> {Nat.pow(2n, Nat.mul(h, c)) == Nat.pow(Nat.pow(2n, c), h) : Nat}:
  match h:
    case 0n:
      {==}
    case 1n+k:
      Equal.trans(Nat, Nat.pow(2n, Nat.add(c, Nat.mul(k, c))), Nat.mul(Nat.pow(2n, c), Nat.pow(2n, Nat.mul(k, c))), Nat.mul(Nat.pow(2n, c), Nat.pow(Nat.pow(2n, c), k)), pow_add(c, Nat.mul(k, c)), Equal.cong(Nat, Nat, w => Nat.mul(Nat.pow(2n, c), w), Nat.pow(2n, Nat.mul(k, c)), Nat.pow(Nat.pow(2n, c), k), pow_mul(k, c)))

# Horner split: windows lo .. lo+h+h2-1 = the first h, plus B^h times the next h2.
def spec_split(+c: Nat, +half: Nat, +ps: +List<M.AP>, +us: +List<+List<Nat>>, +h: Nat, +h2: Nat, +lo: Nat) -> {M.spec(c, half, ps, us, Nat.add(h, h2), lo) == Nat.add(M.spec(c, half, ps, us, h, lo), Nat.mul(Nat.pow(Nat.pow(2n, c), h), M.spec(c, half, ps, us, h2, Nat.add(lo, h)))) : Nat}:
  match h:
    case 0n:
      +s = M.spec(c, half, ps, us, h2, Nat.add(lo, 0n))
      Equal.trans(Nat, M.spec(c, half, ps, us, h2, lo), s, Nat.add(s, 0n), Equal.cong(Nat, Nat, w => M.spec(c, half, ps, us, h2, w), lo, Nat.add(lo, 0n), Equal.sym(Nat, Nat.add(lo, 0n), lo, N.add_zero_r(lo))), Equal.sym(Nat, Nat.add(s, 0n), s, N.add_zero_r(s)))
    case 1n+k:
      +B = Nat.pow(2n, c)
      +Bk = Nat.pow(B, k)
      +ws = M.wsum(ps, us, lo, half)
      +s1 = M.spec(c, half, ps, us, k, 1n+lo)
      +s2 = M.spec(c, half, ps, us, h2, Nat.add(1n+lo, k))
      +s2b = M.spec(c, half, ps, us, h2, Nat.add(lo, 1n+k))
      +e_idx = Equal.cong(Nat, Nat, w => M.spec(c, half, ps, us, h2, w), Nat.add(lo, 1n+k), 1n+Nat.add(lo, k), N.add_succ_r(lo, k))
      Equal.trans(Nat, Nat.add(ws, Nat.mul(B, M.spec(c, half, ps, us, Nat.add(k, h2), 1n+lo))), Nat.add(ws, Nat.mul(B, Nat.add(s1, Nat.mul(Bk, s2)))), Nat.add(Nat.add(ws, Nat.mul(B, s1)), Nat.mul(Nat.mul(B, Bk), s2b)), Equal.cong(Nat, Nat, w => Nat.add(ws, Nat.mul(B, w)), M.spec(c, half, ps, us, Nat.add(k, h2), 1n+lo), Nat.add(s1, Nat.mul(Bk, s2)), spec_split(c, half, ps, us, k, h2, 1n+lo)), Equal.trans(Nat, Nat.add(ws, Nat.mul(B, Nat.add(s1, Nat.mul(Bk, s2)))), Nat.add(ws, Nat.add(Nat.mul(B, s1), Nat.mul(Nat.mul(B, Bk), s2))), Nat.add(Nat.add(ws, Nat.mul(B, s1)), Nat.mul(Nat.mul(B, Bk), s2b)), Equal.cong(Nat, Nat, w => Nat.add(ws, w), Nat.mul(B, Nat.add(s1, Nat.mul(Bk, s2))), Nat.add(Nat.mul(B, s1), Nat.mul(Nat.mul(B, Bk), s2)), Equal.trans(Nat, Nat.mul(B, Nat.add(s1, Nat.mul(Bk, s2))), Nat.add(Nat.mul(B, s1), Nat.mul(B, Nat.mul(Bk, s2))), Nat.add(Nat.mul(B, s1), Nat.mul(Nat.mul(B, Bk), s2)), L.mul_add_l(B, s1, Nat.mul(Bk, s2)), Equal.cong(Nat, Nat, w => Nat.add(Nat.mul(B, s1), w), Nat.mul(B, Nat.mul(Bk, s2)), Nat.mul(Nat.mul(B, Bk), s2), Equal.sym(Nat, Nat.mul(Nat.mul(B, Bk), s2), Nat.mul(B, Nat.mul(Bk, s2)), L.mul_assoc(B, Bk, s2))))), Equal.trans(Nat, Nat.add(ws, Nat.add(Nat.mul(B, s1), Nat.mul(Nat.mul(B, Bk), s2))), Nat.add(Nat.add(ws, Nat.mul(B, s1)), Nat.mul(Nat.mul(B, Bk), s2)), Nat.add(Nat.add(ws, Nat.mul(B, s1)), Nat.mul(Nat.mul(B, Bk), s2b)), Equal.sym(Nat, Nat.add(Nat.add(ws, Nat.mul(B, s1)), Nat.mul(Nat.mul(B, Bk), s2)), Nat.add(ws, Nat.add(Nat.mul(B, s1), Nat.mul(Nat.mul(B, Bk), s2))), N.add_assoc(ws, Nat.mul(B, s1), Nat.mul(Nat.mul(B, Bk), s2))), Equal.cong(Nat, Nat, w => Nat.add(Nat.add(ws, Nat.mul(B, s1)), Nat.mul(Nat.mul(B, Bk), w)), s2, s2b, Equal.sym(Nat, s2b, s2, e_idx)))))

# cnt / 2 + (cnt - cnt / 2) == cnt
def half_split(+cnt: Nat) -> {Nat.add(Nat.div(cnt, 2n), Nat.sub(cnt, Nat.div(cnt, 2n))) == cnt : Nat}:
  +d = Nat.div(cnt, 2n)
  +m = Nat.mod(cnt, 2n)
  +x = Nat.add(d, 0n)
  +e = Equal.trans(Nat, Nat.add(d, Nat.add(m, x)), Nat.add(m, Nat.add(d, x)), cnt, L.add_left_comm(m, d, x), Equal.trans(Nat, Nat.add(m, Nat.mul(2n, d)), Nat.add(m, Nat.mul(d, 2n)), cnt, Equal.cong(Nat, Nat, w => Nat.add(m, w), Nat.mul(2n, d), Nat.mul(d, 2n), Equal.sym(Nat, Nat.mul(d, 2n), Nat.mul(2n, d), L.mul_comm(d, 2n))), L.div_mod(cnt, 1n)))
  L.sub_add(cnt, d, (Nat.add(m, x), e))

def base(+c: Nat, +half: Nat, +rf: Nat, +ps: +List<M.AP>, +us: +List<+List<Nat>>, +lo: Nat, +cnt: Nat, +hf: {cnt == 1n : Nat}, +hw: M.Win(half, us), +hn: M.Le(F.plen(ps), Nat.pow(2n, rf))) -> {M.window_sum(half, rf, ps, us, lo) == M.spec(c, half, ps, us, cnt, lo) : Nat}:
  %Equal.sym(Nat, cnt, 1n, hf) : {M.window_sum(half, rf, ps, us, lo) == M.spec(c, half, ps, us, _, lo) : Nat}
  +ws = M.wsum(ps, us, lo, half)
  Equal.trans(Nat, M.window_sum(half, rf, ps, us, lo), ws, Nat.add(ws, Nat.mul(Nat.pow(2n, c), 0n)), F.window_ok(half, rf, ps, us, lo, hw, hn), Equal.trans(Nat, ws, Nat.add(ws, 0n), Nat.add(ws, Nat.mul(Nat.pow(2n, c), 0n)), Equal.sym(Nat, Nat.add(ws, 0n), ws, N.add_zero_r(ws)), Equal.cong(Nat, Nat, w => Nat.add(ws, w), 0n, Nat.mul(Nat.pow(2n, c), 0n), Equal.sym(Nat, Nat.mul(Nat.pow(2n, c), 0n), 0n, L.mul_zero_r(Nat.pow(2n, c))))))

def wrange_ok(+fuel: Nat, one: Bool, +c: Nat, +half: Nat, +rf: Nat, +ps: +List<M.AP>, +us: +List<+List<Nat>>, +lo: Nat, +cnt: Nat, +hf: M.Fuel(fuel, one, cnt), +hw: M.Win(half, us), +hn: M.Le(F.plen(ps), Nat.pow(2n, rf))) -> {M.wrange(fuel, one, c, half, rf, ps, us, lo, cnt) == M.spec(c, half, ps, us, cnt, lo) : Nat}:
  match fuel one:
    case 1n+f False{}:
      (hf1, hf2) = hf
      +h = Nat.div(cnt, 2n)
      +h2 = Nat.sub(cnt, h)
      +B = Nat.pow(2n, c)
      +sa = M.spec(c, half, ps, us, h, lo)
      +sb = M.spec(c, half, ps, us, h2, Nat.add(lo, h))
      +wa = M.wrange(f, Nat.is_lt(h, 2n), c, half, rf, ps, us, lo, h)
      +wb = M.wrange(f, Nat.is_lt(h2, 2n), c, half, rf, ps, us, Nat.add(lo, h), h2)
      Equal.trans(Nat, Nat.add(wa, M.dbl_n(Nat.mul(h, c), wb)), Nat.add(sa, Nat.mul(Nat.pow(B, h), sb)), M.spec(c, half, ps, us, cnt, lo), R.cadd(wa, sa, M.dbl_n(Nat.mul(h, c), wb), Nat.mul(Nat.pow(B, h), sb), wrange_ok(f, Nat.is_lt(h, 2n), c, half, rf, ps, us, lo, h, hf1, hw, hn), Equal.trans(Nat, M.dbl_n(Nat.mul(h, c), wb), Nat.mul(Nat.pow(2n, Nat.mul(h, c)), wb), Nat.mul(Nat.pow(B, h), sb), dbl_ok(Nat.mul(h, c), wb), Equal.trans(Nat, Nat.mul(Nat.pow(2n, Nat.mul(h, c)), wb), Nat.mul(Nat.pow(B, h), wb), Nat.mul(Nat.pow(B, h), sb), Equal.cong(Nat, Nat, w => Nat.mul(w, wb), Nat.pow(2n, Nat.mul(h, c)), Nat.pow(B, h), pow_mul(h, c)), Equal.cong(Nat, Nat, w => Nat.mul(Nat.pow(B, h), w), wb, sb, wrange_ok(f, Nat.is_lt(h2, 2n), c, half, rf, ps, us, Nat.add(lo, h), h2, hf2, hw, hn))))), Equal.trans(Nat, Nat.add(sa, Nat.mul(Nat.pow(B, h), sb)), M.spec(c, half, ps, us, Nat.add(h, h2), lo), M.spec(c, half, ps, us, cnt, lo), Equal.sym(Nat, M.spec(c, half, ps, us, Nat.add(h, h2), lo), Nat.add(sa, Nat.mul(Nat.pow(B, h), sb)), spec_split(c, half, ps, us, h, h2, lo)), Equal.cong(Nat, Nat, w => M.spec(c, half, ps, us, w, lo), Nat.add(h, h2), cnt, half_split(cnt))))
    case 1n+f True{}:
      base(c, half, rf, ps, us, lo, cnt, hf, hw, hn)
    case 0n _:
      base(c, half, rf, ps, us, lo, cnt, hf, hw, hn)

