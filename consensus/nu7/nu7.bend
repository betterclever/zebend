# NU7 consensus changes (ZIP 259 deployment), in Bend, for Mainnet and Testnet.
#
# Sources (exact texts in consensus/nu7/README.md):
#   zcash/zips 2bdf3949 (2026-10-21): ZIP 259 (NU7 deployment: heights, branch id,
#     NSM_REISSUANCE_HEIGHT), ZIP 218 (25 s spacing, averaging window 102, PostNU7HalvingInterval,
#     BlockSubsidy / 3, shielded action limits), ZIP 235 (NSMFeeContribution = 60% of fees),
#     ZIP 237 (NSM value balance, AdditionalBlockSubsidy), ZIP 207 rev. 2 (NU7 AddressPeriod),
#     ZIP 214 rev. 3 (Revision 2 streams end at the ZIP 218 third halving), ZIP 2008 (FS_FPF_ZCG_H3
#     address list: P2PKH from index N), ZIP 2003 (no v4 transactions).
#   Zebra 1e03ee75 (2026-10-23): zebra-chain parameters/network/subsidy.rs (halving,
#     scheduled_block_subsidy, funding_stream_address_period, nu7_funding_stream_end_height,
#     nsm_fee_contribution, additional_block_subsidy, nsm_value_balance_change),
#     subsidy/check.rs (subsidy_is_valid, miner_fees_are_valid), constants/mainnet.rs
#     (post_nu6_1_funding_stream_fpf_addresses), zebra-consensus block.rs (ShieldedActionCounts).
#
# Amounts below 2^48 are Nat (block subsidies, funding stream values: Bend runtime Nats are
# exact there). Fees and the NSM value balance can reach MAX_MONEY (~2^50.9), so they are
# 64-bit values (H.U64) with 16-bit-limb division; the Nat versions of the same formulas, which
# the laws in LAWS.bend are about, are nsm_contribution_n and reissue_n.
import Base
import ../issuance/issuance.bend as I
import ../issuance/params.bend as IP
import ../../node/wire/hb.bend as H

type Net is Data:
  Main{}
  Test{}

# ---------------------------------------------------------------- network constants
# Zebra zebra-chain/src/parameters/constants.rs (activation heights), ZIP 214/259/237.

def blossom(n: Net) -> Nat:
  match n:
    case Main{}:
      U32.to_nat(653600)
    case Test{}:
      U32.to_nat(584000)

def nu7(n: Net) -> Nat:
  match n:
    case Main{}:
      U32.to_nat(3543405)
    case Test{}:
      U32.to_nat(4465026)

def nu7_u32(n: Net) -> U32:
  match n:
    case Main{}:
      3543405
    case Test{}:
      4465026

# HeightForHalving(1) (ZIP 207), before NU7 on both networks: 1,046,400 / 1,116,000.
def first_halving(n: Net) -> Nat:
  match n:
    case Main{}:
      U32.to_nat(1046400)
    case Test{}:
      U32.to_nat(1116000)

# Revision 2 funding streams FS_FPF_ZCG_H3 (8%) and FS_CCF_H3 (12%, DEFERRED_POOL): start
# height and pre-NU7 end height (ZIP 214).
def fs_start(n: Net) -> Nat:
  match n:
    case Main{}:
      U32.to_nat(3146400)
    case Test{}:
      U32.to_nat(3536500)

def fs_end_pre(n: Net) -> Nat:
  match n:
    case Main{}:
      U32.to_nat(4406400)
    case Test{}:
      U32.to_nat(4476000)

# NSM_REISSUANCE_HEIGHT (ZIP 259; = ZIP 237 DEPLOYMENT_BLOCK_HEIGHT).
def reissue_height(n: Net) -> Nat:
  match n:
    case Main{}:
      U32.to_nat(8939664)
    case Test{}:
      U32.to_nat(7305222)

# INITIAL_NSM_VALUE_BALANCE (ZIP 237): 36,858,445,520 / 55,768,414,957 zat.
def initial_nsm(n: Net) -> H.U64:
  match n:
    case Main{}:
      H.U64{2498707152, 8}
    case Test{}:
      H.U64{4228807405, 12}

def shift() -> Nat:
  U32.to_nat(10000)

def pre_interval() -> Nat:
  U32.to_nat(840000)

def post_interval() -> Nat:
  U32.to_nat(1680000)

# AddressChangeInterval = PostBlossomHalvingInterval / 48.
def change_interval() -> Nat:
  U32.to_nat(35000)

# ---------------------------------------------------------------- Halving (ZIP 218)
# The three cases of Halving(height), each scaled into blocks of its era. Written over
# parameters (shift s, Blossom b, NU7 a, post-Blossom interval iv) so the laws in LAWS.bend
# hold for every network.

# floor((b - s)/PreInterval + (h - b)/PostInterval), PreInterval = PostInterval / 2.
def halving_post(+s: Nat, +b: Nat, +h: Nat, +iv: Nat) -> Nat:
  Nat.div(Nat.add(Nat.mul(2n, Nat.sub(b, s)), Nat.sub(h, b)), iv)

# floor((b - s)/PreInterval + (a - b)/PostInterval + (h - a)/PostNU7Interval),
# PostNU7Interval = 3 * PostInterval: every term scaled into post-NU7 blocks.
def halving_nu7(+s: Nat, +b: Nat, +a: Nat, +h: Nat, +iv: Nat) -> Nat:
  Nat.div(Nat.add(Nat.mul(3n, Nat.add(Nat.mul(2n, Nat.sub(b, s)), Nat.sub(a, b))), Nat.sub(h, a)), Nat.mul(3n, iv))

def halving_ge_b(+n: Net, pre_nu7: Bool, +h: Nat) -> Nat:
  match pre_nu7:
    case True{}:
      halving_post(shift(), blossom(n), h, post_interval())
    case False{}:
      halving_nu7(shift(), blossom(n), nu7(n), h, post_interval())

def halving_ge_s(+n: Net, pre_b: Bool, +h: Nat) -> Nat:
  match pre_b:
    case True{}:
      Nat.div(Nat.sub(h, shift()), pre_interval())
    case False{}:
      halving_ge_b(n, Nat.is_lt(h, nu7(n)), h)

def halving_sel(+n: Net, lt_s: Bool, +h: Nat) -> Nat:
  match lt_s:
    case True{}:
      0n
    case False{}:
      halving_ge_s(n, Nat.is_lt(h, blossom(n)), h)

# ---------------------------------------------------------------- ScheduledBlockSubsidy

def halving(+n: Net, +h: Nat) -> Nat:
  halving_sel(n, Nat.is_lt(h, shift()), h)

# The post-Blossom subsidy of era k, divided by NU7PoWTargetSpacingRatio = 3 (ZIP 218:
# floor(MaxBlockSubsidy / (2 * 3 * 2^k)); the nested floors are equal).
def sub7(+k: Nat, +m: Nat) -> Nat:
  Nat.div(I.halve(k, m), 3n)

def sub_era_post(+n: Net, pre_nu7: Bool, +h: Nat) -> Nat:
  match pre_nu7:
    case True{}:
      I.halve(halving(n, h), Nat.div(I.max_subsidy(), 2n))
    case False{}:
      sub7(halving(n, h), Nat.div(I.max_subsidy(), 2n))

def sub_era(+n: Net, pre_b: Bool, pre_nu7: Bool, +h: Nat) -> Nat:
  match pre_b:
    case True{}:
      I.halve(halving(n, h), I.max_subsidy())
    case False{}:
      sub_era_post(n, pre_nu7, h)

def sub_slow2(+n: Net, lt_ssi: Bool, +h: Nat) -> Nat:
  match lt_ssi:
    case True{}:
      Nat.mul(Nat.div(I.max_subsidy(), I.slow_start_interval()), 1n+h)
    case False{}:
      sub_era(n, Nat.is_lt(h, blossom(n)), Nat.is_lt(h, nu7(n)), h)

def sub_slow1(+n: Net, lt_shift: Bool, +h: Nat) -> Nat:
  match lt_shift:
    case True{}:
      Nat.mul(Nat.div(I.max_subsidy(), I.slow_start_interval()), h)
    case False{}:
      sub_slow2(n, Nat.is_lt(h, I.slow_start_interval()), h)

# ScheduledBlockSubsidy(height) on network n, every era (protocol § 7.8 + ZIP 218).
def subsidy(+n: Net, +h: Nat) -> Nat:
  sub_slow1(n, Nat.is_lt(h, shift()), h)

# Total over K halving eras of one NU7 block each, starting from post-Blossom subsidy m:
# total7(K, m) = sub7(0, m) + ... + sub7(K-1, m) (same recursion as issuance's `total`).
def total7(K: Nat, +m: Nat) -> Nat:
  match K:
    case 0n:
      0n
    case 1n+p:
      Nat.add(Nat.div(m, 3n), total7(p, Nat.div(m, 2n)))

# ---------------------------------------------------------------- funding streams from NU7

# ZIP 214 rev. 3: Revision 2 streams end at A + 3 (H3 - A) when NU7 activates before H3.
def fs_end7(+n: Net) -> Nat:
  Nat.add(nu7(n), Nat.mul(3n, Nat.sub(fs_end_pre(n), nu7(n))))

# ZIP 207 AddressPeriod before NU7: floor((h + I - H1) / C).
def period_pre(+n: Net, +h: Nat) -> Nat:
  Nat.div(Nat.sub(Nat.add(h, post_interval()), first_halving(n)), change_interval())

# ZIP 207 rev. 2 AddressPeriod from NU7: floor((R (A + I - H1) + h - A) / (R C)), R = 3.
def period_nu7(+n: Net, +h: Nat) -> Nat:
  Nat.div(Nat.add(Nat.mul(3n, Nat.sub(Nat.add(nu7(n), post_interval()), first_halving(n))), Nat.sub(h, nu7(n))),
          Nat.mul(3n, change_interval()))

def period_sel(+n: Net, pre: Bool, +h: Nat) -> Nat:
  match pre:
    case True{}:
      period_pre(n, h)
    case False{}:
      period_nu7(n, h)

def period(+n: Net, +h: Nat) -> Nat:
  period_sel(n, Nat.is_lt(h, nu7(n)), h)

# FundingStream[FS_FPF_ZCG_H3].AddressIndex(h) (0-based).
def zcg_index(+n: Net, +h: Nat) -> Nat:
  Nat.sub(period(n, h), period_pre(n, fs_start(n)))

# ZIP 2008: N = AddressIndex(NU7ActivationHeight - 1) + 1; indices >= N pay the P2PKH address.
def zcg_switch(+n: Net) -> Nat:
  1n+zcg_index(n, Nat.sub(nu7(n), 1n))

def zcg_p2sh_main() -> String:
  "a914c20cd5bdf7964ca61764db66bc2531b1792a084d87"

# t1MkHnkxVjNpNbCrSs3AJ8J7ZSp6NTYiUcG: OP_DUP OP_HASH160 <20> OP_EQUALVERIFY OP_CHECKSIG.
def zcg_p2pkh_main() -> String:
  "76a9142a7e627ed7e826b72168ab98740e563d0c52987a88ac"

# Testnet FS_FPF_ZCG_H3.AddressList[0..26] = t2HifwjUj9uyxr9bknR8LFuQbc98c3vkXtu (ZIP 214).
def zcg_p2sh_test() -> String:
  "a9147a86d6c7eb12ce0aa309d7391a6f338eba3c242b87"

def zcg_main_sel(p2pkh: Bool) -> String:
  match p2pkh:
    case True{}:
      zcg_p2pkh_main()
    case False{}:
      zcg_p2sh_main()

def zcg_script(+n: Net, +h: Nat) -> String:
  match n:
    case Main{}:
      zcg_main_sel(Nat.is_ge(zcg_index(Main{}, h), zcg_switch(Main{})))
    case Test{}:
      zcg_p2sh_test()

def end_sel(+n: Net, pre: Bool) -> Nat:
  match pre:
    case True{}:
      fs_end_pre(n)
    case False{}:
      fs_end7(n)

# Is the Revision 2 stream pair active at h (start inclusive, end exclusive; the end moves
# at NU7 activation).
def fs_active(+n: Net, +h: Nat) -> Bool:
  Nat.is_ge(h, fs_start(n)) && Nat.is_lt(h, end_sel(n, Nat.is_lt(h, nu7(n))))

def fs_val(active: Bool, +s: Nat, +num: Nat) -> Nat:
  match active:
    case True{}:
      I.fs_value(s, num)
    case False{}:
      0n

# fs.Value for the 8% (ZCG) and 12% (deferred) streams at h with total block subsidy s.
def fs_zcg(+n: Net, +h: Nat, +s: Nat) -> Nat:
  fs_val(fs_active(n, h), s, 8n)

def fs_deferred(+n: Net, +h: Nat, +s: Nat) -> Nat:
  fs_val(fs_active(n, h), s, 12n)

def req_sel(active: Bool, +n: Net, +h: Nat, +s: Nat) -> +List<IP.Out>:
  match active:
    case True{}:
      [IP.Out{I.fs_value(s, 8n), zcg_script(n, h)}]
    case False{}:
      Nil{}

# The coinbase outputs required at a height >= NU7 activation (subsidy_is_valid: every active
# non-deferred stream; no founders' reward; the NU6.1 disbursement is at 3,146,400 only).
# A zero subsidy removes proportional payouts (Zebra subsidy_is_valid).
def required7(+n: Net, +h: Nat, +s: Nat) -> +List<IP.Out>:
  req_sel(fs_active(n, h) && Nat.is_gt(s, 0n), n, h, s)

# ---------------------------------------------------------------- 64-bit helpers (16-bit limbs)

type L4 is Data:
  L4{a: U32, b: U32, c: U32, d: U32}

type QR is Data:
  QR{q: L4, r: U32}

def l4(v: H.U64) -> L4:
  H.U64{+lo, +hi} = v
  L4{(hi >> 16n : U32), (hi .&. 65535 : U32), (lo >> 16n : U32), (lo .&. 65535 : U32)}

def of_l4(l: L4) -> H.U64:
  L4{+a, +b, +c, +d} = l
  H.U64{((c << 16n) .|. d : U32), ((a << 16n) .|. b : U32)}

# Long division by d, 0 < d < 2^16: quotient and remainder.
def divl(l: L4, +d: U32) -> QR:
  L4{+a, +b, +c, +e} = l
  +ra = (a % d : U32)
  +xb = (ra * 65536 + b : U32)
  +rb = (xb % d : U32)
  +xc = (rb * 65536 + c : U32)
  +rc = (xc % d : U32)
  +xd = (rc * 65536 + e : U32)
  QR{L4{(a / d : U32), (xb / d : U32), (xc / d : U32), (xd / d : U32)}, (xd % d : U32)}

def qr_q(r: QR) -> L4:
  QR{+q, _} = r
  q

def qr_r(r: QR) -> U32:
  QR{_, +x} = r
  x

def div64(+v: H.U64, +d: U32) -> H.U64:
  of_l4(qr_q(divl(l4(v), d)))

def mod64(+v: H.U64, +d: U32) -> U32:
  qr_r(divl(l4(v), d))

# v * m mod 2^64, 0 <= m < 2^16.
def mul_l4(l: L4, +m: U32) -> H.U64:
  L4{+a, +b, +c, +d} = l
  +pd = (d * m : U32)
  +pc = ((c * m) + (pd >> 16n) : U32)
  +pb = ((b * m) + (pc >> 16n) : U32)
  +pa = ((a * m) + (pb >> 16n) : U32)
  of_l4(L4{(pa .&. 65535 : U32), (pb .&. 65535 : U32), (pc .&. 65535 : U32), (pd .&. 65535 : U32)})

def mul64(+v: H.U64, +m: U32) -> H.U64:
  mul_l4(l4(v), m)

def carry(b: Bool) -> U32:
  match b:
    case True{}:
      1
    case False{}:
      0

def add64(a: H.U64, b: H.U64) -> H.U64:
  H.U64{+al, +ah} = a
  H.U64{+bl, +bh} = b
  +lo = (al + bl : U32)
  H.U64{lo, (ah + bh + carry(U32.is_lt(lo, al)) : U32)}

def neg64(v: H.U64) -> H.U64:
  H.U64{+lo, +hi} = v
  +nlo = (U32.not(lo) + 1 : U32)
  H.U64{nlo, (U32.not(hi) + carry(U32.is_eq(nlo, 0)) : U32)}

def sub64(+a: H.U64, +b: H.U64) -> H.U64:
  add64(a, neg64(b))

def z64() -> H.U64:
  H.U64{0, 0}

def is_neg64(+v: H.U64) -> Bool:
  H.U64{_, +hi} = v
  U32.is_eq((hi >> 31n : U32), 1)

# ---------------------------------------------------------------- NSM (ZIP 235 / 237)

# NSMFeeContribution(height) = 6 q + floor(6 r / 10), q = floor(fees / 10), r = fees mod 10
# (ZIP 235, Zebra nsm_fee_contribution): exactly floor(6 fees / 10), from NU7 activation.
def contribution64(+fees: H.U64) -> H.U64:
  add64(mul64(div64(fees, 10), 6), H.U64{((mod64(fees, 10) * 6) / 10 : U32), 0})

def contribution_at(nu7_active: Bool, +fees: H.U64) -> H.U64:
  match nu7_active:
    case True{}:
      contribution64(fees)
    case False{}:
      z64()

def contribution(+n: Net, +h: U32, +fees: H.U64) -> H.U64:
  contribution_at(U32.is_ge(h, nu7_u32(n)), fees)

# MinerFees(height) = TransactionFees(height) - NSMFeeContribution(height).
def miner_fees(+n: Net, +h: U32, +fees: H.U64) -> H.U64:
  sub64(fees, contribution(n, h, fees))

# AdditionalBlockSubsidy = ceiling(1375 * NSMValueBalance(h - 1) / 10^10) from
# DEPLOYMENT_BLOCK_HEIGHT (1375 = floor(LN2_SCALED / PostNU7HalvingInterval)); zero before.
# 1375 * MAX_MONEY < 2^62, so the 64-bit product is exact; 10^10 = 10^4 * 10^4 * 10^2.
def reissue64(+bal: H.U64) -> H.U64:
  div64(div64(div64(add64(mul64(bal, 1375), H.U64{1410065407, 2}), 10000), 10000), 100)

def reissue_at(active: Bool, +bal: H.U64) -> H.U64:
  match active:
    case True{}:
      reissue64(bal)
    case False{}:
      z64()

def seed_at(at_a: Bool, +n: Net) -> H.U64:
  match at_a:
    case True{}:
      initial_nsm(n)
    case False{}:
      z64()

# NSMValueBalance(h - 1) as the block at h sees it: the parent's balance plus the seed at the
# NU7 activation block (Zebra nsm_value_balance_before).
def nsm_before(+n: Net, +h: U32, +parent: H.U64) -> H.U64:
  add64(parent, seed_at(U32.is_eq(h, nu7_u32(n)), n))

def additional(+n: Net, +h: U32, +parent: H.U64) -> H.U64:
  reissue_at(Nat.is_ge(U32.to_nat(h), reissue_height(n)), nsm_before(n, h, parent))

# NSMValueBalance(h) = NSMValueBalance(h - 1) - AdditionalBlockSubsidy(h) + NSMValueRemoved(h),
# with the seed at activation (Zebra nsm_value_balance_change: seed - reissued + contributed).
def nsm_after(+n: Net, +h: U32, +parent: H.U64, +fees: H.U64) -> H.U64:
  add64(sub64(nsm_before(n, h, parent), additional(n, h, parent)), contribution(n, h, fees))

# ---------------------------------------------------------------- Nat versions (for LAWS.bend)

def nsm_contribution_n(+f: Nat) -> Nat:
  Nat.add(Nat.mul(6n, Nat.div(f, 10n)), Nat.div(Nat.mul(6n, Nat.mod(f, 10n)), 10n))

def miner_fees_n(+f: Nat) -> Nat:
  Nat.sub(f, nsm_contribution_n(f))

# ceiling(c * bal / d) as floor((c * bal + d - 1) / d), d = 1 + dp.
def reissue_n(+c: Nat, +dp: Nat, +bal: Nat) -> Nat:
  Nat.div(Nat.add(Nat.mul(c, bal), dp), 1n+dp)

# Issued supply and NSM balance after a block: subsidy s, reissued a, contributed c.
def issued_next(+i: Nat, +s: Nat, +a: Nat, +c: Nat) -> Nat:
  Nat.sub(Nat.add(Nat.add(i, s), a), c)

def nsm_next(+v: Nat, +a: Nat, +c: Nat) -> Nat:
  Nat.add(Nat.sub(v, a), c)

# ---------------------------------------------------------------- ZIP 218 action limits

# Per block: Orchard actions, Ironwood actions, Sapling spends + outputs, JoinSplits.
type Cnt is Data:
  Cnt{o: U32, i: U32, s: U32, j: U32}

def cnt0() -> Cnt:
  Cnt{0, 0, 0, 0}

def cnt_add(x: Cnt, y: Cnt) -> Cnt:
  Cnt{+a, +b, +c, +d} = x
  Cnt{+e, +f, +g, +k} = y
  Cnt{(a + e : U32), (b + f : U32), (c + g : U32), (d + k : U32)}

# GlobalShieldedBudget 330, OrchardProtocolBlockActionLimit 330 (Orchard and Ironwood each),
# SaplingBlockIOLimit 300, SproutBlockJoinSplitLimit 0; cost = o + i + s + 2 j.
# (Each count is bounded by the 2 MB block, so the U32 sums cannot wrap.)
def limits_ok(c: Cnt) -> Bool:
  Cnt{+o, +i, +s, +j} = c
  U32.is_le(o, 330) && U32.is_le(i, 330) && U32.is_le(s, 300) && U32.is_eq(j, 0)
    && U32.is_le((o + i + s + j + j : U32), 330)

def show_cnt(c: Cnt) -> String:
  Cnt{+o, +i, +s, +j} = c
  "orchard " ++ U32.show(o) ++ " ironwood " ++ U32.show(i) ++ " sapling " ++ U32.show(s) ++ " joinsplits " ++ U32.show(j)

# ---------------------------------------------------------------- formatting

def l4_zero(l: L4) -> Bool:
  L4{+a, +b, +c, +d} = l
  U32.is_eq((a .|. b .|. c .|. d : U32), 0)

def digit(+d: U32) -> String:
  SCon{Char.from_u32((48 + d : U32)), SNil{}}

def udec_n(fuel: Nat, z: Bool, +l: L4, acc: String) -> String:
  match fuel z:
    case 0n _:
      acc
    case 1n+p True{}:
      acc
    case 1n+p False{}:
      +r = divl(l, 10)
      udec_n(p, l4_zero(qr_q(r)), qr_q(r), digit(qr_r(r)) ++ acc)

def udec_sel(z: Bool, +l: L4) -> String:
  match z:
    case True{}:
      "0"
    case False{}:
      udec_n(21n, False{}, l, "")

# Decimal digits of an unsigned 64-bit value.
def udec(+v: H.U64) -> String:
  udec_sel(l4_zero(l4(v)), l4(v))
