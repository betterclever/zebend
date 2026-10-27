# Zebend mempool: per-transaction POLICY (not consensus), in Bend.
#
# Mirrors Zebra main 1e03ee7 (zebra-chain/src/transaction/unmined/zip317.rs and
# zebrad/src/components/mempool/storage.rs reject_if_non_standard_tx), which follow zcashd:
#   * ZIP 239 wtxid parts: the txid (display order) and, for v5/v6, the ZIP 244 authorizing
#     data digest (node/block/block.bend auth56; v1-v4: [0xff; 32], not used on the wire)
#   * ZIP 317: logical actions = max(ceil(tx_in_total_size / 150), ceil(tx_out_total_size / 34))
#     + 2 * nJoinSplit + max(nSpendsSapling, nOutputsSapling) + nActionsOrchard
#     + nActionsIronwood; conventional actions = max(2, logical actions); conventional fee =
#     1,000 zat (Zebra MARGINAL_FEE) * conventional actions; unpaid actions =
#     max(0, conventional actions - floor(fee / 1,000)); FAIL if unpaid > 0
#     (BLOCK_UNPAID_ACTION_LIMIT = 0) or fee < clamp(100 * size / 1000, 100, 1000)
#     (MIN_MEMPOOL_TX_FEE_RATE / MEMPOOL_TX_FEE_REQUIREMENT_CAP)
#   * standardness, in Zebra's order: every scriptSig <= 1,650 bytes and push-only; sigops
#     (legacy + P2SH, as bin/rules counts them, passed in) <= 4,000; every output P2PKH, P2SH,
#     P2PK or OP_RETURN (bare multisig rejected); OP_RETURN script <= 83 bytes, at most one;
#     no dust (value < 3 * floor(100 * (output size + 148) / 1000)).
#   * AreInputsStandard (when the spent scripts are given), per input as Zebra does: the spent
#     script is P2PKH / P2SH / P2PK (33..65-byte key) / m-of-n multisig; the push-only scriptSig
#     pushes exactly the expected items (2 / 1 + the redeemed script's / 1 / m + 1); a P2SH
#     redeemed script that is not standard is accepted with <= 15 accurate sigops.
#
# Usage: txpolicy <records.bin>
#   records until EOF: u32 LE n | u32 fee lo | u32 fee hi | u32 flags (1: fee given, 2: spent
#   scripts given) | u32 sigops | u32 m | n bytes: a 1487-byte header-shaped prefix,
#   CompactSize 1, the transaction | m bytes: per transparent input, u32 LE length | the spent
#   output's scriptPubKey. The record is gated by node/wire's block validator
#   (blk.bend parse_capped) before the transaction is parsed.
# Prints per record k:
#   tx <k> v <ver> txid <display hex> auth <hex> size <n> actions <logical> conv_actions <n> conv_fee <zat>
#   zip317 <k> unpaid <n> min_fee <zat> PASS|FAIL <reason>        (only when has_fee = 1)
#   std <k> PASS|FAIL <reason>
#   tx <k> INVALID wire                                             (gate rejected the record)
import Base
import ../../bend/parse.bend as P
import ../../bend/delta.bend as D
import ../../../node/wire/hb.bend as H
import ../../../node/wire/blk.bend as KB
import ../../../node/block/block.bend as K
import ../../../node/block/tx.bend as T
import ../../../node/block/util.bend as U

# ---------------------------------------------------------------- helpers

def cs_len(+n: U32) -> U32:
  D.sel_u32(U32.is_lt(n, 253), 1, D.sel_u32(U32.is_le(n, 65535), 3, 5))

def max32(+a: U32, +b: U32) -> U32:
  D.sel_u32(U32.is_ge(a, b), a, b)

def ceil_div(+a: U32, +b: U32) -> U32:
  ((a + b - 1) / b : U32)

def sel_s(b: Bool, +x: String, +y: String) -> String:
  match b:
    case True{}:
      x
    case False{}:
      y

def len_js(xs: +List<P.Js>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{_, t}:
      (1 + len_js(t) : U32)

# ---------------------------------------------------------------- ZIP 317

def in_size(xs: +List<P.TIn>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{i, t}:
      P.TIn{_, _, +s, _} = i
      +n = H.length(s)
      (40 + cs_len(n) + n + in_size(t) : U32)

def out_size(xs: +List<P.TOut>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{o, t}:
      P.TOut{_, +s} = o
      +n = H.length(s)
      (8 + cs_len(n) + n + out_size(t) : U32)

def sap_n(s: P.Sap) -> U32:
  P.Sap{_, +sp, +so, _} = s
  max32(D.len_sp(sp), D.len_bs(so))

def bun_n(b: P.Bun) -> U32:
  P.Bun{_, _, _, _, +acts, _} = b
  D.len_acts(acts)

def logical(+ins: +List<P.TIn>, +outs: +List<P.TOut>, +js: +List<P.Js>, +sap: P.Sap, +orch: P.Bun, +iron: P.Bun) -> U32:
  (max32(ceil_div(in_size(ins), 150), ceil_div(out_size(outs), 34)) + 2 * len_js(js)
    + sap_n(sap) + bun_n(orch) + bun_n(iron) : U32)

def unpaid(+conv: U32, +lo: U32, +hi: U32) -> U32:
  +paid = (lo / 1000 : U32)
  D.sel_u32(Bool.not(U32.is_eq(hi, 0)) || U32.is_ge(paid, conv), 0, (conv - paid : U32))

def min_fee(+size: U32) -> U32:
  +f = ((100 * size) / 1000 : U32)
  D.sel_u32(U32.is_lt(f, 100), 100, D.sel_u32(U32.is_gt(f, 1000), 1000, f))

def zip317_line(+k: U32, +conv: U32, +size: U32, +lo: U32, +hi: U32) -> String:
  +neg = U32.is_ge(hi, 2147483648)
  +u = unpaid(conv, lo, hi)
  +mf = min_fee(size)
  +low = U32.is_eq(hi, 0) && U32.is_lt(lo, mf)
  "zip317 " ++ U32.show(k) ++ " unpaid " ++ U32.show(u) ++ " min_fee " ++ U32.show(mf) ++ " "
    ++ sel_s(neg, "FAIL negative_fee", sel_s(U32.is_gt(u, 0), "FAIL unpaid_actions",
         sel_s(low, "FAIL fee_below_min_rate", "PASS"))) ++ "\n"

# ---------------------------------------------------------------- standardness

# zcashd CScript::IsPushOnly: every opcode can be read (GetOp) and is <= OP_16 (0x60).
def po_loop(fuel: Nat, live: Bool, +xs: +List<U32>, +rem: U32) -> Bool:
  match fuel live:
    case 0n _:
      U32.is_eq(rem, 0)
    case 1n+p False{}:
      U32.is_eq(rem, 0)
    case 1n+p True{}:
      +op = H.at(xs, 0)
      +t = H.drop(xs, 1)
      +hl = D.push_hl(op)
      +n = D.push_n(op, t)
      +rest = H.drop(t, (hl + n : U32))
      +r2 = (rem - 1 - hl - n : U32)
      U32.is_le(op, 96) && po_loop(p, D.sig_live(rest, r2), rest, r2)

def push_only(+s: +List<U32>) -> Bool:
  +n = H.length(s)
  po_loop(U32.to_nat((n + 1 : U32)), D.sig_live(s, n), s, n)

# 0 ok, 1 scriptsig_too_large, 2 scriptsig_not_push_only
def ins_std(xs: +List<P.TIn>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{i, t}:
      P.TIn{_, _, +s, _} = i
      D.sel_u32(U32.is_gt(H.length(s), 1650), 1, D.sel_u32(push_only(s), ins_std(t), 2))

def b_is(+s: +List<U32>, +i: U32, +v: U32) -> Bool:
  U32.is_eq(H.at(s, i), v)

def is_p2pkh(+s: +List<U32>) -> Bool:
  U32.is_eq(H.length(s), 25) && b_is(s, 0, 118) && b_is(s, 1, 169) && b_is(s, 2, 20) && b_is(s, 23, 136) && b_is(s, 24, 172)

def is_p2sh(+s: +List<U32>) -> Bool:
  U32.is_eq(H.length(s), 23) && b_is(s, 0, 169) && b_is(s, 1, 20) && b_is(s, 22, 135)

# zcashd Solver template OP_PUBKEY OP_CHECKSIG: a direct push of 33..65 bytes, then OP_CHECKSIG.
def is_p2pk(+s: +List<U32>) -> Bool:
  +n = H.length(s)
  U32.is_ge(n, 35) && U32.is_le(n, 67) && b_is(s, 0, (n - 2 : U32)) && b_is(s, (n - 1 : U32), 172)

def is_nulldata(+s: +List<U32>) -> Bool:
  U32.is_ge(H.length(s), 1) && b_is(s, 0, 106) && push_only(H.drop(s, 1))

def is_dust(+v: H.U64, +osz: U32) -> Bool:
  H.U64{+lo, +hi} = v
  +thr = (3 * ((100 * (osz + 148)) / 1000) : U32)
  U32.is_eq(hi, 0) && U32.is_lt(lo, thr)

# ---------------------------------------------------------------- AreInputsStandard (Zebra are_inputs_standard)

def sel_l(b: Bool, +x: +List<U32>, +y: +List<U32>) -> +List<U32>:
  match b:
    case True{}:
      x
    case False{}:
      y

# The stack item a push opcode leaves: its data (direct pushes, PUSHDATA1/2/4), [] for OP_0,
# [0x81] for OP_1NEGATE, [n] for OP_1..OP_16.
def item(+op: U32, +t: +List<U32>) -> +List<U32>:
  sel_l(U32.is_le(op, 78), H.take(H.drop(t, D.push_hl(op)), D.push_n(op, t)),
    sel_l(U32.is_eq(op, 79), 129 <> Nil{}, (op - 80 : U32) <> Nil{}))

# Walk of a push-only scriptSig: number of pushes (= stack depth), the last pushed item, and
# whether every opcode is a push that executes (OP_RESERVED does not).
type SW is Data:
  SW{n: U32, last: +List<U32>, ok: Bool}

def sw_loop(fuel: Nat, live: Bool, +xs: +List<U32>, +rem: U32, +n: U32, +last: +List<U32>, +ok: Bool) -> SW:
  match fuel live:
    case 0n _:
      SW{n, last, ok && U32.is_eq(rem, 0)}
    case 1n+p False{}:
      SW{n, last, ok && U32.is_eq(rem, 0)}
    case 1n+p True{}:
      +op = H.at(xs, 0)
      +t = H.drop(xs, 1)
      +hl = D.push_hl(op)
      +k = D.push_n(op, t)
      +rest = H.drop(t, (hl + k : U32))
      +r2 = (rem - 1 - hl - k : U32)
      sw_loop(p, D.sig_live(rest, r2), rest, r2, (n + 1 : U32), item(op, t),
        ok && U32.is_le(op, 96) && Bool.not(U32.is_eq(op, 80)))

def walk(+s: +List<U32>) -> SW:
  +n = H.length(s)
  sw_loop(U32.to_nat((n + 1 : U32)), D.sig_live(s, n), s, n, 0, Nil{}, True{})

# Multisig template: OP_m, k pushes of 33..65-byte keys, OP_n (n = k, m <= n), OP_CHECKMULTISIG.
type PK is Data:
  PK{k: U32, xs: +List<U32>, rem: U32}

def is_pk_push(+xs: +List<U32>, +rem: U32) -> Bool:
  +l = H.at(xs, 0)
  U32.is_ge(rem, 1) && U32.is_ge(l, 33) && U32.is_le(l, 65) && U32.is_le((l + 1 : U32), rem)

def pk_loop(fuel: Nat, more: Bool, +xs: +List<U32>, +rem: U32, +k: U32) -> PK:
  match fuel more:
    case 0n _:
      PK{k, xs, rem}
    case 1n+p False{}:
      PK{k, xs, rem}
    case 1n+p True{}:
      +l = H.at(xs, 0)
      +rest = H.drop(xs, (1 + l : U32))
      +r2 = (rem - 1 - l : U32)
      pk_loop(p, is_pk_push(rest, r2), rest, r2, (k + 1 : U32))

def ms_tail(r: PK, +m: U32) -> Bool:
  PK{+k, +xs, +rem} = r
  +nop = H.at(xs, 0)
  U32.is_eq(rem, 2) && U32.is_ge(nop, 81) && U32.is_le(nop, 96) && U32.is_eq((nop - 80 : U32), k)
    && U32.is_le(m, k) && U32.is_ge(m, 1) && b_is(xs, 1, 174)

def is_ms_std(+s: +List<U32>) -> Bool:
  +n = H.length(s)
  +m = H.at(s, 0)
  +body = H.drop(s, 1)
  +rb = (n - 1 : U32)
  U32.is_ge(n, 3) && U32.is_ge(m, 81) && U32.is_le(m, 96)
    && ms_tail(pk_loop(U32.to_nat(n), is_pk_push(body, rb), body, rb, 0), (m - 80 : U32))

# zcashd ScriptSigArgsExpected: P2PKH 2, P2PK 1, P2SH 1, multisig m + 1; 255 = not standard
# (non-standard script or OP_RETURN).
def args_expected(+s: +List<U32>) -> U32:
  D.sel_u32(is_p2pkh(s), 2, D.sel_u32(is_p2sh(s), 1, D.sel_u32(is_p2pk(s), 1,
    D.sel_u32(is_ms_std(s), (H.at(s, 0) - 80 + 1 : U32), 255))))

# Accurate sigop count (GetSigOpCount(true)): CHECKMULTISIG(VERIFY) after OP_1..OP_16 counts n, else 20.
def acc_cost(+op: U32, +prev: U32) -> U32:
  D.sel_u32(U32.is_eq(op, 172) || U32.is_eq(op, 173), 1,
    D.sel_u32(U32.is_eq(op, 174) || U32.is_eq(op, 175),
      D.sel_u32(U32.is_ge(prev, 81) && U32.is_le(prev, 96), (prev - 80 : U32), 20), 0))

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
      +k = D.push_n(op, t)
      +rest = H.drop(t, (hl + k : U32))
      +r2 = (rem - 1 - hl - k : U32)
      acc_loop(p, D.sig_live(rest, r2), rest, r2, op, (acc + acc_cost(op, prev) : U32))

def acc_sigops(+s: +List<U32>) -> U32:
  +n = H.length(s)
  acc_loop(U32.to_nat((n + 1 : U32)), D.sig_live(s, n), s, n, 255, 0)

# One input (Zebra are_inputs_standard, per input): the spent script is standard; for P2SH the
# redeemed script (the last push) is standard (its args are added) or else has <= 15 accurate
# sigops (then the input is accepted as is); the scriptSig pushes exactly the expected items.
def sel_b(b: Bool, x: Bool, y: Bool) -> Bool:
  match b:
    case True{}:
      x
    case False{}:
      y

def p2sh_ok(w: SW, +e: U32) -> Bool:
  SW{+n, +last, +ok} = w
  +e2 = args_expected(last)
  ok && U32.is_ge(n, 1) && sel_b(U32.is_eq(e2, 255), U32.is_le(acc_sigops(last), 15), U32.is_eq(n, (e + e2 : U32)))

def plain_ok(w: SW, +e: U32) -> Bool:
  SW{+n, _, +ok} = w
  ok && U32.is_eq(n, e)

def in_std(+sig: +List<U32>, +spk: +List<U32>) -> Bool:
  +e = args_expected(spk)
  +w = walk(sig)
  Bool.not(U32.is_eq(e, 255)) && sel_b(is_p2sh(spk), p2sh_ok(w, e), plain_ok(w, e))

# The spent scripts blob: per input u32 LE length | scriptPubKey.
def blob_next(+b: +List<U32>) -> +List<U32>:
  H.drop(b, (4 + H.le32(b) : U32))

def blob_head(+b: +List<U32>) -> +List<U32>:
  H.take(H.drop(b, 4), H.le32(b))

# 0 ok, 9 non_standard_inputs (also when the blob does not have one script per input)
def ins_std2(xs: +List<P.TIn>, +b: +List<U32>) -> U32:
  match xs:
    case Nil{}:
      D.sel_u32(U32.is_eq(H.length(b), 0), 0, 9)
    case Con{i, +t}:
      P.TIn{_, _, +s, _} = i
      +r = ins_std2(t, blob_next(b))
      D.sel_u32(U32.is_ge(H.length(b), 4) && in_std(s, blob_head(b)), r, 9)

# 0 standard (not OP_RETURN), 100 OP_RETURN within the limit, 3 scriptpubkey_nonstandard,
# 4 bare_multisig, 5 datacarrier_too_large, 6 dust
def out_code(+v: H.U64, +s: +List<U32>) -> U32:
  +n = H.length(s)
  +osz = (8 + cs_len(n) + n : U32)
  D.sel_u32(is_p2pkh(s) || is_p2sh(s) || is_p2pk(s), D.sel_u32(is_dust(v, osz), 6, 0),
    D.sel_u32(is_nulldata(s), D.sel_u32(U32.is_gt(n, 83), 5, 100),
      D.sel_u32(is_ms_std(s), 4, 3)))

# ... 7 multi_op_return. One recursive call per output (both arms of sel_u32 are evaluated).
def outs_std(xs: +List<P.TOut>, +nd: U32) -> U32:
  match xs:
    case Nil{}:
      D.sel_u32(U32.is_gt(nd, 1), 7, 0)
    case Con{o, +t}:
      P.TOut{+v, +s} = o
      +c = out_code(v, s)
      +r = outs_std(t, (nd + D.sel_u32(U32.is_eq(c, 100), 1, 0) : U32))
      D.sel_u32(U32.is_eq(c, 0) || U32.is_eq(c, 100), r, c)

# ... 8 too_many_sigops
def std_code(+ins: +List<P.TIn>, +outs: +List<P.TOut>, +sigops: U32, +spent: Bool, +blob: +List<U32>) -> U32:
  +a = ins_std(ins)
  +b = D.sel_u32(spent, ins_std2(ins, blob), 0)
  D.sel_u32(U32.is_eq(a, 0), D.sel_u32(U32.is_eq(b, 0), D.sel_u32(U32.is_gt(sigops, 4000), 8, outs_std(outs, 0)), b), a)

def reason(+c: U32) -> String:
  sel_s(U32.is_eq(c, 0), "PASS",
  sel_s(U32.is_eq(c, 1), "FAIL scriptsig_too_large",
  sel_s(U32.is_eq(c, 2), "FAIL scriptsig_not_push_only",
  sel_s(U32.is_eq(c, 3), "FAIL scriptpubkey_nonstandard",
  sel_s(U32.is_eq(c, 4), "FAIL bare_multisig",
  sel_s(U32.is_eq(c, 5), "FAIL datacarrier_too_large",
  sel_s(U32.is_eq(c, 6), "FAIL dust",
  sel_s(U32.is_eq(c, 7), "FAIL multi_op_return",
  sel_s(U32.is_eq(c, 8), "FAIL too_many_sigops", "FAIL non_standard_inputs")))))))))

# ---------------------------------------------------------------- one record

def auth_hex(v5: Bool, +xs: +List<U32>) -> String:
  match v5:
    case True{}:
      U.bhex(K.auth56(xs, T.parse(xs)))
    case False{}:
      "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

def has_fee_lines(has: Bool, +k: U32, +conv: U32, +size: U32, +lo: U32, +hi: U32) -> String:
  match has:
    case True{}:
      zip317_line(k, conv, size, lo, hi)
    case False{}:
      ""

def tx_body(+k: U32, +lo: U32, +hi: U32, +has: U32, +sigops: U32, +blob: +List<U32>, +c: P.C, t: P.Tx) -> String:
  P.Tx{+ver, _, _, _, +ins, +outs, _, _, +js, +sap, +orch, +iron, +size} = t
  +v5 = U32.is_ge(ver, 5)
  +la = logical(ins, outs, js, sap, orch, iron)
  +ca = max32(la, 2)
  "tx " ++ U32.show(k) ++ " v " ++ U32.show(ver) ++ " txid " ++ D.hexd(D.txid_sel(v5, c, size))
    ++ " auth " ++ auth_hex(v5, P.c_xs(c)) ++ " size " ++ U32.show(size) ++ " actions " ++ U32.show(la)
    ++ " conv_actions " ++ U32.show(ca) ++ " conv_fee " ++ U32.show((ca * 1000 : U32)) ++ "\n"
    ++ has_fee_lines(U32.is_eq((has .&. 1 : U32), 1), k, ca, size, lo, hi)
    ++ "std " ++ U32.show(k) ++ " " ++ reason(std_code(ins, outs, sigops, U32.is_eq((has >> 1n : U32), 1), blob)) ++ "\n"

def tx_report(+k: U32, +lo: U32, +hi: U32, +has: U32, +sigops: U32, +blob: +List<U32>, +blk: +List<U32>) -> String:
  +c = P.cs_c(P.cs(P.skip(P.start(blk), 1487)))
  tx_body(k, lo, hi, has, sigops, blob, c, P.tx(c))

def gated(m: Maybe<&2, U32>, +k: U32, +lo: U32, +hi: U32, +has: U32, +sigops: U32, +blob: +List<U32>, +blk: +List<U32>) -> String:
  match m:
    case Some{_}:
      tx_report(k, lo, hi, has, sigops, blob, blk)
    case None{}:
      "tx " ++ U32.show(k) ++ " INVALID wire\n"

def rec_out(+k: U32, +lo: U32, +hi: U32, +has: U32, +sigops: U32, +blob: +List<U32>, +blk: +List<U32>) -> String:
  gated(KB.parse_capped(blk), k, lo, hi, has, sigops, blob, blk)

# ---------------------------------------------------------------- the records file

type Hd is Data:
  Stop{}
  Rec{n: U32, lo: U32, hi: U32, has: U32, sigops: U32, m: U32, off: U32}

def hd_sel(full: Bool, +bs: +List<U32>, +off: U32) -> Hd:
  match full:
    case False{}:
      Stop{}
    case True{}:
      Rec{H.le32(bs), H.le32(H.drop(bs, 4)), H.le32(H.drop(bs, 8)), H.le32(H.drop(bs, 12)), H.le32(H.drop(bs, 16)),
          H.le32(H.drop(bs, 20)), off}

def head_of(+bs: +List<U32>, +off: U32) -> Hd:
  hd_sel(U32.is_eq(H.length(bs), 24), bs, off)

def loop(fuel: Nat, st: Hd, +k: U32, +path: String) -> IO(Unit):
  match fuel st:
    case 0n _:
      IO.pure(Unit, Unit{})
    case 1n+p Stop{}:
      IO.pure(Unit, Unit{})
    case 1n+p Rec{+n, +lo, +hi, +has, +sigops, +m, +off}:
      +next = (off + 24 + n + m : U32)
      do IO<Unit>:
        blk : +List<U32> <- D.read_at(path, (off + 24 : U32), n)
        blob : +List<U32> <- D.read_at(path, (off + 24 + n : U32), m)
        IO.print(rec_out(k, lo, hi, has, sigops, blob, blk))
        nh : +List<U32> <- D.read_at(path, next, 24)
        loop(p, head_of(nh, next), (k + 1 : U32), path)

def run(+path: String) -> IO(Unit):
  do IO<Unit>:
    h0 : +List<U32> <- D.read_at(path, 0, 24)
    loop(1000000n, head_of(h0, 0), 0, path)

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<String> <- IO.args()
    run(D.path_of(xs))
