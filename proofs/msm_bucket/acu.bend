import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L

# A proven normaliser for sums of Nats (associativity, commutativity, unit), used to discharge
# rearrangements like (a + b) + (c + d) == (d + a) + (c + b) in one step: write both sides as
# E-terms over an environment of atoms; `acu` proves them equal when their sorted atom lists
# coincide (which the checker computes).

type E is Data:
  V{i: Nat}
  P{a: E, b: E}
  Z{}

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

def ev(+env: +List<Nat>, e: E) -> Nat:
  match e:
    case V{i}:
      nth(env, i)
    case P{a, b}:
      Nat.add(ev(env, a), ev(env, b))
    case Z{}:
      0n

def ins_b(b: Bool, +i: Nat, +h: Nat, +t: +List<Nat>, +rest: +List<Nat>) -> +List<Nat>:
  match b:
    case True{}:
      i <> (h <> t)
    case False{}:
      h <> rest

def ins(+i: Nat, l: +List<Nat>) -> +List<Nat>:
  match l:
    case Nil{}:
      [i]
    case Con{+h, +t}:
      ins_b(Nat.is_le(i, h), i, h, t, ins(i, t))

def fl(e: E, acc: +List<Nat>) -> +List<Nat>:
  match e:
    case V{i}:
      ins(i, acc)
    case P{a, b}:
      fl(a, fl(b, acc))
    case Z{}:
      acc

def sm(+env: +List<Nat>, l: +List<Nat>) -> Nat:
  match l:
    case Nil{}:
      0n
    case Con{+i, t}:
      Nat.add(nth(env, i), sm(env, t))

def ins_b_ok(+env: +List<Nat>, b: Bool, +i: Nat, +h: Nat, +t: +List<Nat>, +rest: +List<Nat>, hr: {sm(env, rest) == Nat.add(nth(env, i), sm(env, t)) : Nat}) -> {sm(env, ins_b(b, i, h, t, rest)) == Nat.add(nth(env, i), Nat.add(nth(env, h), sm(env, t))) : Nat}:
  match b:
    case True{}:
      {==}
    case False{}:
      Equal.trans(Nat, Nat.add(nth(env, h), sm(env, rest)), Nat.add(nth(env, h), Nat.add(nth(env, i), sm(env, t))), Nat.add(nth(env, i), Nat.add(nth(env, h), sm(env, t))), Equal.cong(Nat, Nat, w => Nat.add(nth(env, h), w), sm(env, rest), Nat.add(nth(env, i), sm(env, t)), hr), L.add_left_comm(nth(env, i), nth(env, h), sm(env, t)))

def ins_ok(+env: +List<Nat>, +i: Nat, +l: +List<Nat>) -> {sm(env, ins(i, l)) == Nat.add(nth(env, i), sm(env, l)) : Nat}:
  match l:
    case Nil{}:
      {==}
    case Con{+h, +t}:
      ins_b_ok(env, Nat.is_le(i, h), i, h, t, ins(i, t), ins_ok(env, i, t))

def fl_ok(+env: +List<Nat>, +e: E, +acc: +List<Nat>) -> {sm(env, fl(e, acc)) == Nat.add(ev(env, e), sm(env, acc)) : Nat}:
  match e:
    case V{i}:
      ins_ok(env, i, acc)
    case P{a, b}:
      Equal.trans(Nat, sm(env, fl(a, fl(b, acc))), Nat.add(ev(env, a), sm(env, fl(b, acc))), Nat.add(Nat.add(ev(env, a), ev(env, b)), sm(env, acc)), fl_ok(env, a, fl(b, acc)), Equal.trans(Nat, Nat.add(ev(env, a), sm(env, fl(b, acc))), Nat.add(ev(env, a), Nat.add(ev(env, b), sm(env, acc))), Nat.add(Nat.add(ev(env, a), ev(env, b)), sm(env, acc)), Equal.cong(Nat, Nat, w => Nat.add(ev(env, a), w), sm(env, fl(b, acc)), Nat.add(ev(env, b), sm(env, acc)), fl_ok(env, b, acc)), Equal.sym(Nat, Nat.add(Nat.add(ev(env, a), ev(env, b)), sm(env, acc)), Nat.add(ev(env, a), Nat.add(ev(env, b), sm(env, acc))), N.add_assoc(ev(env, a), ev(env, b), sm(env, acc)))))
    case Z{}:
      {==}

def nf_ok(+env: +List<Nat>, +e: E) -> {sm(env, fl(e, Nil{})) == ev(env, e) : Nat}:
  Equal.trans(Nat, sm(env, fl(e, Nil{})), Nat.add(ev(env, e), 0n), ev(env, e), fl_ok(env, e, Nil{}), N.add_zero_r(ev(env, e)))

law acu:
  for +env: +List<Nat>
  for +x: E
  for +y: E
  for h: {fl(x, Nil{}) == fl(y, Nil{}) : +List<Nat>}
  {ev(env, x) == ev(env, y) : Nat}

def acu(env, x, y, h):
  %nf_ok(env, x) : {_ == ev(env, y) : Nat}
  %nf_ok(env, y) : {sm(env, fl(x, Nil{})) == _ : Nat}
  %h : {sm(env, fl(x, Nil{})) == sm(env, _) : Nat}
  {==}
