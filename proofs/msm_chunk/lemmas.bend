import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L
import ./model.bend as M

# Lemmas about the MSM model (model.bend). Plain Nat algebra; no number is ever computed.

def cadd(+x: Nat, +x2: Nat, +y: Nat, +y2: Nat, hx: {x == x2 : Nat}, hy: {y == y2 : Nat}) -> {Nat.add(x, y) == Nat.add(x2, y2) : Nat}:
  %hx : {Nat.add(x, y) == Nat.add(_, y2) : Nat}
  %hy : {Nat.add(x, y) == Nat.add(x, _) : Nat}
  {==}

def msm_nil_r(+x: +List<Nat>) -> {M.msm(x, Nil{}) == 0n : Nat}:
  match x:
    case Nil{}:
      {==}
    case Con{p, t}:
      {==}

def msm_nil2(+x: +List<Nat>, +y: +List<Nat>) -> {0n == Nat.add(M.msm(x, Nil{}), M.msm(y, Nil{})) : Nat}:
  %Equal.sym(Nat, M.msm(x, Nil{}), 0n, msm_nil_r(x)) : {0n == Nat.add(_, M.msm(y, Nil{})) : Nat}
  %Equal.sym(Nat, M.msm(y, Nil{}), 0n, msm_nil_r(y)) : {0n == Nat.add(0n, _) : Nat}
  {==}

# Splitting both lists at the same position splits the MSM.
def msm_split(+ps: +List<Nat>, +ss: +List<Nat>, +m: Nat) -> {M.msm(ps, ss) == Nat.add(M.msm(M.take(ps, m), M.take(ss, m)), M.msm(M.drop(ps, m), M.drop(ss, m))) : Nat}:
  match ps:
    case Nil{}:
      {==}
    case Con{+p, +pt}:
      match ss:
        case Nil{}:
          msm_nil2(M.take(Con{p, pt}, m), M.drop(Con{p, pt}, m))
        case Con{+s, +st}:
          match m:
            case 0n:
              {==}
            case 1n+k:
              +sp = Nat.mul(s, p)
              +a = M.msm(M.take(pt, k), M.take(st, k))
              +b = M.msm(M.drop(pt, k), M.drop(st, k))
              Equal.trans(Nat, Nat.add(sp, M.msm(pt, st)), Nat.add(sp, Nat.add(a, b)), Nat.add(Nat.add(sp, a), b), Equal.cong(Nat, Nat, w => Nat.add(sp, w), M.msm(pt, st), Nat.add(a, b), msm_split(pt, st, k)), Equal.sym(Nat, Nat.add(Nat.add(sp, a), b), Nat.add(sp, Nat.add(a, b)), N.add_assoc(sp, a, b)))

def mpar_ok(+fuel: Nat, +cnt: Nat, +len: Nat, +ps: +List<Nat>, +ss: +List<Nat>) -> {M.mpar(fuel, cnt, len, ps, ss) == M.msm(ps, ss) : Nat}:
  match fuel:
    case 0n:
      {==}
    case 1n+f:
      match cnt:
        case 0n:
          {==}
        case 1n+c:
          match c:
            case 0n:
              {==}
            case 1n+k:
              +h = Nat.div(2n+k, 2n)
              +m = Nat.div(Nat.mul(len, h), 2n+k)
              Equal.trans(Nat, Nat.add(M.mpar(f, h, m, M.take(ps, m), M.take(ss, m)), M.mpar(f, Nat.sub(2n+k, h), Nat.sub(len, m), M.drop(ps, m), M.drop(ss, m))), Nat.add(M.msm(M.take(ps, m), M.take(ss, m)), M.msm(M.drop(ps, m), M.drop(ss, m))), M.msm(ps, ss), cadd(M.mpar(f, h, m, M.take(ps, m), M.take(ss, m)), M.msm(M.take(ps, m), M.take(ss, m)), M.mpar(f, Nat.sub(2n+k, h), Nat.sub(len, m), M.drop(ps, m), M.drop(ss, m)), M.msm(M.drop(ps, m), M.drop(ss, m)), mpar_ok(f, h, m, M.take(ps, m), M.take(ss, m)), mpar_ok(f, Nat.sub(2n+k, h), Nat.sub(len, m), M.drop(ps, m), M.drop(ss, m))), Equal.sym(Nat, M.msm(ps, ss), Nat.add(M.msm(M.take(ps, m), M.take(ss, m)), M.msm(M.drop(ps, m), M.drop(ss, m))), msm_split(ps, ss, m)))

def msm_auto_ok(+ps: +List<Nat>, +ss: +List<Nat>) -> {M.msm_auto(ps, ss) == M.msm(ps, ss) : Nat}:
  mpar_ok(32n, M.pick_cnt(M.length(ps)), M.length(ps), ps, ss)

# --- appending aligned lists -----------------------------------------------------------------

def msm_append(+p: +List<Nat>, +s: +List<Nat>, +xs: +List<Nat>, +ys: +List<Nat>, h: {M.length(p) == M.length(s) : Nat}) -> {M.msm(M.append(p, xs), M.append(s, ys)) == Nat.add(M.msm(p, s), M.msm(xs, ys)) : Nat}:
  match p s:
    case Nil{} Nil{}:
      {==}
    case Con{+a, +pt} Con{+b, +st}:
      +ba = Nat.mul(b, a)
      Equal.trans(Nat, Nat.add(ba, M.msm(M.append(pt, xs), M.append(st, ys))), Nat.add(ba, Nat.add(M.msm(pt, st), M.msm(xs, ys))), Nat.add(Nat.add(ba, M.msm(pt, st)), M.msm(xs, ys)), Equal.cong(Nat, Nat, w => Nat.add(ba, w), M.msm(M.append(pt, xs), M.append(st, ys)), Nat.add(M.msm(pt, st), M.msm(xs, ys)), msm_append(pt, st, xs, ys, L.succ_inj(M.length(pt), M.length(st), h))), Equal.sym(Nat, Nat.add(Nat.add(ba, M.msm(pt, st)), M.msm(xs, ys)), Nat.add(ba, Nat.add(M.msm(pt, st), M.msm(xs, ys))), N.add_assoc(ba, M.msm(pt, st), M.msm(xs, ys))))
    case Nil{} Con{+b, +st}:
      Empty.absurd({M.msm(M.append(Nil{}, xs), M.append(Con{b, st}, ys)) == Nat.add(M.msm(Nil{}, Con{b, st}), M.msm(xs, ys)) : Nat}, L.succ_ne_zero(M.length(st), Equal.sym(Nat, 0n, 1n+M.length(st), h)))
    case Con{+a, +pt} Nil{}:
      Empty.absurd({M.msm(M.append(Con{a, pt}, xs), M.append(Nil{}, ys)) == Nat.add(M.msm(Con{a, pt}, Nil{}), M.msm(xs, ys)) : Nat}, L.succ_ne_zero(M.length(pt), h))

def flat_msm(+ps: +List<+List<Nat>>, +ss: +List<+List<Nat>>, h: M.Aligned(ps, ss)) -> {M.msm(M.flat(ps, Nil{}), M.flat(ss, Nil{})) == M.psum(ps, ss) : Nat}:
  match ps ss:
    case Nil{} Nil{}:
      {==}
    case Con{+p, +pt} Con{+s, +st}:
      (hl, hr) = h
      Equal.trans(Nat, M.msm(M.append(p, M.flat(pt, Nil{})), M.append(s, M.flat(st, Nil{}))), Nat.add(M.msm(p, s), M.msm(M.flat(pt, Nil{}), M.flat(st, Nil{}))), Nat.add(M.msm(p, s), M.psum(pt, st)), msm_append(p, s, M.flat(pt, Nil{}), M.flat(st, Nil{}), hl), Equal.cong(Nat, Nat, w => Nat.add(M.msm(p, s), w), M.msm(M.flat(pt, Nil{}), M.flat(st, Nil{})), M.psum(pt, st), flat_msm(pt, st, hr)))
    case Nil{} Con{+s, +st}:
      match h:
    case Con{+p, +pt} Nil{}:
      match h:

def psum_nil_r(+x: +List<+List<Nat>>) -> {M.psum(x, Nil{}) == 0n : Nat}:
  match x:
    case Nil{}:
      {==}
    case Con{p, t}:
      {==}

def psum_nil2(+x: +List<+List<Nat>>, +y: +List<+List<Nat>>) -> {Nat.add(M.psum(x, Nil{}), M.psum(y, Nil{})) == 0n : Nat}:
  %Equal.sym(Nat, M.psum(x, Nil{}), 0n, psum_nil_r(x)) : {Nat.add(_, M.psum(y, Nil{})) == 0n : Nat}
  %Equal.sym(Nat, M.psum(y, Nil{}), 0n, psum_nil_r(y)) : {Nat.add(0n, _) == 0n : Nat}
  {==}

def psum_split(+ps: +List<+List<Nat>>, +ss: +List<+List<Nat>>, +m: Nat) -> {M.psum(ps, ss) == Nat.add(M.psum(M.ltake(ps, m), M.ltake(ss, m)), M.psum(M.ldrop(ps, m), M.ldrop(ss, m))) : Nat}:
  match ps:
    case Nil{}:
      {==}
    case Con{+p, +pt}:
      match ss:
        case Nil{}:
          Equal.sym(Nat, Nat.add(M.psum(M.ltake(Con{p, pt}, m), Nil{}), M.psum(M.ldrop(Con{p, pt}, m), Nil{})), 0n, psum_nil2(M.ltake(Con{p, pt}, m), M.ldrop(Con{p, pt}, m)))
        case Con{+s, +st}:
          match m:
            case 0n:
              {==}
            case 1n+k:
              +sp = M.msm(p, s)
              +a = M.psum(M.ltake(pt, k), M.ltake(st, k))
              +b = M.psum(M.ldrop(pt, k), M.ldrop(st, k))
              Equal.trans(Nat, Nat.add(sp, M.psum(pt, st)), Nat.add(sp, Nat.add(a, b)), Nat.add(Nat.add(sp, a), b), Equal.cong(Nat, Nat, w => Nat.add(sp, w), M.psum(pt, st), Nat.add(a, b), psum_split(pt, st, k)), Equal.sym(Nat, Nat.add(Nat.add(sp, a), b), Nat.add(sp, Nat.add(a, b)), N.add_assoc(sp, a, b)))

def aligned_take(+ps: +List<+List<Nat>>, +ss: +List<+List<Nat>>, +m: Nat, +h: M.Aligned(ps, ss)) -> M.Aligned(M.ltake(ps, m), M.ltake(ss, m)):
  match ps ss:
    case Nil{} Nil{}:
      Unit{}
    case Con{+p, +pt} Con{+s, +st}:
      match m:
        case 0n:
          Unit{}
        case 1n+k:
          (hl, hr) = h
          (hl, aligned_take(pt, st, k, hr))
    case Nil{} Con{+s, +st}:
      match h:
    case Con{+p, +pt} Nil{}:
      match h:

def aligned_drop(+ps: +List<+List<Nat>>, +ss: +List<+List<Nat>>, +m: Nat, +h: M.Aligned(ps, ss)) -> M.Aligned(M.ldrop(ps, m), M.ldrop(ss, m)):
  match ps ss:
    case Nil{} Nil{}:
      Unit{}
    case Con{+p, +pt} Con{+s, +st}:
      match m:
        case 0n:
          h
        case 1n+k:
          (hl, hr) = h
          aligned_drop(pt, st, k, hr)
    case Nil{} Con{+s, +st}:
      match h:
    case Con{+p, +pt} Nil{}:
      match h:

def groups_ok(+fuel: Nat, small: Bool, +cnt: Nat, +ps: +List<+List<Nat>>, +ss: +List<+List<Nat>>, +h: M.Aligned(ps, ss)) -> {M.groups(fuel, small, cnt, ps, ss) == M.psum(ps, ss) : Nat}:
  match fuel small:
    case 1n+f False{}:
      +h1 = Nat.div(cnt, 2n)
      +h2 = Nat.sub(cnt, h1)
      +g1 = M.groups(f, M.small_g(h1), h1, M.ltake(ps, h1), M.ltake(ss, h1))
      +g2 = M.groups(f, M.small_g(h2), h2, M.ldrop(ps, h1), M.ldrop(ss, h1))
      +q1 = M.psum(M.ltake(ps, h1), M.ltake(ss, h1))
      +q2 = M.psum(M.ldrop(ps, h1), M.ldrop(ss, h1))
      Equal.trans(Nat, Nat.add(g1, g2), Nat.add(q1, q2), M.psum(ps, ss), cadd(g1, q1, g2, q2, groups_ok(f, M.small_g(h1), h1, M.ltake(ps, h1), M.ltake(ss, h1), aligned_take(ps, ss, h1, h)), groups_ok(f, M.small_g(h2), h2, M.ldrop(ps, h1), M.ldrop(ss, h1), aligned_drop(ps, ss, h1, h))), Equal.sym(Nat, M.psum(ps, ss), Nat.add(q1, q2), psum_split(ps, ss, h1)))
    case 1n+f True{}:
      Equal.trans(Nat, M.msm_auto(M.flat(ps, Nil{}), M.flat(ss, Nil{})), M.msm(M.flat(ps, Nil{}), M.flat(ss, Nil{})), M.psum(ps, ss), msm_auto_ok(M.flat(ps, Nil{}), M.flat(ss, Nil{})), flat_msm(ps, ss, h))
    case 0n _:
      Equal.trans(Nat, M.msm_auto(M.flat(ps, Nil{}), M.flat(ss, Nil{})), M.msm(M.flat(ps, Nil{}), M.flat(ss, Nil{})), M.psum(ps, ss), msm_auto_ok(M.flat(ps, Nil{}), M.flat(ss, Nil{})), flat_msm(ps, ss, h))

# --- merging: weights, shared-base scalar addition, the accumulator tree ---------------------

def msm_scale(+ps: +List<Nat>, +ss: +List<Nat>, +r: Nat) -> {M.msm(ps, M.scale(ss, r)) == Nat.mul(r, M.msm(ps, ss)) : Nat}:
  match ps ss:
    case Con{+p, +pt} Con{+s, +st}:
      +m = M.msm(pt, st)
      +x = Equal.trans(Nat, Nat.mul(Nat.mul(s, r), p), Nat.mul(Nat.mul(r, s), p), Nat.mul(r, Nat.mul(s, p)), Equal.cong(Nat, Nat, w => Nat.mul(w, p), Nat.mul(s, r), Nat.mul(r, s), L.mul_comm(s, r)), L.mul_assoc(r, s, p))
      Equal.trans(Nat, Nat.add(Nat.mul(Nat.mul(s, r), p), M.msm(pt, M.scale(st, r))), Nat.add(Nat.mul(r, Nat.mul(s, p)), Nat.mul(r, m)), Nat.mul(r, Nat.add(Nat.mul(s, p), m)), cadd(Nat.mul(Nat.mul(s, r), p), Nat.mul(r, Nat.mul(s, p)), M.msm(pt, M.scale(st, r)), Nat.mul(r, m), x, msm_scale(pt, st, r)), Equal.sym(Nat, Nat.mul(r, Nat.add(Nat.mul(s, p), m)), Nat.add(Nat.mul(r, Nat.mul(s, p)), Nat.mul(r, m)), L.mul_add_l(r, Nat.mul(s, p), m)))
    case Nil{} _:
      Equal.sym(Nat, Nat.mul(r, 0n), 0n, L.mul_zero_r(r))
    case Con{+p, +pt} Nil{}:
      Equal.sym(Nat, Nat.mul(r, 0n), 0n, L.mul_zero_r(r))

def length_scale(+xs: +List<Nat>, +r: Nat) -> {M.length(M.scale(xs, r)) == M.length(xs) : Nat}:
  match xs:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      Equal.cong(Nat, Nat, w => 1n+w, M.length(M.scale(t, r)), M.length(t), length_scale(t, r))

# s1 * P + s2 * P == (s1 + s2) * P, base by base: adding two proofs' scalar vectors on the
# shared bases adds their MSMs.
def msm_vadd(+bs: +List<Nat>, +a: +List<Nat>, +b: +List<Nat>) -> {M.msm(bs, M.vadd(a, b)) == Nat.add(M.msm(bs, a), M.msm(bs, b)) : Nat}:
  match bs:
    case Nil{}:
      {==}
    case Con{+p, +pt}:
      match a:
        case Nil{}:
          match b:
            case Nil{}:
              {==}
            case Con{+y, +bt}:
              {==}
        case Con{+x, +at}:
          match b:
            case Nil{}:
              Equal.sym(Nat, Nat.add(M.msm(Con{p, pt}, Con{x, at}), 0n), M.msm(Con{p, pt}, Con{x, at}), N.add_zero_r(M.msm(Con{p, pt}, Con{x, at})))
            case Con{+y, +bt}:
              +xp = Nat.mul(x, p)
              +yp = Nat.mul(y, p)
              +ma = M.msm(pt, at)
              +mb = M.msm(pt, bt)
              Equal.trans(Nat, Nat.add(Nat.mul(Nat.add(x, y), p), M.msm(pt, M.vadd(at, bt))), Nat.add(Nat.add(xp, yp), Nat.add(ma, mb)), Nat.add(Nat.add(xp, ma), Nat.add(yp, mb)), cadd(Nat.mul(Nat.add(x, y), p), Nat.add(xp, yp), M.msm(pt, M.vadd(at, bt)), Nat.add(ma, mb), L.mul_add_r(x, y, p), msm_vadd(pt, at, bt)), N.swap_mid(xp, yp, ma, mb))

def aligned_append(+pa: +List<+List<Nat>>, +sa: +List<+List<Nat>>, +pb: +List<+List<Nat>>, +sb: +List<+List<Nat>>, +ha: M.Aligned(pa, sa), +hb: M.Aligned(pb, sb)) -> M.Aligned(M.lapp(pa, pb), M.lapp(sa, sb)):
  match pa sa:
    case Nil{} Nil{}:
      hb
    case Con{+p, +pt} Con{+s, +st}:
      (hl, hr) = ha
      (hl, aligned_append(pt, st, pb, sb, hr, hb))
    case Nil{} Con{+s, +st}:
      match ha:
    case Con{+p, +pt} Nil{}:
      match ha:

def psum_append(+pa: +List<+List<Nat>>, +sa: +List<+List<Nat>>, +pb: +List<+List<Nat>>, +sb: +List<+List<Nat>>, +ha: M.Aligned(pa, sa)) -> {M.psum(M.lapp(pa, pb), M.lapp(sa, sb)) == Nat.add(M.psum(pa, sa), M.psum(pb, sb)) : Nat}:
  match pa sa:
    case Nil{} Nil{}:
      {==}
    case Con{+p, +pt} Con{+s, +st}:
      (hl, hr) = ha
      +m = M.msm(p, s)
      Equal.trans(Nat, Nat.add(m, M.psum(M.lapp(pt, pb), M.lapp(st, sb))), Nat.add(m, Nat.add(M.psum(pt, st), M.psum(pb, sb))), Nat.add(Nat.add(m, M.psum(pt, st)), M.psum(pb, sb)), Equal.cong(Nat, Nat, w => Nat.add(m, w), M.psum(M.lapp(pt, pb), M.lapp(st, sb)), Nat.add(M.psum(pt, st), M.psum(pb, sb)), psum_append(pt, st, pb, sb, hr)), Equal.sym(Nat, Nat.add(Nat.add(m, M.psum(pt, st)), M.psum(pb, sb)), Nat.add(m, Nat.add(M.psum(pt, st), M.psum(pb, sb))), N.add_assoc(m, M.psum(pt, st), M.psum(pb, sb))))
    case Nil{} Con{+s, +st}:
      match ha:
    case Con{+p, +pt} Nil{}:
      match ha:

# The accessors of a join.
def join_ps(+x: M.Acc, +y: M.Acc) -> {M.aps(M.join(x, y)) == M.lapp(M.aps(x), M.aps(y)) : +List<+List<Nat>>}:
  match x y:
    case M.Acc{a, b, c} M.Acc{d, e, f}:
      {==}

def join_ss(+x: M.Acc, +y: M.Acc) -> {M.ass(M.join(x, y)) == M.lapp(M.ass(x), M.ass(y)) : +List<+List<Nat>>}:
  match x y:
    case M.Acc{a, b, c} M.Acc{d, e, f}:
      {==}

def join_gx(+x: M.Acc, +y: M.Acc) -> {M.agx(M.join(x, y)) == M.vadd(M.agx(x), M.agx(y)) : +List<Nat>}:
  match x y:
    case M.Acc{a, b, c} M.Acc{d, e, f}:
      {==}

def check_parts(+x: M.Acc, +bases: +List<Nat>) -> {M.check_sum(x, bases) == Nat.add(M.all_groups(M.aps(x), M.ass(x)), M.msm_auto(bases, M.agx(x))) : Nat}:
  match x:
    case M.Acc{a, b, c}:
      {==}

# The per-proof terms of the accumulator are aligned.
def acc_aligned(+t: M.Tree, +w: M.WF(t)) -> M.Aligned(M.aps(M.acc(t)), M.ass(M.acc(t))):
  match t:
    case M.Em{}:
      Unit{}
    case M.Lf{+r, +p}:
      match p:
        case M.Pf{+ops, +oss, +gx}:
          (Equal.trans(Nat, M.length(ops), M.length(oss), M.length(M.scale(oss, r)), w, Equal.sym(Nat, M.length(M.scale(oss, r)), M.length(oss), length_scale(oss, r))), Unit{})
    case M.Nd{+a, +b}:
      (wa, wb) = w
      %Equal.sym(+List<+List<Nat>>, M.aps(M.join(M.acc(a), M.acc(b))), M.lapp(M.aps(M.acc(a)), M.aps(M.acc(b))), join_ps(M.acc(a), M.acc(b))) : M.Aligned(_, M.ass(M.join(M.acc(a), M.acc(b))))
      %Equal.sym(+List<+List<Nat>>, M.ass(M.join(M.acc(a), M.acc(b))), M.lapp(M.ass(M.acc(a)), M.ass(M.acc(b))), join_ss(M.acc(a), M.acc(b))) : M.Aligned(M.lapp(M.aps(M.acc(a)), M.aps(M.acc(b))), _)
      aligned_append(M.aps(M.acc(a)), M.ass(M.acc(a)), M.aps(M.acc(b)), M.ass(M.acc(b)), acc_aligned(a, wa), acc_aligned(b, wb))

def own(t: M.Tree) -> Nat:
  match t:
    case M.Em{}:
      0n
    case M.Lf{+r, +p}:
      M.Pf{+ops, +oss, _} = p
      Nat.mul(r, M.msm(ops, oss))
    case M.Nd{a, b}:
      Nat.add(own(a), own(b))

def fixs(t: M.Tree, +bases: +List<Nat>) -> Nat:
  match t:
    case M.Em{}:
      0n
    case M.Lf{+r, +p}:
      M.Pf{_, _, +gx} = p
      Nat.mul(r, M.msm(bases, gx))
    case M.Nd{a, b}:
      Nat.add(fixs(a, bases), fixs(b, bases))

def acc_own(+t: M.Tree, +w: M.WF(t)) -> {M.psum(M.aps(M.acc(t)), M.ass(M.acc(t))) == own(t) : Nat}:
  match t:
    case M.Em{}:
      {==}
    case M.Lf{+r, +p}:
      match p:
        case M.Pf{+ops, +oss, +gx}:
          Equal.trans(Nat, Nat.add(M.msm(ops, M.scale(oss, r)), 0n), M.msm(ops, M.scale(oss, r)), Nat.mul(r, M.msm(ops, oss)), N.add_zero_r(M.msm(ops, M.scale(oss, r))), msm_scale(ops, oss, r))
    case M.Nd{+a, +b}:
      (wa, wb) = w
      %Equal.sym(+List<+List<Nat>>, M.aps(M.join(M.acc(a), M.acc(b))), M.lapp(M.aps(M.acc(a)), M.aps(M.acc(b))), join_ps(M.acc(a), M.acc(b))) : {M.psum(_, M.ass(M.join(M.acc(a), M.acc(b)))) == Nat.add(own(a), own(b)) : Nat}
      %Equal.sym(+List<+List<Nat>>, M.ass(M.join(M.acc(a), M.acc(b))), M.lapp(M.ass(M.acc(a)), M.ass(M.acc(b))), join_ss(M.acc(a), M.acc(b))) : {M.psum(M.lapp(M.aps(M.acc(a)), M.aps(M.acc(b))), _) == Nat.add(own(a), own(b)) : Nat}
      Equal.trans(Nat, M.psum(M.lapp(M.aps(M.acc(a)), M.aps(M.acc(b))), M.lapp(M.ass(M.acc(a)), M.ass(M.acc(b)))), Nat.add(M.psum(M.aps(M.acc(a)), M.ass(M.acc(a))), M.psum(M.aps(M.acc(b)), M.ass(M.acc(b)))), Nat.add(own(a), own(b)), psum_append(M.aps(M.acc(a)), M.ass(M.acc(a)), M.aps(M.acc(b)), M.ass(M.acc(b)), acc_aligned(a, wa)), cadd(M.psum(M.aps(M.acc(a)), M.ass(M.acc(a))), own(a), M.psum(M.aps(M.acc(b)), M.ass(M.acc(b))), own(b), acc_own(a, wa), acc_own(b, wb)))

def acc_fix(+t: M.Tree, +bases: +List<Nat>) -> {M.msm(bases, M.agx(M.acc(t))) == fixs(t, bases) : Nat}:
  match t:
    case M.Em{}:
      msm_nil_r(bases)
    case M.Lf{+r, +p}:
      match p:
        case M.Pf{+ops, +oss, +gx}:
          msm_scale(bases, gx, r)
    case M.Nd{+a, +b}:
      %Equal.sym(+List<Nat>, M.agx(M.join(M.acc(a), M.acc(b))), M.vadd(M.agx(M.acc(a)), M.agx(M.acc(b))), join_gx(M.acc(a), M.acc(b))) : {M.msm(bases, _) == Nat.add(fixs(a, bases), fixs(b, bases)) : Nat}
      Equal.trans(Nat, M.msm(bases, M.vadd(M.agx(M.acc(a)), M.agx(M.acc(b)))), Nat.add(M.msm(bases, M.agx(M.acc(a))), M.msm(bases, M.agx(M.acc(b)))), Nat.add(fixs(a, bases), fixs(b, bases)), msm_vadd(bases, M.agx(M.acc(a)), M.agx(M.acc(b))), cadd(M.msm(bases, M.agx(M.acc(a))), fixs(a, bases), M.msm(bases, M.agx(M.acc(b))), fixs(b, bases), acc_fix(a, bases), acc_fix(b, bases)))

def spec_split(+t: M.Tree, +bases: +List<Nat>) -> {M.spec(t, bases) == Nat.add(own(t), fixs(t, bases)) : Nat}:
  match t:
    case M.Em{}:
      {==}
    case M.Lf{+r, +p}:
      match p:
        case M.Pf{+ops, +oss, +gx}:
          L.mul_add_l(r, M.msm(ops, oss), M.msm(bases, gx))
    case M.Nd{+a, +b}:
      Equal.trans(Nat, Nat.add(M.spec(a, bases), M.spec(b, bases)), Nat.add(Nat.add(own(a), fixs(a, bases)), Nat.add(own(b), fixs(b, bases))), Nat.add(Nat.add(own(a), own(b)), Nat.add(fixs(a, bases), fixs(b, bases))), cadd(M.spec(a, bases), Nat.add(own(a), fixs(a, bases)), M.spec(b, bases), Nat.add(own(b), fixs(b, bases)), spec_split(a, bases), spec_split(b, bases)), N.swap_mid(own(a), fixs(a, bases), own(b), fixs(b, bases)))
