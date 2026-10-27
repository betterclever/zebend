# Transparent signature hashes for every Zcash transaction version, in Bend:
#   v1, v2  legacy (zcashd's SignatureHash for pre-Overwinter transactions): SHA-256d of the
#           CTransactionSignatureSerializer output || nHashType (4 bytes LE)
#   v3      ZIP 143 (Overwinter), v4 ZIP 243 (Sapling): BLAKE2b-256 "ZcashSigHash" || branch id,
#           with the raw hash-type byte in the preimage (as zcashd and Zebra do)
#   v5, v6  ZIP 244 S.2 transparent part (Zebra's rules: only hash types 01 02 03 81 82 83, and
#           SIGHASH_SINGLE needs an output at the input's index)
# The transaction is a byte list; fields are found by walking its layout (positions are Nat).
import Base
import ../util.bend as U
import ../../tx/tx.bend as T
import ../../tx/blake2b.bend as B
import ../../block/sha256.bend as S

# ------------------------------------------------------------------ consensus branch ids (mainnet)

def br_sel(c: Bool, +b: U32, +rest: U32) -> U32:
  match c:
    case True{}:
      b
    case False{}:
      rest

# The consensus branch id in force at a mainnet height (0 = Sprout, before Overwinter).
def branch_of_height(+h: U32) -> U32:
  br_sel(U32.is_ge(h, 3543405), 1998129881, br_sel(U32.is_ge(h, 3428143), 933566043,
  br_sel(U32.is_ge(h, 3364600), 1412952880, br_sel(U32.is_ge(h, 3146400), 1307332080,
  br_sel(U32.is_ge(h, 2726400), 3370586197, br_sel(U32.is_ge(h, 1687104), 3268858036,
  br_sel(U32.is_ge(h, 1046400), 3925833126, br_sel(U32.is_ge(h, 903000), 4122551051,
  br_sel(U32.is_ge(h, 653600), 733220448, br_sel(U32.is_ge(h, 419200), 1991772603,
  br_sel(U32.is_ge(h, 347500), 1537743641, 0)))))))))))

# ------------------------------------------------------------------ BLAKE2b personalizations

def P.PrevoutHash() -> B.P4:
  B.P4{1935762266, 1701990504, 1953853302, 1752392008}

def P.SequencHash() -> B.P4:
  B.P4{1935762266, 1902465896, 1668179317, 1752392008}

def P.OutputsHash() -> B.P4:
  B.P4{1935762266, 1953845096, 1937012080, 1752392008}

def P.JSplitsHash() -> B.P4:
  B.P4{1935762266, 1884506728, 1937009004, 1752392008}

def P.SSpendsHash() -> B.P4:
  B.P4{1935762266, 1884509032, 1935961701, 1752392008}

def P.SOutputHash() -> B.P4:
  B.P4{1935762266, 1968132968, 1953853556, 1752392008}

# "ZcashSigHash" || branch id (LE)
def P.SigHash(+branch: U32) -> B.P4:
  B.P4{1935762266, 1734955880, 1752392008, branch}

def zeros32() -> +List<U32>:
  U.zeros(32n)

# ------------------------------------------------------------------ the transaction

# Z244: ZIP 244 digests of a v5/v6 transaction (empty lists for older versions).
type Z244 is Data:
  Z244{+v6: Bool, +hd: +List<U32>, +sd: +List<U32>, +od: +List<U32>, +id: +List<U32>, +am: +List<U32>, +sc: +List<U32>}

def z_none() -> Z244:
  Z244{False{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}}

# A transparent input: outpoint (36 bytes), scriptSig, nSequence (4 bytes).
type TxIn is Data:
  TxIn{+prevout: +List<U32>, +script: +List<U32>, +seq: +List<U32>}

# Inputs and outputs are split off the byte list once, front to back (reading fields by
# absolute position would cost O(position) per access on a list).
type PIn is Data:
  PIn{+ins: List<&2, TxIn>, +rest: +List<U32>}

def pin_ins(p: PIn) -> List<&2, TxIn>:
  PIn{i, _} = p
  i

def pin_rest(p: PIn) -> +List<U32>:
  PIn{_, r} = p
  r

def parse_ins(n: Nat, +xs: +List<U32>) -> PIn:
  match n:
    case 0n:
      PIn{Nil{}, xs}
    case 1n+p:
      +slen = T.cs_val(xs, 36n)
      +sz = T.cs_size(xs, 36n)
      +after = U.drop(xs, (36n + sz + slen : Nat))
      +r = parse_ins(p, U.drop(after, 4n))
      PIn{TxIn{U.take(xs, 36n), U.at(xs, (36n + sz : Nat), slen), U.take(after, 4n)} <> pin_ins(r), pin_rest(r)}

type POut is Data:
  POut{+outs: List<&2, +List<U32>>, +rest: +List<U32>}

def pout_outs(p: POut) -> List<&2, +List<U32>>:
  POut{o, _} = p
  o

def pout_rest(p: POut) -> +List<U32>:
  POut{_, r} = p
  r

# Each output exactly as serialized: value (8) || CompactSize script length || script.
def parse_outs(n: Nat, +xs: +List<U32>) -> POut:
  match n:
    case 0n:
      POut{Nil{}, xs}
    case 1n+p:
      +k = (8n + T.cs_size(xs, 8n) + T.cs_val(xs, 8n) : Nat)
      +r = parse_outs(p, U.drop(xs, k))
      POut{U.take(xs, k) <> pout_outs(r), pout_rest(r)}

def cat_prevouts(xs: List<&2, TxIn>) -> +List<U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{i, t}:
      TxIn{p, _, _} = i
      U.cat(p, cat_prevouts(t))

def cat_seqs(xs: List<&2, TxIn>) -> +List<U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{i, t}:
      TxIn{_, _, q} = i
      U.cat(q, cat_seqs(t))

def cat_all(xs: List<&2, +List<U32>>) -> +List<U32>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{o, t}:
      U.cat(o, cat_all(t))

def snth(xs: List<&2, +List<U32>>, n: Nat) -> +List<U32>:
  match xs n:
    case Con{h, _} 0n:
      h
    case Con{_, t} 1n+p:
      snth(t, p)
    case _ _:
      Nil{}

def inth(xs: List<&2, TxIn>, n: Nat) -> TxIn:
  match xs n:
    case Con{h, _} 0n:
      h
    case Con{_, t} 1n+p:
      inth(t, p)
    case _ _:
      TxIn{Nil{}, Nil{}, Nil{}}

def in_prevout(i: TxIn) -> +List<U32>:
  TxIn{p, _, _} = i
  p

def in_script(i: TxIn) -> +List<U32>:
  TxIn{_, s, _} = i
  s

def in_seq(i: TxIn) -> +List<U32>:
  TxIn{_, _, q} = i
  q

# Joinsplit section of a v2 transaction (xs starts at its count), as the legacy serializer
# writes it: count || descriptions || joinSplitPubKey || 64 zero bytes in place of the signature.
def js_legacy_any(any: Bool, +xs: +List<U32>, +n: Nat) -> +List<U32>:
  match any:
    case True{}:
      U.cat(U.take(xs, (T.cs_size(xs, 0n) + (n * 1802n : Nat) + 32n : Nat)), U.zeros(64n))
    case False{}:
      U.take(xs, T.cs_size(xs, 0n))

def js_legacy(v2: Bool, +xs: +List<U32>) -> +List<U32>:
  match v2:
    case True{}:
      +n = T.cs_val(xs, 0n)
      js_legacy_any(T.nat_pos(n), xs, n)
    case False{}:
      Nil{}

# hashJoinSplits of ZIP 143 (xs starts at the joinsplit count): the descriptions and the
# joinsplit pubkey, or 32 zero bytes.
def js_digest_any(any: Bool, +xs: +List<U32>, +n: Nat, +size: Nat) -> +List<U32>:
  match any:
    case True{}:
      B.hash32(P.JSplitsHash(), U.at(xs, T.cs_size(xs, 0n), ((n * size : Nat) + 32n : Nat)))
    case False{}:
      zeros32()

def js_digest(+xs: +List<U32>, +size: Nat) -> +List<U32>:
  +n = T.cs_val(xs, 0n)
  js_digest_any(T.nat_pos(n), xs, n, size)

def spend320(n: Nat, +xs: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      U.cat(U.take(xs, 320n), spend320(p, U.drop(xs, 384n)))

def sp_digest_any(any: Bool, +xs: +List<U32>, +n: Nat) -> +List<U32>:
  match any:
    case True{}:
      B.hash32(P.SSpendsHash(), spend320(n, U.drop(xs, T.cs_size(xs, 0n))))
    case False{}:
      zeros32()

def so_digest_any(any: Bool, +xs: +List<U32>, +n: Nat) -> +List<U32>:
  match any:
    case True{}:
      B.hash32(P.SOutputHash(), U.at(xs, T.cs_size(xs, 0n), (n * 948n : Nat)))
    case False{}:
      zeros32()

# v4 (ZIP 243), xs at the spend count: hashJoinSplits || hashShieldedSpends || hashShieldedOutputs.
def mid_v4(+xs: +List<U32>) -> +List<U32>:
  +ns = T.cs_val(xs, 0n)
  +ox = U.drop(xs, (T.cs_size(xs, 0n) + (ns * 384n : Nat) : Nat))
  +no = T.cs_val(ox, 0n)
  +jx = U.drop(ox, (T.cs_size(ox, 0n) + (no * 948n : Nat) : Nat))
  U.cat(js_digest(jx, 1698n), U.cat(sp_digest_any(T.nat_pos(ns), xs, ns), so_digest_any(T.nat_pos(no), ox, no)))

type Mid is Data:
  Mid{+mid: +List<U32>, +tail: +List<U32>}

# rest: the bytes after the outputs.
def mid_ow(v4: Bool, +rest: +List<U32>) -> Mid:
  match v4:
    case True{}:
      Mid{mid_v4(U.drop(rest, 16n)), U.take(rest, 16n)}
    case False{}:
      Mid{js_digest(U.drop(rest, 8n), 1802n), U.take(rest, 8n)}

def mk_mid(v34: Bool, +v4: Bool, +rest: +List<U32>) -> Mid:
  match v34:
    case True{}:
      mid_ow(v4, rest)
    case False{}:
      Mid{Nil{}, Nil{}}

def amounts_go(n: Nat, +ps: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      U.cat(U.take(ps, 8n), amounts_go(p, U.drop(ps, (12n + U32.to_nat(U.u32_at(ps, 8n)) : Nat))))

# prevs: the record's spent outputs, amount (8) || script_len (u32) || script, per input.
def scripts_go(n: Nat, +ps: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +k = U32.to_nat(U.u32_at(ps, 8n))
      U.cat(U.cs(U.u32_at(ps, 8n)), U.cat(U.at(ps, 12n, k), scripts_go(p, U.drop(ps, (12n + k : Nat)))))

def z_v5(+xs: +List<U32>, +n: Nat, +prevs: +List<U32>, tx: T.Tx) -> Z244:
  T.Tx{+v6, _, _, _, _, _, +sap, +orch, +iron} = tx
  Z244{v6, B.hash32(B.P.ZTxIdHeadersHash(), U.at(xs, 0n, 20n)), T.sap_digest(sap), T.bnd_digest(xs, orch),
       T.bnd_digest(xs, iron), B.hash32(B.P.ZTxTrAmountsHash(), amounts_go(n, prevs)), B.hash32(B.P.ZTxTrScriptsHash(), scripts_go(n, prevs))}

def mk_z(v5: Bool, +xs: +List<U32>, +n: Nat, +prevs: +List<U32>) -> Z244:
  match v5:
    case True{}:
      z_v5(xs, n, prevs, T.parse(xs))
    case False{}:
      z_none()

# ZIP 143 (personalizations ZcashXxxHash) or ZIP 244 (ZTxIdXxxHash) transparent digests.
type TD is Data:
  TD{+p: +List<U32>, +s: +List<U32>, +o: +List<U32>}

def td_sel(z: Bool, +ins: List<&2, TxIn>, +outs: List<&2, +List<U32>>) -> TD:
  match z:
    case True{}:
      TD{B.hash32(B.P.ZTxIdPrevoutHash(), cat_prevouts(ins)), B.hash32(B.P.ZTxIdSequencHash(), cat_seqs(ins)),
         B.hash32(B.P.ZTxIdOutputsHash(), cat_all(outs))}
    case False{}:
      TD{B.hash32(P.PrevoutHash(), cat_prevouts(ins)), B.hash32(P.SequencHash(), cat_seqs(ins)),
         B.hash32(P.OutputsHash(), cat_all(outs))}

def td_or_none(ow: Bool, +z: Bool, +ins: List<&2, TxIn>, +outs: List<&2, +List<U32>>) -> TD:
  match ow:
    case True{}:
      td_sel(z, ins, outs)
    case False{}:
      TD{Nil{}, Nil{}, Nil{}}

# ver: version (1..6); hdr: the first 8 bytes; js: the legacy joinsplit section (v2 only);
# d_prev, d_seq, d_out: ZIP 143 or ZIP 244 transparent digests; mid / tail: the ZIP 143
# preimage parts between the outputs digest and nHashType.
type Tx is Data:
  Tx{+ver: U32, +branch: U32, +ins: List<&2, TxIn>, +nvin: Nat, +outs: List<&2, +List<U32>>, +nvout: Nat,
     +hdr: +List<U32>, +lock: U32, +js: +List<U32>, +d_prev: +List<U32>, +d_seq: +List<U32>, +d_out: +List<U32>,
     +mid: +List<U32>, +tail: +List<U32>, +z: Z244}

def mk_tx3(td: TD, m: Mid, +ver: U32, +branch: U32, +ins: List<&2, TxIn>, +nvin: Nat, +outs: List<&2, +List<U32>>, +nvout: Nat,
           +hdr: +List<U32>, +lock: U32, +js: +List<U32>, +z: Z244) -> Tx:
  TD{+dp, +ds, +dout} = td
  Mid{+mid, +tail} = m
  Tx{ver, branch, ins, nvin, outs, nvout, hdr, lock, js, dp, ds, dout, mid, tail, z}

def mk_tx2(po: POut, +xs: +List<U32>, +ver: U32, +branch: U32, +ins: List<&2, TxIn>, +nvin: Nat, +nvout: Nat, +prevs: +List<U32>) -> Tx:
  POut{+outs, +rest} = po
  +v5 = U32.is_ge(ver, 5)
  +v34 = U32.is_ge(ver, 3) && Bool.not(v5)
  mk_tx3(td_or_none(U32.is_ge(ver, 3), v5, ins, outs), mk_mid(v34, U32.is_eq(ver, 4), rest), ver, branch, ins, nvin, outs, nvout,
    U.take(xs, 8n), Bool.pick(U32, v5, U.u32_at(xs, 12n), U.le32(rest)), js_legacy(U32.is_eq(ver, 2), U.drop(rest, 4n)),
    mk_z(v5, xs, nvin, prevs))

def mk_tx1(pi: PIn, +xs: +List<U32>, +ver: U32, +branch: U32, +nvin: Nat, +prevs: +List<U32>) -> Tx:
  PIn{+ins, +rest} = pi
  +nvout = T.cs_val(rest, 0n)
  mk_tx2(parse_outs(nvout, U.drop(rest, T.cs_size(rest, 0n))), xs, ver, branch, ins, nvin, nvout, prevs)

def vin_start(+ver: U32, +ow: Bool) -> Nat:
  Bool.pick(Nat, U32.is_ge(ver, 5), 20n, Bool.pick(Nat, ow, 8n, 4n))

# Parse a (well-formed) transaction mined at `height`; prevs as in scripts_go.
def parse(+xs: +List<U32>, +height: U32, +prevs: +List<U32>) -> Tx:
  +hdr = U.u32_at(xs, 0n)
  +ver = (hdr .&. 2147483647 : U32)
  +ow = U32.is_ne((hdr >> 31n : U32), 0)
  +vx = U.drop(xs, vin_start(ver, ow))
  +nvin = T.cs_val(vx, 0n)
  +branch = Bool.pick(U32, U32.is_ge(ver, 5), U.u32_at(xs, 8n), branch_of_height(height))
  mk_tx1(parse_ins(nvin, U.drop(vx, T.cs_size(vx, 0n))), xs, ver, branch, nvin, prevs)

def tx_ver(t: Tx) -> U32:
  Tx{v, _, _, _, _, _, _, _, _, _, _, _, _, _, _} = t
  v

def tx_branch(t: Tx) -> U32:
  Tx{_, b, _, _, _, _, _, _, _, _, _, _, _, _, _} = t
  b

def tx_ins(t: Tx) -> List<&2, TxIn>:
  Tx{_, _, i, _, _, _, _, _, _, _, _, _, _, _, _} = t
  i

def tx_nvin(t: Tx) -> Nat:
  Tx{_, _, _, n, _, _, _, _, _, _, _, _, _, _, _} = t
  n

def tx_lock(t: Tx) -> U32:
  Tx{_, _, _, _, _, _, _, l, _, _, _, _, _, _, _} = t
  l

# ------------------------------------------------------------------ hash-type flags

type HT is Data:
  HT{+acp: Bool, +single: Bool, +none: Bool}

def ht_of(+ht: U32) -> HT:
  +base = (ht .&. 31 : U32)
  HT{U32.is_ne((ht .&. 128 : U32), 0), U32.is_eq(base, 3), U32.is_eq(base, 2)}

def ht_acp(h: HT) -> Bool:
  HT{a, _, _} = h
  a

def ht_single(h: HT) -> Bool:
  HT{_, s, _} = h
  s

def ht_none(h: HT) -> Bool:
  HT{_, _, n} = h
  n

# ------------------------------------------------------------------ legacy (v1, v2)

def leg_script(me: Bool, +sc: +List<U32>) -> +List<U32>:
  match me:
    case True{}:
      U.cat(U.cs(U.len(sc)), sc)
    case False{}:
      0 <> Nil{}

def leg_input(+me: Bool, +zero_seq: Bool, +i: TxIn, +sc: +List<U32>) -> +List<U32>:
  U.cat(in_prevout(i), U.cat(leg_script(me, sc), Bool.pick(+List<U32>, Bool.not(me) && zero_seq, [0, 0, 0, 0], in_seq(i))))

def leg_inputs(ins: List<&2, TxIn>, +i: Nat, +nin: Nat, +sc: +List<U32>, +zero_seq: Bool) -> +List<U32>:
  match ins:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      U.cat(leg_input(Nat.is_eq(i, nin), zero_seq, x, sc), leg_inputs(t, 1n+i, nin, sc, zero_seq))

def leg_ins(acp: Bool, +ins: List<&2, TxIn>, +nvin: Nat, +nin: Nat, +sc: +List<U32>, +zero_seq: Bool) -> +List<U32>:
  match acp:
    case True{}:
      1 <> leg_input(True{}, zero_seq, inth(ins, nin), sc)
    case False{}:
      U.cat(U.cs(U32.from_nat(nvin)), leg_inputs(ins, 0n, nin, sc, zero_seq))

def null_outs(n: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      U.cat([255, 255, 255, 255, 255, 255, 255, 255, 0], null_outs(p))

def leg_outs_single(single: Bool, +outs: List<&2, +List<U32>>, +nvout: Nat, +nin: Nat) -> +List<U32>:
  match single:
    case True{}:
      U.cat(U.cs(U32.from_nat(1n+nin)), U.cat(null_outs(nin), snth(outs, nin)))
    case False{}:
      U.cat(U.cs(U32.from_nat(nvout)), cat_all(outs))

def leg_outs(none: Bool, +single: Bool, +outs: List<&2, +List<U32>>, +nvout: Nat, +nin: Nat) -> +List<U32>:
  match none:
    case True{}:
      0 <> Nil{}
    case False{}:
      leg_outs_single(single, outs, nvout, nin)

def legacy_h(h: HT, +t: Tx, +nin: Nat, +sc: +List<U32>, +ht: U32) -> +List<U32>:
  HT{+acp, +single, +none} = h
  Tx{_, _, +ins, +nvin, +outs, +nvout, +hdr, +lock, +js, _, _, _, _, _, _} = t
  S.hash_d(U.cat(U.take(hdr, 4n), U.cat(leg_ins(acp, ins, nvin, nin, sc, single || none),
    U.cat(leg_outs(none, single, outs, nvout, nin), U.cat(U.le4(lock), U.cat(js, U.le4(ht)))))))

def legacy(+t: Tx, +nin: Nat, +sc: +List<U32>, +ht: U32) -> +List<U32>:
  legacy_h(ht_of(ht), t, nin, sc, ht)

# ------------------------------------------------------------------ ZIP 143 / 243 (v3, v4)

def pick_d(c: Bool, +d: +List<U32>) -> +List<U32>:
  match c:
    case True{}:
      d
    case False{}:
      zeros32()

def z143_single(ok: Bool, +outs: List<&2, +List<U32>>, +nin: Nat) -> +List<U32>:
  match ok:
    case True{}:
      B.hash32(P.OutputsHash(), snth(outs, nin))
    case False{}:
      zeros32()

def z143_out(all: Bool, +single: Bool, +d: +List<U32>, +outs: List<&2, +List<U32>>, +nin: Nat, +nvout: Nat) -> +List<U32>:
  match all:
    case True{}:
      d
    case False{}:
      z143_single(single && Nat.is_lt(nin, nvout), outs, nin)

def zip143_h(h: HT, +t: Tx, +nin: Nat, +sc: +List<U32>, +amount: +List<U32>, +ht: U32) -> +List<U32>:
  HT{+acp, +single, +none} = h
  Tx{_, +branch, +ins, _, +outs, +nvout, +hdr, _, _, +dp, +ds, +dout, +mid, +tail, _} = t
  +me = inth(ins, nin)
  B.hash32(P.SigHash(branch), U.cat(hdr, U.cat(pick_d(Bool.not(acp), dp),
    U.cat(pick_d(Bool.not(acp || single || none), ds), U.cat(z143_out(Bool.not(single || none), single, dout, outs, nin, nvout),
    U.cat(mid, U.cat(tail, U.cat(U.le4(ht), U.cat(in_prevout(me), U.cat(U.cs(U.len(sc)), U.cat(sc,
    U.cat(amount, in_seq(me)))))))))))))

def zip143(+t: Tx, +nin: Nat, +sc: +List<U32>, +amount: +List<U32>, +ht: U32) -> +List<U32>:
  zip143_h(ht_of(ht), t, nin, sc, amount, ht)

# ------------------------------------------------------------------ ZIP 244 (v5, v6)

def e244(acp: Bool, +p: B.P4, +d: +List<U32>) -> +List<U32>:
  match acp:
    case True{}:
      B.hash32(p, Nil{})
    case False{}:
      d

def z244_single(ok: Bool, +outs: List<&2, +List<U32>>, +nin: Nat) -> +List<U32>:
  match ok:
    case True{}:
      B.hash32(B.P.ZTxIdOutputsHash(), snth(outs, nin))
    case False{}:
      B.hash32(B.P.ZTxIdOutputsHash(), Nil{})

def z244_out(all: Bool, +single: Bool, +d: +List<U32>, +outs: List<&2, +List<U32>>, +nin: Nat) -> +List<U32>:
  match all:
    case True{}:
      d
    case False{}:
      z244_single(single, outs, nin)

def zip244_h(h: HT, +t: Tx, +nin: Nat, +spk: +List<U32>, +amount: +List<U32>, +ht: U32) -> +List<U32>:
  HT{+acp, +single, +none} = h
  Tx{_, +branch, +ins, _, +outs, _, _, _, _, +dp, +ds, +dout, _, _, +z} = t
  Z244{+v6, +hd, +sd, +od, +id, +am, +scd} = z
  +me = inth(ins, nin)
  +txin = B.hash32(B.P.Zcash___TxInHash(), U.cat(in_prevout(me), U.cat(amount, U.cat(U.cs(U.len(spk)), U.cat(spk, in_seq(me))))))
  +ts = B.hash32(B.P.ZTxIdTranspaHash(), ht <> U.cat(e244(acp, B.P.ZTxIdPrevoutHash(), dp),
    U.cat(e244(acp, B.P.ZTxTrAmountsHash(), am), U.cat(e244(acp, B.P.ZTxTrScriptsHash(), scd),
    U.cat(e244(acp, B.P.ZTxIdSequencHash(), ds), U.cat(z244_out(Bool.not(single || none), single, dout, outs, nin), txin))))))
  T.root(v6, branch, hd, ts, sd, od, id)

def zip244(+t: Tx, +nin: Nat, +spk: +List<U32>, +amount: +List<U32>, +ht: U32) -> +List<U32>:
  zip244_h(ht_of(ht), t, nin, spk, amount, ht)

# Zebra: a v5+ hash type must be one of 01 02 03 81 82 83, and SIGHASH_SINGLE needs an output.
def v5_ok(+ht: U32, +nin: Nat, +nvout: Nat) -> Bool:
  +b = (ht .&. 127 : U32)
  +known = U32.is_eq((ht .&. 124 : U32), 0) && U32.is_ge(b, 1) && U32.is_le(b, 3)
  known && Bool.not(U32.is_eq(b, 3) && Nat.is_ge(nin, nvout))

# zcashd: a legacy SIGHASH_SINGLE without a matching output fails the signature check.
def leg_ok(+ht: U32, +nin: Nat, +nvout: Nat) -> Bool:
  Bool.not(U32.is_eq((ht .&. 31 : U32), 3) && Nat.is_ge(nin, nvout))

def sh_v5(ok: Bool, +t: Tx, +nin: Nat, +spk: +List<U32>, +amount: +List<U32>, +ht: U32) -> Maybe<&2, +List<U32>>:
  match ok:
    case True{}:
      Some{zip244(t, nin, spk, amount, ht)}
    case False{}:
      None{}

def sh_leg(ok: Bool, +t: Tx, +nin: Nat, +sc: +List<U32>, +ht: U32) -> Maybe<&2, +List<U32>>:
  match ok:
    case True{}:
      Some{legacy(t, nin, sc, ht)}
    case False{}:
      None{}

def sh_old(ow: Bool, +t: Tx, +nin: Nat, +sc: +List<U32>, +amount: +List<U32>, +ht: U32, +nvout: Nat) -> Maybe<&2, +List<U32>>:
  match ow:
    case True{}:
      Some{zip143(t, nin, sc, amount, ht)}
    case False{}:
      sh_leg(leg_ok(ht, nin, nvout), t, nin, sc, ht)

def sh_ver(v5: Bool, +ver: U32, +nvout: Nat, +t: Tx, +nin: Nat, +sc: +List<U32>, +spk: +List<U32>, +amount: +List<U32>, +ht: U32) -> Maybe<&2, +List<U32>>:
  match v5:
    case True{}:
      sh_v5(v5_ok(ht, nin, nvout), t, nin, spk, amount, ht)
    case False{}:
      sh_old(U32.is_ge(ver, 3), t, nin, sc, amount, ht, nvout)

# The sighash a CHECKSIG of input nin computes for script code sc and hash-type byte ht.
# spk / amount (8 bytes LE): the spent output. None: the signature check fails.
def sighash(+t: Tx, +nin: Nat, +sc: +List<U32>, +spk: +List<U32>, +amount: +List<U32>, +ht: U32) -> Maybe<&2, +List<U32>>:
  Tx{+ver, _, _, _, _, +nvout, _, _, _, _, _, _, _, _, _} = t
  sh_ver(U32.is_ge(ver, 5), ver, nvout, t, nin, sc, spk, amount, ht)
