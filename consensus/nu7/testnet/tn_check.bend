# NU7 block rules on real TESTNET blocks, with the network-generic consensus/nu7 code (the same
# functions fullnode/rules/rules.bend runs with N7.Main{} on Mainnet).
#
# Usage: tn_check <blocks.bin> <ctx.bin>   (fullnode/rules formats; ctx.bin without the pools
#        header: per block u32 L | height | nt | times | spent transparent outputs)
# Per block, with Testnet parameters (NU6.3 at 4,134,000, NU7 at 4,465,026):
#   tx_version   NU7: every tx v5 (0x26A7270A) or v6 (0xD8853298), no v4 (ZIP 2003);
#                NU6.3: v4/v5/v6
#   branch_id    every v5/v6 tx carries the height's branch id (NU7 0x77190ad9, NU6.3 0x37a5165b)
#   issuance_required_outputs   FS_FPF_ZCG_H3 8% of the ZIP 218 subsidy to its P2SH address
#                while the Revision 2 streams are active (end 4,476,000 -> 4,497,948 at NU7)
#   miner_fees   coinbase out - shielded value balance + FS_CCF_H3 12% (lockbox)
#                == subsidy + MinerFees, MinerFees = fees - floor(6 fees / 10) from NU7 (ZIP 235)
#   shielded_action_limits   ZIP 218, from NU7
#   value_balance            every non-coinbase tx pays a fee >= 0
# Prints "tn <h> subsidy <s> fees <f> contribution <c> deferred <d> nsm <bal> <counts> verdict VALID|INVALID [fails]".
# The NSM value balance is carried across the file from 0 (it is only meaningful over a
# contiguous range starting before activation).
import Base
import ../../../fullnode/bend/parse.bend as P
import ../../../fullnode/bend/delta.bend as D
import ../rules/rules_nu7.bend as R
import ../../../node/wire/hb.bend as H
import ../../../node/wire/blk.bend as KB
import ../../../consensus/issuance/issuance.bend as I
import ../../../consensus/issuance/params.bend as IP
import ../../../consensus/issuance/cb_main.bend as CB
import ../nu7.bend as N7

def nu63_test() -> U32:
  4134000

def branch_test(+h: U32) -> U32:
  R.sel32(U32.is_ge(h, 4465026), 1998129881, R.sel32(U32.is_ge(h, nu63_test()), 933566043, 0))

def ver_ok(+h: U32, +v: U32, +ow: Bool, +g: U32) -> Bool:
  +v4 = ow && U32.is_eq(v, 4) && U32.is_eq(g, 2301567109)
  +v5 = ow && U32.is_eq(v, 5) && U32.is_eq(g, 648488714)
  +v6 = ow && U32.is_eq(v, 6) && U32.is_eq(g, 3632576152)
  (U32.is_ge(h, 4465026) && (v5 || v6)) || (U32.is_lt(h, 4465026) && (v4 || v5 || v6))

def vline(t: P.Tx, +h: U32, +k: U32) -> String:
  P.Tx{+ver, +ow, +grp, +br, _, _, _, _, _, _, _, _, _} = t
  R.when(Bool.not(ver_ok(h, ver, ow, grp)), R.flt(h, "tx_version", k))
    ++ R.when(U32.is_ge(ver, 5) && Bool.not(U32.is_eq(br, branch_test(h))), R.flt(h, "branch_id", k))

# Version and branch id of every tx.
def vers(n: Nat, +h: U32, +k: U32, +c: P.C) -> String:
  match n:
    case 0n:
      ""
    case 1n+m:
      +t = P.tx(c)
      vline(t, h, k) ++ vers(m, h, (k + 1 : U32), P.skip(c, P.tx_size(t)))

def fin(a: R.BA, +h: U32, +vf: String, +nsm: H.U64) -> R.BOut:
  R.BA{_, +fees, _, _, _, _, _, _, _, _, +ncb, +cbout, +cbvb, +cbo, +first, _, +cnt} = a
  +hn = U32.to_nat(h)
  +n : N7.Net = N7.Test{}
  +s = Nat.add(N7.subsidy(n, hn), R.nat_of(N7.additional(n, h, nsm)))
  +dfr = R.w64(U32.from_nat(N7.fs_deferred(n, hn, s)))
  +es = N7.required7(n, hn, s)
  +need = List.length(&2, IP.Out, es)
  +got = CB.matched(es, cbo)
  +total_out = R.add64(R.sub64(cbout, cbvb), dfr)
  +total_in = R.add64(R.w64(U32.from_nat(s)), N7.miner_fees(n, h, fees))
  +nnsm = N7.nsm_after(n, h, nsm, fees)
  +f2 = vf
    ++ R.when(Bool.not(first) || Bool.not(U32.is_eq(ncb, 1)), R.fl(h, "coinbase_first"))
    ++ R.when(Bool.not(Nat.is_eq(need, got)), R.fl(h, "issuance_required_outputs"))
    ++ R.when(Bool.not(R.eq64(total_in, total_out)), R.fl(h, "miner_fees"))
    ++ R.when(U32.is_ge(h, 4465026) && Bool.not(N7.limits_ok(cnt)), R.fl(h, "shielded_action_limits"))
    ++ R.when(R.neg_q(fees), R.fl(h, "fees_negative"))
  R.BOut{f2 ++ "tn " ++ U32.show(h) ++ " subsidy " ++ Nat.show(s) ++ " fees " ++ D.sdec(fees)
       ++ " contribution " ++ N7.udec(N7.contribution(n, h, fees)) ++ " deferred " ++ D.sdec(dfr)
       ++ " nsm " ++ N7.udec(nnsm) ++ " " ++ N7.show_cnt(cnt) ++ " verdict " ++ R.vstr(String.eq(f2, "")) ++ "\n",
       R.Pools{R.z64(), R.z64(), R.z64(), R.z64(), R.z64(), R.z64(), nnsm}}

def nsm_of(p: R.Pools) -> H.U64:
  R.Pools{_, _, _, _, _, _, +x} = p
  x

def block(+h: U32, +blk: +List<U32>, +ctx: +List<U32>, p: R.Pools) -> R.BOut:
  +bt = H.le32(H.drop(H.take(blk, 1487), 100))
  +c = P.skip(P.start(blk), 1487)
  +nn = P.cs(c)
  +cc = P.start(ctx)
  +nt = P.u32(P.skip(cc, 4))
  +c0 = P.skip(cc, (8 + 4 * nt : U32))
  +ntx = P.cs_v(nn)
  +a = R.txs_walk(U32.to_nat(ntx), h, bt, 0, P.cs_c(nn),
                  R.BA{"", R.z64(), R.z64(), R.z64(), R.z64(), R.z64(), R.z64(), R.z64(), 0, Nil{}, 0, R.z64(), R.z64(), Nil{}, False{}, c0, N7.cnt0()})
  fin(a, h, vers(U32.to_nat(ntx), h, 0, P.cs_c(nn)), nsm_of(p))

def gated(m: Maybe<&2, U32>, +h: U32, +blk: +List<U32>, +ctx: +List<U32>, p: R.Pools) -> R.BOut:
  match m:
    case Some{_}:
      block(h, blk, ctx, p)
    case None{}:
      R.BOut{R.fl(h, "wire") ++ "tn " ++ U32.show(h) ++ " verdict INVALID\n", p}

def with_cr(+blk: +List<U32>, +h: U32, cr: R.CR, p: R.Pools) -> R.BW:
  R.CR{+ctx, +co} = cr
  R.BW{gated(KB.parse_capped(blk), h, blk, ctx, p), co}

def loop(fuel: Nat, st: R.Hd, r: R.BW, +wp: String, +cp: String) -> IO(Unit):
  match fuel st:
    case 0n _:
      R.BW{+b, _} = r
      IO.print(R.bout_s(b))
    case 1n+q R.Stop{}:
      R.BW{+b, _} = r
      IO.print(R.bout_s(b))
    case 1n+q R.Rec{+h, +blen, +off}:
      R.BW{+b, +coff} = r
      +next = (off + 1495 + blen : U32)
      do IO<Unit>:
        IO.print(R.bout_s(b))
        blk : +List<U32> <- R.read_at(wp, (off + 1495 : U32), blen)
        cr : R.CR <- R.rd_ctx(cp, coff)
        nh : +List<U32> <- R.read_at(wp, next, 1495)
        loop(q, R.head_of(nh, next), with_cr(blk, h, cr, R.bout_p(b)), wp, cp)

def run(ps: R.Paths) -> IO(Unit):
  R.Paths{+wp, +cp} = ps
  do IO<Unit>:
    h0 : +List<U32> <- R.read_at(wp, 0, 1495)
    loop(1000000n, R.head_of(h0, 0), R.BW{R.BOut{"", R.Pools{R.z64(), R.z64(), R.z64(), R.z64(), R.z64(), R.z64(), R.z64()}}, 0}, wp, cp)

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<String> <- IO.args()
    run(R.paths_of(xs))
