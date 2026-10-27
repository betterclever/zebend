# fullnode blockdelta: parse a window of raw mainnet blocks (any era) and print each block's
# state deltas: txids, transparent inputs/outputs, Sprout JoinSplits, Sapling spends/outputs,
# Orchard and Ironwood actions, plus the checks a checkpointed block needs: the header is
# byte-identical to the verified header at its height, and the txids hash to its merkle root.
#
# Usage: blockdelta <window.bin>
#   window.bin: records until EOF: u32 LE height | 1487-byte verified header | u32 LE length | block
# Every block first goes through zcash/wire's hardened validator (blk.bend parse_capped:
# header form, canonical capped CompactSizes, every tx well-formed for its version, exact
# end, <= 2,000,000 bytes); a rejected block prints "block <h> INVALID wire".
import Base
import ./parse.bend as P
import ../../../zcash/wire/hb.bend as H
import ../../../zcash/wire/blk.bend as KB
import ../../../zcash/block/block.bend as K
import ./zip244.bend as Z
import ../../../zcash/block/sha256.bend as S
import ../../../zcash/block/bytes.bend as Y
import ../../../zcash/block/util.bend as U
import ../../../zcash/halo2/lib/words.bend as Wd

# ---------------------------------------------------------------- formatting

# u64 as 4 16-bit limbs, most significant first.
type L4 is Data:
  L4{a: U32, b: U32, c: U32, d: U32}

# One long division by 10: quotient limbs and remainder.
type QR is Data:
  QR{q: L4, r: U32}

type BR is Data:
  BR{ids: List<&2, +List<U32>>, out: String}

# A record header: height, verified header, block length, at offset off.
type Hd is Data:
  Stop{}
  Rec{h: U32, exp: +List<U32>, blen: U32, off: U32}

def hexd(+xs: +List<U32>) -> String:
  U.bhex(Y.reverse(xs))

def hex8(+x: U32) -> String:
  Wd.hex_byte((x >> 24n : U32)) ++ Wd.hex_byte(((x >> 16n) .&. 255 : U32)) ++ Wd.hex_byte(((x >> 8n) .&. 255 : U32)) ++ Wd.hex_byte((x .&. 255 : U32))

def digit(+d: U32) -> String:
  SCon{Char.from_u32((48 + d : U32)), SNil{}}

def l4_zero(l: L4) -> Bool:
  L4{+a, +b, +c, +d} = l
  U32.is_eq((a .|. b .|. c .|. d : U32), 0)

def qr_q(d: QR) -> L4:
  QR{+q, _} = d
  q

def qr_r(d: QR) -> U32:
  QR{_, +r} = d
  r

def div10(l: L4) -> QR:
  L4{+a, +b, +c, +d} = l
  +ra = (a % 10 : U32)
  +xb = (ra * 65536 + b : U32)
  +rb = (xb % 10 : U32)
  +xc = (rb * 65536 + c : U32)
  +rc = (xc % 10 : U32)
  +xd = (rc * 65536 + d : U32)
  QR{L4{(a / 10 : U32), (xb / 10 : U32), (xc / 10 : U32), (xd / 10 : U32)}, (xd % 10 : U32)}

def limbs(v: H.U64) -> L4:
  H.U64{+lo, +hi} = v
  L4{(hi >> 16n : U32), (hi .&. 65535 : U32), (lo >> 16n : U32), (lo .&. 65535 : U32)}

def udec_n(fuel: Nat, z: Bool, +l: L4, acc: String) -> String:
  match fuel z:
    case 0n _:
      acc
    case 1n+p True{}:
      acc
    case 1n+p False{}:
      +d = div10(l)
      udec_n(p, l4_zero(qr_q(d)), qr_q(d), digit(qr_r(d)) ++ acc)

def udec_sel(z: Bool, +l: L4) -> String:
  match z:
    case True{}:
      "0"
    case False{}:
      udec_n(21n, False{}, l, "")

def udec_l(+l: L4) -> String:
  udec_sel(l4_zero(l), l)

# Decimal digits of an unsigned 64-bit value (at most 20 digits).
def udec(+v: H.U64) -> String:
  udec_l(limbs(v))

def carry(b: Bool) -> U32:
  match b:
    case True{}:
      1
    case False{}:
      0

# Two's complement negation of a u64.
def neg64(v: H.U64) -> H.U64:
  H.U64{+lo, +hi} = v
  +nlo = (U32.not(lo) + 1 : U32)
  H.U64{nlo, (U32.not(hi) + carry(U32.is_eq(nlo, 0)) : U32)}

def sdec_sel(neg: Bool, +v: H.U64) -> String:
  match neg:
    case True{}:
      "-" ++ udec(neg64(v))
    case False{}:
      udec(v)

def hi_of(v: H.U64) -> U32:
  H.U64{_, +hi} = v
  hi

# Decimal of a signed 64-bit value (valueBalance, vpub, amounts).
def sdec(+v: H.U64) -> String:
  sdec_sel(U32.is_eq((hi_of(v) >> 31n : U32), 1), v)

def bit(b: Bool) -> String:
  match b:
    case True{}:
      "1"
    case False{}:
      "0"

def verdict(b: Bool) -> String:
  match b:
    case True{}:
      "MATCH"
    case False{}:
      "MISMATCH"

# ---------------------------------------------------------------- legacy sigops (zcashd GetSigOpCount(false))

def sel_u32(b: Bool, +x: U32, +y: U32) -> U32:
  match b:
    case True{}:
      x
    case False{}:
      y

# Header bytes of a push opcode: PUSHDATA1/2/4 = 1/2/4, else 0.
def push_hl(+op: U32) -> U32:
  sel_u32(U32.is_eq(op, 76), 1, sel_u32(U32.is_eq(op, 77), 2, sel_u32(U32.is_eq(op, 78), 4, 0)))

# Payload bytes of a push opcode (0..75: the opcode itself), read from t (after the opcode).
def push_n(+op: U32, +t: +List<U32>) -> U32:
  sel_u32(U32.is_lt(op, 76), op, sel_u32(U32.is_eq(op, 76), H.at(t, 0),
    sel_u32(U32.is_eq(op, 77), H.le16(t), sel_u32(U32.is_eq(op, 78), H.le32(t), 0))))

def op_cost(+op: U32) -> U32:
  sel_u32(U32.is_eq(op, 172) || U32.is_eq(op, 173), 1, sel_u32(U32.is_eq(op, 174) || U32.is_eq(op, 175), 20, 0))

# Whether the opcode at xs can be read (GetOp succeeds): bytes remain and the push fits.
def sig_live(+xs: +List<U32>, +rem: U32) -> Bool:
  +op = H.at(xs, 0)
  +r1 = (rem - 1 : U32)
  +hl = push_hl(op)
  +n = push_n(op, H.drop(xs, 1))
  Bool.not(U32.is_eq(rem, 0)) && U32.is_le(hl, r1) && U32.is_le(n, (r1 - hl : U32))

# One def: fuel shrinks every opcode; `live` is whether the next opcode can be read.
def sig_loop(fuel: Nat, live: Bool, +xs: +List<U32>, +rem: U32, +acc: U32) -> U32:
  match fuel live:
    case 0n _:
      acc
    case 1n+p False{}:
      acc
    case 1n+p True{}:
      +op = H.at(xs, 0)
      +t = H.drop(xs, 1)
      +hl = push_hl(op)
      +n = push_n(op, t)
      +rest = H.drop(t, (hl + n : U32))
      +r2 = (rem - 1 - hl - n : U32)
      sig_loop(p, sig_live(rest, r2), rest, r2, (acc + op_cost(op) : U32))

def script_sigops(+s: +List<U32>) -> U32:
  +n = H.length(s)
  sig_loop(U32.to_nat((n + 1 : U32)), sig_live(s, n), s, n, 0)

def ins_sigops(xs: +List<P.TIn>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{i, t}:
      P.TIn{_, _, +s, _} = i
      (script_sigops(s) + ins_sigops(t) : U32)

def outs_sigops(xs: +List<P.TOut>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{o, t}:
      P.TOut{_, +s} = o
      (script_sigops(s) + outs_sigops(t) : U32)

# ---------------------------------------------------------------- lines

def is_null_prev(+prev: +List<U32>, +idx: U32) -> Bool:
  U32.is_eq(idx, 4294967295) && Y.is_eq(prev, Y.zeros(32n))

def in_line(null: Bool, +k: U32, i: P.TIn) -> String:
  match null:
    case True{}:
      P.TIn{_, _, +s, +q} = i
      "cb " ++ U.bhex(s) ++ " " ++ U32.show(q) ++ "\n"
    case False{}:
      P.TIn{+prev, +idx, _, +q} = i
      "in " ++ U32.show(k) ++ " " ++ hexd(prev) ++ " " ++ U32.show(idx) ++ " " ++ U32.show(q) ++ "\n"

def null_of(i: P.TIn) -> Bool:
  P.TIn{+prev, +idx, _, _} = i
  is_null_prev(prev, idx)

def in_lines(xs: +List<P.TIn>, +k: U32) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+i, t}:
      in_line(null_of(i), k, i) ++ in_lines(t, (k + 1 : U32))

def out_lines(xs: +List<P.TOut>, +k: U32) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{o, t}:
      P.TOut{+v, +s} = o
      "out " ++ U32.show(k) ++ " " ++ udec(v) ++ " " ++ U.bhex(s) ++ "\n" ++ out_lines(t, (k + 1 : U32))

def js_lines(xs: +List<P.Js>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{j, t}:
      P.Js{+o, +n, +a, +n1, +n2, +c1, +c2} = j
      "js " ++ udec(o) ++ " " ++ udec(n) ++ " " ++ U.bhex(a) ++ " " ++ U.bhex(n1) ++ " " ++ U.bhex(n2) ++ " "
        ++ U.bhex(c1) ++ " " ++ U.bhex(c2) ++ "\n" ++ js_lines(t)

def ss_lines(xs: +List<P.SSp>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{s, t}:
      P.SSp{+a, +nf} = s
      "ss " ++ U.bhex(a) ++ " " ++ U.bhex(nf) ++ "\n" ++ ss_lines(t)

def so_lines(xs: +List<+List<U32>>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{+c, t}:
      "so " ++ U.bhex(c) ++ "\n" ++ so_lines(t)

def len_sp(xs: +List<P.SSp>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{_, t}:
      (1 + len_sp(t) : U32)

def len_bs(xs: +List<+List<U32>>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{_, t}:
      (1 + len_bs(t) : U32)

def sap_any(any: Bool, s: P.Sap) -> String:
  match any:
    case False{}:
      ""
    case True{}:
      P.Sap{+vb, +sp, +op, _} = s
      "sap " ++ sdec(vb) ++ " " ++ U32.show(len_sp(sp)) ++ " " ++ U32.show(len_bs(op)) ++ "\n" ++ ss_lines(sp) ++ so_lines(op)

def sap_lines(+s: P.Sap) -> String:
  P.Sap{_, +sp, +op, _} = s
  sap_any(Bool.not(P.nil_sp(sp) && P.nil_bs(op)), s)

def act_lines(+tag: String, xs: +List<P.Act>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{a, t}:
      P.Act{+nf, +cmx} = a
      tag ++ " " ++ U.bhex(nf) ++ " " ++ U.bhex(cmx) ++ "\n" ++ act_lines(tag, t)

def len_acts(xs: +List<P.Act>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{_, t}:
      (1 + len_acts(t) : U32)

def bun_sel(present: Bool, +name: String, +tag: String, +vb: H.U64, +anchor: +List<U32>, +flags: U32, +acts: +List<P.Act>) -> String:
  match present:
    case False{}:
      ""
    case True{}:
      name ++ " " ++ sdec(vb) ++ " " ++ U.bhex(anchor) ++ " " ++ Wd.hex_byte(flags) ++ " " ++ U32.show(len_acts(acts)) ++ "\n"
        ++ act_lines(tag, acts)

def bun_lines(+name: String, +tag: String, b: P.Bun) -> String:
  P.Bun{present, +vb, +anchor, +flags, +acts, _} = b
  bun_sel(present, name, tag, vb, anchor, flags, acts)

def tx_lines(+k: U32, +txid: +List<U32>, t: P.Tx) -> String:
  P.Tx{+ver, +ow, +grp, +br, +ins, +outs, +lock, +exp, +js, +sap, +orch, +iron, +size} = t
  "tx " ++ U32.show(k) ++ " " ++ hexd(txid) ++ " v " ++ U32.show(ver) ++ " ow " ++ bit(ow) ++ " grp " ++ hex8(grp)
    ++ " br " ++ hex8(br) ++ " lock " ++ U32.show(lock) ++ " exp " ++ U32.show(exp) ++ " size " ++ U32.show(size)
    ++ " sigops " ++ U32.show((ins_sigops(ins) + outs_sigops(outs) : U32)) ++ "\n"
    ++ in_lines(ins, 0) ++ out_lines(outs, 0) ++ js_lines(js) ++ sap_lines(sap)
    ++ bun_lines("orch", "oa", orch) ++ bun_lines("iw", "ia", iron)

# ---------------------------------------------------------------- blocks

# v1-v4: SHA-256d of the raw transaction; v5/v6: the ZIP 244 txid (zcash/block, zcash/tx).
def txid_sel(v5: Bool, +c: P.C, +size: U32) -> +List<U32>:
  match v5:
    case True{}:
      Z.txid56(P.c_xs(c))
    case False{}:
      Y.zeros(32n)

def br_ids(r: BR) -> List<&2, +List<U32>>:
  BR{+i, _} = r
  i

def br_out(r: BR) -> String:
  BR{_, +o} = r
  o

def txs(n: Nat, +k: U32, +c: P.C) -> BR:
  match n:
    case 0n:
      BR{Nil{}, ""}
    case 1n+m:
      +t = P.tx(c)
      +size = P.tx_size(t)
      +id = txid_sel(U32.is_ge(P.tx_ver(t), 5), c, size)
      +rest = txs(m, (k + 1 : U32), P.skip(c, size))
      BR{id <> br_ids(rest), tx_lines(k, id, t) ++ br_out(rest)}

def report(+h: U32, +expected: +List<U32>, +blk: +List<U32>) -> String:
  +hdr = H.take(blk, 1487)
  +c = P.skip(P.start(blk), 1487)
  +n = P.cs(c)
  +r = txs(U32.to_nat(P.cs_v(n)), 0, P.cs_c(n))
  +mr = K.merkle_root(br_ids(r))
  "block " ++ U32.show(h) ++ " " ++ hexd(S.hash_d(hdr)) ++ " " ++ hexd(H.take(H.drop(hdr, 4), 32))
    ++ " time " ++ U32.show(H.le32(H.drop(hdr, 100))) ++ " bits " ++ hex8(H.le32(H.drop(hdr, 104)))
    ++ " size " ++ U32.show(H.length(blk)) ++ " txs " ++ U32.show(P.cs_v(n))
    ++ " header " ++ verdict(Y.is_eq(hdr, expected))
    ++ " merkle " ++ verdict(Y.is_eq(mr, H.take(H.drop(hdr, 36), 32))) ++ "\n"
    ++ br_out(r) ++ "end " ++ U32.show(h)

def gated(m: Maybe<&2, U32>, +h: U32, +expected: +List<U32>, +blk: +List<U32>) -> String:
  match m:
    case Some{_}:
      report(h, expected, blk)
    case None{}:
      "block " ++ U32.show(h) ++ " INVALID wire\nend " ++ U32.show(h)

def block_out(+h: U32, +expected: +List<U32>, +blk: +List<U32>) -> String:
  gated(KB.parse_capped(blk), h, expected, blk)

# ---------------------------------------------------------------- the window file

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
      Rec{H.le32(bs), H.take(H.drop(bs, 4), 1487), H.le32(H.drop(bs, 1491)), off}

def head_of(+bs: +List<U32>, +off: U32) -> Hd:
  hd_sel(U32.is_eq(H.length(bs), 1495), bs, off)

def loop(fuel: Nat, st: Hd, +path: String) -> IO(Unit):
  match fuel st:
    case 0n _:
      IO.pure(Unit, Unit{})
    case 1n+p Stop{}:
      IO.pure(Unit, Unit{})
    case 1n+p Rec{+h, +exp, +blen, +off}:
      +next = (off + 1495 + blen : U32)
      do IO<Unit>:
        blk : +List<U32> <- read_at(path, (off + 1495 : U32), blen)
        IO.print(block_out(h, exp, blk))
        nh : +List<U32> <- read_at(path, next, 1495)
        loop(p, head_of(nh, next), path)

def path_of(xs: List<String>) -> String:
  match xs:
    case Con{_, Con{p, _}}:
      p
    case _:
      ""

def run(+path: String) -> IO(Unit):
  do IO<Unit>:
    h0 : +List<U32> <- read_at(path, 0, 1495)
    loop(1000000n, head_of(h0, 0), path)

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<String> <- IO.args()
    run(path_of(xs))
