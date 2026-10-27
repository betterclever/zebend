# fullnode/fast: as fullnode/bend/zip244.bend, with every cat(at(xs, p, n), rest) written
# onto(xs, p, n, rest) (one copy of the bytes instead of two). Same digests.
# fullnode: the ZIP 244 txid of v5/v6 transactions, from node/block/tx.bend (same code), with
# the per-element loops made linear: each recursive step drops the element it consumed
# instead of re-indexing the transaction from its start (node/block's loops are quadratic in
# the number of outputs/actions; on 2 MB spam blocks that dominated blockdelta's time).
# Only the txid parts are kept (no sighash / signatures). Tested: merkle MATCH and every
# txid identical to zcash_primitives on the blocks in data/ (see README.md).
import Base
import ../../node/block/blake2b.bend as B
import ../../node/block/util.bend as U

# ------------------------------------------------------------------ byte access

type Sap is Data:
  Sap{+digest: +List<U32>, +end: Nat, +count: Nat}

# Bundle formats: personalizations, and whether the anchor is in the txid digest.
type Fmt is Data:
  OrchardV5{}
  OrchardV6{}
  IronwoodV6{}

# A parsed bundle, as positions into the transaction: fields are read on demand.
# After the actions (at `tail`): flags (1) || valueBalance (8) || anchor (32) ||
# proof (CompactSize bytes) || spend-auth sigs (64 each, at `sigs`) || binding sig (64).
type Bnd is Data:
  Bnd{+fmt: Fmt, +n: Nat, +acts: Nat, +tail: Nat, +sigs: Nat, +end: Nat}

type Tx is Data:
  Tx{+v6: Bool, +branch: U32, +nvin: Nat, +vin0: Nat, +nvout: Nat, +vout0: Nat, +sap: Sap, +orch: Bnd, +iron: Bnd}

type TDig is Data:
  TDig{+present: Bool, +prevouts: +List<U32>, +sequence: +List<U32>, +outputs: +List<U32>}

def cat(a: +List<U32>, b: +List<U32>) -> +List<U32>:
  List.append(&2, U32, a, b)

# The n bytes at pos, followed by rest: one copy (cat(at(..), rest) copied them twice).
def take_onto(n: Nat, xs: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match n xs:
    case 0n _:
      rest
    case 1n+p Con{h, t}:
      h <> take_onto(p, t, rest)
    case 1n+p Nil{}:
      rest

def onto(+xs: +List<U32>, +pos: Nat, +n: Nat, rest: +List<U32>) -> +List<U32>:
  take_onto(n, List.drop(&2, U32, xs, pos), rest)

def at(+xs: +List<U32>, +pos: Nat, +n: Nat) -> +List<U32>:
  List.take(&2, U32, List.drop(&2, U32, xs, pos), n)

def head0(xs: +List<U32>) -> U32:
  match xs:
    case Con{b, _}:
      b
    case Nil{}:
      0

def byte_at(+xs: +List<U32>, +pos: Nat) -> U32:
  head0(List.drop(&2, U32, xs, pos))

def le_u32(xs: +List<U32>) -> U32:
  match xs:
    case Con{a, Con{b, Con{c, Con{d, _}}}}:
      (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32)
    case Con{a, Con{b, _}}:
      (a .|. (b << 8n) : U32)
    case _:
      0

def u32_at(+xs: +List<U32>, +pos: Nat) -> U32:
  le_u32(at(xs, pos, 4n))

def u16_at(+xs: +List<U32>, +pos: Nat) -> U32:
  le_u32(at(xs, pos, 2n))

def zeros(+n: Nat) -> +List<U32>:
  List.replicate(U32, n, 0)

# A U32 as a 32-byte little-endian field element encoding.
def u32_le32(+v: U32) -> +List<U32>:
  B.b2_w4(v, zeros(28n))

# CompactSize: one byte below 253, else a 0xfd/0xfe/0xff marker and 2/4/8 LE bytes.
# (Values here always fit in 32 bits; an 0xff prefix reads its low word.)
def cs_wide_b(is16: Bool, +xs: +List<U32>, +pos: Nat) -> Nat:
  match is16:
    case True{}:
      U32.to_nat(u16_at(xs, (pos + 1n : Nat)))
    case False{}:
      U32.to_nat(u32_at(xs, (pos + 1n : Nat)))

def cs_pick(small: Bool, +k: U32, +xs: +List<U32>, +pos: Nat) -> Nat:
  match small:
    case True{}:
      U32.to_nat(k)
    case False{}:
      cs_wide_b(U32.is_eq(k, 253), xs, pos)

def cs_val(+xs: +List<U32>, +pos: Nat) -> Nat:
  +k = byte_at(xs, pos)
  cs_pick(U32.is_lt(k, 253), k, xs, pos)

def cs_size_x(is254: Bool) -> Nat:
  match is254:
    case True{}:
      5n
    case False{}:
      9n

def cs_size_w(is253: Bool, +k: U32) -> Nat:
  match is253:
    case True{}:
      3n
    case False{}:
      cs_size_x(U32.is_eq(k, 254))

def cs_size_k(small: Bool, +k: U32) -> Nat:
  match small:
    case True{}:
      1n
    case False{}:
      cs_size_w(U32.is_eq(k, 253), k)

def cs_size(+xs: +List<U32>, +pos: Nat) -> Nat:
  +k = byte_at(xs, pos)
  cs_size_k(U32.is_lt(k, 253), k)

# First byte after a CompactSize-prefixed byte string starting at pos.
def after_bytes(+xs: +List<U32>, +pos: Nat) -> Nat:
  (pos + cs_size(xs, pos) + cs_val(xs, pos) : Nat)

def nat_pos(+n: Nat) -> Bool:
  match n:
    case 0n:
      False{}
    case 1n+p:
      True{}

# ------------------------------------------------------------------ transparent (ZIP 225)

# TxIn: prevout (32 + 4) || script (CompactSize bytes) || sequence (4)
def txin_end(+xs: +List<U32>, +pos: Nat) -> Nat:
  (after_bytes(xs, (pos + 36n : Nat)) + 4n : Nat)

def vin_end(+n: Nat, +xs: +List<U32>, +pos: Nat) -> Nat:
  match n:
    case 0n:
      pos
    case 1n+p:
      +e = txin_end(xs, pos)
      (e + vin_end(p, List.drop(&2, U32, xs, e), 0n) : Nat)

def prevouts(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      onto(xs, pos, 36n, prevouts(p, List.drop(&2, U32, xs, txin_end(xs, pos)), 0n))

def sequences(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +e = txin_end(xs, pos)
      onto(xs, Nat.sub(e, 4n), 4n, sequences(p, List.drop(&2, U32, xs, e), 0n))

# TxOut: value (8) || script (CompactSize bytes); hashed exactly as serialized.
def txout_end(+xs: +List<U32>, +pos: Nat) -> Nat:
  after_bytes(xs, (pos + 8n : Nat))

def vout_end(+n: Nat, +xs: +List<U32>, +pos: Nat) -> Nat:
  match n:
    case 0n:
      pos
    case 1n+p:
      +e = txout_end(xs, pos)
      (e + vout_end(p, List.drop(&2, U32, xs, e), 0n) : Nat)

def outputs(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +e = txout_end(xs, pos)
      onto(xs, pos, Nat.sub(e, pos), outputs(p, List.drop(&2, U32, xs, e), 0n))

def all_zero(xs: +List<U32>) -> Bool:
  match xs:
    case Con{b, t}:
      U32.is_zero(b) && all_zero(t)
    case Nil{}:
      True{}

# Coinbase: exactly one input whose prevout is (0^32, 0xffffffff).
def coinbase_one(+xs: +List<U32>, +pos: Nat) -> Bool:
  all_zero(at(xs, pos, 32n)) && U32.is_eq(u32_at(xs, (pos + 32n : Nat)), 4294967295)

def is_one(+p: Nat, +xs: +List<U32>, +pos: Nat) -> Bool:
  match p:
    case 0n:
      coinbase_one(xs, pos)
    case 1n+q:
      False{}

def is_coinbase(+nvin: Nat, +xs: +List<U32>, +pos: Nat) -> Bool:
  match nvin:
    case 0n:
      False{}
    case 1n+p:
      is_one(p, xs, pos)

# ------------------------------------------------------------------ Sapling (v5 layout, also used by v6)

# Spend: cv (32) || nullifier (32) || rk (32).  Output (756): cv || cmu || epk || enc (580) || out (80);
# proofs and signatures follow all descriptions.
def sap_nf(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      onto(xs, (pos + 32n : Nat), 32n, sap_nf(p, List.drop(&2, U32, xs, (pos + 96n : Nat)), 0n))

# v5 hashes (cv, anchor, rk) per spend; v6 (ZIP 229) hashes (cv, rk): pass anchor = [].
def sap_spend_n(+n: Nat, +xs: +List<U32>, +pos: Nat, +anchor: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      onto(xs, pos, 32n, cat(anchor, onto(xs, (pos + 64n : Nat), 32n, sap_spend_n(p, List.drop(&2, U32, xs, (pos + 96n : Nat)), 0n, anchor))))

def sap_out_c(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      onto(xs, (pos + 32n : Nat), 116n, sap_out_c(p, List.drop(&2, U32, xs, (pos + 756n : Nat)), 0n))

def sap_out_m(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      onto(xs, (pos + 148n : Nat), 512n, sap_out_m(p, List.drop(&2, U32, xs, (pos + 756n : Nat)), 0n))

def sap_out_n(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      onto(xs, pos, 32n, onto(xs, (pos + 660n : Nat), 96n, sap_out_n(p, List.drop(&2, U32, xs, (pos + 756n : Nat)), 0n)))

def sap_noncompact(v6: Bool, +ns: Nat, +xs: +List<U32>, +sp: Nat, +anchor: +List<U32>) -> +List<U32>:
  match v6:
    case True{}:
      B.hash32(B.P.ZTxIdSSpendNH_v6(), sap_spend_n(ns, xs, sp, Nil{}))
    case False{}:
      B.hash32(B.P.ZTxIdSSpendNHash(), sap_spend_n(ns, xs, sp, anchor))

def sap_spends_digest(any: Bool, +ns: Nat, +xs: +List<U32>, +sp: Nat, +anchor: +List<U32>, +v6: Bool) -> +List<U32>:
  match any:
    case True{}:
      B.hash32(B.P.ZTxIdSSpendsHash(), cat(B.hash32(B.P.ZTxIdSSpendCHash(), sap_nf(ns, xs, sp)), sap_noncompact(v6, ns, xs, sp, anchor)))
    case False{}:
      B.hash32(B.P.ZTxIdSSpendsHash(), Nil{})

def sap_outputs_digest(any: Bool, +no: Nat, +xs: +List<U32>, +op: Nat) -> +List<U32>:
  match any:
    case True{}:
      B.hash32(B.P.ZTxIdSOutputHash(), cat(B.hash32(B.P.ZTxIdSOutC__Hash(), sap_out_c(no, xs, op)),
        cat(B.hash32(B.P.ZTxIdSOutM__Hash(), sap_out_m(no, xs, op)), B.hash32(B.P.ZTxIdSOutN__Hash(), sap_out_n(no, xs, op)))))
    case False{}:
      B.hash32(B.P.ZTxIdSOutputHash(), Nil{})

def sap_anchor_len(+ns: Nat) -> Nat:
  match ns:
    case 0n:
      0n
    case 1n+p:
      32n

# Bytes after the Sapling outputs: valueBalance (8, if any), anchor (32, if spends), the
# spend proofs and auth sigs (192 + 64 each), the output proofs (192 each), binding sig (64).
def sap_tail(any: Bool, +ns: Nat, +no: Nat) -> Nat:
  match any:
    case True{}:
      (8n + sap_anchor_len(ns) + (ns * 256n : Nat) + (no * 192n : Nat) + 64n : Nat)
    case False{}:
      0n

def sap_digest_any(any: Bool, +ns: Nat, +no: Nat, +xs: +List<U32>, +sp: Nat, +op: Nat, +ae: Nat, +v6: Bool) -> +List<U32>:
  match any:
    case True{}:
      +anchor = at(xs, (ae + 8n : Nat), 32n)
      B.hash32(B.P.ZTxIdSaplingHash(), cat(sap_spends_digest(nat_pos(ns), ns, xs, sp, anchor, v6),
        cat(sap_outputs_digest(nat_pos(no), no, xs, op), at(xs, ae, 8n))))
    case False{}:
      B.hash32(B.P.ZTxIdSaplingHash(), Nil{})

def sapling(+xs: +List<U32>, +pos: Nat, +v6: Bool) -> Sap:
  +ns = cs_val(xs, pos)
  +sp = (pos + cs_size(xs, pos) : Nat)
  +opos = (sp + (ns * 96n : Nat) : Nat)
  +no = cs_val(xs, opos)
  +op = (opos + cs_size(xs, opos) : Nat)
  +ae = (op + (no * 756n : Nat) : Nat)
  +any = nat_pos((ns + no : Nat))
  Sap{sap_digest_any(any, ns, no, xs, sp, op, ae, v6), (ae + sap_tail(any, ns, no) : Nat), (ns + no : Nat)}

def sap_end(s: Sap) -> Nat:
  Sap{_, e, _} = s
  e

def sap_digest(s: Sap) -> +List<U32>:
  Sap{d, _, _} = s
  d

# ------------------------------------------------------------------ Orchard / Ironwood bundles

# Action (820 bytes): cv 0, nf 32, rk 64, cmx 96, epk 128, enc 160 (580), out 740 (80).
def act_c(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      onto(xs, (pos + 32n : Nat), 32n, onto(xs, (pos + 96n : Nat), 116n, act_c(p, List.drop(&2, U32, xs, (pos + 820n : Nat)), 0n)))

def act_m(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      onto(xs, (pos + 212n : Nat), 512n, act_m(p, List.drop(&2, U32, xs, (pos + 820n : Nat)), 0n))

def act_n(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      onto(xs, pos, 32n, onto(xs, (pos + 64n : Nat), 32n, onto(xs, (pos + 724n : Nat), 96n, act_n(p, List.drop(&2, U32, xs, (pos + 820n : Nat)), 0n))))

def p_bundle(f: Fmt) -> B.P4:
  match f:
    case OrchardV5{}:
      B.P.ZTxIdOrchardHash()
    case OrchardV6{}:
      B.P.ZTxIdOrchardH_v6()
    case IronwoodV6{}:
      B.P.ZTxIdIronwd_H_v6()

def p_c(f: Fmt) -> B.P4:
  match f:
    case IronwoodV6{}:
      B.P.ZTxIdIrnActCH_v6()
    case _:
      B.P.ZTxIdOrcActCHash()

def p_m(f: Fmt) -> B.P4:
  match f:
    case IronwoodV6{}:
      B.P.ZTxIdIrnActMH_v6()
    case _:
      B.P.ZTxIdOrcActMHash()

def p_n(f: Fmt) -> B.P4:
  match f:
    case IronwoodV6{}:
      B.P.ZTxIdIrnActNH_v6()
    case _:
      B.P.ZTxIdOrcActNHash()

def anchor_in_txid(f: Fmt, +anchor: +List<U32>) -> +List<U32>:
  match f:
    case OrchardV5{}:
      anchor
    case _:
      Nil{}

def is_iron(f: Fmt) -> Bool:
  match f:
    case IronwoodV6{}:
      True{}
    case _:
      False{}

def pool_name(f: Fmt) -> String:
  match f:
    case IronwoodV6{}:
      "ironwood"
    case _:
      "orchard"

def bnd_after(any: Bool, +xs: +List<U32>, +n: Nat, +tail: Nat) -> Nat:
  match any:
    case True{}:
      (after_bytes(xs, (tail + 41n : Nat)) + (n * 64n : Nat) + 64n : Nat)
    case False{}:
      tail

def bundle(+f: Fmt, +xs: +List<U32>, +pos: Nat) -> Bnd:
  +n = cs_val(xs, pos)
  +acts = (pos + cs_size(xs, pos) : Nat)
  +tail = (acts + (n * 820n : Nat) : Nat)
  Bnd{f, n, acts, tail, after_bytes(xs, (tail + 41n : Nat)), bnd_after(nat_pos(n), xs, n, tail)}

def bnd_n(b: Bnd) -> Nat:
  Bnd{_, n, _, _, _, _} = b
  n

def bnd_end(b: Bnd) -> Nat:
  Bnd{_, _, _, _, _, e} = b
  e

def bnd_digest_any(any: Bool, +xs: +List<U32>, b: Bnd) -> +List<U32>:
  match any:
    case True{}:
      Bnd{+f, +n, +acts, +tail, _, _} = b
      B.hash32(p_bundle(f), cat(B.hash32(p_c(f), act_c(n, xs, acts)), cat(B.hash32(p_m(f), act_m(n, xs, acts)),
        cat(B.hash32(p_n(f), act_n(n, xs, acts)), onto(xs, tail, 9n, anchor_in_txid(f, at(xs, (tail + 9n : Nat), 32n)))))))
    case False{}:
      Bnd{+f, _, _, _, _, _} = b
      B.hash32(p_bundle(f), Nil{})

def bnd_digest(+xs: +List<U32>, +b: Bnd) -> +List<U32>:
  bnd_digest_any(nat_pos(bnd_n(b)), xs, b)

# ------------------------------------------------------------------ the transaction

def is_v6(+xs: +List<U32>) -> Bool:
  U32.is_eq((u32_at(xs, 0n) .&. 2147483647 : U32), 6)

def iron_or_empty(v6: Bool, +xs: +List<U32>, +pos: Nat) -> Bnd:
  match v6:
    case True{}:
      bundle(IronwoodV6{}, xs, pos)
    case False{}:
      Bnd{IronwoodV6{}, 0n, pos, pos, pos, pos}

def orch_fmt(v6: Bool) -> Fmt:
  match v6:
    case True{}:
      OrchardV6{}
    case False{}:
      OrchardV5{}

def parse(+xs: +List<U32>) -> Tx:
  +v6 = is_v6(xs)
  +nvin = cs_val(xs, 20n)
  +vin0 = (20n + cs_size(xs, 20n) : Nat)
  +vout_pos = vin_end(nvin, xs, vin0)
  +nvout = cs_val(xs, vout_pos)
  +vout0 = (vout_pos + cs_size(xs, vout_pos) : Nat)
  +sap = sapling(xs, vout_end(nvout, xs, vout0), v6)
  +orch = bundle(orch_fmt(v6), xs, sap_end(sap))
  Tx{v6, u32_at(xs, 8n), nvin, vin0, nvout, vout0, sap, orch, iron_or_empty(v6, xs, bnd_end(orch))}

# ------------------------------------------------------------------ ZIP 244 digests

def t_digests(+xs: +List<U32>, tx: Tx) -> TDig:
  Tx{_, _, +nvin, +vin0, +nvout, +vout0, _, _, _} = tx
  TDig{nat_pos((nvin + nvout : Nat)),
       B.hash32(B.P.ZTxIdPrevoutHash(), prevouts(nvin, xs, vin0)),
       B.hash32(B.P.ZTxIdSequencHash(), sequences(nvin, xs, vin0)),
       B.hash32(B.P.ZTxIdOutputsHash(), outputs(nvout, xs, vout0))}

def t_txid_present(present: Bool, +p: +List<U32>, +s: +List<U32>, +o: +List<U32>) -> +List<U32>:
  match present:
    case True{}:
      B.hash32(B.P.ZTxIdTranspaHash(), cat(p, cat(s, o)))
    case False{}:
      B.hash32(B.P.ZTxIdTranspaHash(), Nil{})

def t_txid(t: TDig) -> +List<U32>:
  TDig{+present, +p, +s, +o} = t
  t_txid_present(present, p, s, o)

def iron_part(v6: Bool, +i: +List<U32>) -> +List<U32>:
  match v6:
    case True{}:
      i
    case False{}:
      Nil{}

def root(+v6: Bool, +branch: U32, +h: +List<U32>, +t: +List<U32>, +s: +List<U32>, +o: +List<U32>, +i: +List<U32>) -> +List<U32>:
  B.hash32(B.P.ZcashTxHash(branch), cat(h, cat(t, cat(s, cat(o, iron_part(v6, i))))))

def txid_of(+xs: +List<U32>, +tx: Tx) -> +List<U32>:
  Tx{+v6, +branch, _, _, _, _, +sap, +orch, +iron} = tx
  +hd = B.hash32(B.P.ZTxIdHeadersHash(), at(xs, 0n, 20n))
  root(v6, branch, hd, t_txid(t_digests(xs, tx)), sap_digest(sap), bnd_digest(xs, orch), bnd_digest(xs, iron))

# ZIP 244 txid of a v5/v6 transaction starting at xs (as node/block/block.bend txid56).
def txid56(+xs: +List<U32>) -> +List<U32>:
  txid_of(xs, parse(xs))
