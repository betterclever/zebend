# Zebend full node: the non-cryptographic consensus rules, per block, in Bend.
#
# Usage: rules <window.bin> <ctx.bin>
#   window.bin: blockdelta's input format (records: u32 height | 1487-byte verified header |
#               u32 length | block). The verified header is ignored here (blockdelta checks it).
#   ctx.bin:    7 x (u32 lo, u32 hi): value pools before the first block (sprout, sapling,
#               orchard, ironwood, lockbox, transparent, NSM value balance (ZIP 237);
#               two's complement 64-bit),
#               then per block: u32 L | L bytes:
#                 u32 height | u32 nt | nt x u32 times of the previous (up to 11) blocks |
#                 per spent transparent input of the block, in block order (coinbase input
#                 excluded): u32 value lo | u32 value hi | u32 height | u32 from-coinbase (0/1) |
#                 u32 script length | scriptPubKey bytes
# Every block is gated by node/wire's validator (blk.bend parse_capped) and parsed with
# fullnode/bend/parse.bend. Prints, per block:
#   fail <h> <rule> [tx <i>] [detail]      one line per violated rule
#   fees <h> <total miner fees>
#   pools <h> <sprout> <sapling> <orchard> <ironwood> <lockbox> <transparent> <nsm>   (after the block)
#   verdict <h> VALID|INVALID
# Rules (Zebra 7a839a6 / zcashd; see README.md for the source of each): coinbase position,
# script length, BIP34 height, coinbase shielded restrictions, coinbase expiry, issuance
# (founders' reward / funding streams / lockbox disbursement, via consensus/issuance), miner
# fees (<= pre-NU6, == from NU6, ZIP 236), tx version / group per height, v5/v6 branch id,
# inputs and outputs present, Orchard/Ironwood flags, NU6.3 Orchard restrictions, the
# temporary Orchard disable, JoinSplit vpub rules, duplicate spends and nullifiers in the
# block, expiry, lock time, pre-Sapling tx size, value balance (fee >= 0), output total range,
# coinbase maturity and the coinbase-spend shielding rule, block sigops (legacy + P2SH),
# block time > median-time-past, and the ZIP 209 turnstile (no pool negative).
# NU7 (>= 3,543,405; consensus/nu7, Zebra 1e03ee75): ZIP 218 subsidy / 3 and halving schedule,
# ZIP 214 rev. 3 / ZIP 207 rev. 2 / ZIP 2008 funding streams, ZIP 235 miner fees (40% of
# the fees; 60% to the NSM value balance), ZIP 237 NSM balance + reissuance (from 8,939,664),
# ZIP 218 shielded action limits, ZIP 2003 (no v4: tx_version).
import Base
import ../../../fullnode/bend/parse.bend as P
import ../../../fullnode/bend/delta.bend as D
import ../../../node/wire/hb.bend as H
import ../../../node/wire/blk.bend as KB
import ../../../node/block/bytes.bend as Y
import ../../../node/block/util.bend as U
import ../../issuance/issuance.bend as I
import ../../issuance/params.bend as IP
import ../../issuance/cb_main.bend as CB
import ../nu7.bend as N7

# ---------------------------------------------------------------- 64-bit two's complement

type Pv is Data:
  Pv{v: H.U64, h: U32, cb: U32, s: +List<U32>}

type PvC is Data:
  PvC{p: Pv, c: P.C}

# f: fail lines; v: sum of spent values; sig: P2SH sigops; keys: spend keys (outpoints,
# nullifiers) for the block-wide duplicate check; fin: every sequence is final; nn: inputs
# with a null prevout; c: ctx cursor.
type IA is Data:
  IA{f: String, v: H.U64, sig: U32, keys: +List<+List<U32>>, fin: Bool, nn: U32, c: P.C}

type JA is Data:
  JA{old: H.U64, new: H.U64, bad_both: Bool, bad_old: Bool, keys: +List<+List<U32>>}

# Per-tx result: fail lines; transparent in/out sums; Sprout net (sum vpub_old - sum vpub_new);
# Sapling/Orchard/Ironwood valueBalances; sigops; spend keys; null-prevout input count; the
# coinbase's outputs for the issuance check; the ctx cursor after this tx's inputs.
type TR is Data:
  TR{f: String, tin: H.U64, tout: H.U64, spr: H.U64, sap: H.U64, orch: H.U64, iw: H.U64, sig: U32,
     keys: +List<+List<U32>>, cb: Bool, cbo: +List<IP.Out>, c: P.C, cnt: N7.Cnt}

type Two is Data:
  Two{a: +List<+List<U32>>, b: +List<+List<U32>>}

type M3 is Data:
  M3{h: +List<U32>, xs: +List<+List<U32>>, ys: +List<+List<U32>>}

type Pools is Data:
  Pools{spr: H.U64, sap: H.U64, orch: H.U64, iw: H.U64, lock: H.U64, tr: H.U64, nsm: H.U64}

# Block accumulator over its transactions.
type BA is Data:
  BA{f: String, fees: H.U64, tin: H.U64, tout: H.U64, spr: H.U64, sap: H.U64, orch: H.U64, iw: H.U64,
     sig: U32, keys: +List<+List<U32>>, ncb: U32, cbout: H.U64, cbvb: H.U64, cbo: +List<IP.Out>, first_cb: Bool, c: P.C,
     cnt: N7.Cnt}

type BOut is Data:
  BOut{s: String, p: Pools}

type Hd is Data:
  Stop{}
  Rec{h: U32, blen: U32, off: U32}

type Paths is Type:
  Paths{w: String, c: String}

type CR is Data:
  CR{ctx: +List<U32>, co: U32}

type BW is Data:
  BW{b: BOut, co: U32}

def z64() -> H.U64:
  H.U64{0, 0}

def w64(+x: U32) -> H.U64:
  H.U64{x, 0}

def add64(a: H.U64, b: H.U64) -> H.U64:
  H.U64{+al, +ah} = a
  H.U64{+bl, +bh} = b
  +lo = (al + bl : U32)
  H.U64{lo, (ah + bh + D.carry(U32.is_lt(lo, al)) : U32)}

def sub64(+a: H.U64, +b: H.U64) -> H.U64:
  add64(a, D.neg64(b))

def neg_q(+a: H.U64) -> Bool:
  U32.is_eq((D.hi_of(a) >> 31n : U32), 1)

def is_zero64(a: H.U64) -> Bool:
  H.U64{+lo, +hi} = a
  U32.is_eq((lo .|. hi : U32), 0)

def eq64(+a: H.U64, +b: H.U64) -> Bool:
  is_zero64(sub64(a, b))

# Signed a < b (all values here are sums of in-range amounts: no overflow).
def lt64(+a: H.U64, +b: H.U64) -> Bool:
  neg_q(sub64(a, b))

def max_money() -> H.U64:
  H.max_money()

# ---------------------------------------------------------------- small helpers

def when(b: Bool, +s: String) -> String:
  match b:
    case True{}:
      s
    case False{}:
      ""

def sel32(b: Bool, +x: U32, +y: U32) -> U32:
  match b:
    case True{}:
      x
    case False{}:
      y

def sel64(b: Bool, +x: H.U64, +y: H.U64) -> H.U64:
  match b:
    case True{}:
      x
    case False{}:
      y

def b32(b: Bool) -> U32:
  sel32(b, 1, 0)

def fl(+h: U32, +rule: String) -> String:
  "fail " ++ U32.show(h) ++ " " ++ rule ++ "\n"

def flt(+h: U32, +rule: String, +k: U32) -> String:
  "fail " ++ U32.show(h) ++ " " ++ rule ++ " tx " ++ U32.show(k) ++ "\n"

def len_in(xs: +List<P.TIn>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{_, t}:
      (1 + len_in(t) : U32)

def len_out(xs: +List<P.TOut>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{_, t}:
      (1 + len_out(t) : U32)

def len_js(xs: +List<P.Js>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{_, t}:
      (1 + len_js(t) : U32)

def le32b(+x: U32) -> +List<U32>:
  [(x .&. 255 : U32), ((x >> 8n) .&. 255 : U32), ((x >> 16n) .&. 255 : U32), (x >> 24n : U32)]

# ---------------------------------------------------------------- network upgrades (Zebra
# zebra-chain/src/parameters/constants.rs, mainnet; branch ids network_upgrade.rs)

def overwinter() -> U32:
  347500

def sapling_h() -> U32:
  419200

def heartwood() -> U32:
  903000

def canopy_h() -> U32:
  1046400

def nu5() -> U32:
  1687104

def nu6() -> U32:
  2726400

def nu61() -> U32:
  3146400

def nu62() -> U32:
  3364600

def nu63() -> U32:
  3428143

# Zebra MAINNET_TEMPORARY_ORCHARD_DISABLING_SOFT_FORK_HEIGHT (zebra-chain network.rs).
def orchard_off() -> U32:
  3363426

# Zebra main 1e03ee7 (2026-10-23): NU7 at 3,543,405, branch 0x77190ad9 (ZIP 259).
def nu7() -> U32:
  3543405

def branch_at(+h: U32) -> U32:
  sel32(U32.is_ge(h, nu7()), 1998129881,
  sel32(U32.is_ge(h, nu63()), 933566043,
  sel32(U32.is_ge(h, nu62()), 1412952880,
  sel32(U32.is_ge(h, nu61()), 1307332080,
  sel32(U32.is_ge(h, nu6()), 3370586197,
  sel32(U32.is_ge(h, nu5()), 3268858036,
  sel32(U32.is_ge(h, canopy_h()), 3925833126,
  sel32(U32.is_ge(h, heartwood()), 4122551051,
  sel32(U32.is_ge(h, 653600), 733220448,
  sel32(U32.is_ge(h, sapling_h()), 1991772603,
  sel32(U32.is_ge(h, overwinter()), 1537743641, 0)))))))))))

def ver_sel(+pre_ow: Bool, +pre_sap: Bool, +pre_nu5: Bool, +pre_nu63: Bool, +v: U32, +ow: Bool, +g: U32,
            +v4: Bool, +v5: Bool, +v6: Bool) -> Bool:
  (pre_ow && Bool.not(ow) && U32.is_ge(v, 1))
    || (Bool.not(pre_ow) && pre_sap && ow && U32.is_eq(v, 3) && U32.is_eq(g, 63210096))
    || (Bool.not(pre_sap) && pre_nu5 && v4)
    || (Bool.not(pre_nu5) && pre_nu63 && (v4 || v5))
    || (Bool.not(pre_nu63) && (v4 || v5 || v6))
    || False{}

# ---------------------------------------------------------------- spent outputs (ctx)

# Version groups: Overwinter 0x03C48270, Sapling 0x892F2085, v5 0x26A7270A, v6 0xD8853298.
def ver_ok(+h: U32, +v: U32, +ow: Bool, +g: U32) -> Bool:
  +v4 = ow && U32.is_eq(v, 4) && U32.is_eq(g, 2301567109)
  +v5 = ow && U32.is_eq(v, 5) && U32.is_eq(g, 648488714)
  +v6 = ow && U32.is_eq(v, 6) && U32.is_eq(g, 3632576152)
  Bool.not(U32.is_ge(h, nu7()) && U32.is_eq(v, 4)) && ver_sel(U32.is_lt(h, overwinter()), U32.is_lt(h, sapling_h()), U32.is_lt(h, nu5()), U32.is_lt(h, nu63()), v, ow, g, v4, v5, v6)

def pv(+c: P.C) -> PvC:
  +n = P.u32(P.skip(c, 16))
  PvC{Pv{H.U64{P.u32(c), P.u32(P.skip(c, 4))}, P.u32(P.skip(c, 8)), P.u32(P.skip(c, 12)), P.take(P.skip(c, 20), n)},
      P.skip(c, (20 + n : U32))}

# ---------------------------------------------------------------- P2SH sigops (zcashd
# CScript::GetSigOpCount(const CScript& scriptSig) and GetSigOpCount(fAccurate = true))

def is_p2sh(+s: +List<U32>) -> Bool:
  U32.is_eq(H.length(s), 23) && U32.is_eq(H.at(s, 0), 169) && U32.is_eq(H.at(s, 1), 20) && U32.is_eq(H.at(s, 22), 135)

def acc_cost(+op: U32, +prev: U32) -> U32:
  sel32(U32.is_eq(op, 172) || U32.is_eq(op, 173), 1,
    sel32(U32.is_eq(op, 174) || U32.is_eq(op, 175),
      sel32(U32.is_ge(prev, 81) && U32.is_le(prev, 96), (prev - 80 : U32), 20), 0))

def acc_loop(fuel: Nat, live: Bool, +xs: +List<U32>, +rem: U32, +prev: U32, +acc: U32) -> U32:
  match fuel live:
    case 0n _:
      acc
    case 1n+p False{}:
      acc
    case 1n+p True{}:
      +op = H.at(xs, 0)
      +t = H.drop(xs, 1)
      +hl = D.push_hl(op)
      +n = D.push_n(op, t)
      +rest = H.drop(t, (hl + n : U32))
      +r2 = (rem - 1 - hl - n : U32)
      acc_loop(p, D.sig_live(rest, r2), rest, r2, op, (acc + acc_cost(op, prev) : U32))

def accurate_sigops(+s: +List<U32>) -> U32:
  +n = H.length(s)
  acc_loop(U32.to_nat((n + 1 : U32)), D.sig_live(s, n), s, n, 255, 0)

def lp_end(ok: Bool, last: +List<U32>) -> Maybe<&2, +List<U32>>:
  match ok:
    case True{}:
      Some{last}
    case False{}:
      None{}

# The last data a push-only scriptSig pushes; None if an op fails to decode or is not a push.
def lp_loop(fuel: Nat, live: Bool, +xs: +List<U32>, +rem: U32, last: +List<U32>, +bad: Bool) -> Maybe<&2, +List<U32>>:
  match fuel live:
    case 0n _:
      lp_end(Bool.not(bad), last)
    case 1n+p False{}:
      lp_end(U32.is_eq(rem, 0) && Bool.not(bad), last)
    case 1n+p True{}:
      +op = H.at(xs, 0)
      +t = H.drop(xs, 1)
      +hl = D.push_hl(op)
      +n = D.push_n(op, t)
      +rest = H.drop(t, (hl + n : U32))
      +r2 = (rem - 1 - hl - n : U32)
      +isbad = U32.is_gt(op, 96)
      lp_loop(p, D.sig_live(rest, r2) && Bool.not(isbad), rest, r2, H.take(H.drop(t, hl), n), isbad)

def p2sh_of(m: Maybe<&2, +List<U32>>) -> U32:
  match m:
    case None{}:
      0
    case Some{d}:
      accurate_sigops(d)

def p2sh_sel(p2sh: Bool, +ss: +List<U32>) -> U32:
  match p2sh:
    case False{}:
      0
    case True{}:
      +n = H.length(ss)
      p2sh_of(lp_loop(U32.to_nat((n + 1 : U32)), D.sig_live(ss, n), ss, n, Nil{}, False{}))

def p2sh_sigops(+ps: +List<U32>, +ss: +List<U32>) -> U32:
  p2sh_sel(is_p2sh(ps), ss)

# ---------------------------------------------------------------- transparent inputs

def in_spend(r: PvC, +h: U32, +k: U32, +nout: U32, +prev: +List<U32>, +idx: U32, +ss: +List<U32>, +q: U32,
             +f: String, +v: H.U64, +sig: U32, +keys: +List<+List<U32>>, +fin: Bool, +nn: U32) -> IA:
  PvC{+p, +c2} = r
  Pv{+pval, +ph, +pcb, +ps} = p
  +iscb = U32.is_eq(pcb, 1)
  +f2 = f ++ when(iscb && U32.is_lt(h, (ph + 100 : U32)), flt(h, "coinbase_maturity", k)) ++ when(iscb && U32.is_gt(nout, 0), flt(h, "coinbase_spend_transparent_outputs", k))
  IA{f2, add64(v, pval), (sig + p2sh_sigops(ps, ss) : U32), Y.append([9], Y.append(prev, le32b(idx))) <> keys,
     fin && U32.is_eq(q, 4294967295), nn, c2}

def in_sel(null: Bool, +h: U32, +k: U32, +nout: U32, +prev: +List<U32>, +idx: U32, +ss: +List<U32>, +q: U32,
           +f: String, +v: H.U64, +sig: U32, +keys: +List<+List<U32>>, +fin: Bool, +nn: U32, +c: P.C) -> IA:
  match null:
    case True{}:
      IA{f, v, sig, keys, fin && U32.is_eq(q, 4294967295), (nn + 1 : U32), c}
    case False{}:
      in_spend(pv(c), h, k, nout, prev, idx, ss, q, f, v, sig, keys, fin, nn)

def in_step(null: Bool, +h: U32, +k: U32, +nout: U32, +prev: +List<U32>, +idx: U32, +ss: +List<U32>, +q: U32, a: IA) -> IA:
  IA{+f, +v, +sig, +keys, +fin, +nn, +c} = a
  in_sel(null, h, k, nout, prev, idx, ss, q, f, v, sig, keys, fin, nn, c)

def ins_walk(xs: +List<P.TIn>, +h: U32, +k: U32, +nout: U32, a: IA) -> IA:
  match xs:
    case Nil{}:
      a
    case Con{i, t}:
      P.TIn{+prev, +idx, +ss, +q} = i
      ins_walk(t, h, k, nout, in_step(D.is_null_prev(prev, idx), h, k, nout, prev, idx, ss, q, a))

# ---------------------------------------------------------------- outputs

def outs_sum(xs: +List<P.TOut>) -> H.U64:
  match xs:
    case Nil{}:
      z64()
    case Con{o, t}:
      P.TOut{+v, _} = o
      add64(v, outs_sum(t))

def nat_sel(small: Bool, +lo: U32, +hi: U32) -> Nat:
  match small:
    case True{}:
      IP.big(hi, lo)
    case False{}:
      0n

# Coinbase outputs as consensus/issuance's (value, script hex); values >= 2^48 zat (never a
# real coinbase output) map to a value no required output has.
def nat_of(v: H.U64) -> Nat:
  H.U64{+lo, +hi} = v
  nat_sel(U32.is_lt(hi, 65536), lo, hi)

def iouts(xs: +List<P.TOut>) -> +List<IP.Out>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{o, t}:
      P.TOut{+v, +s} = o
      IP.Out{nat_of(v), U.bhex(s)} <> iouts(t)

# ---------------------------------------------------------------- shielded parts

def js_walk(xs: +List<P.Js>, +canopy: Bool, a: JA) -> JA:
  match xs:
    case Nil{}:
      a
    case Con{j, t}:
      P.Js{+jo, +jn, _, +n1, +n2, _, _} = j
      JA{+o, +n, +bb, +bo, +keys} = a
      js_walk(t, canopy, JA{add64(o, jo), add64(n, jn), bb || (Bool.not(is_zero64(jo)) && Bool.not(is_zero64(jn))),
                             bo || (canopy && Bool.not(is_zero64(jo))),
                             Y.append([0], n1) <> Y.append([0], n2) <> keys})

def ja_old(a: JA) -> H.U64:
  JA{+x, _, _, _, _} = a
  x

def ja_new(a: JA) -> H.U64:
  JA{_, +x, _, _, _} = a
  x

def ja_bb(a: JA) -> Bool:
  JA{_, _, +x, _, _} = a
  x

def ja_bo(a: JA) -> Bool:
  JA{_, _, _, +x, _} = a
  x

def ja_keys(a: JA) -> +List<+List<U32>>:
  JA{_, _, _, _, +x} = a
  x

def sp_keys(xs: +List<P.SSp>, keys: +List<+List<U32>>) -> +List<+List<U32>>:
  match xs:
    case Nil{}:
      keys
    case Con{s, t}:
      P.SSp{_, +nf} = s
      sp_keys(t, Y.append([1], nf) <> keys)

def act_keys(+tag: U32, xs: +List<P.Act>, keys: +List<+List<U32>>) -> +List<+List<U32>>:
  match xs:
    case Nil{}:
      keys
    case Con{a, t}:
      P.Act{+nf, _} = a
      act_keys(tag, t, Y.append([tag], nf) <> keys)

# ---------------------------------------------------------------- one transaction

def sig_legacy(+ins: +List<P.TIn>, +outs: +List<P.TOut>) -> U32:
  (D.ins_sigops(ins) + D.outs_sigops(outs) : U32)

def pad_sel(neg: Bool, +xs: +List<U32>) -> +List<U32>:
  match neg:
    case True{}:
      Y.append(xs, [0])
    case False{}:
      xs

def pad_sign(+xs: +List<U32>, +top: U32) -> +List<U32>:
  pad_sel(U32.is_ge(top, 128), xs)

def nb3(l3: Bool, +b0: U32, +b1: U32, +b2: U32, +b3: U32) -> +List<U32>:
  match l3:
    case True{}:
      pad_sign([b0, b1, b2], b2)
    case False{}:
      pad_sign([b0, b1, b2, b3], b3)

def nb2(l2: Bool, +l3: Bool, +b0: U32, +b1: U32, +b2: U32, +b3: U32) -> +List<U32>:
  match l2:
    case True{}:
      pad_sign([b0, b1], b1)
    case False{}:
      nb3(l3, b0, b1, b2, b3)

def nb_sel(l1: Bool, +l2: Bool, +l3: Bool, +b0: U32, +b1: U32, +b2: U32, +b3: U32) -> +List<U32>:
  match l1:
    case True{}:
      pad_sign([b0], b0)
    case False{}:
      nb2(l2, l3, b0, b1, b2, b3)

# BIP34 (as Zebra's parse_coinbase_height / zcashd): the coinbase scriptSig starts with the
# minimal CScriptNum push of the height (OP_1..OP_16 for 1..16).
def num_bytes(+h: U32) -> +List<U32>:
  +b0 = (h .&. 255 : U32)
  +b1 = ((h >> 8n) .&. 255 : U32)
  +b2 = ((h >> 16n) .&. 255 : U32)
  +b3 = (h >> 24n : U32)
  nb_sel(U32.is_lt(h, 256), U32.is_lt(h, 65536), U32.is_lt(h, 16777216), b0, b1, b2, b3)

def hp_sel(small: Bool, +h: U32) -> +List<U32>:
  match small:
    case True{}:
      [(h + 80 : U32)]
    case False{}:
      +nb = num_bytes(h)
      H.length(nb) <> nb

def height_push(+h: U32) -> +List<U32>:
  hp_sel(U32.is_ge(h, 1) && U32.is_le(h, 16), h)

def starts_with(+xs: +List<U32>, +pre: +List<U32>) -> Bool:
  Y.is_eq(H.take(xs, H.length(pre)), pre)

def cb_script(xs: +List<P.TIn>) -> +List<U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{i, _}:
      P.TIn{_, _, +s, _} = i
      s

def coinbase_rules(+h: U32, +ins: +List<P.TIn>, +njs: U32, +nsp: U32, +nso: U32, +oflags: U32, +oacts: U32,
                   +iflags: U32, +iacts: U32, +exp: U32, +ow: Bool) -> String:
  +s = cb_script(ins)
  +sl = H.length(s)
  when(U32.is_lt(sl, 2) || U32.is_gt(sl, 100), flt(h, "coinbase_script_length", 0))
    ++ when(U32.is_gt(h, 0) && Bool.not(starts_with(s, height_push(h))), flt(h, "coinbase_height", 0))
    ++ when(U32.is_gt(njs, 0) || U32.is_gt(nsp, 0)
            || (U32.is_gt(oacts, 0) && U32.is_eq((oflags .&. 1 : U32), 1))
            || (U32.is_gt(iacts, 0) && U32.is_eq((iflags .&. 1 : U32), 1)), flt(h, "coinbase_shielded_spend", 0))
    ++ when(U32.is_ge(h, nu63()) && U32.is_gt(oacts, 0), flt(h, "coinbase_orchard_nu63", 0))
    ++ when(U32.is_lt(h, heartwood()) && U32.is_gt(nso, 0), flt(h, "coinbase_sapling_output_pre_heartwood", 0))
    ++ when(U32.is_ge(h, nu5()) && Bool.not(U32.is_eq(exp, h)), flt(h, "coinbase_expiry", 0))
    ++ when(U32.is_lt(h, nu5()) && ow && U32.is_gt(exp, 499999999), flt(h, "expiry_max", 0))

def noncb_rules(+h: U32, +bt: U32, +k: U32, +lock: U32, +exp: U32, +ow: Bool, +fin: Bool, +nn: U32) -> String:
  +tlock = U32.is_ge(lock, 500000000)
  when(U32.is_gt(nn, 0), flt(h, "coinbase_first", k))
    ++ when(ow && U32.is_gt(exp, 499999999), flt(h, "expiry_max", k))
    ++ when(ow && U32.is_gt(exp, 0) && U32.is_gt(h, exp), flt(h, "expired", k))
    ++ when(Bool.not(fin) && U32.is_gt(lock, 0)
            && ((Bool.not(tlock) && U32.is_ge(lock, h)) || (tlock && U32.is_ge(lock, bt))), flt(h, "lock_time", k))

def bun_n(b: P.Bun) -> U32:
  P.Bun{_, _, _, _, +acts, _} = b
  D.len_acts(acts)

def bun_f(b: P.Bun) -> U32:
  P.Bun{_, _, _, +f, _, _} = b
  f

def bun_vb(b: P.Bun) -> H.U64:
  P.Bun{_, +vb, _, _, _, _} = b
  vb

def bun_acts(b: P.Bun) -> +List<P.Act>:
  P.Bun{_, _, _, _, +acts, _} = b
  acts

def tx_out(is_cb: Bool, +h: U32, +bt: U32, +k: U32, +f: String, +common: String, +tin: H.U64, +tout: H.U64,
           +spr: H.U64, +svb: H.U64, +ovb: H.U64, +ivb: H.U64, +fee: H.U64, +p2sh: U32, +keys: +List<+List<U32>>,
           +fin: Bool, +nn: U32, +ins: +List<P.TIn>, +outs: +List<P.TOut>, +lock: U32, +exp: U32, +ow: Bool,
           +njs: U32, +nsp: U32, +nso: U32, +oflags: U32, +oacts: U32, +iflags: U32, +iacts: U32, +c2: P.C) -> TR:
  match is_cb:
    case True{}:
      TR{f ++ common ++ coinbase_rules(h, ins, njs, nsp, nso, oflags, oacts, iflags, iacts, exp, ow),
         tin, tout, spr, svb, ovb, ivb, (sig_legacy(ins, outs) + p2sh : U32), keys, True{}, iouts(outs), c2,
         N7.Cnt{oacts, iacts, (nsp + nso : U32), njs}}
    case False{}:
      TR{f ++ common ++ noncb_rules(h, bt, k, lock, exp, ow, fin, nn) ++ when(neg_q(fee), flt(h, "value_balance", k)),
         tin, tout, spr, svb, ovb, ivb, (sig_legacy(ins, outs) + p2sh : U32), keys, False{}, Nil{}, c2,
         N7.Cnt{oacts, iacts, (nsp + nso : U32), njs}}

# ---------------------------------------------------------------- duplicates (sort, then adjacent)

def tx_fin(ia: IA, +h: U32, +bt: U32, +k: U32, +ver: U32, +ow: Bool, +grp: U32, +br: U32, +ins: +List<P.TIn>,
           +outs: +List<P.TOut>, +lock: U32, +exp: U32, +js: +List<P.Js>, +svb: H.U64, +sps: +List<P.SSp>,
           +nin: U32, +nout: U32, +njs: U32, +nsp: U32, +nso: U32, +oacts: U32, +oflags: U32, +iacts: U32,
           +iflags: U32, +ovb: H.U64, +ivb: H.U64, +oa: +List<P.Act>, +iwa: +List<P.Act>, +size: U32) -> TR:
  IA{+f, +tin, +p2sh, +keys0, +fin, +nn, +c2} = ia
  +is_cb = U32.is_eq(nin, 1) && U32.is_eq(nn, 1)
  +ja = js_walk(js, U32.is_ge(h, canopy_h()), JA{z64(), z64(), False{}, False{}, keys0})
  +jold = ja_old(ja)
  +jnew = ja_new(ja)
  +bad_both = ja_bb(ja)
  +bad_old = ja_bo(ja)
  +keys1 = ja_keys(ja)
  +keys = act_keys(3, iwa, act_keys(2, oa, sp_keys(sps, keys1)))
  +tout = outs_sum(outs)
  +spr = sub64(jold, jnew)
  +fee = sub64(add64(add64(add64(sub64(tin, spr), svb), ovb), ivb), tout)
  +has_in = U32.is_gt(nin, 0) || U32.is_gt(nsp, 0) || U32.is_gt(njs, 0)
            || (U32.is_gt(oacts, 0) && U32.is_eq((oflags .&. 1 : U32), 1))
            || (U32.is_gt(iacts, 0) && U32.is_eq((iflags .&. 1 : U32), 1))
  +has_out = U32.is_gt(nout, 0) || U32.is_gt(nso, 0) || U32.is_gt(njs, 0)
            || (U32.is_gt(oacts, 0) && U32.is_eq((oflags .&. 2 : U32), 2))
            || (U32.is_gt(iacts, 0) && U32.is_eq((iflags .&. 2 : U32), 2))
  +common = when(Bool.not(ver_ok(h, ver, ow, grp)), flt(h, "tx_version", k))
    ++ when(U32.is_ge(ver, 5) && U32.is_ge(h, nu5()) && Bool.not(U32.is_eq(br, branch_at(h))), flt(h, "branch_id", k))
    ++ when(Bool.not(has_in && has_out), flt(h, "inputs_outputs", k))
    ++ when(U32.is_gt(oacts, 0) && U32.is_eq((oflags .&. 3 : U32), 0), flt(h, "orchard_flags", k))
    ++ when(U32.is_gt(iacts, 0) && U32.is_eq((iflags .&. 3 : U32), 0), flt(h, "ironwood_flags", k))
    ++ when(U32.is_ge(h, nu63()) && U32.is_gt(oacts, 0) && neg_q(ovb), flt(h, "orchard_value_balance_nu63", k))
    ++ when(U32.is_ge(h, orchard_off()) && U32.is_lt(h, nu62()) && U32.is_gt(oacts, 0), flt(h, "orchard_disabled", k))
    ++ when(bad_both, flt(h, "joinsplit_vpub", k))
    ++ when(bad_old, flt(h, "sprout_vpub_old_canopy", k))
    ++ when(U32.is_lt(h, sapling_h()) && U32.is_gt(size, 100000), flt(h, "tx_size", k))
    ++ when(Bool.not(H.u64_le(tout, max_money())), flt(h, "output_total_range", k))
  tx_out(is_cb, h, bt, k, f, common, tin, tout, spr, svb, ovb, ivb, fee, p2sh, keys, fin, nn, ins, outs, lock, exp,
         ow, njs, nsp, nso, oflags, oacts, iflags, iacts, c2)

def tx_rules(+h: U32, +bt: U32, +k: U32, t: P.Tx, +c: P.C) -> TR:
  P.Tx{+ver, +ow, +grp, +br, +ins, +outs, +lock, +exp, +js, +sap, +orch, +iron, +size} = t
  P.Sap{+svb, +sps, +sos, _} = sap
  +nin = len_in(ins)
  +nout = len_out(outs)
  +njs = len_js(js)
  +nsp = D.len_sp(sps)
  +nso = D.len_bs(sos)
  +oacts = bun_n(orch)
  +oflags = bun_f(orch)
  +iacts = bun_n(iron)
  +iflags = bun_f(iron)
  +ovb = bun_vb(orch)
  +ivb = bun_vb(iron)
  +ia = ins_walk(ins, h, k, nout, IA{"", z64(), 0, Nil{}, True{}, 0, c})
  tx_fin(ia, h, bt, k, ver, ow, grp, br, ins, outs, lock, exp, js, svb, sps, nin, nout, njs, nsp, nso,
         oacts, oflags, iacts, iflags, ovb, ivb, bun_acts(orch), bun_acts(iron), size)

def key_lt(xs: +List<U32>, ys: +List<U32>) -> Bool:
  match xs ys:
    case Nil{} Nil{}:
      False{}
    case Nil{} _:
      True{}
    case _ Nil{}:
      False{}
    case Con{+a, at} Con{+b, bt}:
      U32.is_lt(a, b) || (U32.is_eq(a, b) && key_lt(at, bt))

def two_a(t: Two) -> +List<+List<U32>>:
  Two{+x, _} = t
  x

def two_b(t: Two) -> +List<+List<U32>>:
  Two{_, +x} = t
  x

def split(xs: +List<+List<U32>>, l: +List<+List<U32>>, r: +List<+List<U32>>) -> Two:
  match xs:
    case Nil{}:
      Two{l, r}
    case Con{x, t}:
      split(t, r, x <> l)

def mstep(ylt: Bool, +x: +List<U32>, xt: +List<+List<U32>>, +y: +List<U32>, yt: +List<+List<U32>>) -> M3:
  match ylt:
    case True{}:
      M3{y, x <> xt, yt}
    case False{}:
      M3{x, xt, y <> yt}

def m_h(m: M3) -> +List<U32>:
  M3{+x, _, _} = m
  x

def m_xs(m: M3) -> +List<+List<U32>>:
  M3{_, +x, _} = m
  x

def m_ys(m: M3) -> +List<+List<U32>>:
  M3{_, _, +x} = m
  x

def kappend(xs: +List<+List<U32>>, ys: +List<+List<U32>>) -> +List<+List<U32>>:
  match xs:
    case Nil{}:
      ys
    case Con{x, t}:
      x <> kappend(t, ys)

def merge(fuel: Nat, xs: +List<+List<U32>>, ys: +List<+List<U32>>) -> +List<+List<U32>>:
  match fuel xs ys:
    case 0n _ _:
      kappend(xs, ys)
    case 1n+p Nil{} _:
      ys
    case 1n+p _ Nil{}:
      xs
    case 1n+p Con{+x, xt} Con{+y, yt}:
      +st = mstep(key_lt(y, x), x, xt, y, yt)
      m_h(st) <> merge(p, m_xs(st), m_ys(st))

def msort(+fuel: Nat, +n: Nat, xs: +List<+List<U32>>) -> +List<+List<U32>>:
  match fuel xs:
    case 0n _:
      xs
    case 1n+p Nil{}:
      Nil{}
    case 1n+p Con{x, Nil{}}:
      [x]
    case 1n+p Con{x, Con{y, t}}:
      +sp = split(x <> y <> t, Nil{}, Nil{})
      merge(n, msort(p, n, two_a(sp)), msort(p, n, two_b(sp)))

def adj_dups(xs: +List<+List<U32>>) -> U32:
  match xs:
    case Con{+a, Con{+b, t}}:
      (b32(Y.is_eq(a, b)) + adj_dups(b <> t) : U32)
    case _:
      0

def kcount(xs: +List<+List<U32>>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{_, t}:
      1n+kcount(t)

def dups(+keys: +List<+List<U32>>) -> U32:
  +n = kcount(keys)
  adj_dups(msort(1n+n, 1n+n, keys))

# ---------------------------------------------------------------- median time past

def cnt_lt(xs: +List<U32>, +x: U32) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{+y, t}:
      (b32(U32.is_lt(y, x)) + cnt_lt(t, x) : U32)

def cnt_le(xs: +List<U32>, +x: U32) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{+y, t}:
      (b32(U32.is_le(y, x)) + cnt_le(t, x) : U32)

def pick_med(xs: +List<U32>, +all: +List<U32>, +m: U32) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{+x, t}:
      sel32(U32.is_le(cnt_lt(all, x), m) && U32.is_gt(cnt_le(all, x), m), x, pick_med(t, all, m))

def read_times(n: Nat, +c: P.C) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      P.u32(c) <> read_times(p, P.skip(c, 4))

# zcashd GetMedianTimePast: sort the (up to 11) previous times, take element [n / 2].
def mtp(+ts: +List<U32>) -> U32:
  pick_med(ts, ts, (H.length(ts) / 2 : U32))

# ---------------------------------------------------------------- one block

def sel_b(b: Bool, +x: Bool, +y: Bool) -> Bool:
  match b:
    case True{}:
      x
    case False{}:
      y

def cbo_sel(b: Bool, +x: +List<IP.Out>, +y: +List<IP.Out>) -> +List<IP.Out>:
  match b:
    case True{}:
      x
    case False{}:
      y

def ba_add(r: TR, +k: U32, a: BA) -> BA:
  TR{+f, +tin, +tout, +spr, +sap, +orch, +iw, +sig, +keys, +cb, +cbo, +c, +tc} = r
  BA{+af, +fees, +atin, +atout, +aspr, +asap, +aorch, +aiw, +asig, +akeys, +ncb, +cbout, +cbvb, +acbo, +first, _, +acnt} = a
  +fee = sub64(add64(add64(add64(sub64(tin, spr), sap), orch), iw), tout)
  +k0 = U32.is_eq(k, 0)
  BA{af ++ f, sel64(cb, fees, add64(fees, fee)), add64(atin, tin), add64(atout, tout), add64(aspr, spr),
     add64(asap, sap), add64(aorch, orch), add64(aiw, iw), (asig + sig : U32), kappend(keys, akeys),
     (ncb + b32(cb) : U32), sel64(k0, tout, cbout), sel64(k0, add64(add64(sap, orch), iw), cbvb),
     cbo_sel(k0, cbo, acbo), sel_b(k0, cb, first), c, N7.cnt_add(acnt, tc)}

def ba_c(a: BA) -> P.C:
  BA{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +c, _} = a
  c

def txs_walk(n: Nat, +h: U32, +bt: U32, +k: U32, +c: P.C, +a: BA) -> BA:
  match n:
    case 0n:
      a
    case 1n+m:
      +t = P.tx(c)
      +size = P.tx_size(t)
      txs_walk(m, h, bt, (k + 1 : U32), P.skip(c, size), ba_add(tx_rules(h, bt, k, t, ba_c(a)), k, a))

def show_pools(+h: U32, p: Pools) -> String:
  Pools{+a, +b, +c, +d, +e, +f, +g} = p
  "pools " ++ U32.show(h) ++ " " ++ D.sdec(a) ++ " " ++ D.sdec(b) ++ " " ++ D.sdec(c) ++ " " ++ D.sdec(d) ++ " "
    ++ D.sdec(e) ++ " " ++ D.sdec(f) ++ " " ++ D.sdec(g) ++ "\n"

# Funding stream share deferred to the lockbox (ZIP 1015/2001: 12% from NU6 until 4,406,400),
# less the NU6.1 one-time disbursement of 78,750 ZEC (ZIP 271) at 3,146,400.
def deferred(+h: U32, +subsidy: Nat) -> H.U64:
  +share = sel64(U32.is_ge(h, nu6()) && U32.is_lt(h, 4406400), w64(U32.from_nat(I.fs_value(subsidy, 12n))), z64())
  sel64(U32.is_eq(h, nu61()), sub64(share, H.U64{2324946432, 1833}), share)

def vstr(b: Bool) -> String:
  match b:
    case True{}:
      "VALID"
    case False{}:
      "INVALID"

def nat_sel2(b: Bool, +x: Nat, +y: Nat) -> Nat:
  match b:
    case True{}:
      x
    case False{}:
      y

def block_fin(a: BA, +h: U32, +bt: U32, +ntx: U32, +ts: +List<U32>, p: Pools) -> BOut:
  BA{+f, +fees, +tin, +tout, +spr, +sap, +orch, +iw, +sig, +keys, +ncb, +cbout, +cbvb, +cbo, +first, _, +cnt} = a
  Pools{+psp, +psa, +por, +piw, +plo, +ptr, +pnsm} = p
  +hn = U32.to_nat(h)
  +a7 = U32.is_ge(h, nu7())
  +subsidy = nat_sel2(a7, Nat.add(N7.subsidy(N7.Main{}, hn), nat_of(N7.additional(N7.Main{}, h, pnsm))), I.block_subsidy(hn))
  +dfr = sel64(a7, w64(U32.from_nat(N7.fs_deferred(N7.Main{}, hn, subsidy))), deferred(h, subsidy))
  +es = cbo_sel(a7, N7.required7(N7.Main{}, hn, subsidy), CB.expected(hn))
  +need = List.length(&2, IP.Out, es)
  +got = CB.matched(es, cbo)
  +total_out = add64(sub64(cbout, cbvb), dfr)
  +total_in = add64(w64(U32.from_nat(subsidy)), N7.miner_fees(N7.Main{}, h, fees))
  +nsp = add64(psp, spr)
  +nsa = sub64(psa, sap)
  +nor = sub64(por, orch)
  +niw = sub64(piw, iw)
  +nlo = add64(plo, dfr)
  +ntr = add64(ptr, sub64(tout, tin))
  +nnsm = N7.nsm_after(N7.Main{}, h, pnsm, fees)
  +nd = dups(keys)
  +f2 = f
    ++ when(Bool.not(first) || Bool.not(U32.is_eq(ncb, 1)), fl(h, "coinbase_first"))
    ++ when(Bool.not(Nat.is_eq(need, got)), fl(h, "issuance_required_outputs"))
    ++ when((U32.is_lt(h, nu6()) && lt64(total_in, total_out)) || (U32.is_ge(h, nu6()) && Bool.not(eq64(total_in, total_out))),
            fl(h, "miner_fees"))
    ++ when(a7 && Bool.not(N7.limits_ok(cnt)), fl(h, "shielded_action_limits"))

    ++ when(U32.is_gt(nd, 0), fl(h, "duplicate_spend"))
    ++ when(U32.is_gt(sig, 20000), fl(h, "sigops"))
    ++ when(U32.is_gt(H.length(ts), 0) && U32.is_le(bt, mtp(ts)), fl(h, "mtp"))
    ++ when(neg_q(nsp), fl(h, "turnstile_sprout")) ++ when(neg_q(nsa), fl(h, "turnstile_sapling"))
    ++ when(neg_q(nor), fl(h, "turnstile_orchard")) ++ when(neg_q(niw), fl(h, "turnstile_ironwood"))
    ++ when(neg_q(nlo), fl(h, "turnstile_lockbox")) ++ when(neg_q(ntr), fl(h, "turnstile_transparent"))
    ++ when(neg_q(nnsm), fl(h, "turnstile_nsm"))
  +ok = String.eq(f2, "")
  BOut{f2 ++ "fees " ++ U32.show(h) ++ " " ++ D.sdec(fees) ++ " sigops " ++ U32.show(sig) ++ " txs " ++ U32.show(ntx) ++ "\n"
       ++ show_pools(h, Pools{nsp, nsa, nor, niw, nlo, ntr, nnsm}) ++ "verdict " ++ U32.show(h) ++ " " ++ vstr(ok) ++ "\n", Pools{nsp, nsa, nor, niw, nlo, ntr, nnsm}}

def block_rules(+h: U32, +blk: +List<U32>, +ctx: +List<U32>, p: Pools) -> BOut:
  +hdr = H.take(blk, 1487)
  +bt = H.le32(H.drop(hdr, 100))
  +c = P.skip(P.start(blk), 1487)
  +n = P.cs(c)
  +cc = P.start(ctx)
  +nt = P.u32(P.skip(cc, 4))
  +ts = read_times(U32.to_nat(nt), P.skip(cc, 8))
  +c0 = P.skip(cc, (8 + 4 * nt : U32))
  +ntx = P.cs_v(n)
  +a = txs_walk(U32.to_nat(ntx), h, bt, 0, P.cs_c(n),
                BA{"", z64(), z64(), z64(), z64(), z64(), z64(), z64(), 0, Nil{}, 0, z64(), z64(), Nil{}, False{}, c0, N7.cnt0()})
  block_fin(a, h, bt, ntx, ts, p)

def gated(m: Maybe<&2, U32>, +h: U32, +blk: +List<U32>, +ctx: +List<U32>, p: Pools) -> BOut:
  match m:
    case Some{_}:
      block_rules(h, blk, ctx, p)
    case None{}:
      BOut{fl(h, "wire") ++ "verdict " ++ U32.show(h) ++ " INVALID\n", p}

# ---------------------------------------------------------------- files

def res_bytes(res: Result<&1, &1, U32 & String, +List<U32>>) -> +List<U32>:
  match res:
    case Done{bs}:
      bs
    case Fail{_}:
      Nil{}

def close_with(r: File & Result<&1, &1, U32 & String, +List<U32>>) -> IO(+List<U32>):
  (f, res) = r
  do IO<+List<U32>>:
    File.close(f)
    return res_bytes(res)

def read_at(+path: String, +off: U32, +n: U32) -> IO(+List<U32>):
  do IO<+List<U32>>:
    f : File <- IO.try(File, File.open(path, "r"))
    r : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_at(f, off, n)
    close_with(r)

def hd_sel(full: Bool, +bs: +List<U32>, +off: U32) -> Hd:
  match full:
    case False{}:
      Stop{}
    case True{}:
      Rec{H.le32(bs), H.le32(H.drop(bs, 1491)), off}

def head_of(+bs: +List<U32>, +off: U32) -> Hd:
  hd_sel(U32.is_eq(H.length(bs), 1495), bs, off)

def u64_at(+bs: +List<U32>, +i: U32) -> H.U64:
  H.U64{H.le32(H.drop(bs, i)), H.le32(H.drop(bs, (i + 4 : U32)))}

def pools_of(+bs: +List<U32>) -> Pools:
  Pools{u64_at(bs, 0), u64_at(bs, 8), u64_at(bs, 16), u64_at(bs, 24), u64_at(bs, 32), u64_at(bs, 40), u64_at(bs, 48)}

def bout_s(b: BOut) -> String:
  BOut{+s, _} = b
  s

def bout_p(b: BOut) -> Pools:
  BOut{_, +p} = b
  p

def rd_ctx2(+coff: U32, +lb: +List<U32>, +cp: String) -> IO(CR):
  do IO<CR>:
    ctx : +List<U32> <- read_at(cp, (coff + 4 : U32), H.le32(lb))
    return CR{ctx, (coff + 4 + H.le32(lb) : U32)}

def rd_ctx(+cp: String, +coff: U32) -> IO(CR):
  do IO<CR>:
    lb : +List<U32> <- read_at(cp, coff, 4)
    rd_ctx2(coff, lb, cp)

def with_cr(+blk: +List<U32>, +h: U32, cr: CR, p: Pools) -> BW:
  CR{+ctx, +co} = cr
  BW{gated(KB.parse_capped(blk), h, blk, ctx, p), co}

def loop(fuel: Nat, st: Hd, r: BW, +wp: String, +cp: String) -> IO(Unit):
  match fuel st:
    case 0n _:
      BW{+b, _} = r
      IO.print(bout_s(b))
    case 1n+q Stop{}:
      BW{+b, _} = r
      IO.print(bout_s(b))
    case 1n+q Rec{+h, +blen, +off}:
      BW{+b, +coff} = r
      +next = (off + 1495 + blen : U32)
      do IO<Unit>:
        IO.print(bout_s(b))
        blk : +List<U32> <- read_at(wp, (off + 1495 : U32), blen)
        cr : CR <- rd_ctx(cp, coff)
        nh : +List<U32> <- read_at(wp, next, 1495)
        loop(q, head_of(nh, next), with_cr(blk, h, cr, bout_p(b)), wp, cp)

def paths_of(xs: List<String>) -> Paths:
  match xs:
    case Con{_, Con{a, Con{b, _}}}:
      Paths{a, b}
    case _:
      Paths{"", ""}

def run(ps: Paths) -> IO(Unit):
  Paths{+wp, +cp} = ps
  do IO<Unit>:
    h0 : +List<U32> <- read_at(wp, 0, 1495)
    pb : +List<U32> <- read_at(cp, 0, 56)
    loop(1000000n, head_of(h0, 0), BW{BOut{"", pools_of(pb)}, 56}, wp, cp)

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<String> <- IO.args()
    run(paths_of(xs))
