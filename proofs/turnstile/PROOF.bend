import Base
import ./pools.bend as P
import ./lemmas.bend as L
import ./LAWS.bend as Laws

# Inverting the model
# -------------------

law le_add_sub:
  for b: Nat
  for a: Nat
  for h: {Nat.is_le(b, a) == True{} : Bool}
  {Nat.add(b, Nat.sub(a, b)) == a : Nat}

def le_add_sub(b, a, h):
  match b a:
    case 0n 0n:
      {==}
    case 0n 1n+ap:
      {==}
    case 1n+bp 0n:
      Empty.absurd({1n+Nat.add(bp, 0n) == 0n : Nat}, L.false_not_true(h))
    case 1n+bp 1n+ap:
      %le_add_sub(bp, ap, h) : {1n+Nat.add(bp, Nat.sub(ap, bp)) == 1n+_ : Nat}
      {==}

law csub_go_ok:
  for ok: Bool
  for +a: Nat
  for +b: Nat
  for -r: Nat
  for le: {Nat.is_le(b, a) == ok : Bool}
  for e: {P.csub.go(ok, a, b) == Some{r} : Maybe<Nat>}
  {Nat.add(b, r) == a : Nat}

def csub_go_ok(ok, a, b, r, le, e):
  match ok:
    case False{}:
      Empty.absurd({Nat.add(b, r) == a : Nat}, L.none_not_some(Nat, r, e))
    case True{}:
      %L.some_inj_nat(Nat.sub(a, b), r, e) : {Nat.add(b, _) == a : Nat}
      le_add_sub(b, a, le)

law csub_ok:
  for +a: Nat
  for +b: Nat
  for -r: Nat
  for e: {P.csub(a, b) == Some{r} : Maybe<Nat>}
  {Nat.add(b, r) == a : Nat}

def csub_ok(a, b, r, e):
  csub_go_ok(Nat.is_le(b, a), a, b, r, {==}, e)

law pool_step_ok:
  for +bal: Nat
  for f: P.Flow
  for -r: Nat
  for e: {P.pool_step(bal, f) == Some{r} : Maybe<Nat>}
  {Nat.add(P.Flow.out(f), r) == Nat.add(bal, P.Flow.inp(f)) : Nat}

def pool_step_ok(bal, f, r, e):
  match f:
    case P.Flow{i, o}:
      csub_ok(Nat.add(bal, i), o, r, e)

def Mp.t(m: Maybe<P.Pools>) -> Nat:
  match m:
    case None{}:
      0n
    case Some{p}:
      P.Pools.t(p)

def Mp.sp(m: Maybe<P.Pools>) -> Nat:
  match m:
    case None{}:
      0n
    case Some{p}:
      P.Pools.sp(p)

def Mp.sa(m: Maybe<P.Pools>) -> Nat:
  match m:
    case None{}:
      0n
    case Some{p}:
      P.Pools.sa(p)

def Mp.orc(m: Maybe<P.Pools>) -> Nat:
  match m:
    case None{}:
      0n
    case Some{p}:
      P.Pools.orc(p)

def Mp.iw(m: Maybe<P.Pools>) -> Nat:
  match m:
    case None{}:
      0n
    case Some{p}:
      P.Pools.iw(p)

def some_nat(n: Nat) -> Maybe<Nat>:
  Some{n}

def Step5Eqs(-a: Maybe<Nat>, -b: Maybe<Nat>, -c: Maybe<Nat>, -d: Maybe<Nat>, -e: Maybe<Nat>, -s2: P.Pools) -> Type:
  {a == Some{P.Pools.t(s2)} : Maybe<Nat>} &
  {b == Some{P.Pools.sp(s2)} : Maybe<Nat>} &
  {c == Some{P.Pools.sa(s2)} : Maybe<Nat>} &
  {d == Some{P.Pools.orc(s2)} : Maybe<Nat>} &
  {e == Some{P.Pools.iw(s2)} : Maybe<Nat>}

law step5_inv:
  for a: Maybe<Nat>
  for b: Maybe<Nat>
  for c: Maybe<Nat>
  for d: Maybe<Nat>
  for e: Maybe<Nat>
  for -s2: P.Pools
  for +h: {P.step5(a, b, c, d, e) == Some{s2} : Maybe<P.Pools>}
  Step5Eqs(a, b, c, d, e, s2)

def step5_inv(a, b, c, d, e, s2, h):
  match a:
    case None{}:
      Empty.absurd(Step5Eqs(None{}, b, c, d, e, s2), L.none_not_some(P.Pools, s2, h))
    case Some{x1}:
      match b:
        case None{}:
          Empty.absurd(Step5Eqs(Some{x1}, None{}, c, d, e, s2), L.none_not_some(P.Pools, s2, h))
        case Some{x2}:
          match c:
            case None{}:
              Empty.absurd(Step5Eqs(Some{x1}, Some{x2}, None{}, d, e, s2), L.none_not_some(P.Pools, s2, h))
            case Some{x3}:
              match d:
                case None{}:
                  Empty.absurd(Step5Eqs(Some{x1}, Some{x2}, Some{x3}, None{}, e, s2), L.none_not_some(P.Pools, s2, h))
                case Some{x4}:
                  match e:
                    case None{}:
                      Empty.absurd(Step5Eqs(Some{x1}, Some{x2}, Some{x3}, Some{x4}, None{}, s2), L.none_not_some(P.Pools, s2, h))
                    case Some{x5}:
                      (Equal.cong(Nat, Maybe<Nat>, some_nat, x1, P.Pools.t(s2), Equal.cong(Maybe<P.Pools>, Nat, Mp.t, Some{P.Pools{x1, x2, x3, x4, x5}}, Some{s2}, h)),
                       (Equal.cong(Nat, Maybe<Nat>, some_nat, x2, P.Pools.sp(s2), Equal.cong(Maybe<P.Pools>, Nat, Mp.sp, Some{P.Pools{x1, x2, x3, x4, x5}}, Some{s2}, h)),
                        (Equal.cong(Nat, Maybe<Nat>, some_nat, x3, P.Pools.sa(s2), Equal.cong(Maybe<P.Pools>, Nat, Mp.sa, Some{P.Pools{x1, x2, x3, x4, x5}}, Some{s2}, h)),
                         (Equal.cong(Nat, Maybe<Nat>, some_nat, x4, P.Pools.orc(s2), Equal.cong(Maybe<P.Pools>, Nat, Mp.orc, Some{P.Pools{x1, x2, x3, x4, x5}}, Some{s2}, h)),
                          Equal.cong(Nat, Maybe<Nat>, some_nat, x5, P.Pools.iw(s2), Equal.cong(Maybe<P.Pools>, Nat, Mp.iw, Some{P.Pools{x1, x2, x3, x4, x5}}, Some{s2}, h))))))

law go_ok:
  for ok: Bool
  for -s: P.Pools
  for -x: P.Tx
  for -s2: P.Pools
  for h: {P.apply.go(ok, s, x) == Some{s2} : Maybe<P.Pools>}
  {ok == True{} : Bool}

def go_ok(ok, s, x, s2, h):
  match ok:
    case False{}:
      Empty.absurd({False{} == True{} : Bool}, L.none_not_some(P.Pools, s2, h))
    case True{}:
      {==}

law go_step:
  for ok: Bool
  for -s: P.Pools
  for -x: P.Tx
  for -s2: P.Pools
  for h: {P.apply.go(ok, s, x) == Some{s2} : Maybe<P.Pools>}
  {P.step(s, x) == Some{s2} : Maybe<P.Pools>}

def go_step(ok, s, x, s2, h):
  match ok:
    case False{}:
      Empty.absurd({P.step(s, x) == Some{s2} : Maybe<P.Pools>}, L.none_not_some(P.Pools, s2, h))
    case True{}:
      h

# An accepted transaction obeyed its era's rules ...
law rules_ok:
  for +e: P.Era
  for -s: P.Pools
  for +x: P.Tx
  for -s2: P.Pools
  for h: {P.apply(e, s, x) == Some{s2} : Maybe<P.Pools>}
  {P.Era.rules(e, x) == True{} : Bool}

def rules_ok(e, s, x, s2, h):
  L.and_l(P.Era.rules(e, x), P.balanced(x), go_ok(Bool.and(P.Era.rules(e, x), P.balanced(x)), s, x, s2, h))

# ... and balanced.
law balanced_ok:
  for +e: P.Era
  for -s: P.Pools
  for +x: P.Tx
  for -s2: P.Pools
  for h: {P.apply(e, s, x) == Some{s2} : Maybe<P.Pools>}
  {Nat.add(P.Tx.ins(x), P.Tx.burn(x)) == Nat.add(P.Tx.outs(x), P.Tx.issue(x)) : Nat}

def balanced_ok(e, s, x, s2, h):
  L.is_eq_true(Nat.add(P.Tx.ins(x), P.Tx.burn(x)), Nat.add(P.Tx.outs(x), P.Tx.issue(x)), L.and_r(P.Era.rules(e, x), P.balanced(x), go_ok(Bool.and(P.Era.rules(e, x), P.balanced(x)), s, x, s2, h)))

def acc5(
  +t: Nat, +sp: Nat, +sa: Nat, +orc: Nat, +iw: Nat,
  +ft: P.Flow, +fsp: P.Flow, +fsa: P.Flow, +forc: P.Flow, +fiw: P.Flow,
  -issue: Nat, -burn: Nat, -s2: P.Pools,
  eqs: Step5Eqs(P.pool_step(t, ft), P.pool_step(sp, fsp), P.pool_step(sa, fsa), P.pool_step(orc, forc), P.pool_step(iw, fiw), s2)
) -> Laws.Accounted(P.Pools{t, sp, sa, orc, iw}, P.Tx{ft, fsp, fsa, forc, fiw, issue, burn}, s2):
  (e1, r1) = eqs
  (e2, r2) = r1
  (e3, r3) = r2
  (e4, e5) = r3
  (pool_step_ok(t, ft, P.Pools.t(s2), e1),
   (pool_step_ok(sp, fsp, P.Pools.sp(s2), e2),
    (pool_step_ok(sa, fsa, P.Pools.sa(s2), e3),
     (pool_step_ok(orc, forc, P.Pools.orc(s2), e4),
      pool_step_ok(iw, fiw, P.Pools.iw(s2), e5)))))

# (a) Turnstile.
def Laws.turnstile(e, s, x, s2, h):
  match s x:
    case P.Pools{t, sp, sa, orc, iw} P.Tx{ft, fsp, fsa, forc, fiw, issue, burn}:
      +ok = Bool.and(P.Era.rules(e, P.Tx{ft, fsp, fsa, forc, fiw, issue, burn}), P.balanced(P.Tx{ft, fsp, fsa, forc, fiw, issue, burn}))
      hs = go_step(ok, P.Pools{t, sp, sa, orc, iw}, P.Tx{ft, fsp, fsa, forc, fiw, issue, burn}, s2, h)
      acc5(t, sp, sa, orc, iw, ft, fsp, fsa, forc, fiw, issue, burn, s2,
        step5_inv(P.pool_step(t, ft), P.pool_step(sp, fsp), P.pool_step(sa, fsa), P.pool_step(orc, forc), P.pool_step(iw, fiw), s2, hs))

# Taking Accounted apart
# ----------------------

def Acc.t(-s: P.Pools, -x: P.Tx, -s2: P.Pools, a: Laws.Accounted(s, x, s2)) -> {Nat.add(P.Flow.out(P.Tx.t(x)), P.Pools.t(s2)) == Nat.add(P.Pools.t(s), P.Flow.inp(P.Tx.t(x))) : Nat}:
  (e1, r) = a
  e1

def Acc.sp(-s: P.Pools, -x: P.Tx, -s2: P.Pools, a: Laws.Accounted(s, x, s2)) -> {Nat.add(P.Flow.out(P.Tx.sp(x)), P.Pools.sp(s2)) == Nat.add(P.Pools.sp(s), P.Flow.inp(P.Tx.sp(x))) : Nat}:
  (e1, r1) = a
  (e2, r2) = r1
  e2

def Acc.orc(-s: P.Pools, -x: P.Tx, -s2: P.Pools, a: Laws.Accounted(s, x, s2)) -> {Nat.add(P.Flow.out(P.Tx.orc(x)), P.Pools.orc(s2)) == Nat.add(P.Pools.orc(s), P.Flow.inp(P.Tx.orc(x))) : Nat}:
  (e1, r1) = a
  (e2, r2) = r1
  (e3, r3) = r2
  (e4, e5) = r3
  e4

def Acc.iw(-s: P.Pools, -x: P.Tx, -s2: P.Pools, a: Laws.Accounted(s, x, s2)) -> {Nat.add(P.Flow.out(P.Tx.iw(x)), P.Pools.iw(s2)) == Nat.add(P.Pools.iw(s), P.Flow.inp(P.Tx.iw(x))) : Nat}:
  (e1, r1) = a
  (e2, r2) = r1
  (e3, r3) = r2
  (e4, e5) = r3
  e5

# The five pool equations add up to one for the totals.
def sum5(
  +t: Nat, +sp: Nat, +sa: Nat, +orc: Nat, +iw: Nat,
  +ft: P.Flow, +fsp: P.Flow, +fsa: P.Flow, +forc: P.Flow, +fiw: P.Flow,
  -issue: Nat, -burn: Nat, +s2: P.Pools,
  acc: Laws.Accounted(P.Pools{t, sp, sa, orc, iw}, P.Tx{ft, fsp, fsa, forc, fiw, issue, burn}, s2)
) -> {Nat.add(P.Tx.outs(P.Tx{ft, fsp, fsa, forc, fiw, issue, burn}), Nat.add(P.Pools.t(s2), Nat.add(P.Pools.sp(s2), Nat.add(P.Pools.sa(s2), Nat.add(P.Pools.orc(s2), P.Pools.iw(s2)))))) == Nat.add(P.Pools.total(P.Pools{t, sp, sa, orc, iw}), P.Tx.ins(P.Tx{ft, fsp, fsa, forc, fiw, issue, burn})) : Nat}:
  (e1, r1) = acc
  (e2, r2) = r1
  (e3, r3) = r2
  (e4, e5) = r3
  L.add_eqs(P.Flow.out(ft), P.Pools.t(s2), t, P.Flow.inp(ft),
    Nat.add(P.Flow.out(fsp), Nat.add(P.Flow.out(fsa), Nat.add(P.Flow.out(forc), P.Flow.out(fiw)))),
    Nat.add(P.Pools.sp(s2), Nat.add(P.Pools.sa(s2), Nat.add(P.Pools.orc(s2), P.Pools.iw(s2)))),
    Nat.add(sp, Nat.add(sa, Nat.add(orc, iw))),
    Nat.add(P.Flow.inp(fsp), Nat.add(P.Flow.inp(fsa), Nat.add(P.Flow.inp(forc), P.Flow.inp(fiw)))),
    e1,
    L.add_eqs(P.Flow.out(fsp), P.Pools.sp(s2), sp, P.Flow.inp(fsp),
      Nat.add(P.Flow.out(fsa), Nat.add(P.Flow.out(forc), P.Flow.out(fiw))),
      Nat.add(P.Pools.sa(s2), Nat.add(P.Pools.orc(s2), P.Pools.iw(s2))),
      Nat.add(sa, Nat.add(orc, iw)),
      Nat.add(P.Flow.inp(fsa), Nat.add(P.Flow.inp(forc), P.Flow.inp(fiw))),
      e2,
      L.add_eqs(P.Flow.out(fsa), P.Pools.sa(s2), sa, P.Flow.inp(fsa),
        Nat.add(P.Flow.out(forc), P.Flow.out(fiw)),
        Nat.add(P.Pools.orc(s2), P.Pools.iw(s2)),
        Nat.add(orc, iw),
        Nat.add(P.Flow.inp(forc), P.Flow.inp(fiw)),
        e3,
        L.add_eqs(P.Flow.out(forc), P.Pools.orc(s2), orc, P.Flow.inp(forc),
          P.Flow.out(fiw), P.Pools.iw(s2), iw, P.Flow.inp(fiw), e4, e5))))

law total_eta:
  for p: P.Pools
  {Nat.add(P.Pools.t(p), Nat.add(P.Pools.sp(p), Nat.add(P.Pools.sa(p), Nat.add(P.Pools.orc(p), P.Pools.iw(p))))) == P.Pools.total(p) : Nat}

def total_eta(p):
  match p:
    case P.Pools{t, sp, sa, orc, iw}:
      {==}

# (b) Conservation.
def Laws.conservation(e, s, x, s2, h):
  match s x:
    case P.Pools{t, sp, sa, orc, iw} P.Tx{ft, fsp, fsa, forc, fiw, issue, burn}:
      %total_eta(s2) : {Nat.add(_, burn) == Nat.add(P.Pools.total(P.Pools{t, sp, sa, orc, iw}), issue) : Nat}
      L.conserve(P.Tx.outs(P.Tx{ft, fsp, fsa, forc, fiw, issue, burn}), Nat.add(P.Pools.t(s2), Nat.add(P.Pools.sp(s2), Nat.add(P.Pools.sa(s2), Nat.add(P.Pools.orc(s2), P.Pools.iw(s2))))), P.Pools.total(P.Pools{t, sp, sa, orc, iw}), P.Tx.ins(P.Tx{ft, fsp, fsa, forc, fiw, issue, burn}), burn, issue,
        sum5(t, sp, sa, orc, iw, ft, fsp, fsa, forc, fiw, issue, burn, s2, Laws.turnstile(e, P.Pools{t, sp, sa, orc, iw}, P.Tx{ft, fsp, fsa, forc, fiw, issue, burn}, s2, h)),
        balanced_ok(e, P.Pools{t, sp, sa, orc, iw}, P.Tx{ft, fsp, fsa, forc, fiw, issue, burn}, s2, h))

# Era rules, unpacked (&& is left-associative)
# -------------------------------------------

law zero_l:
  for n: Nat
  for -b: Bool
  for e: {Bool.and(P.is_zero(n), b) == True{} : Bool}
  {n == 0n : Nat}

def zero_l(n, b, e):
  match n:
    case 0n:
      {==}
    case 1n+p:
      Empty.absurd({1n+p == 0n : Nat}, L.false_not_true(e))

law zero_r:
  for a: Bool
  for n: Nat
  for e: {Bool.and(a, P.is_zero(n)) == True{} : Bool}
  {n == 0n : Nat}

def zero_r(a, n, e):
  match a:
    case False{}:
      Empty.absurd({n == 0n : Nat}, L.false_not_true(e))
    case True{}:
      match n:
        case 0n:
          {==}
        case 1n+p:
          Empty.absurd({1n+p == 0n : Nat}, L.false_not_true(e))

# out + new == old + 0  gives  out + new == old
def drop_zero_in(+o: Nat, +y: Nat, +x: Nat, i: Nat, z: {i == 0n : Nat}, eq: {Nat.add(o, y) == Nat.add(x, i) : Nat}) -> {Nat.add(o, y) == x : Nat}:
  %L.add_zero_r(x) : {Nat.add(o, y) == _ : Nat}
  %z : {Nat.add(o, y) == Nat.add(x, _) : Nat}
  eq

# (c) NU6.3: Orchard is withdraw-only.
def Laws.orchard_withdraw_only(e, s, x, s2, post, h):
  match e:
    case P.PreNU63{}:
      Empty.absurd({Nat.add(P.Flow.out(P.Tx.orc(x)), P.Pools.orc(s2)) == P.Pools.orc(s) : Nat}, L.false_not_true(post))
    case P.NU63{}:
      drop_zero_in(P.Flow.out(P.Tx.orc(x)), P.Pools.orc(s2), P.Pools.orc(s), P.Flow.inp(P.Tx.orc(x)),
        zero_r(P.is_zero(P.Flow.inp(P.Tx.sp(x))), P.Flow.inp(P.Tx.orc(x)), L.and_l(Bool.and(P.is_zero(P.Flow.inp(P.Tx.sp(x))), P.is_zero(P.Flow.inp(P.Tx.orc(x)))), P.is_zero(P.Tx.burn(x)), rules_ok(P.NU63{}, s, x, s2, h))),
        Acc.orc(s, x, s2, Laws.turnstile(P.NU63{}, s, x, s2, h)))
    case P.NU7{}:
      drop_zero_in(P.Flow.out(P.Tx.orc(x)), P.Pools.orc(s2), P.Pools.orc(s), P.Flow.inp(P.Tx.orc(x)),
        zero_r(Bool.and(P.is_zero(P.Flow.inp(P.Tx.sp(x))), P.is_zero(P.Flow.out(P.Tx.sp(x)))), P.Flow.inp(P.Tx.orc(x)), rules_ok(P.NU7{}, s, x, s2, h)),
        Acc.orc(s, x, s2, Laws.turnstile(P.NU7{}, s, x, s2, h)))

# (d) NU7: Sprout is frozen.
def Laws.sprout_frozen(s, x, s2, h):
  %zero_r(P.is_zero(P.Flow.inp(P.Tx.sp(x))), P.Flow.out(P.Tx.sp(x)), L.and_l(Bool.and(P.is_zero(P.Flow.inp(P.Tx.sp(x))), P.is_zero(P.Flow.out(P.Tx.sp(x)))), P.is_zero(P.Flow.inp(P.Tx.orc(x))), rules_ok(P.NU7{}, s, x, s2, h))) : {Nat.add(_, P.Pools.sp(s2)) == P.Pools.sp(s) : Nat}
  drop_zero_in(P.Flow.out(P.Tx.sp(x)), P.Pools.sp(s2), P.Pools.sp(s), P.Flow.inp(P.Tx.sp(x)),
    zero_l(P.Flow.inp(P.Tx.sp(x)), P.is_zero(P.Flow.out(P.Tx.sp(x))), L.and_l(Bool.and(P.is_zero(P.Flow.inp(P.Tx.sp(x))), P.is_zero(P.Flow.out(P.Tx.sp(x)))), P.is_zero(P.Flow.inp(P.Tx.orc(x))), rules_ok(P.NU7{}, s, x, s2, h))),
    Acc.sp(s, x, s2, Laws.turnstile(P.NU7{}, s, x, s2, h)))

# (d') ZIP 211: Sprout never grows, in every era.
def Laws.sprout_never_grows(e, s, x, s2, h):
  match e:
    case P.PreNU63{}:
      drop_zero_in(P.Flow.out(P.Tx.sp(x)), P.Pools.sp(s2), P.Pools.sp(s), P.Flow.inp(P.Tx.sp(x)),
        zero_l(P.Flow.inp(P.Tx.sp(x)), P.is_zero(P.Flow.inp(P.Tx.iw(x))), L.and_l(Bool.and(P.is_zero(P.Flow.inp(P.Tx.sp(x))), P.is_zero(P.Flow.inp(P.Tx.iw(x)))), P.is_zero(P.Flow.out(P.Tx.iw(x))), L.and_l(Bool.and(Bool.and(P.is_zero(P.Flow.inp(P.Tx.sp(x))), P.is_zero(P.Flow.inp(P.Tx.iw(x)))), P.is_zero(P.Flow.out(P.Tx.iw(x)))), P.is_zero(P.Tx.burn(x)), rules_ok(P.PreNU63{}, s, x, s2, h)))),
        Acc.sp(s, x, s2, Laws.turnstile(P.PreNU63{}, s, x, s2, h)))
    case P.NU63{}:
      drop_zero_in(P.Flow.out(P.Tx.sp(x)), P.Pools.sp(s2), P.Pools.sp(s), P.Flow.inp(P.Tx.sp(x)),
        zero_l(P.Flow.inp(P.Tx.sp(x)), P.is_zero(P.Flow.inp(P.Tx.orc(x))), L.and_l(Bool.and(P.is_zero(P.Flow.inp(P.Tx.sp(x))), P.is_zero(P.Flow.inp(P.Tx.orc(x)))), P.is_zero(P.Tx.burn(x)), rules_ok(P.NU63{}, s, x, s2, h))),
        Acc.sp(s, x, s2, Laws.turnstile(P.NU63{}, s, x, s2, h)))
    case P.NU7{}:
      drop_zero_in(P.Flow.out(P.Tx.sp(x)), P.Pools.sp(s2), P.Pools.sp(s), P.Flow.inp(P.Tx.sp(x)),
        zero_l(P.Flow.inp(P.Tx.sp(x)), P.is_zero(P.Flow.out(P.Tx.sp(x))), L.and_l(Bool.and(P.is_zero(P.Flow.inp(P.Tx.sp(x))), P.is_zero(P.Flow.out(P.Tx.sp(x)))), P.is_zero(P.Flow.inp(P.Tx.orc(x))), rules_ok(P.NU7{}, s, x, s2, h))),
        Acc.sp(s, x, s2, Laws.turnstile(P.NU7{}, s, x, s2, h)))

# (d'') Before NU6.3, Ironwood does not move.
def Laws.ironwood_dormant_before_nu63(s, x, s2, h):
  %zero_r(Bool.and(P.is_zero(P.Flow.inp(P.Tx.sp(x))), P.is_zero(P.Flow.inp(P.Tx.iw(x)))), P.Flow.out(P.Tx.iw(x)), L.and_l(Bool.and(Bool.and(P.is_zero(P.Flow.inp(P.Tx.sp(x))), P.is_zero(P.Flow.inp(P.Tx.iw(x)))), P.is_zero(P.Flow.out(P.Tx.iw(x)))), P.is_zero(P.Tx.burn(x)), rules_ok(P.PreNU63{}, s, x, s2, h))) : {Nat.add(_, P.Pools.iw(s2)) == P.Pools.iw(s) : Nat}
  drop_zero_in(P.Flow.out(P.Tx.iw(x)), P.Pools.iw(s2), P.Pools.iw(s), P.Flow.inp(P.Tx.iw(x)),
    zero_r(P.is_zero(P.Flow.inp(P.Tx.sp(x))), P.Flow.inp(P.Tx.iw(x)), L.and_l(Bool.and(P.is_zero(P.Flow.inp(P.Tx.sp(x))), P.is_zero(P.Flow.inp(P.Tx.iw(x)))), P.is_zero(P.Flow.out(P.Tx.iw(x))), L.and_l(Bool.and(Bool.and(P.is_zero(P.Flow.inp(P.Tx.sp(x))), P.is_zero(P.Flow.inp(P.Tx.iw(x)))), P.is_zero(P.Flow.out(P.Tx.iw(x)))), P.is_zero(P.Tx.burn(x)), rules_ok(P.PreNU63{}, s, x, s2, h)))),
    Acc.iw(s, x, s2, Laws.turnstile(P.PreNU63{}, s, x, s2, h)))

# (a') No counterfeit exit.
def nce_go(
  m: Maybe<P.Pools>, +e: P.Era, +s: P.Pools, +x: P.Tx,
  eq: {P.apply(e, s, x) == m : Maybe<P.Pools>},
  lt: {Nat.is_lt(Nat.add(P.Pools.iw(s), P.Flow.inp(P.Tx.iw(x))), P.Flow.out(P.Tx.iw(x))) == True{} : Bool}
) -> {m == None{} : Maybe<P.Pools>}:
  match m:
    case None{}:
      {==}
    case Some{s2}:
      Empty.absurd({Some{s2} == None{} : Maybe<P.Pools>},
        L.lt_add_absurd(Nat.add(P.Pools.iw(s), P.Flow.inp(P.Tx.iw(x))), P.Flow.out(P.Tx.iw(x)), P.Pools.iw(s2), lt,
          Acc.iw(s, x, s2, Laws.turnstile(e, s, x, s2, eq))))

def Laws.no_counterfeit_exit(e, s, x, h):
  nce_go(P.apply(e, s, x), e, s, x, {==}, h)

# Whole histories
# ---------------

def Mp.get(m: Maybe<P.Pools>) -> P.Pools:
  match m:
    case None{}:
      P.Pools{0n, 0n, 0n, 0n, 0n}
    case Some{p}:
      p

law some_inj_pools:
  for -a: P.Pools
  for -b: P.Pools
  for e: {Some{a} == Some{b} : Maybe<P.Pools>}
  {a == b : P.Pools}

def some_inj_pools(a, b, e):
  Equal.cong(Maybe<P.Pools>, P.Pools, Mp.get, Some{a}, Some{b}, e)

def ChainInv(m: Maybe<P.Pools>, xs: +List<P.Tx>, +s2: P.Pools) -> Type:
  match m:
    case None{}:
      Empty
    case Some{+s}:
      {Nat.add(P.Pools.total(s2), Laws.Sum.burn(xs)) == Nat.add(P.Pools.total(s), Laws.Sum.issue(xs)) : Nat}

def chain_nil(m: Maybe<P.Pools>, +s2: P.Pools, h: {m == Some{s2} : Maybe<P.Pools>}) -> ChainInv(m, Nil{}, s2):
  match m:
    case None{}:
      L.none_not_some(P.Pools, s2, h)
    case Some{+s}:
      %some_inj_pools(s, s2, h) : {Nat.add(P.Pools.total(_), 0n) == Nat.add(P.Pools.total(s), 0n) : Nat}
      {==}

def chain_step(
  m2: Maybe<P.Pools>, +e: P.Era, +s: P.Pools, +x: P.Tx, +rest: +List<P.Tx>, +s2: P.Pools,
  eq: {P.apply(e, s, x) == m2 : Maybe<P.Pools>},
  ih: ChainInv(m2, rest, s2)
) -> ChainInv(Some{s}, Con{x, rest}, s2):
  match m2:
    case None{}:
      Empty.absurd(ChainInv(Some{s}, Con{x, rest}, s2), ih)
    case Some{+s1}:
      L.chain_alg(P.Pools.total(s2), Laws.Sum.burn(rest), P.Pools.total(s1), Laws.Sum.issue(rest),
        P.Tx.burn(x), P.Pools.total(s), P.Tx.issue(x), ih, Laws.conservation(e, s, x, s1, eq))

# A failed history stays failed.
law all_none:
  for +e: P.Era
  for xs: +List<P.Tx>
  for -s2: P.Pools
  for h: {P.apply_all(e, xs, None{}) == Some{s2} : Maybe<P.Pools>}
  Empty

def all_none(e, xs, s2, h):
  match xs:
    case Nil{}:
      L.none_not_some(P.Pools, s2, h)
    case Con{x, rest}:
      all_none(e, rest, s2, h)

law chain:
  for +e: P.Era
  for xs: +List<P.Tx>
  for m: Maybe<P.Pools>
  for +s2: P.Pools
  for h: {P.apply_all(e, xs, m) == Some{s2} : Maybe<P.Pools>}
  ChainInv(m, xs, s2)

def chain(e, xs, m, s2, h):
  match xs:
    case Nil{}:
      chain_nil(m, s2, h)
    case Con{+x, +rest}:
      match m:
        case None{}:
          Empty.absurd(ChainInv(None{}, Con{x, rest}, s2), all_none(e, rest, s2, h))
        case Some{+s}:
          chain_step(P.apply(e, s, x), e, s, x, rest, s2, {==}, chain(e, rest, P.apply(e, s, x), s2, h))

# (e) Conservation over any accepted history.
def Laws.chain_conservation(e, xs, s, s2, h):
  chain(e, xs, Some{s}, s2, h)

# (e') After NU6.3, Orchard only ever shrinks over a history.
def ChainOrc(m: Maybe<P.Pools>, +s2: P.Pools) -> Type:
  match m:
    case None{}:
      Empty
    case Some{+s}:
      &k: Nat -> {Nat.add(k, P.Pools.orc(s2)) == P.Pools.orc(s) : Nat}

def orc_nil(m: Maybe<P.Pools>, +s2: P.Pools, h: {m == Some{s2} : Maybe<P.Pools>}) -> ChainOrc(m, s2):
  match m:
    case None{}:
      L.none_not_some(P.Pools, s2, h)
    case Some{+s}:
      (0n, Equal.cong(P.Pools, Nat, P.Pools.orc, s2, s, Equal.sym(P.Pools, s, s2, some_inj_pools(s, s2, h))))

def orc_join.eq(+o: Nat, +k: Nat, +y: Nat, +y1: Nat, +x0: Nat, one: {Nat.add(o, y1) == x0 : Nat}, pk: {Nat.add(k, y) == y1 : Nat}) -> {Nat.add(Nat.add(o, k), y) == x0 : Nat}:
  %Equal.sym(Nat, Nat.add(Nat.add(o, k), y), Nat.add(o, Nat.add(k, y)), L.add_assoc(o, k, y)) : {_ == x0 : Nat}
  %Equal.sym(Nat, Nat.add(k, y), y1, pk) : {Nat.add(o, _) == x0 : Nat}
  one

def orc_join(+o: Nat, +y: Nat, +y1: Nat, +x0: Nat, one: {Nat.add(o, y1) == x0 : Nat}, ih: &k: Nat -> {Nat.add(k, y) == y1 : Nat}) -> &k: Nat -> {Nat.add(k, y) == x0 : Nat}:
  (+k, pk) = ih
  (Nat.add(o, k), orc_join.eq(o, k, y, y1, x0, one, pk))

def orc_step(
  m2: Maybe<P.Pools>, +e: P.Era, +s: P.Pools, +x: P.Tx, +s2: P.Pools,
  +post: {Laws.PostNU63(e) == True{} : Bool},
  +eq: {P.apply(e, s, x) == m2 : Maybe<P.Pools>},
  ih: ChainOrc(m2, s2)
) -> ChainOrc(Some{s}, s2):
  match m2:
    case None{}:
      Empty.absurd(ChainOrc(Some{s}, s2), ih)
    case Some{+s1}:
      orc_join(P.Flow.out(P.Tx.orc(x)), P.Pools.orc(s2), P.Pools.orc(s1), P.Pools.orc(s),
        Laws.orchard_withdraw_only(e, s, x, s1, post, eq), ih)

law chain_orc:
  for +e: P.Era
  for xs: +List<P.Tx>
  for m: Maybe<P.Pools>
  for +s2: P.Pools
  for +post: {Laws.PostNU63(e) == True{} : Bool}
  for h: {P.apply_all(e, xs, m) == Some{s2} : Maybe<P.Pools>}
  ChainOrc(m, s2)

def chain_orc(e, xs, m, s2, post, h):
  match xs:
    case Nil{}:
      orc_nil(m, s2, h)
    case Con{+x, rest}:
      match m:
        case None{}:
          Empty.absurd(ChainOrc(None{}, s2), all_none(e, rest, s2, h))
        case Some{+s}:
          orc_step(P.apply(e, s, x), e, s, x, s2, post, {==}, chain_orc(e, rest, P.apply(e, s, x), s2, post, h))

def Laws.chain_orchard_shrinks(e, xs, s, s2, post, h):
  chain_orc(e, xs, Some{s}, s2, post, h)
