# fullnode: a structured parser for Zcash mainnet transactions of every version
# (v1/v2 Sprout incl. PHGR JoinSplits, v3 Overwinter, v4 Sapling incl. Groth16 JoinSplits,
# v5 NU5, v6 NU6.3 with Ironwood), for state updates and the consensus rules engine.
#
# It reads only input that node/wire's hardened validator (txv.bend / blk.bend) accepted,
# so it does no bounds checks of its own: callers must gate on the validator first
# (see delta.bend). The layouts mirror txv.bend, which is fuzzed against zcash_primitives.
#
# A cursor C{xs, pos} holds the remaining bytes and how many bytes were consumed, so a
# transaction's size is the difference of two positions and its raw bytes are a prefix of
# the cursor it started at (no indexing from the start of the block: linear in block size).
import Base
import ../../node/wire/hb.bend as H

type C is Data:
  C{xs: +List<U32>, pos: U32}

# CompactSize value and its encoded size (already validated canonical and capped).
type CS is Data:
  CS{v: U32, c: C}

# A CompactSize-prefixed byte string.
type BV is Data:
  BV{bs: +List<U32>, c: C}

# prev: the outpoint's txid (internal byte order), idx its output index.
type TIn is Data:
  TIn{prev: +List<U32>, idx: U32, script: +List<U32>, seq: U32}

type TOut is Data:
  TOut{value: H.U64, script: +List<U32>}

type LIn is Data:
  LIn{xs: +List<TIn>, c: C}

type LOut is Data:
  LOut{xs: +List<TOut>, c: C}

# vpub_old, vpub_new, anchor (rt), nullifiers, commitments; fields in wire byte order.
type Js is Data:
  Js{old: H.U64, new: H.U64, anchor: +List<U32>, nf1: +List<U32>, nf2: +List<U32>, cm1: +List<U32>, cm2: +List<U32>}

type LJs is Data:
  LJs{xs: +List<Js>, c: C}

type SSp is Data:
  SSp{anchor: +List<U32>, nf: +List<U32>}

# vb: valueBalance (two's complement u64); spends; output note commitments (cmu).
type Sap is Data:
  Sap{vb: H.U64, spends: +List<SSp>, outs: +List<+List<U32>>, c: C}

type Act is Data:
  Act{nf: +List<U32>, cmx: +List<U32>}

# present: any actions; vb: valueBalance; flags byte; anchor.
type Bun is Data:
  Bun{present: Bool, vb: H.U64, anchor: +List<U32>, flags: U32, acts: +List<Act>, c: C}

# ver: version (low 31 bits); ow: fOverwintered; grp: nVersionGroupId (0 if none);
# br: consensus branch id (v5/v6 only, else 0); size: bytes.
type Tx is Data:
  Tx{ver: U32, ow: Bool, grp: U32, br: U32, ins: +List<TIn>, outs: +List<TOut>, lock: U32, exp: U32,
     js: +List<Js>, sap: Sap, orch: Bun, iron: Bun, size: U32}

# Transparent part: vin then vout. Returns both lists and the cursor after them.
type TP is Data:
  TP{ins: +List<TIn>, outs: +List<TOut>, c: C}

def c_xs(c: C) -> +List<U32>:
  C{+xs, _} = c
  xs

def c_pos(c: C) -> U32:
  C{_, +p} = c
  p

def start(+xs: +List<U32>) -> C:
  C{xs, 0}

def skip(c: C, +k: U32) -> C:
  C{+xs, +p} = c
  C{H.drop(xs, k), (p + k : U32)}

def take(+c: C, +k: U32) -> +List<U32>:
  H.take(c_xs(c), k)

def u8(+c: C) -> U32:
  H.at(c_xs(c), 0)

def u32(+c: C) -> U32:
  H.le32(c_xs(c))

# Two 32-bit halves of a little-endian u64.
def u64(+c: C) -> H.U64:
  +xs = c_xs(c)
  H.U64{H.le32(xs), H.le32(H.drop(xs, 4))}

def cs_v(r: CS) -> U32:
  CS{+v, _} = r
  v

def cs_c(r: CS) -> C:
  CS{_, +c} = r
  c

def cs_wide(is253: Bool, +c: C) -> CS:
  match is253:
    case True{}:
      CS{H.le16(c_xs(skip(c, 1))), skip(c, 3)}
    case False{}:
      CS{H.le32(c_xs(skip(c, 1))), skip(c, 5)}

def cs_sel(small: Bool, +f: U32, +c: C) -> CS:
  match small:
    case True{}:
      CS{f, skip(c, 1)}
    case False{}:
      cs_wide(U32.is_eq(f, 253), c)

def cs(+c: C) -> CS:
  +f = u8(c)
  cs_sel(U32.is_lt(f, 253), f, c)

def bv_bs(r: BV) -> +List<U32>:
  BV{+b, _} = r
  b

def bv_c(r: BV) -> C:
  BV{_, +c} = r
  c

def bytes_after(r: CS) -> BV:
  CS{+n, +c} = r
  BV{take(c, n), skip(c, n)}

def bytes(+c: C) -> BV:
  bytes_after(cs(c))

# ---------------------------------------------------------------- transparent

def tin_mk(+prev: +List<U32>, +idx: U32, r: BV) -> LIn:
  BV{+s, +c} = r
  LIn{TIn{prev, idx, s, u32(c)} <> Nil{}, skip(c, 4)}

def tin(+c: C) -> LIn:
  tin_mk(take(c, 32), u32(skip(c, 32)), bytes(skip(c, 36)))

def lin_xs(r: LIn) -> +List<TIn>:
  LIn{+x, _} = r
  x

def lin_cons(+a: LIn, r: LIn) -> LIn:
  LIn{+t, +c} = r
  LIn{List.append(&2, TIn, lin_xs(a), t), c}

def lin_c(r: LIn) -> C:
  LIn{_, +c} = r
  c

def tins(n: Nat, +c: C) -> LIn:
  match n:
    case 0n:
      LIn{Nil{}, c}
    case 1n+m:
      +a = tin(c)
      lin_cons(a, tins(m, lin_c(a)))

def tout_mk(+v: H.U64, r: BV) -> LOut:
  BV{+s, +c} = r
  LOut{TOut{v, s} <> Nil{}, c}

def tout(+c: C) -> LOut:
  tout_mk(u64(c), bytes(skip(c, 8)))

def lout_xs(r: LOut) -> +List<TOut>:
  LOut{+x, _} = r
  x

def lout_c(r: LOut) -> C:
  LOut{_, +c} = r
  c

def lout_cons(+a: LOut, r: LOut) -> LOut:
  LOut{+t, +c} = r
  LOut{List.append(&2, TOut, lout_xs(a), t), c}

def touts(n: Nat, +c: C) -> LOut:
  match n:
    case 0n:
      LOut{Nil{}, c}
    case 1n+m:
      +a = tout(c)
      lout_cons(a, touts(m, lout_c(a)))

# ---------------------------------------------------------------- Sprout JoinSplits

def ljs_xs(r: LJs) -> +List<Js>:
  LJs{+x, _} = r
  x

def ljs_c(r: LJs) -> C:
  LJs{_, +c} = r
  c

# PHGR13 descriptions are 1802 bytes, Groth16 ones 1698.
def js_size(g: Bool) -> U32:
  match g:
    case True{}:
      1698
    case False{}:
      1802

def js_one(+g: Bool, +c: C) -> Js:
  Js{u64(c), u64(skip(c, 8)), take(skip(c, 16), 32), take(skip(c, 48), 32), take(skip(c, 80), 32),
     take(skip(c, 112), 32), take(skip(c, 144), 32)}

def ljs_cons(+j: Js, r: LJs) -> LJs:
  LJs{+t, +c} = r
  LJs{j <> t, c}

def jss(n: Nat, +g: Bool, +c: C) -> LJs:
  match n:
    case 0n:
      LJs{Nil{}, c}
    case 1n+m:
      ljs_cons(js_one(g, c), jss(m, g, skip(c, js_size(g))))

def js_tail_sel(empty: Bool, +x: +List<Js>, +c: C) -> LJs:
  match empty:
    case True{}:
      LJs{x, c}
    case False{}:
      LJs{x, skip(c, 96)}

def nil_js(xs: +List<Js>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{_, _}:
      False{}

# vJoinSplit, then joinSplitPubKey (32) + joinSplitSig (64) when non-empty.
def js_tail(r: LJs) -> LJs:
  LJs{+x, +c} = r
  js_tail_sel(nil_js(x), x, c)

def joinsplits(+g: Bool, +c: C) -> LJs:
  +n = cs(c)
  js_tail(jss(U32.to_nat(cs_v(n)), g, cs_c(n)))

# ---------------------------------------------------------------- Sapling

def sap_c(s: Sap) -> C:
  Sap{_, _, _, +c} = s
  c

def zero64() -> H.U64:
  H.U64{0, 0}

# v4 spends: cv 32, anchor 32, nf 32, rk 32, proof 192, sig 64 (384 bytes).
def sp4(n: Nat, +c: C) -> +List<SSp>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      SSp{take(skip(c, 32), 32), take(skip(c, 64), 32)} <> sp4(m, skip(c, 384))

# v4 outputs: cv 32, cmu 32, epk 32, enc 580, out 80, proof 192 (948 bytes).
def op4(n: Nat, +c: C) -> +List<+List<U32>>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      take(skip(c, 32), 32) <> op4(m, skip(c, 948))

# v4: valueBalance, vShieldedSpend, vShieldedOutput (binding sig comes after JoinSplits).
def sapling4(+c: C) -> Sap:
  +vb = u64(c)
  +ns = cs(skip(c, 8))
  +nsv = cs_v(ns)
  +oc = skip(cs_c(ns), (nsv * 384 : U32))
  +no = cs(oc)
  +nov = cs_v(no)
  Sap{vb, sp4(U32.to_nat(nsv), cs_c(ns)), op4(U32.to_nat(nov), cs_c(no)), skip(cs_c(no), (nov * 948 : U32))}

# v5/v6 spends: cv 32, nf 32, rk 32 (96 bytes); the shared anchor comes later.
def sp5(n: Nat, +anchor: +List<U32>, +c: C) -> +List<SSp>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      SSp{anchor, take(skip(c, 32), 32)} <> sp5(m, anchor, skip(c, 96))

# v5/v6 outputs: cv 32, cmu 32, epk 32, enc 580, out 80 (756 bytes).
def op5(n: Nat, +c: C) -> +List<+List<U32>>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      take(skip(c, 32), 32) <> op5(m, skip(c, 756))

def sap5_al(z: Bool) -> U32:
  match z:
    case True{}:
      0
    case False{}:
      32

def sap5_anchor_len(+ns: U32) -> U32:
  sap5_al(U32.is_eq(ns, 0))

def sap5_any(any: Bool, +ns: U32, +no: U32, +sc: C, +oc: C, +tc: C) -> Sap:
  match any:
    case False{}:
      Sap{zero64(), Nil{}, Nil{}, tc}
    case True{}:
      +al = sap5_anchor_len(ns)
      +anchor = take(skip(tc, 8), al)
      +after = skip(tc, (8 + al + ns * 256 + no * 192 + 64 : U32))
      Sap{u64(tc), sp5(U32.to_nat(ns), anchor, sc), op5(U32.to_nat(no), oc), after}

# v5: spends, outputs, then valueBalance + anchor (if spends) + proofs + sigs + binding sig.
def sapling5(+c: C) -> Sap:
  +ns = cs(c)
  +nsv = cs_v(ns)
  +no = cs(skip(cs_c(ns), (nsv * 96 : U32)))
  +nov = cs_v(no)
  sap5_any(Bool.not(U32.is_eq(nsv, 0) && U32.is_eq(nov, 0)), nsv, nov, cs_c(ns), cs_c(no),
           skip(cs_c(no), (nov * 756 : U32)))

# ---------------------------------------------------------------- Orchard / Ironwood bundles

def bun_c(b: Bun) -> C:
  Bun{_, _, _, _, _, +c} = b
  c

# action: cv 32, nf 32, rk 32, cmx 32, epk 32, enc 580, out 80 (820 bytes).
def acts(n: Nat, +c: C) -> +List<Act>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      Act{take(skip(c, 32), 32), take(skip(c, 96), 32)} <> acts(m, skip(c, 820))

def bun_any(any: Bool, +n: U32, +ac: C, +tc: C) -> Bun:
  match any:
    case False{}:
      Bun{False{}, zero64(), Nil{}, 0, Nil{}, tc}
    case True{}:
      +pl = cs(skip(tc, 41))
      +after = skip(cs_c(pl), (cs_v(pl) + n * 64 + 64 : U32))
      Bun{True{}, u64(skip(tc, 1)), take(skip(tc, 9), 32), u8(tc), acts(U32.to_nat(n), ac), after}

# actions; if any: flags 1, valueBalance 8, anchor 32, proof (CompactSize bytes),
# spend-auth sigs 64 each, binding sig 64.
def bundle(+c: C) -> Bun:
  +na = cs(c)
  +n = cs_v(na)
  bun_any(Bool.not(U32.is_eq(n, 0)), n, cs_c(na), skip(cs_c(na), (n * 820 : U32)))

def no_bundle(+c: C) -> Bun:
  Bun{False{}, zero64(), Nil{}, 0, Nil{}, c}

# ---------------------------------------------------------------- transactions

def tx_size(t: Tx) -> U32:
  Tx{_, _, _, _, _, _, _, _, _, _, _, _, +s} = t
  s

def tx_ver(t: Tx) -> U32:
  Tx{+v, _, _, _, _, _, _, _, _, _, _, _, _} = t
  v

def tp_after_in(r: LIn) -> TP:
  LIn{+ins, +c} = r
  +n = cs(c)
  +o = touts(U32.to_nat(cs_v(n)), cs_c(n))
  TP{ins, lout_xs(o), lout_c(o)}

def transparent(+c: C) -> TP:
  +n = cs(c)
  tp_after_in(tins(U32.to_nat(cs_v(n)), cs_c(n)))

def tp_ins(t: TP) -> +List<TIn>:
  TP{+x, _, _} = t
  x

def tp_outs(t: TP) -> +List<TOut>:
  TP{_, +x, _} = t
  x

def tp_c(t: TP) -> C:
  TP{_, _, +c} = t
  c

def empty_sap(+c: C) -> Sap:
  Sap{zero64(), Nil{}, Nil{}, c}

def v4_bind_sel(none: Bool) -> U32:
  match none:
    case True{}:
      0
    case False{}:
      64

def nil_sp(xs: +List<SSp>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{_, _}:
      False{}

def nil_bs(xs: +List<+List<U32>>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{_, _}:
      False{}

# Bytes after the binding sig of a v4 tx: 64 if it has Sapling spends or outputs.
def v4_bind(s: Sap) -> U32:
  Sap{_, +sp, +op, _} = s
  v4_bind_sel(nil_sp(sp) && nil_bs(op))

def size_from(+c0: C, +c1: C) -> U32:
  (c_pos(c1) - c_pos(c0) : U32)

def js_sel(has: Bool, +g: Bool, +c: C) -> LJs:
  match has:
    case True{}:
      joinsplits(g, c)
    case False{}:
      LJs{Nil{}, c}

# v1/v2 (Sprout): vin, vout, lock; PHGR JoinSplits when v >= 2.
def tx_sprout(+ver: U32, +c0: C) -> Tx:
  +tp = transparent(skip(c0, 4))
  +lc = tp_c(tp)
  +j = js_sel(U32.is_le(2, ver), False{}, skip(lc, 4))
  +e = ljs_c(j)
  Tx{ver, False{}, 0, 0, tp_ins(tp), tp_outs(tp), u32(lc), 0, ljs_xs(j), empty_sap(e), no_bundle(e), no_bundle(e), size_from(c0, e)}

# v3 (Overwinter): vin, vout, lock, expiry, PHGR JoinSplits.
def tx_v3(+ver: U32, +c0: C) -> Tx:
  +tp = transparent(skip(c0, 8))
  +lc = tp_c(tp)
  +j = joinsplits(False{}, skip(lc, 8))
  +e = ljs_c(j)
  Tx{ver, True{}, u32(skip(c0, 4)), 0, tp_ins(tp), tp_outs(tp), u32(lc), u32(skip(lc, 4)), ljs_xs(j), empty_sap(e),
     no_bundle(e), no_bundle(e), size_from(c0, e)}

# v4 (Sapling): vin, vout, lock, expiry, Sapling v4, Groth16 JoinSplits, binding sig.
def tx_v4(+ver: U32, +c0: C) -> Tx:
  +tp = transparent(skip(c0, 8))
  +lc = tp_c(tp)
  +sap = sapling4(skip(lc, 8))
  +j = joinsplits(True{}, sap_c(sap))
  +e = skip(ljs_c(j), v4_bind(sap))
  Tx{ver, True{}, u32(skip(c0, 4)), 0, tp_ins(tp), tp_outs(tp), u32(lc), u32(skip(lc, 4)), ljs_xs(j), sap,
     no_bundle(e), no_bundle(e), size_from(c0, e)}

# v5/v6: header fragment (branch, lock, expiry), vin, vout, Sapling v5, Orchard, [Ironwood].
def iron_sel(v6: Bool, +c: C) -> Bun:
  match v6:
    case True{}:
      bundle(c)
    case False{}:
      no_bundle(c)

def tx_v56(+ver: U32, +c0: C) -> Tx:
  +tp = transparent(skip(c0, 20))
  +sap = sapling5(tp_c(tp))
  +orch = bundle(sap_c(sap))
  +iron = iron_sel(U32.is_eq(ver, 6), bun_c(orch))
  +e = bun_c(iron)
  Tx{ver, True{}, u32(skip(c0, 4)), u32(skip(c0, 8)), tp_ins(tp), tp_outs(tp), u32(skip(c0, 12)), u32(skip(c0, 16)),
     Nil{}, sap, orch, iron, size_from(c0, e)}

def by_ver3(v3: Bool, +v: U32, +c: C) -> Tx:
  match v3:
    case True{}:
      tx_v3(v, c)
    case False{}:
      tx_sprout(v, c)

def by_ver4(v4: Bool, +v3: Bool, +v: U32, +c: C) -> Tx:
  match v4:
    case True{}:
      tx_v4(v, c)
    case False{}:
      by_ver3(v3, v, c)

def by_ver_sel(v56: Bool, +v4: Bool, +v3: Bool, +v: U32, +c: C) -> Tx:
  match v56:
    case True{}:
      tx_v56(v, c)
    case False{}:
      by_ver4(v4, v3, v, c)

def by_ver(+v: U32, +c: C) -> Tx:
  by_ver_sel(U32.is_ge(v, 5), U32.is_eq(v, 4), U32.is_eq(v, 3), v, c)

# One transaction starting at cursor c (input already accepted by the wire validator).
def tx(+c: C) -> Tx:
  by_ver((u32(c) .&. 2147483647 : U32), c)
