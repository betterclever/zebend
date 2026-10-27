# fullnode blockdelta: parse a window of raw mainnet blocks (any era) and print each block's
# state deltas: txids, transparent inputs/outputs, Sprout JoinSplits, Sapling spends/outputs,
# Orchard and Ironwood actions, plus the checks a checkpointed block needs: the header is
# byte-identical to the verified header at its height, and the txids hash to its merkle root.
#
# Usage: blockdelta <window.bin>
#   (node/fast: zcash/wire's curve-point decodings are deferred: ../wire/txv.bend only
#   consumes the 32 bytes, pts.bend lists the same fields and checks them in one batch per
#   part without square roots; SHA-256 and ZIP 244 copy each byte once (sha.bend,
#   zip244.bend). Output is identical to node/bend/delta.bend's, see research/fast/README.md.)
#   window.bin: records until EOF: u32 LE height | 1487-byte verified header | u32 LE length | block
# Every block first goes through zcash/wire's hardened validator (blk.bend parse_capped:
# header form, canonical capped CompactSizes, every tx well-formed for its version, exact
# end, <= 2,000,000 bytes); a rejected block prints "block <h> INVALID wire".
import Base
import ./parse.bend as P
import ../../../zcash/wire/hb.bend as H
import ../wire/blk.bend as KB
import ./pts.bend as T
import ../../../zcash/block/block.bend as K
import ./zip244.bend as Z
import ../../../zcash/block/sha256.bend as S
import ./sha.bend as S2
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
  BR{ids: List<&2, +List<U32>>, out: String, pts: +List<T.Pt>}

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
      S2.hash_d_n(P.c_xs(c), size)

def br_ids(r: BR) -> List<&2, +List<U32>>:
  BR{+i, _, _} = r
  i

def br_out(r: BR) -> String:
  BR{_, +o, _} = r
  o

def br_pts(r: BR) -> +List<T.Pt>:
  BR{_, _, +p} = r
  p

# Also collects the transaction's curve points (pts.bend) for the batched check.
def txs(n: Nat, +b: U32, +k: U32, +c: P.C) -> BR:
  match n:
    case 0n:
      BR{Nil{}, "", Nil{}}
    case 1n+m:
      +t = P.tx(c)
      +size = P.tx_size(t)
      +id = txid_sel(U32.is_ge(P.tx_ver(t), 5), c, size)
      +rest = txs(m, b, (k + 1 : U32), P.skip(c, size))
      BR{id <> br_ids(rest), tx_lines(k, id, t) ++ br_out(rest), T.tx(b, c, br_pts(rest))}

# A block the (structural) wire validator accepted: its lines and its curve points.
type Rep is Data:
  Rep{out: String, pts: +List<T.Pt>}

def report(+b: U32, +h: U32, +expected: +List<U32>, +blk: +List<U32>) -> Rep:
  +hdr = H.take(blk, 1487)
  +c = P.skip(P.start(blk), 1487)
  +n = P.cs(c)
  +r = txs(U32.to_nat(P.cs_v(n)), b, 0, P.cs_c(n))
  +mr = K.merkle_root(br_ids(r))
  Rep{"block " ++ U32.show(h) ++ " " ++ hexd(S2.hash_d_n(hdr, 1487)) ++ " " ++ hexd(H.take(H.drop(hdr, 4), 32))
    ++ " time " ++ U32.show(H.le32(H.drop(hdr, 100))) ++ " bits " ++ hex8(H.le32(H.drop(hdr, 104)))
    ++ " size " ++ U32.show(H.length(blk)) ++ " txs " ++ U32.show(P.cs_v(n))
    ++ " header " ++ verdict(Y.is_eq(hdr, expected))
    ++ " merkle " ++ verdict(Y.is_eq(mr, H.take(H.drop(hdr, 36), 32))) ++ "\n"
    ++ br_out(r) ++ "end " ++ U32.show(h), br_pts(r)}

def invalid(+h: U32) -> String:
  "block " ++ U32.show(h) ++ " INVALID wire\nend " ++ U32.show(h)

# One block's result before the point check: ok = the structural validator accepted it.
type Blk is Data:
  Blk{h: U32, ok: Bool, out: String}

type Acc is Data:
  Acc{bs: +List<Blk>, pts: +List<T.Pt>, n: U32}

def acc_ok(r: Rep, +h: U32, a: Acc) -> Acc:
  Rep{+out, +p} = r
  Acc{+bs, +ps, +n} = a
  Acc{Blk{h, True{}, out} <> bs, List.append(&2, T.Pt, p, ps), (n + 1 : U32)}

def acc_bad(+h: U32, a: Acc) -> Acc:
  Acc{+bs, +ps, +n} = a
  Acc{Blk{h, False{}, ""} <> bs, ps, (n + 1 : U32)}

def acc_n(a: Acc) -> U32:
  Acc{_, _, +n} = a
  n

def acc_add(m: Maybe<&2, U32>, +h: U32, +expected: +List<U32>, +blk: +List<U32>, +a: Acc) -> Acc:
  match m:
    case Some{_}:
      acc_ok(report(acc_n(a), h, expected, blk), h, a)
    case None{}:
      acc_bad(h, a)

# ---------------------------------------------------------------- the batched point check

type PT is Data:
  Leaf{ps: +List<T.Pt>}
  Node{l: PT, r: PT}

type RT is Data:
  RLeaf{bs: +List<U32>}
  RNode{l: RT, r: RT}

def bad_sel(ok: Bool, +b: U32, acc: +List<U32>) -> +List<U32>:
  match ok:
    case True{}:
      acc
    case False{}:
      b <> acc

# Indexes of the blocks owning a point that fails (tail-recursive: GPU lane stacks).
def leaf_check(ps: +List<T.Pt>, acc: +List<U32>) -> +List<U32>:
  match ps:
    case Nil{}:
      acc
    case Con{p, t}:
      T.Pt{+b, k, +w} = p
      leaf_check(t, bad_sel(T.pt_ok(k, w), b, acc))

def check(+k: Nat, t: PT) -> RT:
  match k t:
    case _ Leaf{ps}:
      RLeaf{leaf_check(ps, Nil{})}
    case 1n+j Node{l, r}:
      a b = check(j, l) check(j, r)
      RNode{a, b}
    case _ _:
      RLeaf{Nil{}}

def flatten(t: RT, acc: +List<U32>) -> +List<U32>:
  match t:
    case RLeaf{bs}:
      List.append(&2, U32, bs, acc)
    case RNode{l, r}:
      flatten(l, flatten(r, acc))

def leaf_size(c: Bool, +base: Nat) -> Nat:
  match c:
    case True{}:
      1n+base
    case False{}:
      base

def leaves(k: Nat, +base: Nat, +extra: Nat, ps: +List<T.Pt>) -> +List<PT>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      +p2 = ps
      +sz = leaf_size(Nat.is_lt(0n, extra), base)
      Leaf{List.take(&2, T.Pt, p2, sz)} <> leaves(p, base, Nat.sub(extra, 1n), List.drop(&2, T.Pt, p2, sz))

def pair_up(xs: +List<PT>) -> +List<PT>:
  match xs:
    case Con{a, Con{b, rest}}:
      Node{a, b} <> pair_up(rest)
    case Con{a, Nil{}}:
      [a]
    case Nil{}:
      Nil{}

def levels(k: Nat, xs: +List<PT>) -> +List<PT>:
  match k:
    case 0n:
      xs
    case 1n+p:
      levels(p, pair_up(xs))

def root(xs: +List<PT>) -> PT:
  match xs:
    case Con{t, _}:
      t
    case Nil{}:
      Leaf{Nil{}}

# Depth: the largest d <= dmax with 2^(d+1) <= n (at least 2 points per leaf); more: d + 1 fits.
def depth_of(fuel: Nat, more: Bool, +d: Nat, +n: Nat) -> Nat:
  match fuel more:
    case 0n _:
      d
    case 1n+p False{}:
      d
    case 1n+p True{}:
      depth_of(p, Nat.is_le(Nat.pow(2n, 1n+(1n+(1n+d))), n), 1n+d, n)

# The batch, sequentially on the CPU (one process per window part is the parallelism).
# gpu_variant.py writes delta_gpu.bend, which runs it as a balanced tree under `check!`.
def bad_blocks(any: Bool, +dmax: Nat, +ps: +List<T.Pt>) -> +List<U32>:
  match any:
    case False{}:
      Nil{}
    case True{}:
      +n = List.length(&2, T.Pt, ps)
      +d = depth_of(dmax, Nat.is_le(4n, n), 0n, n)
      +lanes = Nat.pow(2n, d)
      +tree = root(levels(d, leaves(lanes, Nat.div(n, lanes), Nat.mod(n, lanes), ps)))
      flatten(check!(d, tree), Nil{})

def member(xs: +List<U32>, +x: U32) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{+y, t}:
      U32.is_eq(x, y) || member(t, x)

def nil_pts(xs: +List<T.Pt>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{_, _}:
      False{}

def line_sel(ok: Bool, +h: U32, +out: String) -> String:
  match ok:
    case True{}:
      out
    case False{}:
      invalid(h)

def blk_line(b: Blk, +ok_pts: Bool) -> String:
  Blk{+h, +ok, +out} = b
  line_sel(ok && ok_pts, h, out)

# Blocks in window order (bs is newest first); i counts from the last block's index down.
def emit(bs: +List<Blk>, +bad: +List<U32>, +i: U32, acc: +List<String>) -> +List<String>:
  match bs:
    case Nil{}:
      acc
    case Con{b, t}:
      emit(t, bad, (i - 1 : U32), blk_line(b, Bool.not(member(bad, i))) <> acc)

def print_all(xs: +List<String>) -> IO(Unit):
  match xs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{s, t}:
      do IO<Unit>:
        IO.print(s)
        print_all(t)

def finish(a: Acc, +dmax: Nat) -> IO(Unit):
  Acc{+bs, +ps, +n} = a
  +bad = bad_blocks(Bool.not(nil_pts(ps)), dmax, ps)
  print_all(emit(bs, bad, (n - 1 : U32), Nil{}))

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

def block_in(+h: U32, +expected: +List<U32>, +blk: +List<U32>, +a: Acc) -> Acc:
  acc_add(KB.parse_capped(blk), h, expected, blk, a)

def loop(fuel: Nat, st: Hd, +path: String, a: Acc, +dmax: Nat) -> IO(Unit):
  match fuel st:
    case 0n _:
      finish(a, dmax)
    case 1n+p Stop{}:
      finish(a, dmax)
    case 1n+p Rec{+h, +exp, +blen, +off}:
      +next = (off + 1495 + blen : U32)
      do IO<Unit>:
        blk : +List<U32> <- read_at(path, (off + 1495 : U32), blen)
        a2 : Acc = block_in(h, exp, blk, a)
        nh : +List<U32> <- read_at(path, next, 1495)
        loop(p, head_of(nh, next), path, a2, dmax)

type Args is Data:
  Args{path: String, d: Nat}

def num(s: String) -> U32:
  Maybe.default(&2, U32, U32.read(s), 14)

def args_of(xs: List<String>) -> Args:
  match xs:
    case Con{_, Con{p, Con{d, _}}}:
      Args{p, U32.to_nat(num(d))}
    case Con{_, Con{p, _}}:
      Args{p, 14n}
    case _:
      Args{"", 14n}

def run(a: Args) -> IO(Unit):
  Args{+path, +d} = a
  do IO<Unit>:
    h0 : +List<U32> <- read_at(path, 0, 1495)
    loop(1000000n, head_of(h0, 0), path, Acc{Nil{}, Nil{}, 0}, d)

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<String> <- IO.args()
    run(args_of(xs))
