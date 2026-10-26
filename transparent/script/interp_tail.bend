
# ------------------------------------------------------------------ evaluation state

# code: the bytes not yet executed; vex: the IF/ELSE branch flags (top first); nf: how many of
# them are false (0 = executing); ops: operation count (max 201); bad: the script failed.
type St is Data:
  St{+code: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32, +bad: Bool}

def badst() -> St:
  St{Nil{}, Nil{}, Nil{}, Nil{}, 0, 0, True{}}

def lim_ok(ok: Bool, +code: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32) -> St:
  match ok:
    case True{}:
      St{code, stk, alt, vex, nf, ops, False{}}
    case False{}:
      badst()

# MAX_STACK_DEPTH: stack + altstack <= 1000 after every opcode.
def limit(+code: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32) -> St:
  lim_ok(Nat.is_le((C.slen(stk) + C.slen(alt) : Nat), 1000n), code, stk, alt, vex, nf, ops)

# ------------------------------------------------------------------ pushes

def small_ok(+x: U32) -> Bool:
  U32.is_ne(x, 129) && (U32.is_lt(x, 1) || U32.is_gt(x, 16))

# PushValue::is_minimal_push for opcode b (0..78) carrying d.
def is_min_push(+b: U32, +d: +List<U32>) -> Bool:
  +len = U.len(d)
  Bool.pick(Bool, U32.is_le(b, 75), U32.is_ne(len, 1) || small_ok(U.head0(d)),
    Bool.pick(Bool, U32.is_eq(b, 76), U32.is_ge(len, 76), Bool.pick(Bool, U32.is_eq(b, 77), U32.is_ge(len, 256), U32.is_ge(len, 65536))))

def push_mn(ok: Bool, +d: +List<U32>, +rest: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32) -> St:
  match ok:
    case True{}:
      limit(rest, d <> stk, alt, vex, nf, ops)
    case False{}:
      badst()

def push_ex(exec: Bool, +b: U32, +d: +List<U32>, +rest: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32, +flags: U32) -> St:
  match exec:
    case True{}:
      push_mn(Bool.not(C.has(flags, C.f_minimaldata())) || is_min_push(b, d), d, rest, stk, alt, vex, nf, ops)
    case False{}:
      St{rest, stk, alt, vex, nf, ops, False{}}

def push_ok(ok: Bool, +b: U32, +sz: U32, +r2: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32, +flags: U32) -> St:
  match ok:
    case True{}:
      +n = U32.to_nat(sz)
      push_ex(U32.is_zero(nf), b, U.take(r2, n), U.drop(r2, n), stk, alt, vex, nf, ops, flags)
    case False{}:
      badst()

def size_bytes(+b: U32) -> Nat:
  Bool.pick(Nat, U32.is_le(b, 75), 0n, Bool.pick(Nat, U32.is_eq(b, 76), 1n, Bool.pick(Nat, U32.is_eq(b, 77), 2n, 4n)))

# Opcodes 0..78: OP_0, direct pushes of 1..75 bytes, OP_PUSHDATA1/2/4. A push that runs past
# the end of the script, or of more than 520 bytes, fails even on a non-executed branch.
def op_push(+b: U32, +rest: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32, +flags: U32) -> St:
  +k = size_bytes(b)
  +sz = Bool.pick(U32, U32.is_le(b, 75), b, U.le32(U.take(rest, k)))
  +r2 = U.drop(rest, k)
  push_ok(C.has_n(rest, k) && U32.is_le(sz, 520) && C.has_n(r2, U32.to_nat(sz)), b, sz, r2, stk, alt, vex, nf, ops, flags)

def small_exec(exec: Bool, +d: +List<U32>, +rest: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32) -> St:
  match exec:
    case True{}:
      limit(rest, d <> stk, alt, vex, nf, ops)
    case False{}:
      St{rest, stk, alt, vex, nf, ops, False{}}

def reserved(exec: Bool, +rest: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32) -> St:
  match exec:
    case True{}:
      badst()
    case False{}:
      St{rest, stk, alt, vex, nf, ops, False{}}

# 79..96: OP_1NEGATE, OP_RESERVED (fails when executed, not counted), OP_1..OP_16.
def op_small_r(res: Bool, +b: U32, +rest: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32) -> St:
  match res:
    case True{}:
      reserved(U32.is_zero(nf), rest, stk, alt, vex, nf, ops)
    case False{}:
      small_exec(U32.is_zero(nf), Bool.pick(U32, U32.is_eq(b, 79), 129, (b - 80 : U32)) <> Nil{}, rest, stk, alt, vex, nf, ops)

def op_small(+b: U32, +rest: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32) -> St:
  op_small_r(U32.is_eq(b, 80), b, rest, stk, alt, vex, nf, ops)

# ------------------------------------------------------------------ control

def if_exec(stk: List<&2, +List<U32>>, +notif: Bool, +rest: +List<U32>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32) -> St:
  match stk:
    case Con{a, t}:
      +v = Bool.xor(C.ctb(a), notif)
      limit(rest, t, alt, v <> vex, Bool.pick(U32, v, nf, (nf + 1 : U32)), ops)
    case Nil{}:
      badst()

def ctl_if(exec: Bool, +notif: Bool, +rest: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32) -> St:
  match exec:
    case True{}:
      if_exec(stk, notif, rest, alt, vex, nf, ops)
    case False{}:
      limit(rest, stk, alt, False{} <> vex, (nf + 1 : U32), ops)

def ctl_else(vex: +List<Bool>, +rest: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +nf: U32, +ops: U32) -> St:
  match vex:
    case Con{+v, t}:
      limit(rest, stk, alt, Bool.not(v) <> t, Bool.pick(U32, v, (nf + 1 : U32), (nf - 1 : U32)), ops)
    case Nil{}:
      badst()

def ctl_endif(vex: +List<Bool>, +rest: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +nf: U32, +ops: U32) -> St:
  match vex:
    case Con{+v, t}:
      limit(rest, stk, alt, t, Bool.pick(U32, v, nf, (nf - 1 : U32)), ops)
    case Nil{}:
      badst()

def ctl_ee(is_else: Bool, +rest: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32) -> St:
  match is_else:
    case True{}:
      ctl_else(vex, rest, stk, alt, nf, ops)
    case False{}:
      ctl_endif(vex, rest, stk, alt, nf, ops)

# OP_IF 0x63, OP_NOTIF 0x64, OP_ELSE 0x67, OP_ENDIF 0x68 (evaluated on every branch).
def op_ctl(is_if: Bool, +b: U32, +rest: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32) -> St:
  match is_if:
    case True{}:
      ctl_if(U32.is_zero(nf), U32.is_eq(b, 100), rest, stk, alt, vex, nf, ops)
    case False{}:
      ctl_ee(U32.is_eq(b, 103), rest, stk, alt, vex, nf, ops)

# ------------------------------------------------------------------ dispatch

def is_disabled(+b: U32) -> Bool:
  (U32.is_ge(b, 126) && U32.is_le(b, 129)) || (U32.is_ge(b, 131) && U32.is_le(b, 134)) || U32.is_eq(b, 141) || U32.is_eq(b, 142)
    || (U32.is_ge(b, 149) && U32.is_le(b, 153)) || U32.is_eq(b, 171)

def is_ctl(+b: U32) -> Bool:
  U32.is_eq(b, 99) || U32.is_eq(b, 100) || U32.is_eq(b, 103) || U32.is_eq(b, 104)

# OP_VER, OP_VERIF, OP_VERNOTIF, OP_RESERVED1/2 and the unassigned 0xba..0xff.
def is_badop(+b: U32) -> Bool:
  U32.is_eq(b, 98) || U32.is_eq(b, 101) || U32.is_eq(b, 102) || U32.is_eq(b, 137) || U32.is_eq(b, 138) || U32.is_ge(b, 186)

def r3_ok(ok: Bool, +rest: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32) -> St:
  match ok:
    case True{}:
      limit(rest, stk, alt, vex, nf, ops)
    case False{}:
      badst()

def r3_st(r: C.R3, +rest: +List<U32>, +vex: +List<Bool>, +nf: U32) -> St:
  C.R3{+ok, +stk, +alt, +ops} = r
  r3_ok(ok, rest, stk, alt, vex, nf, ops)

def op_exec(exec: Bool, +b: U32, +rest: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32, +env: C.Env) -> St:
  match exec:
    case True{}:
      r3_st(exec_op(b, C.has(C.env_flags(env), C.f_minimaldata()), stk, alt, ops, env), rest, vex, nf)
    case False{}:
      St{rest, stk, alt, vex, nf, ops, False{}}

def op_bad(bad: Bool, +b: U32, +rest: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32, +env: C.Env) -> St:
  match bad:
    case True{}:
      Bool.pick(St, U32.is_zero(nf) || U32.is_eq(b, 101) || U32.is_eq(b, 102), badst(), St{rest, stk, alt, vex, nf, ops, False{}})
    case False{}:
      op_exec(U32.is_zero(nf), b, rest, stk, alt, vex, nf, ops, env)

def op_kind(ctl: Bool, +b: U32, +rest: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32, +env: C.Env) -> St:
  match ctl:
    case True{}:
      op_ctl(U32.is_eq(b, 99) || U32.is_eq(b, 100), b, rest, stk, alt, vex, nf, ops)
    case False{}:
      op_bad(is_badop(b), b, rest, stk, alt, vex, nf, ops, env)

# Every opcode above OP_16 counts towards the 201-operation limit, executed or not.
def op_cnt(ok: Bool, +b: U32, +rest: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32, +env: C.Env) -> St:
  match ok:
    case True{}:
      op_kind(is_ctl(b), b, rest, stk, alt, vex, nf, ops, env)
    case False{}:
      badst()

def op_d(dis: Bool, +b: U32, +rest: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32, +env: C.Env) -> St:
  match dis:
    case True{}:
      badst()
    case False{}:
      op_cnt(U32.is_le((ops + 1 : U32), 201), b, rest, stk, alt, vex, nf, (ops + 1 : U32), env)

def op_s(small: Bool, +b: U32, +rest: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32, +env: C.Env) -> St:
  match small:
    case True{}:
      op_small(b, rest, stk, alt, vex, nf, ops)
    case False{}:
      op_d(is_disabled(b), b, rest, stk, alt, vex, nf, ops, env)

def op(push: Bool, +b: U32, +rest: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32, +env: C.Env) -> St:
  match push:
    case True{}:
      op_push(b, rest, stk, alt, vex, nf, ops, C.env_flags(env))
    case False{}:
      op_s(U32.is_le(b, 96), b, rest, stk, alt, vex, nf, ops, env)

def step_c(code: +List<U32>, +stk: List<&2, +List<U32>>, +alt: List<&2, +List<U32>>, +vex: +List<Bool>, +nf: U32, +ops: U32, +env: C.Env) -> St:
  match code:
    case Nil{}:
      St{Nil{}, stk, alt, vex, nf, ops, False{}}
    case Con{+b, rest}:
      op(U32.is_le(b, 78), b, rest, stk, alt, vex, nf, ops, env)

def step(st: St, +env: C.Env) -> St:
  St{+code, +stk, +alt, +vex, +nf, +ops, +bad} = st
  match bad:
    case True{}:
      badst()
    case False{}:
      step_c(code, stk, alt, vex, nf, ops, env)

def run(fuel: Nat, +st: St, +env: C.Env) -> St:
  match fuel:
    case 0n:
      st
    case 1n+p:
      run(p, step(st, env), env)

# ------------------------------------------------------------------ whole scripts

def bempty(xs: +List<Bool>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{_, _}:
      False{}

def fin_ok(ok: Bool, +stk: List<&2, +List<U32>>) -> Maybe<&2, List<&2, +List<U32>>>:
  match ok:
    case True{}:
      Some{stk}
    case False{}:
      None{}

def fin(st: St) -> Maybe<&2, List<&2, +List<U32>>>:
  St{+code, +stk, _, +vex, _, _, +bad} = st
  fin_ok(Bool.not(bad) && U.is_empty(code) && bempty(vex), stk)

def ev_sz(ok: Bool, +script: +List<U32>, +stack: List<&2, +List<U32>>, +flags: U32, +ctx: C.Ctx) -> Maybe<&2, List<&2, +List<U32>>>:
  match ok:
    case True{}:
      fin(run(1n+U.nlen(script), St{script, stack, Nil{}, Nil{}, 0, 0, False{}}, C.Env{flags, script, ctx}))
    case False{}:
      None{}

# Evaluate one script (at most 10,000 bytes) on a stack; None if it fails or leaves an
# IF unclosed.
def eval_script(+script: +List<U32>, +stack: List<&2, +List<U32>>, +flags: U32, +ctx: C.Ctx) -> Maybe<&2, List<&2, +List<U32>>>:
  ev_sz(U32.is_le(U.len(script), 10000), script, stack, flags, ctx)

# ---- push-only scripts (OP_RESERVED and over-long pushes count as pushes, truncated ones don't)

type PO is Data:
  Go{c: +List<U32>}
  Ok{}
  No{}

def po_go(ok: Bool, +r: +List<U32>) -> PO:
  match ok:
    case True{}:
      Go{r}
    case False{}:
      No{}

def po_b(push: Bool, +b: U32, +rest: +List<U32>) -> PO:
  match push:
    case True{}:
      +k = Bool.pick(Nat, U32.is_ge(b, 79), 0n, size_bytes(b))
      +sz = Bool.pick(U32, U32.is_le(b, 75), b, Bool.pick(U32, U32.is_ge(b, 79), 0, U.le32(U.take(rest, k))))
      +r2 = U.drop(rest, k)
      po_go(C.has_n(rest, k) && C.has_n(r2, U32.to_nat(sz)), U.drop(r2, U32.to_nat(sz)))
    case False{}:
      No{}

def po_step(code: +List<U32>) -> PO:
  match code:
    case Nil{}:
      Ok{}
    case Con{+b, rest}:
      po_b(U32.is_le(b, 96), b, rest)

def po(fuel: Nat, x: PO) -> Bool:
  match fuel x:
    case 1n+p Go{c}:
      po(p, po_step(c))
    case _ Ok{}:
      True{}
    case _ _:
      False{}

def push_only(+code: +List<U32>) -> Bool:
  po(2n+U.nlen(code), Go{code})

def is_p2sh(+spk: +List<U32>) -> Bool:
  U32.is_eq(U.len(spk), 23) && U32.is_eq(U.byte_at(spk, 0n), 169) && U32.is_eq(U.byte_at(spk, 1n), 20) && U32.is_eq(U.byte_at(spk, 22n), 135)

# ---- the verdict (script/iter.rs eval_script)

def top_true(s: List<&2, +List<U32>>) -> Bool:
  match s:
    case Con{a, _}:
      C.ctb(a)
    case Nil{}:
      False{}

def clean_ok(+flags: U32, +s: List<&2, +List<U32>>) -> Bool:
  Bool.not(C.has(flags, C.f_cleanstack())) || Nat.is_eq(C.slen(s), 1n)

def final_ok(m: Maybe<&2, List<&2, +List<U32>>>, +flags: U32) -> Bool:
  match m:
    case Some{+s}:
      top_true(s) && clean_ok(flags, s)
    case None{}:
      False{}

def redeem_ok(st1: List<&2, +List<U32>>, +flags: U32, +ctx: C.Ctx) -> Bool:
  match st1:
    case Con{red, rest}:
      final_ok(eval_script(red, rest, flags, ctx), flags)
    case Nil{}:
      False{}

def vi_p2(p2sh: Bool, +sig_po: Bool, +s1: List<&2, +List<U32>>, +s2: List<&2, +List<U32>>, +flags: U32, +ctx: C.Ctx) -> Bool:
  match p2sh:
    case True{}:
      match sig_po:
        case True{}:
          redeem_ok(s1, flags, ctx)
        case False{}:
          False{}
    case False{}:
      clean_ok(flags, s2)

def vi_true(t: Bool, +p2sh: Bool, +sig_po: Bool, +s1: List<&2, +List<U32>>, +s2: List<&2, +List<U32>>, +flags: U32, +ctx: C.Ctx) -> Bool:
  match t:
    case True{}:
      vi_p2(p2sh, sig_po, s1, s2, flags, ctx)
    case False{}:
      False{}

def vi_after(m2: Maybe<&2, List<&2, +List<U32>>>, +p2sh: Bool, +sig: +List<U32>, +s1: List<&2, +List<U32>>, +flags: U32, +ctx: C.Ctx) -> Bool:
  match m2:
    case Some{+s2}:
      vi_true(top_true(s2), p2sh, push_only(sig), s1, s2, flags, ctx)
    case None{}:
      False{}

def vi_sig(m1: Maybe<&2, List<&2, +List<U32>>>, +sig: +List<U32>, +spk: +List<U32>, +flags: U32, +ctx: C.Ctx) -> Bool:
  match m1:
    case Some{+s1}:
      vi_after(eval_script(spk, s1, flags, ctx), C.has(flags, C.f_p2sh()) && is_p2sh(spk), sig, s1, flags, ctx)
    case None{}:
      False{}

def vi_start(ok: Bool, +sig: +List<U32>, +spk: +List<U32>, +flags: U32, +ctx: C.Ctx) -> Bool:
  match ok:
    case True{}:
      vi_sig(eval_script(sig, Nil{}, flags, ctx), sig, spk, flags, ctx)
    case False{}:
      False{}

# Does scriptSig `sig` satisfy scriptPubKey `spk` under `flags`, for the input in ctx?
def verify_input(+flags: U32, +sig: +List<U32>, +spk: +List<U32>, +ctx: C.Ctx) -> Bool:
  vi_start(Bool.not(C.has(flags, C.f_sigpushonly())) || push_only(sig), sig, spk, flags, ctx)
