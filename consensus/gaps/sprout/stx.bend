# Sapling transactions in Bend: v4 (Sapling/Overwinter layout, ZIP 243 sighash, SHA-256d
# txid) and v5 (ZIP 225 layout, ZIP 244 txid/sighash via node/tx), the Sapling bundle's
# spend descriptions, output descriptions and signatures, turned into RedJubjub items
# (../sig/sig.bend) whose message is the shielded sighash.
#
# Bytes are U32 values in 0..255 in a +List<U32>; field reads are pure functions of
# (bytes, position), as in node/tx.
import Base
import ../../../halo2/lib/words.bend as Wd
import ../../../node/tx/tx.bend as NT
import ../../../node/tx/blake2b.bend as B
import ../../../node/tx/util.bend as U
import ../../../node/block/sha256.bend as SH
import ../../../sapling/sig/sig.bend as G
import ../../../sapling/jubjub/jubjub.bend as J
import ../../../sapling/jubjub/fr.bend as F
import ./ed.bend as ED

def at(+xs: +List<U32>, +pos: Nat, +n: Nat) -> +List<U32>:
  NT.at(xs, pos, n)

def cat(a: +List<U32>, b: +List<U32>) -> +List<U32>:
  List.append(&2, U32, a, b)

def zeros32() -> +List<U32>:
  NT.zeros(32n)

# Descriptions are walked as segments (the list from a description onward), advanced by
# dropping a stride, so a transaction with thousands of descriptions stays linear.
def adv(+seg: +List<U32>, +k: Nat) -> +List<U32>:
  List.drop(&2, U32, seg, k)

# ------------------------------------------------------------------ consensus branch id

def br7(b: Bool, +h: U32) -> U32:
  match b:
    case True{}:
      733220448
    case False{}:
      1991772603

def br6(b: Bool, +h: U32) -> U32:
  match b:
    case True{}:
      4122551051
    case False{}:
      br7(U32.is_ge(h, 653600), h)

def br5(b: Bool, +h: U32) -> U32:
  match b:
    case True{}:
      3925833126
    case False{}:
      br6(U32.is_ge(h, 903000), h)

def br4(b: Bool, +h: U32) -> U32:
  match b:
    case True{}:
      3268858036
    case False{}:
      br5(U32.is_ge(h, 1046400), h)

def br3(b: Bool, +h: U32) -> U32:
  match b:
    case True{}:
      3370586197
    case False{}:
      br4(U32.is_ge(h, 1687104), h)

def br2(b: Bool, +h: U32) -> U32:
  match b:
    case True{}:
      1307332080
    case False{}:
      br3(U32.is_ge(h, 2726400), h)

def br1(b: Bool, +h: U32) -> U32:
  match b:
    case True{}:
      1412952880
    case False{}:
      br2(U32.is_ge(h, 3146400), h)

def br0(b: Bool, +h: U32) -> U32:
  match b:
    case True{}:
      933566043
    case False{}:
      br1(U32.is_ge(h, 3364600), h)

# Consensus branch id by height (zcash_protocol BranchId::for_height, mainnet, >= Sapling):
# Sapling 0x76b809bb, Blossom 0x2bb40e60 (653,600), Heartwood 0xf5b9230b (903,000), Canopy
# 0xe9ff75a6 (1,046,400), NU5 0xc2d6d0b4 (1,687,104), NU6 0xc8e71055 (2,726,400), NU6.1
# 0x4dec4df0 (3,146,400), NU6.2 0x5437f330 (3,364,600), NU6.3 0x37a5165b (3,428,143).
def branch_of(+h: U32) -> U32:
  br0(U32.is_ge(h, 3428143), h)

# ------------------------------------------------------------------ v4 layout

# header 4 | nVersionGroupId 4 | vin | vout | nLockTime 4 | nExpiryHeight 4 | valueBalance 8 |
# spends (384: cv 0, anchor 32, nf 64, rk 96, proof 128, sig 320) |
# outputs (948: cv, cmu, epk, enc 580, out 80, proof 192) |
# joinsplits (1698, Groth16) | joinSplitPubKey 32 + joinSplitSig 64 (if any) | bindingSig 64 (if any)
type V4 is Data:
  V4{nvin: Nat, vin0: Nat, nvout: Nat, vout0: Nat, lt: Nat, ns: Nat, sp: Nat, no: Nat, op: Nat, nj: Nat, jp: Nat, end: Nat}

def if_pos(+k: Nat, +bytes: Nat) -> Nat:
  match k:
    case 0n:
      0n
    case 1n+p:
      bytes

def parse4(+xs: +List<U32>) -> V4:
  +nvin = NT.cs_val(xs, 8n)
  +vin0 = (8n + NT.cs_size(xs, 8n) : Nat)
  +vout_pos = NT.vin_end(nvin, xs, vin0)
  +nvout = NT.cs_val(xs, vout_pos)
  +vout0 = (vout_pos + NT.cs_size(xs, vout_pos) : Nat)
  +lt = NT.vout_end(nvout, xs, vout0)
  +spp = (lt + 16n : Nat)
  +ns = NT.cs_val(xs, spp)
  +sp = (spp + NT.cs_size(xs, spp) : Nat)
  +opp = (sp + (ns * 384n : Nat) : Nat)
  +no = NT.cs_val(xs, opp)
  +op = (opp + NT.cs_size(xs, opp) : Nat)
  +jpp = (op + (no * 948n : Nat) : Nat)
  +nj = NT.cs_val(xs, jpp)
  +jp = (jpp + NT.cs_size(xs, jpp) : Nat)
  V4{nvin, vin0, nvout, vout0, lt, ns, sp, no, op, nj, jp, (jp + (nj * 1698n : Nat) + if_pos(nj, 96n) + if_pos((ns + no : Nat), 64n) : Nat)}

def v4_end(v: V4) -> Nat:
  V4{_, _, _, _, _, _, _, _, _, _, _, e} = v
  e

# Spends without their signatures: cv || anchor || nf || rk || zkproof (320 bytes each).
def spends_nosig(+n: Nat, +seg: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      cat(at(seg, 0n, 320n), spends_nosig(p, adv(seg, 384n)))

def p_sighash(+branch: U32) -> B.P4:
  B.P4{1935762266, 1734955880, 1752392008, branch}

def p_prevouts() -> B.P4:
  B.P4{1935762266, 1701990504, 1953853302, 1752392008}

def p_sequence() -> B.P4:
  B.P4{1935762266, 1902465896, 1668179317, 1752392008}

def p_outputs() -> B.P4:
  B.P4{1935762266, 1953845096, 1937012080, 1752392008}

def p_jsplits() -> B.P4:
  B.P4{1935762266, 1884506728, 1937009004, 1752392008}

def p_sspends() -> B.P4:
  B.P4{1935762266, 1884509032, 1935961701, 1752392008}

def p_soutputs() -> B.P4:
  B.P4{1935762266, 1968132968, 1953853556, 1752392008}

def hash_or_zero(any: Bool, +p: B.P4, +data: +List<U32>) -> +List<U32>:
  match any:
    case True{}:
      B.hash32(p, data)
    case False{}:
      zeros32()

# The ZIP 243 digests (hashPrevouts, hashSequence, hashOutputs, hashJoinSplits,
# hashShieldedSpends, hashShieldedOutputs) for SIGHASH_ALL. As zcashd and zcash_primitives:
# the transparent ones are hashed even when empty; the shielded ones are 0^32 when empty.
type D4 is Data:
  D4{prevouts: +List<U32>, sequence: +List<U32>, outputs: +List<U32>, js: +List<U32>, spends: +List<U32>, outs: +List<U32>}

def digests4(+xs: +List<U32>, v: V4) -> D4:
  V4{+nvin, +vin0, +nvout, +vout0, +lt, +ns, +sp, +no, +op, +nj, +jp, _} = v
  D4{B.hash32(p_prevouts(), NT.prevouts(nvin, xs, vin0)),
     B.hash32(p_sequence(), NT.sequences(nvin, xs, vin0)),
     B.hash32(p_outputs(), NT.outputs(nvout, xs, vout0)),
     hash_or_zero(NT.nat_pos(nj), p_jsplits(), cat(at(xs, jp, (nj * 1698n : Nat)), at(xs, (jp + (nj * 1698n : Nat) : Nat), 32n))),
     hash_or_zero(NT.nat_pos(ns), p_sspends(), spends_nosig(ns, adv(xs, sp))),
     hash_or_zero(NT.nat_pos(no), p_soutputs(), at(xs, op, (no * 948n : Nat)))}

# ZIP 243 shielded sighash (SIGHASH_ALL, no transparent input being signed).
def sighash4(+xs: +List<U32>, +v: V4, d: D4, +branch: U32) -> +List<U32>:
  V4{_, _, _, _, +lt, _, _, _, _, _, _, _} = v
  D4{p, s, o, j, ss, so} = d
  B.hash32(p_sighash(branch), cat(at(xs, 0n, 8n), cat(p, cat(s, cat(o, cat(j, cat(ss, cat(so,
    cat(at(xs, lt, 16n), 1 <> 0 <> 0 <> 0 <> Nil{})))))))))

# v4 txid: SHA-256d of the whole transaction (hash output order).
def txid4(+xs: +List<U32>, +v: V4) -> +List<U32>:
  SH.hash_d(at(xs, 0n, v4_end(v)))

# ------------------------------------------------------------------ v5 layout (ZIP 225)

# Positions of the v5 Sapling bundle, starting at pos (after the transparent part):
# spends (96: cv, nf, rk) | outputs (756: cv, cmu, epk, enc 580, out 80) | valueBalance 8 |
# anchor 32 (if spends) | spend proofs 192 each | spend auth sigs 64 each | output proofs |
# bindingSig 64.
type V5 is Data:
  V5{ns: Nat, sp: Nat, no: Nat, op: Nat, ae: Nat}

def sap5(+xs: +List<U32>, +pos: Nat) -> V5:
  +ns = NT.cs_val(xs, pos)
  +sp = (pos + NT.cs_size(xs, pos) : Nat)
  +opos = (sp + (ns * 96n : Nat) : Nat)
  +no = NT.cs_val(xs, opos)
  +op = (opos + NT.cs_size(xs, opos) : Nat)
  V5{ns, sp, no, op, (op + (no * 756n : Nat) : Nat)}

# ------------------------------------------------------------------ RedJubjub items

def w(+bs: +List<U32>) -> Wd.W:
  NT.w_of(bs)

# Spend-auth items: rk i at offset 0 of rks (stride `stride`), sig i at offset 0 of sigs
# (stride `sstride`: v4 sigs sit inside the 384-byte spends, v5 sigs are contiguous).
def sa_items(+n: Nat, +rks: +List<U32>, +stride: Nat, +sigs: +List<U32>, +sstride: Nat, +msg: Wd.W) -> +List<G.It>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      G.It{0, 0, 0, 0, w(at(sigs, 0n, 32n)), w(at(sigs, 32n, 32n)), msg, w(at(rks, 0n, 32n)), Nil{}}
        <> sa_items(p, adv(rks, stride), stride, adv(sigs, sstride), sstride, msg)

# cvs of n descriptions (cv at offset 0), stride apart.
def cvs(+n: Nat, +seg: +List<U32>, +stride: Nat) -> +List<Wd.W>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      w(at(seg, 0n, 32n)) <> cvs(p, adv(seg, stride), stride)

def bd_item(any: Bool, +xs: +List<U32>, +ns: Nat, +no: Nat, +spcv: Nat, +spst: Nat, +opcv: Nat, +opst: Nat, +vbpos: Nat, +sigpos: Nat, +msg: Wd.W) -> +List<G.It>:
  match any:
    case False{}:
      Nil{}
    case True{}:
      +ncv = (U32.from_nat(ns) .|. (U32.from_nat(no) << 16n) : U32)
      G.It{1, ncv, NT.u32_at(xs, vbpos), NT.u32_at(xs, (vbpos + 4n : Nat)), w(at(xs, sigpos, 32n)), w(at(xs, (sigpos + 32n : Nat), 32n)), msg, Wd.zero(),
        List.append(&2, Wd.W, cvs(ns, adv(xs, spcv), spst), cvs(no, adv(xs, opcv), opst))} <> Nil{}

def items4(+xs: +List<U32>, +v: V4, +msg: Wd.W) -> +List<G.It>:
  V4{_, _, _, _, +lt, +ns, +sp, +no, +op, _, _, +e} = v
  List.append(&2, G.It, sa_items(ns, adv(xs, (sp + 96n : Nat)), 384n, adv(xs, (sp + 320n : Nat)), 384n, msg),
    bd_item(NT.nat_pos((ns + no : Nat)), xs, ns, no, sp, 384n, op, 948n, (lt + 8n : Nat), Nat.sub(e, 64n), msg))

# v5: sigs after valueBalance, anchor and the spend proofs.
def items5(+xs: +List<U32>, +s: V5, +msg: Wd.W) -> +List<G.It>:
  V5{+ns, +sp, +no, +op, +ae} = s
  +sig0 = (ae + 8n + if_pos(ns, 32n) + (ns * 192n : Nat) : Nat)
  +bsig = (sig0 + (ns * 64n : Nat) + (no * 192n : Nat) : Nat)
  List.append(&2, G.It, sa_items(ns, adv(xs, (sp + 64n : Nat)), 96n, adv(xs, sig0), 64n, msg),
    bd_item(NT.nat_pos((ns + no : Nat)), xs, ns, no, sp, 96n, op, 756n, ae, bsig, msg))

# ------------------------------------------------------------------ description consensus checks

# Protocol spec 4.4 / 4.5 (with ZIP 216): a spend's cv and rk, and an output's cv and epk, must
# decode and must not be of small order; an output's cmu must be canonical (< r_BLS).
def m_ok(m: Maybe<&2, J.Pt>) -> Bool:
  match m:
    case Some{p}:
      Bool.not(J.is_small_order(p))
    case None{}:
      False{}

def pt_ok(+seg: +List<U32>, +off: Nat) -> Bool:
  m_ok(J.decompress(w(at(seg, off, 32n))))

def spends_ok(+n: Nat, +seg: +List<U32>, +stride: Nat, +rkoff: Nat) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      pt_ok(seg, 0n) && pt_ok(seg, rkoff) && spends_ok(p, adv(seg, stride), stride, rkoff)

def outs_ok(+n: Nat, +seg: +List<U32>, +stride: Nat) -> Bool:
  match n:
    case 0n:
      True{}
    case 1n+p:
      pt_ok(seg, 0n) && Wd.is_lt(w(at(seg, 32n, 32n)), F.modulus()) && pt_ok(seg, 64n) && outs_ok(p, adv(seg, stride), stride)

def cons4(+xs: +List<U32>, v: V4) -> Bool:
  V4{_, _, _, _, _, +ns, +sp, +no, +op, _, _, _} = v
  spends_ok(ns, adv(xs, sp), 384n, 96n) && outs_ok(no, adv(xs, op), 948n)

def cons5(+xs: +List<U32>, s: V5) -> Bool:
  V5{+ns, +sp, +no, +op, _} = s
  spends_ok(ns, adv(xs, sp), 96n, 64n) && outs_ok(no, adv(xs, op), 756n)

# ------------------------------------------------------------------ Groth16 records

# Proof records for sapling/groth16's verify_raw_main / batch_main (raw-field format):
# u32 kind (0 spend, 1 output) | u32 tag (0) | proof[192] | spend: cv anchor nf rk /
# output: cv cmu epk (32 bytes each), in transaction order (spends, then outputs).
def hdr(+kind: U32, tail: +List<U32>) -> +List<U32>:
  B.b2_w4(kind, B.b2_w4(0, tail))

# v4 spend (384): cv anchor nf rk at 0..128, proof at 128.
def sp_recs4(+n: Nat, +seg: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      hdr(0, cat(at(seg, 128n, 192n), cat(at(seg, 0n, 128n), sp_recs4(p, adv(seg, 384n)))))

# v4 output (948): cv cmu epk at 0..96, proof at 756.
def out_recs4(+n: Nat, +seg: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      hdr(1, cat(at(seg, 756n, 192n), cat(at(seg, 0n, 96n), out_recs4(p, adv(seg, 948n)))))

# v4 JoinSplit (1698, Groth16): vpub_old 0 | vpub_new 8 | anchor 16 | nf1 48 | nf2 80 |
# cm1 112 | cm2 144 | ephemeralKey 176 | randomSeed 208 | mac1 240 | mac2 272 | proof 304 |
# ciphertexts 496. Record (kind 2, sapling/groth16 verify_raw_main): proof[192] | rt |
# randomSeed | nf1 | nf2 | mac1 | mac2 | cm1 | cm2 | joinSplitPubKey | vpub_old | vpub_new.
def js_recs4(+n: Nat, +seg: +List<U32>, +pk: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      hdr(2, cat(at(seg, 304n, 192n), cat(at(seg, 16n, 32n), cat(at(seg, 208n, 32n), cat(at(seg, 48n, 64n),
        cat(at(seg, 240n, 64n), cat(at(seg, 112n, 64n), cat(pk, cat(at(seg, 0n, 16n), js_recs4(p, adv(seg, 1698n), pk))))))))))

def recs4(+xs: +List<U32>, v: V4) -> +List<U32>:
  V4{_, _, _, _, _, +ns, +sp, +no, +op, +nj, +jp, _} = v
  cat(sp_recs4(ns, adv(xs, sp)), cat(out_recs4(no, adv(xs, op)), js_recs4(nj, adv(xs, jp), at(xs, (jp + (nj * 1698n : Nat) : Nat), 32n))))

# joinSplitSig: Ed25519 (ZIP 215 rules, ./ed.bend) by joinSplitPubKey over the ZIP 243
# sighash (SIGHASH_ALL, not an input: the same digest the binding signature signs).
def jsig_v(b: Bool) -> String:
  match b:
    case True{}:
      "1"
    case False{}:
      "0"

def jsig_n(any: Bool, +xs: +List<U32>, +kp: Nat, +sh: +List<U32>) -> String:
  match any:
    case False{}:
      "-"
    case True{}:
      jsig_v(ED.verify(at(xs, kp, 32n), at(xs, (kp + 32n : Nat), 64n), sh))

def jsig4(+xs: +List<U32>, +v: V4, +sh: +List<U32>) -> String:
  V4{_, _, _, _, _, _, _, _, _, +nj, +jp, _} = v
  jsig_n(NT.nat_pos(nj), xs, (jp + (nj * 1698n : Nat) : Nat), sh)

# v5 spend (96: cv nf rk), shared anchor, proofs contiguous (192 each).
def sp_recs5(+n: Nat, +seg: +List<U32>, +anchor: +List<U32>, +prf: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      hdr(0, cat(at(prf, 0n, 192n), cat(at(seg, 0n, 32n), cat(anchor, cat(at(seg, 32n, 64n), sp_recs5(p, adv(seg, 96n), anchor, adv(prf, 192n)))))))

# v5 output (756: cv cmu epk ...), proofs contiguous.
def out_recs5(+n: Nat, +seg: +List<U32>, +prf: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      hdr(1, cat(at(prf, 0n, 192n), cat(at(seg, 0n, 96n), out_recs5(p, adv(seg, 756n), adv(prf, 192n)))))

def recs5(+xs: +List<U32>, s: V5) -> +List<U32>:
  V5{+ns, +sp, +no, +op, +ae} = s
  +sprf = (ae + 8n + if_pos(ns, 32n) : Nat)
  +oprf = (sprf + (ns * 256n : Nat) : Nat)
  cat(sp_recs5(ns, adv(xs, sp), at(xs, (ae + 8n : Nat), 32n), adv(xs, sprf)), out_recs5(no, adv(xs, op), adv(xs, oprf)))

# ------------------------------------------------------------------ one transaction

# What a transaction yields: version, txid, sighash, spend/output counts, valueBalance
# (lo, hi words), RedJubjub items (spend-auth first, then binding).
type R is Data:
  R{ver: U32, txid: +List<U32>, sighash: +List<U32>, ns: Nat, no: Nat, vlo: U32, vhi: U32, cons: Bool, nj: Nat, items: +List<G.It>, recs: +List<U32>, jsig: String}

def run4v(+xs: +List<U32>, +height: U32, +v: V4) -> R:
  V4{_, _, _, _, +lt, +ns, _, +no, _, +nj, _, _} = v
  +sh = sighash4(xs, v, digests4(xs, v), branch_of(height))
  R{4, txid4(xs, v), sh, ns, no, NT.u32_at(xs, (lt + 8n : Nat)), NT.u32_at(xs, (lt + 12n : Nat)), cons4(xs, v), nj, items4(xs, v, w(sh)), recs4(xs, v), jsig4(xs, v, sh)}

def run4(+xs: +List<U32>, +height: U32) -> R:
  run4v(xs, height, parse4(xs))

def vb5(any: Bool, +xs: +List<U32>, +ae: Nat, +hi: Bool) -> U32:
  match any hi:
    case True{} False{}:
      NT.u32_at(xs, ae)
    case True{} True{}:
      NT.u32_at(xs, (ae + 4n : Nat))
    case _ _:
      0

# Linear transparent digests (node/tx's prevouts/sequences/outputs index the whole byte list
# per input, quadratic for transactions with hundreds of inputs). The input and output
# lists are walked as segments, once each.
def txin_len(+seg: +List<U32>) -> Nat:
  (36n + NT.cs_size(seg, 36n) + NT.cs_val(seg, 36n) + 4n : Nat)

def pv_lin(+n: Nat, +seg: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      cat(at(seg, 0n, 36n), pv_lin(p, adv(seg, txin_len(seg))))

def sq_lin(+n: Nat, +seg: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +l = txin_len(seg)
      cat(at(seg, Nat.sub(l, 4n), 4n), sq_lin(p, adv(seg, l)))

def txout_len(+seg: +List<U32>) -> Nat:
  (8n + NT.cs_size(seg, 8n) + NT.cs_val(seg, 8n) : Nat)

def out_lin(+n: Nat, +seg: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +l = txout_len(seg)
      cat(at(seg, 0n, l), out_lin(p, adv(seg, l)))

def t_digests_lin(+xs: +List<U32>, tx: NT.Tx) -> NT.TDig:
  NT.Tx{_, _, +nvin, +vin0, +nvout, +vout0, _, _, _} = tx
  NT.TDig{NT.nat_pos((nvin + nvout : Nat)),
       B.hash32(B.P.ZTxIdPrevoutHash(), pv_lin(nvin, adv(xs, vin0))),
       B.hash32(B.P.ZTxIdSequencHash(), sq_lin(nvin, adv(xs, vin0))),
       B.hash32(B.P.ZTxIdOutputsHash(), out_lin(nvout, adv(xs, vout0)))}

def txid5(+xs: +List<U32>, +tx: NT.Tx, +td: NT.TDig) -> +List<U32>:
  NT.Tx{+v6, +branch, _, _, _, _, +sap, +orch, +iron} = tx
  +hd = B.hash32(B.P.ZTxIdHeadersHash(), at(xs, 0n, 20n))
  NT.root(v6, branch, hd, NT.t_txid(td), NT.sap_digest(sap), NT.bnd_digest(xs, orch), NT.bnd_digest(xs, iron))

def sighash5(+xs: +List<U32>, +tx: NT.Tx, +td: NT.TDig, +amounts: +List<U32>, +scripts: +List<U32>) -> +List<U32>:
  NT.Tx{+v6, +branch, _, _, _, _, +sap, +orch, +iron} = tx
  +hd = B.hash32(B.P.ZTxIdHeadersHash(), at(xs, 0n, 20n))
  +ts = NT.t_sig(NT.has_t_inputs(xs, tx), td, amounts, scripts)
  NT.root(v6, branch, hd, ts, NT.sap_digest(sap), NT.bnd_digest(xs, orch), NT.bnd_digest(xs, iron))

def sap_start(+xs: +List<U32>, t: NT.Tx) -> Nat:
  NT.Tx{_, _, _, _, +nvout, +vout0, _, _, _} = t
  NT.vout_end(nvout, xs, vout0)

def run5s(+xs: +List<U32>, +tx: NT.Tx, +s: V5, +amounts: +List<U32>, +scripts: +List<U32>) -> R:
  V5{+ns, _, +no, _, +ae} = s
  +any = NT.nat_pos((ns + no : Nat))
  +td = t_digests_lin(xs, tx)
  +sh = sighash5(xs, tx, td, amounts, scripts)
  R{(NT.u32_at(xs, 0n) .&. 255 : U32), txid5(xs, tx, td), sh, ns, no, vb5(any, xs, ae, False{}), vb5(any, xs, ae, True{}), cons5(xs, s), 0n, items5(xs, s, w(sh)), recs5(xs, s), "-"}

def run5t(+xs: +List<U32>, +tx: NT.Tx, +amounts: +List<U32>, +scripts: +List<U32>) -> R:
  run5s(xs, tx, sap5(xs, sap_start(xs, tx)), amounts, scripts)

def run5(+xs: +List<U32>, +amounts: +List<U32>, +scripts: +List<U32>) -> R:
  run5t(xs, NT.parse(xs), amounts, scripts)

def run_v(is4: Bool, +xs: +List<U32>, +height: U32, +amounts: +List<U32>, +scripts: +List<U32>) -> R:
  match is4:
    case True{}:
      run4(xs, height)
    case False{}:
      run5(xs, amounts, scripts)

# header = 0x80000004 (v4) or 0x80000005 (v5).
def run(+xs: +List<U32>, +height: U32, +amounts: +List<U32>, +scripts: +List<U32>) -> R:
  run_v(U32.is_eq(NT.u32_at(xs, 0n), 2147483652), xs, height, amounts, scripts)

def bits(xs: +List<Bool>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{b, t}:
      match b:
        case True{}:
          "1" ++ bits(t)
        case False{}:
          "0" ++ bits(t)

def verdicts(xs: +List<G.It>) -> +List<Bool>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+x, t}:
      G.verify1(x) <> verdicts(t)

# "v txid sighash ns no vb_lo vb_hi cons nj verdicts" (cons = 1: every description passes the
# checks above; nj: Sprout JoinSplits (v4); verdicts: RedJubjub, spend-auth then binding, 1 = valid).
def line(r: R) -> String:
  R{+ver, txid, sighash, +ns, +no, +vlo, +vhi, cons, +nj, items, _, js} = r
  U32.show(ver) ++ " " ++ U.bhex(txid) ++ " " ++ U.bhex(sighash) ++ " " ++ Nat.show(ns) ++ " " ++ Nat.show(no) ++ " " ++ U32.show(vlo) ++ " " ++ U32.show(vhi) ++ " " ++ bits(cons <> Nil{}) ++ " " ++ Nat.show(nj) ++ " jsig=" ++ js ++ " " ++ bits(verdicts(items))

def recs_of(r: R) -> +List<U32>:
  R{_, _, _, _, _, _, _, _, _, _, rs, _} = r
  rs
