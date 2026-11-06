import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L

# A decision procedure for sums: two sums of the same atoms (in any order and
# bracketing) are equal. An expression is a tree of atom indices; `ac` proves
# ev(env, e1) == ev(env, e2) once the sorted atom lists agree, which the checker
# decides by computing on the (small, concrete) index lists. The atoms themselves
# (env) stay symbolic.

type AE is Data:
  AV{i: Nat}
  AP{a: AE, b: AE}

def nth(+xs: +List<Nat>, +i: Nat) -> Nat:
  match xs:
    case []:
      0n
    case x <> r:
      match i:
        case 0n:
          x
        case 1n+j:
          nth(r, j)

def ev(+env: +List<Nat>, e: AE) -> Nat:
  match e:
    case AV{i}:
      nth(env, i)
    case AP{a, b}:
      Nat.add(ev(env, a), ev(env, b))

def fl(e: AE, +acc: +List<Nat>) -> +List<Nat>:
  match e:
    case AV{i}:
      i <> acc
    case AP{a, b}:
      fl(a, fl(b, acc))

def sumi(+env: +List<Nat>, xs: +List<Nat>) -> Nat:
  match xs:
    case []:
      0n
    case i <> r:
      Nat.add(nth(env, i), sumi(env, r))

def ins_go(b: Bool, +i: Nat, +x: Nat, +r: +List<Nat>, +ir: +List<Nat>) -> +List<Nat>:
  match b:
    case True{}:
      i <> x <> r
    case False{}:
      x <> ir

def ins(+i: Nat, +xs: +List<Nat>) -> +List<Nat>:
  match xs:
    case []:
      [i]
    case x <> r:
      ins_go(Nat.is_le(i, x), i, x, r, ins(i, r))

def srt(+xs: +List<Nat>) -> +List<Nat>:
  match xs:
    case []:
      []
    case x <> r:
      ins(x, srt(r))

law fl_ok:
  for +env: +List<Nat>
  for +e: AE
  for +acc: +List<Nat>
  {sumi(env, fl(e, acc)) == Nat.add(ev(env, e), sumi(env, acc)) : Nat}

def fl_ok(env, e, acc):
  match e:
    case AV{i}:
      {==}
    case AP{a, b}:
      %Equal.sym(Nat, sumi(env, fl(a, fl(b, acc))), Nat.add(ev(env, a), sumi(env, fl(b, acc))), fl_ok(env, a, fl(b, acc))) : {_ == Nat.add(Nat.add(ev(env, a), ev(env, b)), sumi(env, acc)) : Nat}
      %Equal.sym(Nat, sumi(env, fl(b, acc)), Nat.add(ev(env, b), sumi(env, acc)), fl_ok(env, b, acc)) : {Nat.add(ev(env, a), _) == Nat.add(Nat.add(ev(env, a), ev(env, b)), sumi(env, acc)) : Nat}
      Equal.sym(Nat, Nat.add(Nat.add(ev(env, a), ev(env, b)), sumi(env, acc)), Nat.add(ev(env, a), Nat.add(ev(env, b), sumi(env, acc))), N.add_assoc(ev(env, a), ev(env, b), sumi(env, acc)))

def ins_go_ok(+env: +List<Nat>, b: Bool, +i: Nat, +x: Nat, +r: +List<Nat>,
    ih: {sumi(env, ins(i, r)) == Nat.add(nth(env, i), sumi(env, r)) : Nat})
    -> {sumi(env, ins_go(b, i, x, r, ins(i, r))) == Nat.add(nth(env, i), Nat.add(nth(env, x), sumi(env, r))) : Nat}:
  match b:
    case True{}:
      {==}
    case False{}:
      %Equal.sym(Nat, sumi(env, ins(i, r)), Nat.add(nth(env, i), sumi(env, r)), ih) : {Nat.add(nth(env, x), _) == Nat.add(nth(env, i), Nat.add(nth(env, x), sumi(env, r))) : Nat}
      L.add_left_comm(nth(env, i), nth(env, x), sumi(env, r))

law ins_ok:
  for +env: +List<Nat>
  for +i: Nat
  for +xs: +List<Nat>
  {sumi(env, ins(i, xs)) == Nat.add(nth(env, i), sumi(env, xs)) : Nat}

def ins_ok(env, i, xs):
  match xs:
    case []:
      {==}
    case x <> r:
      ins_go_ok(env, Nat.is_le(i, x), i, x, r, ins_ok(env, i, r))

law srt_ok:
  for +env: +List<Nat>
  for +xs: +List<Nat>
  {sumi(env, srt(xs)) == sumi(env, xs) : Nat}

def srt_ok(env, xs):
  match xs:
    case []:
      {==}
    case x <> r:
      %Equal.sym(Nat, sumi(env, ins(x, srt(r))), Nat.add(nth(env, x), sumi(env, srt(r))), ins_ok(env, x, srt(r))) : {_ == Nat.add(nth(env, x), sumi(env, r)) : Nat}
      Equal.cong(Nat, Nat, v => Nat.add(nth(env, x), v), sumi(env, srt(r)), sumi(env, r), srt_ok(env, r))

def ev_sum(+env: +List<Nat>, +e: AE) -> {ev(env, e) == sumi(env, srt(fl(e, []))) : Nat}:
  %Equal.sym(Nat, sumi(env, srt(fl(e, []))), sumi(env, fl(e, [])), srt_ok(env, fl(e, []))) : {ev(env, e) == _ : Nat}
  %Equal.sym(Nat, sumi(env, fl(e, [])), Nat.add(ev(env, e), 0n), fl_ok(env, e, [])) : {ev(env, e) == _ : Nat}
  Equal.sym(Nat, Nat.add(ev(env, e), 0n), ev(env, e), N.add_zero_r(ev(env, e)))

# Two sums with the same atoms are equal.
law ac:
  for +env: +List<Nat>
  for +e1: AE
  for +e2: AE
  for h: {srt(fl(e1, [])) == srt(fl(e2, [])) : +List<Nat>}
  {ev(env, e1) == ev(env, e2) : Nat}

def ac(env, e1, e2, h):
  %Equal.sym(Nat, ev(env, e2), sumi(env, srt(fl(e2, []))), ev_sum(env, e2)) : {ev(env, e1) == _ : Nat}
  %h : {ev(env, e1) == sumi(env, _) : Nat}
  ev_sum(env, e1)
