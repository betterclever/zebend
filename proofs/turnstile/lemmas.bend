import Base

# General lemmas (Nat arithmetic, Bool/Maybe inversion) used by PROOF.bend.

# Discrimination
# --------------

def IsTrue(b: Bool) -> Type:
  match b:
    case False{}:
      Empty
    case True{}:
      Unit

law false_not_true:
  for e: {False{} == True{} : Bool}
  Empty

def false_not_true(e):
  %Equal.sym(Bool, False{}, True{}, e) : IsTrue(_)
  Unit{}

def IsSome(-A: Data, m: Maybe<A>) -> Type:
  match m:
    case None{}:
      Empty
    case Some{x}:
      Unit

law none_not_some:
  for -A: Data
  for -r: A
  for e: {None{} == Some{r} : Maybe<A>}
  Empty

def none_not_some(A, r, e):
  %Equal.sym(Maybe<A>, None{}, Some{r}, e) : IsSome(A, _)
  Unit{}

def Nat.pred(n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n+p:
      p

def Maybe.nat(m: Maybe<Nat>) -> Nat:
  match m:
    case None{}:
      0n
    case Some{x}:
      x

law some_inj_nat:
  for -a: Nat
  for -b: Nat
  for e: {Some{a} == Some{b} : Maybe<Nat>}
  {a == b : Nat}

def some_inj_nat(a, b, e):
  Equal.cong(Maybe<Nat>, Nat, Maybe.nat, Some{a}, Some{b}, e)

# Bool inversion
# --------------

law and_true:
  for a: Bool
  for -b: Bool
  for e: {Bool.and(a, b) == True{} : Bool}
  {a == True{} : Bool} & {b == True{} : Bool}

def and_true(a, b, e):
  match a:
    case False{}:
      Empty.absurd({False{} == True{} : Bool} & {b == True{} : Bool}, false_not_true(e))
    case True{}:
      ({==}, e)

law is_eq_true:
  for a: Nat
  for b: Nat
  for e: {Nat.is_eq(a, b) == True{} : Bool}
  {a == b : Nat}

def is_eq_true(a, b, e):
  match a b:
    case 0n 0n:
      {==}
    case 0n 1n+bp:
      Empty.absurd({0n == 1n+bp : Nat}, false_not_true(e))
    case 1n+ap 0n:
      Empty.absurd({1n+ap == 0n : Nat}, false_not_true(e))
    case 1n+ap 1n+bp:
      %is_eq_true(ap, bp, e) : {1n+ap == 1n+_ : Nat}
      {==}

# Nat.add algebra
# ---------------

law add_zero_r:
  for n: Nat
  {Nat.add(n, 0n) == n : Nat}

def add_zero_r(n):
  match n:
    case 0n:
      {==}
    case 1n+p:
      %add_zero_r(p) : {1n+Nat.add(p, 0n) == 1n+_ : Nat}
      {==}

law add_succ_r:
  for n: Nat
  for -m: Nat
  {Nat.add(n, 1n+m) == 1n+Nat.add(n, m) : Nat}

def add_succ_r(n, m):
  match n:
    case 0n:
      {==}
    case 1n+p:
      %add_succ_r(p, m) : {1n+Nat.add(p, 1n+m) == 1n+_ : Nat}
      {==}

law add_comm:
  for a: Nat
  for +b: Nat
  {Nat.add(a, b) == Nat.add(b, a) : Nat}

def add_comm(a, b):
  match a:
    case 0n:
      Equal.sym(Nat, Nat.add(b, 0n), b, add_zero_r(b))
    case 1n+p:
      %Equal.sym(Nat, Nat.add(b, 1n+p), 1n+Nat.add(b, p), add_succ_r(b, p)) : {1n+Nat.add(p, b) == _ : Nat}
      %add_comm(p, b) : {1n+Nat.add(p, b) == 1n+_ : Nat}
      {==}

law add_assoc:
  for a: Nat
  for -b: Nat
  for -c: Nat
  {Nat.add(Nat.add(a, b), c) == Nat.add(a, Nat.add(b, c)) : Nat}

def add_assoc(a, b, c):
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_assoc(p, b, c) : {1n+Nat.add(Nat.add(p, b), c) == 1n+_ : Nat}
      {==}

law add_cancel_l:
  for k: Nat
  for -a: Nat
  for -b: Nat
  for e: {Nat.add(k, a) == Nat.add(k, b) : Nat}
  {a == b : Nat}

def add_cancel_l(k, a, b, e):
  match k:
    case 0n:
      e
    case 1n+p:
      add_cancel_l(p, a, b, Equal.cong(Nat, Nat, Nat.pred, 1n+Nat.add(p, a), 1n+Nat.add(p, b), e))

# (p + q) + (r + s) == (p + r) + (q + s)
law interchange:
  for +p: Nat
  for +q: Nat
  for +r: Nat
  for +s: Nat
  {Nat.add(Nat.add(p, q), Nat.add(r, s)) == Nat.add(Nat.add(p, r), Nat.add(q, s)) : Nat}

def interchange(p, q, r, s):
  # (p+q)+(r+s) ~> p+(q+(r+s))
  %Equal.sym(Nat, Nat.add(Nat.add(p, q), Nat.add(r, s)), Nat.add(p, Nat.add(q, Nat.add(r, s))), add_assoc(p, q, Nat.add(r, s))) : {_ == Nat.add(Nat.add(p, r), Nat.add(q, s)) : Nat}
  # (p+r)+(q+s) ~> p+(r+(q+s))
  %Equal.sym(Nat, Nat.add(Nat.add(p, r), Nat.add(q, s)), Nat.add(p, Nat.add(r, Nat.add(q, s))), add_assoc(p, r, Nat.add(q, s))) : {Nat.add(p, Nat.add(q, Nat.add(r, s))) == _ : Nat}
  # q+(r+s) ~> (q+r)+s
  %add_assoc(q, r, s) : {Nat.add(p, _) == Nat.add(p, Nat.add(r, Nat.add(q, s))) : Nat}
  # r+(q+s) ~> (r+q)+s
  %add_assoc(r, q, s) : {Nat.add(p, Nat.add(Nat.add(q, r), s)) == Nat.add(p, _) : Nat}
  # q+r ~> r+q
  %add_comm(r, q) : {Nat.add(p, Nat.add(_, s)) == Nat.add(p, Nat.add(Nat.add(r, q), s)) : Nat}
  {==}

# Two "out + new == old + in" equations add up to one.
law add_eqs:
  for +o1: Nat
  for +y1: Nat
  for +x1: Nat
  for +i1: Nat
  for +o2: Nat
  for +y2: Nat
  for +x2: Nat
  for +i2: Nat
  for e1: {Nat.add(o1, y1) == Nat.add(x1, i1) : Nat}
  for e2: {Nat.add(o2, y2) == Nat.add(x2, i2) : Nat}
  {Nat.add(Nat.add(o1, o2), Nat.add(y1, y2)) == Nat.add(Nat.add(x1, x2), Nat.add(i1, i2)) : Nat}

def add_eqs(o1, y1, x1, i1, o2, y2, x2, i2, e1, e2):
  %interchange(o1, y1, o2, y2) : {_ == Nat.add(Nat.add(x1, x2), Nat.add(i1, i2)) : Nat}
  %interchange(x1, i1, x2, i2) : {Nat.add(Nat.add(o1, y1), Nat.add(o2, y2)) == _ : Nat}
  %Equal.sym(Nat, Nat.add(o1, y1), Nat.add(x1, i1), e1) : {Nat.add(_, Nat.add(o2, y2)) == Nat.add(Nat.add(x1, i1), Nat.add(x2, i2)) : Nat}
  %Equal.sym(Nat, Nat.add(o2, y2), Nat.add(x2, i2), e2) : {Nat.add(Nat.add(x1, i1), _) == Nat.add(Nat.add(x1, i1), Nat.add(x2, i2)) : Nat}
  {==}

def IsSucc(n: Nat) -> Type:
  match n:
    case 0n:
      Empty
    case 1n+p:
      Unit

law succ_not_zero:
  for -p: Nat
  for e: {1n+p == 0n : Nat}
  Empty

def succ_not_zero(p, e):
  %e : IsSucc(_)
  Unit{}

# If out > available, "out + new == available" is impossible.
law lt_add_absurd:
  for a: Nat
  for o: Nat
  for -y: Nat
  for lt: {Nat.is_lt(a, o) == True{} : Bool}
  for e: {Nat.add(o, y) == a : Nat}
  Empty

def lt_add_absurd(a, o, y, lt, e):
  match a o:
    case 0n 0n:
      false_not_true(lt)
    case 0n 1n+op:
      succ_not_zero(Nat.add(op, y), e)
    case 1n+ap 0n:
      false_not_true(lt)
    case 1n+ap 1n+op:
      lt_add_absurd(ap, op, y, lt, Equal.cong(Nat, Nat, Nat.pred, 1n+Nat.add(op, y), 1n+ap, e))

# One transaction: from  O + Y == X + I  (pools)  and  I + B == O + S  (balance)
# conclude  Y + B == X + S.
law conserve.go:
  for +o: Nat
  for +y: Nat
  for +x: Nat
  for +i: Nat
  for +b: Nat
  for +s: Nat
  for pools: {Nat.add(o, y) == Nat.add(x, i) : Nat}
  for bal: {Nat.add(i, b) == Nat.add(o, s) : Nat}
  {Nat.add(o, Nat.add(y, b)) == Nat.add(o, Nat.add(x, s)) : Nat}

def conserve.go(o, y, x, i, b, s, pools, bal):
  %add_assoc(o, y, b) : {_ == Nat.add(o, Nat.add(x, s)) : Nat}
  %Equal.sym(Nat, Nat.add(o, y), Nat.add(x, i), pools) : {Nat.add(_, b) == Nat.add(o, Nat.add(x, s)) : Nat}
  %Equal.sym(Nat, Nat.add(Nat.add(x, i), b), Nat.add(x, Nat.add(i, b)), add_assoc(x, i, b)) : {_ == Nat.add(o, Nat.add(x, s)) : Nat}
  %Equal.sym(Nat, Nat.add(i, b), Nat.add(o, s), bal) : {Nat.add(x, _) == Nat.add(o, Nat.add(x, s)) : Nat}
  %add_assoc(x, o, s) : {_ == Nat.add(o, Nat.add(x, s)) : Nat}
  %add_assoc(o, x, s) : {Nat.add(Nat.add(x, o), s) == _ : Nat}
  %add_comm(o, x) : {Nat.add(_, s) == Nat.add(Nat.add(o, x), s) : Nat}
  {==}

law conserve:
  for +o: Nat
  for +y: Nat
  for +x: Nat
  for +i: Nat
  for +b: Nat
  for +s: Nat
  for pools: {Nat.add(o, y) == Nat.add(x, i) : Nat}
  for bal: {Nat.add(i, b) == Nat.add(o, s) : Nat}
  {Nat.add(y, b) == Nat.add(x, s) : Nat}

def conserve(o, y, x, i, b, s, pools, bal):
  add_cancel_l(o, Nat.add(y, b), Nat.add(x, s), conserve.go(o, y, x, i, b, s, pools, bal))


# Two consecutive steps: from  Y2 + Br == Y1 + Ir  (rest of chain) and
# Y1 + Bx == X + Ix  (first tx) conclude  Y2 + (Bx + Br) == X + (Ix + Ir).
law chain_alg.go:
  for +y2: Nat
  for +br: Nat
  for +y1: Nat
  for +ir: Nat
  for +bx: Nat
  for +x: Nat
  for +ix: Nat
  for ih: {Nat.add(y2, br) == Nat.add(y1, ir) : Nat}
  for one: {Nat.add(y1, bx) == Nat.add(x, ix) : Nat}
  {Nat.add(y1, Nat.add(y2, Nat.add(bx, br))) == Nat.add(y1, Nat.add(x, Nat.add(ix, ir))) : Nat}

def chain_alg.go(y2, br, y1, ir, bx, x, ix, ih, one):
  %add_comm(br, bx) : {Nat.add(y1, Nat.add(y2, _)) == Nat.add(y1, Nat.add(x, Nat.add(ix, ir))) : Nat}
  %add_assoc(y2, br, bx) : {Nat.add(y1, _) == Nat.add(y1, Nat.add(x, Nat.add(ix, ir))) : Nat}
  %add_assoc(y1, Nat.add(y2, br), bx) : {_ == Nat.add(y1, Nat.add(x, Nat.add(ix, ir))) : Nat}
  %add_comm(Nat.add(y2, br), y1) : {Nat.add(_, bx) == Nat.add(y1, Nat.add(x, Nat.add(ix, ir))) : Nat}
  %Equal.sym(Nat, Nat.add(Nat.add(Nat.add(y2, br), y1), bx), Nat.add(Nat.add(y2, br), Nat.add(y1, bx)), add_assoc(Nat.add(y2, br), y1, bx)) : {_ == Nat.add(y1, Nat.add(x, Nat.add(ix, ir))) : Nat}
  %Equal.sym(Nat, Nat.add(y2, br), Nat.add(y1, ir), ih) : {Nat.add(_, Nat.add(y1, bx)) == Nat.add(y1, Nat.add(x, Nat.add(ix, ir))) : Nat}
  %Equal.sym(Nat, Nat.add(y1, bx), Nat.add(x, ix), one) : {Nat.add(Nat.add(y1, ir), _) == Nat.add(y1, Nat.add(x, Nat.add(ix, ir))) : Nat}
  %Equal.sym(Nat, Nat.add(Nat.add(y1, ir), Nat.add(x, ix)), Nat.add(y1, Nat.add(ir, Nat.add(x, ix))), add_assoc(y1, ir, Nat.add(x, ix))) : {_ == Nat.add(y1, Nat.add(x, Nat.add(ix, ir))) : Nat}
  %add_comm(Nat.add(x, ix), ir) : {Nat.add(y1, _) == Nat.add(y1, Nat.add(x, Nat.add(ix, ir))) : Nat}
  %Equal.sym(Nat, Nat.add(Nat.add(x, ix), ir), Nat.add(x, Nat.add(ix, ir)), add_assoc(x, ix, ir)) : {Nat.add(y1, _) == Nat.add(y1, Nat.add(x, Nat.add(ix, ir))) : Nat}
  {==}

law chain_alg:
  for +y2: Nat
  for +br: Nat
  for +y1: Nat
  for +ir: Nat
  for +bx: Nat
  for +x: Nat
  for +ix: Nat
  for ih: {Nat.add(y2, br) == Nat.add(y1, ir) : Nat}
  for one: {Nat.add(y1, bx) == Nat.add(x, ix) : Nat}
  {Nat.add(y2, Nat.add(bx, br)) == Nat.add(x, Nat.add(ix, ir)) : Nat}

def chain_alg(y2, br, y1, ir, bx, x, ix, ih, one):
  add_cancel_l(y1, Nat.add(y2, Nat.add(bx, br)), Nat.add(x, Nat.add(ix, ir)), chain_alg.go(y2, br, y1, ir, bx, x, ix, ih, one))


law and_l:
  for a: Bool
  for -b: Bool
  for e: {Bool.and(a, b) == True{} : Bool}
  {a == True{} : Bool}

def and_l(a, b, e):
  match a:
    case False{}:
      Empty.absurd({False{} == True{} : Bool}, false_not_true(e))
    case True{}:
      {==}

law and_r:
  for a: Bool
  for -b: Bool
  for e: {Bool.and(a, b) == True{} : Bool}
  {b == True{} : Bool}

def and_r(a, b, e):
  match a:
    case False{}:
      Empty.absurd({b == True{} : Bool}, false_not_true(e))
    case True{}:
      e
