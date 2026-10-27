# history: the ZIP 221 history-tree check of a window of blocks, carrying the tree between windows.
# Usage: history <state.in | -> <window.bin> <side.bin> <state.out> [main|test]
#   window.bin: the full node's window (fullnode/sync.py window_file): records
#     u32 LE height | 1487-byte verified header | u32 LE block length | raw block
#     in height order.
#   side.bin: one 100-byte record per window block, same order:
#     u32 LE height | final Sapling root 32 | final Orchard root 32 | final Ironwood root 32
#     (the note commitment tree roots after the block, as the 32-byte LE field encoding used in
#     anchors / tree states; roots a block's node-data version does not use are ignored).
#     32 zero bytes = "unchanged since the previous block": the root is carried from the tree.
#   state.in / state.out: the tree (hist.bend: "ZHT1" binary format); "-" = no history.
# Per block prints
#   hist <h> MATCH|MISMATCH <header field hex> <computed hex> root <history root hex>
#   hist <h> n/a                (pre-Heartwood)
#   hist <h> SKIP no-history    (the state does not hold the tree of blocks up to h-1)
#   hist <h> MISMATCH side-height <side h> | MISMATCH block-header
# Everything per block is computed here from the raw block: block hash (SHA-256d of the
# header), nTime, nBits, per-pool tx counts (fullnode/bend/parse.bend), and for NU5+ the
# ZIP 244 hashAuthDataRoot (node/block/block.bend auth digests + tree).
import Base
import ./hist.bend as X
import ../../../fullnode/bend/parse.bend as P
import ../../../node/block/block.bend as K
import ../../../node/block/tx.bend as T
import ../../../node/block/sha256.bend as S
import ../../../node/block/bytes.bend as Y
import ../../../node/wire/hb.bend as H

type Hd is Data:
  Stop{}
  Rec{h: U32, exp: +List<U32>, blen: U32, off: U32}

# Auth digests (in tx order) and the three pool counts.
type BX is Data:
  BX{auths: List<&2, +List<U32>>, s: U32, o: U32, i: U32}

def ff32(+n: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      255 <> ff32(p)

def auth_sel(v5: Bool, +xs: +List<U32>) -> +List<U32>:
  match v5:
    case True{}:
      K.auth56(xs, T.parse(xs))
    case False{}:
      ff32(32n)

def sap_has(s: P.Sap) -> U32:
  P.Sap{_, +sp, +op, _} = s
  X.b2u(Bool.not(P.nil_sp(sp) && P.nil_bs(op)))

def bun_has(b: P.Bun) -> U32:
  P.Bun{+present, _, _, _, _, _} = b
  X.b2u(present)

def bx_add(+a: +List<U32>, +s: U32, +o: U32, +i: U32, r: BX) -> BX:
  BX{+as, +rs, +ro, +ri} = r
  BX{a <> as, (s + rs : U32), (o + ro : U32), (i + ri : U32)}

def tx_s(t: P.Tx) -> U32:
  P.Tx{_, _, _, _, _, _, _, _, _, +sap, _, _, _} = t
  sap_has(sap)

def tx_o(t: P.Tx) -> U32:
  P.Tx{_, _, _, _, _, _, _, _, _, _, +orch, _, _} = t
  bun_has(orch)

def tx_i(t: P.Tx) -> U32:
  P.Tx{_, _, _, _, _, _, _, _, _, _, _, +iron, _} = t
  bun_has(iron)

def txs(n: Nat, +c: P.C) -> BX:
  match n:
    case 0n:
      BX{Nil{}, 0, 0, 0}
    case 1n+m:
      +t = P.tx(c)
      bx_add(auth_sel(U32.is_ge(P.tx_ver(t), 5), P.c_xs(c)), tx_s(t), tx_o(t), tx_i(t), txs(m, P.skip(c, P.tx_size(t))))

def bx_s(r: BX) -> U32:
  BX{_, +x, _, _} = r
  x

def bx_o(r: BX) -> U32:
  BX{_, _, +x, _} = r
  x

def bx_i(r: BX) -> U32:
  BX{_, _, _, +x} = r
  x

def bx_auths(r: BX) -> List<&2, +List<U32>>:
  BX{+a, _, _, _} = r
  a

def side_ok(ok: Bool, +s: X.St, +h: U32, +exp: +List<U32>, +blk: +List<U32>, +side: +List<U32>) -> X.R:
  match ok:
    case False{}:
      X.R{"hist " ++ U32.show(h) ++ " MISMATCH side-height " ++ U32.show(H.le32(side)) ++ " or block-header", s}
    case True{}:
      +c = P.skip(P.start(blk), 1487)
      +n = P.cs(c)
      +bx = txs(U32.to_nat(P.cs_v(n)), P.cs_c(n))
      X.step(s, h, H.take(H.drop(exp, 68), 32), K.auth_root(bx_auths(bx)), True{}, S.hash_d(exp),
        H.le32(H.drop(exp, 100)), H.le32(H.drop(exp, 104)),
        X.carry(s, 0, H.take(H.drop(side, 4), 32)), X.carry(s, 1, H.take(H.drop(side, 36), 32)), X.carry(s, 2, H.take(H.drop(side, 68), 32)), bx_s(bx), bx_o(bx), bx_i(bx))

def block(+s: X.St, +h: U32, +exp: +List<U32>, +blk: +List<U32>, +side: +List<U32>) -> X.R:
  side_ok(Bool.and(U32.is_eq(H.le32(side), h), Y.is_eq(H.take(blk, 1487), exp)), s, h, exp, blk, side)

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
      Rec{H.le32(bs), H.take(H.drop(bs, 4), 1487), H.le32(H.drop(bs, 1491)), off}

def head_of(+bs: +List<U32>, +off: U32) -> Hd:
  hd_sel(U32.is_eq(H.length(bs), 1495), bs, off)

def close_pair(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, _) = r
  File.close(f)

def write_state(+p: String, +bs: +List<U32>) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(p, "w"))
    r : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, bs)
    close_pair(r)

def loop(fuel: Nat, st: Hd, +path: String, +sp: String, +k: U32, +s: X.St, +outp: String) -> IO(Unit):
  match fuel st:
    case 1n+p Rec{+h, +exp, +blen, +off}:
      +next = (off + 1495 + blen : U32)
      do IO<Unit>:
        +blk : +List<U32> <- read_at(path, (off + 1495 : U32), blen)
        +side : +List<U32> <- read_at(sp, (k * 100 : U32), 100)
        +r : X.R = block(s, h, exp, blk, side)
        IO.print(X.r_line(r))
        +nh : +List<U32> <- read_at(path, next, 1495)
        loop(p, head_of(nh, next), path, sp, (k + 1 : U32), X.r_st(r), outp)
    case _ _:
      write_state(outp, X.state_bytes(s))

def state_in(dash: Bool, +p: String, +net: U32) -> IO(X.St):
  match dash:
    case True{}:
      IO.pure(X.St, X.state_of(net, Nil{}))
    case False{}:
      do IO<X.St>:
        +hd : +List<U32> <- read_at(p, 0, 20)
        +xs : +List<U32> <- read_at(p, 0, (20 + H.le32(H.drop(hd, 16)) * 300 : U32))
        return X.state_of(net, xs)

def run(+sin: String, +win: String, +side: String, +sout: String, +net: U32) -> IO(Unit):
  do IO<Unit>:
    s : X.St <- state_in(String.eq(sin, "-"), sin, net)
    h0 : +List<U32> <- read_at(win, 0, 1495)
    loop(10000000n, head_of(h0, 0), win, side, 0, s, sout)

def go(xs: List<String>) -> IO(Unit):
  match xs:
    case Con{_, Con{a, Con{b, Con{c, Con{d, Con{e, _}}}}}}:
      run(a, b, c, d, X.b2u(String.eq(e, "test")))
    case Con{_, Con{a, Con{b, Con{c, Con{d, _}}}}}:
      run(a, b, c, d, 0)
    case _:
      IO.print("usage: history <state.in|-> <window.bin> <side.bin> <state.out> [main|test]")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<String> <- IO.args()
    go(xs)
