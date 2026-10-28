import Base
import ../field/natlemmas.bend as N
import ../prims/natlib.bend as L
import ./term.bend as T

# Soundness of the normaliser: every rewrite rule of term.bend preserves the value in
# Z/p (p = 1 + bp, bp >= 1), for every assignment of the atoms and of the constants.

# --- every value is canonical ----------------------------------------------------------

def kv_canon(+bp: Nat, +l1: L.Le(1n, bp), +cs: +List<Nat>, +i: Nat) -> L.Le(T.kv(bp, cs, i), bp):
  match i:
    case 0n:
      l1
    case 1n+j:
      match j:
        case 0n:
          (bp, {==})
        case 1n+k:
          L.mod_le(T.nth(cs, k), bp)

law canon:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +env: +List<Nat>
  for +cs: +List<Nat>
  for +t: T.T
  L.Le(T.ev(bp, env, cs, t), bp)

def canon(bp, l1, env, cs, t):
  match t:
    case T.A{i}:
      L.mod_le(T.nth(env, i), bp)
    case T.K{i}:
      kv_canon(bp, l1, cs, i)
    case T.Ad{a, b}:
      L.mod_le(Nat.add(T.ev(bp, env, cs, a), T.ev(bp, env, cs, b)), bp)
    case T.Sb{a, b}:
      L.mod_le(Nat.add(T.ev(bp, env, cs, a), Nat.sub(1n+bp, T.ev(bp, env, cs, b))), bp)
    case T.Ml{a, b}:
      L.mod_le(Nat.mul(T.ev(bp, env, cs, a), T.ev(bp, env, cs, b)), bp)
    case T.Ng{a}:
      L.mod_le(Nat.sub(1n+bp, T.ev(bp, env, cs, a)), bp)
    case T.Iv{a}:
      L.mod_le(Nat.pow(T.ev(bp, env, cs, a), Nat.sub(bp, 1n)), bp)

# --- the field laws each rule needs, on canonical values ------------------------------

def fadd_comm(+bp: Nat, +x: Nat, +y: Nat) -> {T.fadd(bp, x, y) == T.fadd(bp, y, x) : Nat}:
  %N.add_comm(x, y) : {Nat.mod(Nat.add(x, y), 1n+bp) == Nat.mod(_, 1n+bp) : Nat}
  {==}

def fmul_comm(+bp: Nat, +x: Nat, +y: Nat) -> {T.fmul(bp, x, y) == T.fmul(bp, y, x) : Nat}:
  %L.mul_comm(x, y) : {Nat.mod(Nat.mul(x, y), 1n+bp) == Nat.mod(_, 1n+bp) : Nat}
  {==}

def fadd_zero_r(+bp: Nat, +x: Nat, +lx: L.Le(x, bp)) -> {T.fadd(bp, x, 0n) == x : Nat}:
  Equal.trans(Nat, Nat.mod(Nat.add(x, 0n), 1n+bp), Nat.mod(x, 1n+bp), x, Equal.cong(Nat, Nat, w => Nat.mod(w, 1n+bp), Nat.add(x, 0n), x, N.add_zero_r(x)), L.mod_small(x, bp, lx))

def fadd_zero_l(+bp: Nat, +x: Nat, +lx: L.Le(x, bp)) -> {T.fadd(bp, 0n, x) == x : Nat}:
  L.mod_small(x, bp, lx)

def fsub_zero(+bp: Nat, +x: Nat, +lx: L.Le(x, bp)) -> {T.fsub(bp, x, 0n) == x : Nat}:
  Equal.trans(Nat, Nat.mod(Nat.add(x, 1n+bp), 1n+bp), Nat.mod(x, 1n+bp), x, L.mod_add_self(x, bp), L.mod_small(x, bp, lx))

def fneg_zero(+bp: Nat) -> {T.fneg(bp, 0n) == 0n : Nat}:
  L.mod_add_self(0n, bp)

def fmul_one_r(+bp: Nat, +x: Nat, +lx: L.Le(x, bp)) -> {T.fmul(bp, x, 1n) == x : Nat}:
  Equal.trans(Nat, Nat.mod(Nat.mul(x, 1n), 1n+bp), Nat.mod(x, 1n+bp), x, Equal.cong(Nat, Nat, w => Nat.mod(w, 1n+bp), Nat.mul(x, 1n), x, L.mul_one_r(x)), L.mod_small(x, bp, lx))

def fmul_one_l(+bp: Nat, +x: Nat, +lx: L.Le(x, bp)) -> {T.fmul(bp, 1n, x) == x : Nat}:
  Equal.trans(Nat, Nat.mod(Nat.mul(1n, x), 1n+bp), Nat.mod(x, 1n+bp), x, Equal.cong(Nat, Nat, w => Nat.mod(w, 1n+bp), Nat.mul(1n, x), x, L.mul_one_l(x)), L.mod_small(x, bp, lx))

def fmul_zero_r(+bp: Nat, +x: Nat) -> {T.fmul(bp, x, 0n) == 0n : Nat}:
  Equal.cong(Nat, Nat, w => Nat.mod(w, 1n+bp), Nat.mul(x, 0n), 0n, L.mul_zero_r(x))

# a + (-c) == a - c
def fadd_neg(+bp: Nat, +x: Nat, +y: Nat) -> {T.fadd(bp, x, T.fneg(bp, y)) == T.fsub(bp, x, y) : Nat}:
  L.mod_add_mod_r(x, Nat.sub(1n+bp, y), bp)

# (-c) + b == b - c
def fadd_neg_l(+bp: Nat, +x: Nat, +y: Nat) -> {T.fadd(bp, T.fneg(bp, y), x) == T.fsub(bp, x, y) : Nat}:
  Equal.trans(Nat, T.fadd(bp, T.fneg(bp, y), x), T.fadd(bp, x, T.fneg(bp, y)), T.fsub(bp, x, y), fadd_comm(bp, T.fneg(bp, y), x), fadd_neg(bp, x, y))

def cong_add(+bp: Nat, +x: Nat, +x2: Nat, +y: Nat, +y2: Nat, hx: {x == x2 : Nat}, hy: {y == y2 : Nat}) -> {T.fadd(bp, x, y) == T.fadd(bp, x2, y2) : Nat}:
  %hx : {T.fadd(bp, x, y) == T.fadd(bp, _, y2) : Nat}
  %hy : {T.fadd(bp, x, y) == T.fadd(bp, x, _) : Nat}
  {==}

def cong_sub(+bp: Nat, +x: Nat, +x2: Nat, +y: Nat, +y2: Nat, hx: {x == x2 : Nat}, hy: {y == y2 : Nat}) -> {T.fsub(bp, x, y) == T.fsub(bp, x2, y2) : Nat}:
  %hx : {T.fsub(bp, x, y) == T.fsub(bp, _, y2) : Nat}
  %hy : {T.fsub(bp, x, y) == T.fsub(bp, x, _) : Nat}
  {==}

def cong_mul(+bp: Nat, +x: Nat, +x2: Nat, +y: Nat, +y2: Nat, hx: {x == x2 : Nat}, hy: {y == y2 : Nat}) -> {T.fmul(bp, x, y) == T.fmul(bp, x2, y2) : Nat}:
  %hx : {T.fmul(bp, x, y) == T.fmul(bp, _, y2) : Nat}
  %hy : {T.fmul(bp, x, y) == T.fmul(bp, x, _) : Nat}
  {==}

def cong_neg(+bp: Nat, +x: Nat, +x2: Nat, hx: {x == x2 : Nat}) -> {T.fneg(bp, x) == T.fneg(bp, x2) : Nat}:
  %hx : {T.fneg(bp, x) == T.fneg(bp, _) : Nat}
  {==}

def cong_inv(+bp: Nat, +x: Nat, +x2: Nat, hx: {x == x2 : Nat}) -> {T.finv(bp, x) == T.finv(bp, x2) : Nat}:
  %hx : {T.finv(bp, x) == T.finv(bp, _) : Nat}
  {==}

# --- each smart constructor computes its operation --------------------------------------

def ng_k_ok(+bp: Nat, +env: +List<Nat>, +cs: +List<Nat>, +i: Nat) -> {T.ev(bp, env, cs, T.ng_k(i)) == T.fneg(bp, T.kv(bp, cs, i)) : Nat}:
  match i:
    case 0n:
      {==}
    case 1n+j:
      match j:
        case 0n:
          Equal.sym(Nat, T.fneg(bp, 0n), 0n, fneg_zero(bp))
        case 1n+k:
          {==}

def mk_ng_ok(+bp: Nat, +env: +List<Nat>, +cs: +List<Nat>, +a: T.T) -> {T.ev(bp, env, cs, T.mk_ng(a)) == T.fneg(bp, T.ev(bp, env, cs, a)) : Nat}:
  match a:
    case T.A{i}:
      {==}
    case T.K{i}:
      ng_k_ok(bp, env, cs, i)
    case T.Ad{x, y}:
      {==}
    case T.Sb{x, y}:
      {==}
    case T.Ml{x, y}:
      {==}
    case T.Ng{x}:
      {==}
    case T.Iv{x}:
      {==}

def sb_k_ok(+bp: Nat, +l1: L.Le(1n, bp), +env: +List<Nat>, +cs: +List<Nat>, +a: T.T, +i: Nat) -> {T.ev(bp, env, cs, T.sb_k(a, i)) == T.fsub(bp, T.ev(bp, env, cs, a), T.kv(bp, cs, i)) : Nat}:
  match i:
    case 0n:
      {==}
    case 1n+j:
      match j:
        case 0n:
          Equal.sym(Nat, T.fsub(bp, T.ev(bp, env, cs, a), 0n), T.ev(bp, env, cs, a), fsub_zero(bp, T.ev(bp, env, cs, a), canon(bp, l1, env, cs, a)))
        case 1n+k:
          {==}

def mk_sb_ok(+bp: Nat, +l1: L.Le(1n, bp), +env: +List<Nat>, +cs: +List<Nat>, +a: T.T, +b: T.T) -> {T.ev(bp, env, cs, T.mk_sb(a, b)) == T.fsub(bp, T.ev(bp, env, cs, a), T.ev(bp, env, cs, b)) : Nat}:
  match b:
    case T.A{i}:
      {==}
    case T.K{i}:
      sb_k_ok(bp, l1, env, cs, a, i)
    case T.Ad{x, y}:
      {==}
    case T.Sb{x, y}:
      {==}
    case T.Ml{x, y}:
      {==}
    case T.Ng{x}:
      {==}
    case T.Iv{x}:
      {==}

def ord_ad_ok(+bp: Nat, +env: +List<Nat>, +cs: +List<Nat>, c: Bool, +a: T.T, +b: T.T) -> {T.ev(bp, env, cs, T.ord_ad(c, a, b)) == T.fadd(bp, T.ev(bp, env, cs, a), T.ev(bp, env, cs, b)) : Nat}:
  match c:
    case True{}:
      fadd_comm(bp, T.ev(bp, env, cs, b), T.ev(bp, env, cs, a))
    case False{}:
      {==}

def ord_ml_ok(+bp: Nat, +env: +List<Nat>, +cs: +List<Nat>, c: Bool, +a: T.T, +b: T.T) -> {T.ev(bp, env, cs, T.ord_ml(c, a, b)) == T.fmul(bp, T.ev(bp, env, cs, a), T.ev(bp, env, cs, b)) : Nat}:
  match c:
    case True{}:
      fmul_comm(bp, T.ev(bp, env, cs, b), T.ev(bp, env, cs, a))
    case False{}:
      {==}

def ad_kb_ok(+bp: Nat, +l1: L.Le(1n, bp), +env: +List<Nat>, +cs: +List<Nat>, +a: T.T, +i: Nat) -> {T.ev(bp, env, cs, T.ad_kb(a, i)) == T.fadd(bp, T.ev(bp, env, cs, a), T.kv(bp, cs, i)) : Nat}:
  match i:
    case 0n:
      ord_ad_ok(bp, env, cs, T.tlt(T.K{0n}, a), a, T.K{0n})
    case 1n+j:
      match j:
        case 0n:
          Equal.sym(Nat, T.fadd(bp, T.ev(bp, env, cs, a), 0n), T.ev(bp, env, cs, a), fadd_zero_r(bp, T.ev(bp, env, cs, a), canon(bp, l1, env, cs, a)))
        case 1n+k:
          ord_ad_ok(bp, env, cs, T.tlt(T.K{2n+k}, a), a, T.K{2n+k})

def ad_fb_ok(+bp: Nat, +l1: L.Le(1n, bp), +env: +List<Nat>, +cs: +List<Nat>, +a: T.T, +b: T.T) -> {T.ev(bp, env, cs, T.ad_fb(a, b)) == T.fadd(bp, T.ev(bp, env, cs, a), T.ev(bp, env, cs, b)) : Nat}:
  match b:
    case T.A{i}:
      ord_ad_ok(bp, env, cs, T.tlt(T.A{i}, a), a, T.A{i})
    case T.K{i}:
      ad_kb_ok(bp, l1, env, cs, a, i)
    case T.Ad{x, y}:
      ord_ad_ok(bp, env, cs, T.tlt(T.Ad{x, y}, a), a, T.Ad{x, y})
    case T.Sb{x, y}:
      ord_ad_ok(bp, env, cs, T.tlt(T.Sb{x, y}, a), a, T.Sb{x, y})
    case T.Ml{x, y}:
      ord_ad_ok(bp, env, cs, T.tlt(T.Ml{x, y}, a), a, T.Ml{x, y})
    case T.Ng{x}:
      ord_ad_ok(bp, env, cs, T.tlt(T.Ng{x}, a), a, T.Ng{x})
    case T.Iv{x}:
      ord_ad_ok(bp, env, cs, T.tlt(T.Iv{x}, a), a, T.Iv{x})

def ad_ka_ok(+bp: Nat, +l1: L.Le(1n, bp), +env: +List<Nat>, +cs: +List<Nat>, +i: Nat, +b: T.T) -> {T.ev(bp, env, cs, T.ad_ka(i, b)) == T.fadd(bp, T.kv(bp, cs, i), T.ev(bp, env, cs, b)) : Nat}:
  match i:
    case 0n:
      ad_fb_ok(bp, l1, env, cs, T.K{0n}, b)
    case 1n+j:
      match j:
        case 0n:
          Equal.sym(Nat, T.fadd(bp, 0n, T.ev(bp, env, cs, b)), T.ev(bp, env, cs, b), fadd_zero_l(bp, T.ev(bp, env, cs, b), canon(bp, l1, env, cs, b)))
        case 1n+k:
          ad_fb_ok(bp, l1, env, cs, T.K{2n+k}, b)

def ad_f_ok(+bp: Nat, +l1: L.Le(1n, bp), +env: +List<Nat>, +cs: +List<Nat>, +a: T.T, +b: T.T) -> {T.ev(bp, env, cs, T.ad_f(a, b)) == T.fadd(bp, T.ev(bp, env, cs, a), T.ev(bp, env, cs, b)) : Nat}:
  match a:
    case T.A{i}:
      ad_fb_ok(bp, l1, env, cs, T.A{i}, b)
    case T.K{i}:
      ad_ka_ok(bp, l1, env, cs, i, b)
    case T.Ad{x, y}:
      ad_fb_ok(bp, l1, env, cs, T.Ad{x, y}, b)
    case T.Sb{x, y}:
      ad_fb_ok(bp, l1, env, cs, T.Sb{x, y}, b)
    case T.Ml{x, y}:
      ad_fb_ok(bp, l1, env, cs, T.Ml{x, y}, b)
    case T.Ng{x}:
      ad_fb_ok(bp, l1, env, cs, T.Ng{x}, b)
    case T.Iv{x}:
      ad_fb_ok(bp, l1, env, cs, T.Iv{x}, b)

def ad_a_ok(+bp: Nat, +l1: L.Le(1n, bp), +env: +List<Nat>, +cs: +List<Nat>, +a: T.T, +b: T.T) -> {T.ev(bp, env, cs, T.ad_a(a, b)) == T.fadd(bp, T.ev(bp, env, cs, a), T.ev(bp, env, cs, b)) : Nat}:
  match a:
    case T.A{i}:
      ad_f_ok(bp, l1, env, cs, T.A{i}, b)
    case T.K{i}:
      ad_f_ok(bp, l1, env, cs, T.K{i}, b)
    case T.Ad{x, y}:
      ad_f_ok(bp, l1, env, cs, T.Ad{x, y}, b)
    case T.Sb{x, y}:
      ad_f_ok(bp, l1, env, cs, T.Sb{x, y}, b)
    case T.Ml{x, y}:
      ad_f_ok(bp, l1, env, cs, T.Ml{x, y}, b)
    case T.Ng{c}:
      +eb = T.ev(bp, env, cs, b)
      +ec = T.ev(bp, env, cs, c)
      Equal.trans(Nat, T.ev(bp, env, cs, T.mk_sb(b, c)), T.fsub(bp, eb, ec), T.fadd(bp, T.fneg(bp, ec), eb), mk_sb_ok(bp, l1, env, cs, b, c), Equal.sym(Nat, T.fadd(bp, T.fneg(bp, ec), eb), T.fsub(bp, eb, ec), fadd_neg_l(bp, eb, ec)))
    case T.Iv{x}:
      ad_f_ok(bp, l1, env, cs, T.Iv{x}, b)

def mk_ad_ok(+bp: Nat, +l1: L.Le(1n, bp), +env: +List<Nat>, +cs: +List<Nat>, +a: T.T, +b: T.T) -> {T.ev(bp, env, cs, T.mk_ad(a, b)) == T.fadd(bp, T.ev(bp, env, cs, a), T.ev(bp, env, cs, b)) : Nat}:
  match b:
    case T.A{i}:
      ad_a_ok(bp, l1, env, cs, a, T.A{i})
    case T.K{i}:
      ad_a_ok(bp, l1, env, cs, a, T.K{i})
    case T.Ad{x, y}:
      ad_a_ok(bp, l1, env, cs, a, T.Ad{x, y})
    case T.Sb{x, y}:
      ad_a_ok(bp, l1, env, cs, a, T.Sb{x, y})
    case T.Ml{x, y}:
      ad_a_ok(bp, l1, env, cs, a, T.Ml{x, y})
    case T.Ng{c}:
      +ea = T.ev(bp, env, cs, a)
      +ec = T.ev(bp, env, cs, c)
      Equal.trans(Nat, T.ev(bp, env, cs, T.mk_sb(a, c)), T.fsub(bp, ea, ec), T.fadd(bp, ea, T.fneg(bp, ec)), mk_sb_ok(bp, l1, env, cs, a, c), Equal.sym(Nat, T.fadd(bp, ea, T.fneg(bp, ec)), T.fsub(bp, ea, ec), fadd_neg(bp, ea, ec)))
    case T.Iv{x}:
      ad_a_ok(bp, l1, env, cs, a, T.Iv{x})

def ml_kb_ok(+bp: Nat, +l1: L.Le(1n, bp), +env: +List<Nat>, +cs: +List<Nat>, +a: T.T, +i: Nat) -> {T.ev(bp, env, cs, T.ml_kb(a, i)) == T.fmul(bp, T.ev(bp, env, cs, a), T.kv(bp, cs, i)) : Nat}:
  match i:
    case 0n:
      Equal.sym(Nat, T.fmul(bp, T.ev(bp, env, cs, a), 1n), T.ev(bp, env, cs, a), fmul_one_r(bp, T.ev(bp, env, cs, a), canon(bp, l1, env, cs, a)))
    case 1n+j:
      match j:
        case 0n:
          Equal.sym(Nat, T.fmul(bp, T.ev(bp, env, cs, a), 0n), 0n, fmul_zero_r(bp, T.ev(bp, env, cs, a)))
        case 1n+k:
          ord_ml_ok(bp, env, cs, T.tlt(T.K{2n+k}, a), a, T.K{2n+k})

def ml_b_ok(+bp: Nat, +l1: L.Le(1n, bp), +env: +List<Nat>, +cs: +List<Nat>, +a: T.T, +b: T.T) -> {T.ev(bp, env, cs, T.ml_b(a, b)) == T.fmul(bp, T.ev(bp, env, cs, a), T.ev(bp, env, cs, b)) : Nat}:
  match b:
    case T.A{i}:
      ord_ml_ok(bp, env, cs, T.tlt(T.A{i}, a), a, T.A{i})
    case T.K{i}:
      ml_kb_ok(bp, l1, env, cs, a, i)
    case T.Ad{x, y}:
      ord_ml_ok(bp, env, cs, T.tlt(T.Ad{x, y}, a), a, T.Ad{x, y})
    case T.Sb{x, y}:
      ord_ml_ok(bp, env, cs, T.tlt(T.Sb{x, y}, a), a, T.Sb{x, y})
    case T.Ml{x, y}:
      ord_ml_ok(bp, env, cs, T.tlt(T.Ml{x, y}, a), a, T.Ml{x, y})
    case T.Ng{x}:
      ord_ml_ok(bp, env, cs, T.tlt(T.Ng{x}, a), a, T.Ng{x})
    case T.Iv{x}:
      ord_ml_ok(bp, env, cs, T.tlt(T.Iv{x}, a), a, T.Iv{x})

def ml_ka_ok(+bp: Nat, +l1: L.Le(1n, bp), +env: +List<Nat>, +cs: +List<Nat>, +i: Nat, +b: T.T) -> {T.ev(bp, env, cs, T.ml_ka(i, b)) == T.fmul(bp, T.kv(bp, cs, i), T.ev(bp, env, cs, b)) : Nat}:
  match i:
    case 0n:
      Equal.sym(Nat, T.fmul(bp, 1n, T.ev(bp, env, cs, b)), T.ev(bp, env, cs, b), fmul_one_l(bp, T.ev(bp, env, cs, b), canon(bp, l1, env, cs, b)))
    case 1n+j:
      match j:
        case 0n:
          {==}
        case 1n+k:
          ml_b_ok(bp, l1, env, cs, T.K{2n+k}, b)

def mk_ml_ok(+bp: Nat, +l1: L.Le(1n, bp), +env: +List<Nat>, +cs: +List<Nat>, +a: T.T, +b: T.T) -> {T.ev(bp, env, cs, T.mk_ml(a, b)) == T.fmul(bp, T.ev(bp, env, cs, a), T.ev(bp, env, cs, b)) : Nat}:
  match a:
    case T.A{i}:
      ml_b_ok(bp, l1, env, cs, T.A{i}, b)
    case T.K{i}:
      ml_ka_ok(bp, l1, env, cs, i, b)
    case T.Ad{x, y}:
      ml_b_ok(bp, l1, env, cs, T.Ad{x, y}, b)
    case T.Sb{x, y}:
      ml_b_ok(bp, l1, env, cs, T.Sb{x, y}, b)
    case T.Ml{x, y}:
      ml_b_ok(bp, l1, env, cs, T.Ml{x, y}, b)
    case T.Ng{x}:
      ml_b_ok(bp, l1, env, cs, T.Ng{x}, b)
    case T.Iv{x}:
      ml_b_ok(bp, l1, env, cs, T.Iv{x}, b)

# --- the normaliser preserves the value of every term ----------------------------------

law nf_sound:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +env: +List<Nat>
  for +cs: +List<Nat>
  for +t: T.T
  {T.ev(bp, env, cs, T.nf(t)) == T.ev(bp, env, cs, t) : Nat}

def nf_sound(bp, l1, env, cs, t):
  match t:
    case T.A{i}:
      {==}
    case T.K{i}:
      {==}
    case T.Ad{a, b}:
      Equal.trans(Nat, T.ev(bp, env, cs, T.mk_ad(T.nf(a), T.nf(b))), T.fadd(bp, T.ev(bp, env, cs, T.nf(a)), T.ev(bp, env, cs, T.nf(b))), T.fadd(bp, T.ev(bp, env, cs, a), T.ev(bp, env, cs, b)), mk_ad_ok(bp, l1, env, cs, T.nf(a), T.nf(b)), cong_add(bp, T.ev(bp, env, cs, T.nf(a)), T.ev(bp, env, cs, a), T.ev(bp, env, cs, T.nf(b)), T.ev(bp, env, cs, b), nf_sound(bp, l1, env, cs, a), nf_sound(bp, l1, env, cs, b)))
    case T.Sb{a, b}:
      Equal.trans(Nat, T.ev(bp, env, cs, T.mk_sb(T.nf(a), T.nf(b))), T.fsub(bp, T.ev(bp, env, cs, T.nf(a)), T.ev(bp, env, cs, T.nf(b))), T.fsub(bp, T.ev(bp, env, cs, a), T.ev(bp, env, cs, b)), mk_sb_ok(bp, l1, env, cs, T.nf(a), T.nf(b)), cong_sub(bp, T.ev(bp, env, cs, T.nf(a)), T.ev(bp, env, cs, a), T.ev(bp, env, cs, T.nf(b)), T.ev(bp, env, cs, b), nf_sound(bp, l1, env, cs, a), nf_sound(bp, l1, env, cs, b)))
    case T.Ml{a, b}:
      Equal.trans(Nat, T.ev(bp, env, cs, T.mk_ml(T.nf(a), T.nf(b))), T.fmul(bp, T.ev(bp, env, cs, T.nf(a)), T.ev(bp, env, cs, T.nf(b))), T.fmul(bp, T.ev(bp, env, cs, a), T.ev(bp, env, cs, b)), mk_ml_ok(bp, l1, env, cs, T.nf(a), T.nf(b)), cong_mul(bp, T.ev(bp, env, cs, T.nf(a)), T.ev(bp, env, cs, a), T.ev(bp, env, cs, T.nf(b)), T.ev(bp, env, cs, b), nf_sound(bp, l1, env, cs, a), nf_sound(bp, l1, env, cs, b)))
    case T.Ng{a}:
      Equal.trans(Nat, T.ev(bp, env, cs, T.mk_ng(T.nf(a))), T.fneg(bp, T.ev(bp, env, cs, T.nf(a))), T.fneg(bp, T.ev(bp, env, cs, a)), mk_ng_ok(bp, env, cs, T.nf(a)), cong_neg(bp, T.ev(bp, env, cs, T.nf(a)), T.ev(bp, env, cs, a), nf_sound(bp, l1, env, cs, a)))
    case T.Iv{a}:
      cong_inv(bp, T.ev(bp, env, cs, T.nf(a)), T.ev(bp, env, cs, a), nf_sound(bp, l1, env, cs, a))

law evs_nf:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +env: +List<Nat>
  for +cs: +List<Nat>
  for +ts: +List<T.T>
  {T.evs(bp, env, cs, T.nfs(ts)) == T.evs(bp, env, cs, ts) : +List<Nat>}

def evs_nf(bp, l1, env, cs, ts):
  match ts:
    case Nil{}:
      {==}
    case Con{t, rest}:
      %nf_sound(bp, l1, env, cs, t) : {T.ev(bp, env, cs, T.nf(t)) <> T.evs(bp, env, cs, T.nfs(rest)) == _ <> T.evs(bp, env, cs, rest) : +List<Nat>}
      %evs_nf(bp, l1, env, cs, rest) : {T.ev(bp, env, cs, T.nf(t)) <> T.evs(bp, env, cs, T.nfs(rest)) == T.ev(bp, env, cs, T.nf(t)) <> _ : +List<Nat>}
      {==}

# Translation validation: two lists of terms with the same normal forms have the same
# values, pointwise, for every p >= 2 and every values of the atoms and constants.
law equiv:
  for +bp: Nat
  for +l1: L.Le(1n, bp)
  for +env: +List<Nat>
  for +cs: +List<Nat>
  for +xs: +List<T.T>
  for +ys: +List<T.T>
  for h: {T.nfs(xs) == T.nfs(ys) : +List<T.T>}
  {T.evs(bp, env, cs, xs) == T.evs(bp, env, cs, ys) : +List<Nat>}

def equiv(bp, l1, env, cs, xs, ys, h):
  %evs_nf(bp, l1, env, cs, xs) : {_ == T.evs(bp, env, cs, ys) : +List<Nat>}
  %evs_nf(bp, l1, env, cs, ys) : {T.evs(bp, env, cs, T.nfs(xs)) == _ : +List<Nat>}
  %h : {T.evs(bp, env, cs, T.nfs(xs)) == T.evs(bp, env, cs, _) : +List<Nat>}
  {==}
