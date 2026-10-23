# Zcash v5 / v6 transactions in Bend: byte-level parsing (ZIP 225, ZIP 229), the ZIP 244
# txid and shielded sighash, RedPallas spend-auth and binding signature verification for
# Orchard and Ironwood bundles, and the per-action Halo 2 public inputs (orchard 0.16).
#
# Bytes are U32 values in 0..255 in a +List<U32>. Every field read is a pure function of
# (bytes, position): positions are computed by walking the CompactSize-prefixed layout,
# so no reader has to return a (value, rest) pair.
import Base
import ./blake2b.bend as B
import ./util.bend as U
import ./consts.bend as K
import ../../halo2/lib/words.bend as Wd
import ../../halo2/lib/fp.bend as Fp
import ../../halo2/lib/fq.bend as Fq
import ../../halo2/lib/pallas.bend as Pa

# ------------------------------------------------------------------ byte access

def cat(a: +List<U32>, b: +List<U32>) -> +List<U32>:
  List.append(&2, U32, a, b)

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
      vin_end(p, xs, txin_end(xs, pos))

def prevouts(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      cat(at(xs, pos, 36n), prevouts(p, xs, txin_end(xs, pos)))

def sequences(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +e = txin_end(xs, pos)
      cat(at(xs, Nat.sub(e, 4n), 4n), sequences(p, xs, e))

# TxOut: value (8) || script (CompactSize bytes); hashed exactly as serialized.
def txout_end(+xs: +List<U32>, +pos: Nat) -> Nat:
  after_bytes(xs, (pos + 8n : Nat))

def vout_end(+n: Nat, +xs: +List<U32>, +pos: Nat) -> Nat:
  match n:
    case 0n:
      pos
    case 1n+p:
      vout_end(p, xs, txout_end(xs, pos))

def outputs(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +e = txout_end(xs, pos)
      cat(at(xs, pos, Nat.sub(e, pos)), outputs(p, xs, e))

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
      cat(at(xs, (pos + 32n : Nat), 32n), sap_nf(p, xs, (pos + 96n : Nat)))

# v5 hashes (cv, anchor, rk) per spend; v6 (ZIP 229) hashes (cv, rk): pass anchor = [].
def sap_spend_n(+n: Nat, +xs: +List<U32>, +pos: Nat, +anchor: +List<U32>) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      cat(at(xs, pos, 32n), cat(anchor, cat(at(xs, (pos + 64n : Nat), 32n), sap_spend_n(p, xs, (pos + 96n : Nat), anchor))))

def sap_out_c(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      cat(at(xs, (pos + 32n : Nat), 116n), sap_out_c(p, xs, (pos + 756n : Nat)))

def sap_out_m(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      cat(at(xs, (pos + 148n : Nat), 512n), sap_out_m(p, xs, (pos + 756n : Nat)))

def sap_out_n(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      cat(at(xs, pos, 32n), cat(at(xs, (pos + 660n : Nat), 96n), sap_out_n(p, xs, (pos + 756n : Nat))))

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

type Sap is Data:
  Sap{+digest: +List<U32>, +end: Nat, +count: Nat}

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
      cat(at(xs, (pos + 32n : Nat), 32n), cat(at(xs, (pos + 96n : Nat), 116n), act_c(p, xs, (pos + 820n : Nat))))

def act_m(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      cat(at(xs, (pos + 212n : Nat), 512n), act_m(p, xs, (pos + 820n : Nat)))

def act_n(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      cat(at(xs, pos, 32n), cat(at(xs, (pos + 64n : Nat), 32n), cat(at(xs, (pos + 724n : Nat), 96n), act_n(p, xs, (pos + 820n : Nat)))))

# Bundle formats: personalizations, and whether the anchor is in the txid digest.
type Fmt is Data:
  OrchardV5{}
  OrchardV6{}
  IronwoodV6{}

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

# A parsed bundle, as positions into the transaction: fields are read on demand.
# After the actions (at `tail`): flags (1) || valueBalance (8) || anchor (32) ||
# proof (CompactSize bytes) || spend-auth sigs (64 each, at `sigs`) || binding sig (64).
type Bnd is Data:
  Bnd{+fmt: Fmt, +n: Nat, +acts: Nat, +tail: Nat, +sigs: Nat, +end: Nat}

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
        cat(B.hash32(p_n(f), act_n(n, xs, acts)), cat(at(xs, tail, 9n), anchor_in_txid(f, at(xs, (tail + 9n : Nat), 32n)))))))
    case False{}:
      Bnd{+f, _, _, _, _, _} = b
      B.hash32(p_bundle(f), Nil{})

def bnd_digest(+xs: +List<U32>, +b: Bnd) -> +List<U32>:
  bnd_digest_any(nat_pos(bnd_n(b)), xs, b)

# ------------------------------------------------------------------ the transaction

type Tx is Data:
  Tx{+v6: Bool, +branch: U32, +nvin: Nat, +vin0: Nat, +nvout: Nat, +vout0: Nat, +sap: Sap, +orch: Bnd, +iron: Bnd}

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

type TDig is Data:
  TDig{+present: Bool, +prevouts: +List<U32>, +sequence: +List<U32>, +outputs: +List<U32>}

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

def amounts_digest(+amounts: +List<U32>) -> +List<U32>:
  B.hash32(B.P.ZTxTrAmountsHash(), amounts)

def scripts_digest(+scripts: +List<U32>) -> +List<U32>:
  B.hash32(B.P.ZTxTrScriptsHash(), scripts)

# Transparent part of the shielded (SIGHASH_ALL) signature digest, ZIP 244 S.2.
# amounts / scripts: the spent outputs' values and scriptPubKeys exactly as hashed.
def t_sig(has_inputs: Bool, t: TDig, +amounts: +List<U32>, +scripts: +List<U32>) -> +List<U32>:
  match has_inputs:
    case True{}:
      TDig{_, +p, +s, +o} = t
      B.hash32(B.P.ZTxIdTranspaHash(), cat(1 <> Nil{}, cat(p, cat(amounts_digest(amounts),
        cat(scripts_digest(scripts), cat(s, cat(o, B.hash32(B.P.Zcash___TxInHash(), Nil{}))))))))
    case False{}:
      t_txid(t)

def nvin_of(t: Tx) -> Nat:
  Tx{_, _, n, _, _, _, _, _, _} = t
  n

def vin0_of(t: Tx) -> Nat:
  Tx{_, _, _, p, _, _, _, _, _} = t
  p

def has_t_inputs(+xs: +List<U32>, +tx: Tx) -> Bool:
  +n = nvin_of(tx)
  nat_pos(n) && Bool.not(is_coinbase(n, xs, vin0_of(tx)))

def iron_part(v6: Bool, +i: +List<U32>) -> +List<U32>:
  match v6:
    case True{}:
      i
    case False{}:
      Nil{}

def root(+v6: Bool, +branch: U32, +h: +List<U32>, +t: +List<U32>, +s: +List<U32>, +o: +List<U32>, +i: +List<U32>) -> +List<U32>:
  B.hash32(B.P.ZcashTxHash(branch), cat(h, cat(t, cat(s, cat(o, iron_part(v6, i))))))

# ------------------------------------------------------------------ RedPallas (Pallas, cofactor 1)

def w_of(+bs: +List<U32>) -> Wd.W:
  Wd.W{le_u32(at(bs, 0n, 4n)), le_u32(at(bs, 4n, 4n)), le_u32(at(bs, 8n, 4n)), le_u32(at(bs, 12n, 4n)),
       le_u32(at(bs, 16n, 4n)), le_u32(at(bs, 20n, 4n)), le_u32(at(bs, 24n, 4n)), le_u32(at(bs, 28n, 4n))}

def bytes_of(w: Wd.W) -> +List<U32>:
  Wd.W{a, b, c, d, e, f, g, h} = w
  B.b2_w4(a, B.b2_w4(b, B.b2_w4(c, B.b2_w4(d, B.b2_w4(e, B.b2_w4(f, B.b2_w4(g, B.b2_w4(h, Nil{}))))))))

def pt_or_id(m: Maybe<&2, Pa.Pt>) -> Pa.Pt:
  match m:
    case Some{p}:
      p
    case None{}:
      Pa.identity()

def point(+bs: +List<U32>) -> Pa.Pt:
  pt_or_id(Pa.decompress(w_of(bs)))

# [S]B == R + [c]vk, with c = BLAKE2b-512("Zcash_RedPallasH", R̄ || vk || msg) mod q and
# S canonical: reddsa's verification equation for a prime-order group.
def rp_eq(canon: Bool, +base: Pa.Pt, +r: Pa.Pt, +v: Pa.Pt, +s: Wd.W, c: Fq.Fq) -> Bool:
  match canon:
    case True{}:
      Pa.is_eq(Pa.scalar_mul(base, s), Pa.add(r, Pa.scalar_mul_s(v, c)))
    case False{}:
      False{}

def rp_v(mv: Maybe<&2, Pa.Pt>, +base: Pa.Pt, +r: Pa.Pt, +s: Wd.W, c: Fq.Fq) -> Bool:
  match mv:
    case Some{v}:
      rp_eq(Wd.is_lt(s, Fq.modulus()), base, r, v, s, c)
    case None{}:
      False{}

def rp_r(mr: Maybe<&2, Pa.Pt>, mv: Maybe<&2, Pa.Pt>, +base: Pa.Pt, +s: Wd.W, c: Fq.Fq) -> Bool:
  match mr:
    case Some{r}:
      rp_v(mv, base, r, s, c)
    case None{}:
      False{}

def rp_challenge(+h: +List<U32>) -> Fq.Fq:
  Fq.from_wide(w_of(at(h, 0n, 32n)), w_of(at(h, 32n, 32n)))

def rp_verify(+base: Pa.Pt, +vk: +List<U32>, +sig: +List<U32>, +msg: +List<U32>) -> Bool:
  +rbar = at(sig, 0n, 32n)
  c = rp_challenge(B.hash64(B.P.Zcash_RedPallasH(), cat(rbar, cat(vk, msg))))
  rp_r(Pa.decompress(w_of(rbar)), Pa.decompress(w_of(vk)), base, w_of(at(sig, 32n, 32n)), c)

# ------------------------------------------------------------------ binding signature

def cv_sum(+n: Nat, +xs: +List<U32>, +pos: Nat, acc: Pa.Pt) -> Pa.Pt:
  match n:
    case 0n:
      acc
    case 1n+p:
      cv_sum(p, xs, (pos + 820n : Nat), Pa.add(acc, point(at(xs, pos, 32n))))

# valueBalance as a scalar: an i64 (lo, hi) mod q.
def vb_neg_scalar(+lo: U32, +hi: U32) -> Fq.Fq:
  +nlo = (U32.not(lo) + 1 : U32)
  +nhi = (U32.not(hi) + Bool.to_u32(U32.is_zero(lo)) : U32)
  Fq.neg(Fq.from_words(Wd.W{nlo, nhi, 0, 0, 0, 0, 0, 0}))

def vb_scalar_s(nonneg: Bool, +lo: U32, +hi: U32) -> Fq.Fq:
  match nonneg:
    case True{}:
      Fq.from_words(Wd.W{lo, hi, 0, 0, 0, 0, 0, 0})
    case False{}:
      vb_neg_scalar(lo, hi)

def vb_scalar(+lo: U32, +hi: U32) -> Fq.Fq:
  vb_scalar_s(U32.is_lt(hi, 2147483648), lo, hi)

# bvk = Σ cv_net − ValueCommit_0(valueBalance) = Σ cv_net − [valueBalance] V
def bvk(+xs: +List<U32>, +n: Nat, +acts: Nat, +tail: Nat) -> +List<U32>:
  +sum = cv_sum(n, xs, acts, Pa.identity())
  +vbs = vb_scalar(u32_at(xs, (tail + 1n : Nat)), u32_at(xs, (tail + 5n : Nat)))
  bytes_of(Pa.encode(Pa.sub(sum, Pa.scalar_mul_s(point(bytes_of(K.V_CV())), vbs))))

# ------------------------------------------------------------------ Halo 2 public inputs

def aff_x(a: Pa.Aff) -> +List<U32>:
  Pa.Aff{x, _} = a
  bytes_of(Fp.to_words(x))

def aff_y(a: Pa.Aff) -> +List<U32>:
  Pa.Aff{_, y} = a
  bytes_of(Fp.to_words(y))

# disableCrossAddress (orchard Instance::from_parts): only protocol V3 (NU6.3, NU7)
# restricts it; there an Orchard bundle is always restricted and an Ironwood bundle
# is restricted unless flag bit 2 (enableCrossAddress) is set.
def is_v3(+branch: U32) -> Bool:
  U32.is_eq(branch, 933566043) || U32.is_eq(branch, 1998129881)

def cross_disabled_v3(iron: Bool, +flags: U32) -> U32:
  match iron:
    case True{}:
      (1 .^. ((flags >> 2n) .&. 1) : U32)
    case False{}:
      1

def cross_disabled(v3: Bool, +iron: Bool, +flags: U32) -> U32:
  match v3:
    case True{}:
      cross_disabled_v3(iron, flags)
    case False{}:
      0

# ------------------------------------------------------------------ report (oracle line names)

def line(+name: String, +bs: +List<U32>) -> String:
  name ++ " " ++ U.bhex(bs) ++ "\n"

def nline(+name: String, +n: Nat) -> String:
  name ++ " " ++ Nat.show(n) ++ "\n"

def ok_u32(b: Bool) -> Nat:
  match b:
    case True{}:
      1n
    case False{}:
      0n

def action_report(+pre: String, +xs: +List<U32>, +a: Nat, +sig: +List<U32>, +anchor: +List<U32>, +flags: U32,
                  +cross: U32, +sighash: +List<U32>) -> String:
  +cv = at(xs, a, 32n)
  +rk = at(xs, (a + 64n : Nat), 32n)
  +cva = Pa.to_aff(point(cv))
  +rka = Pa.to_aff(point(rk))
  line(pre ++ ".cv", cv) ++ line(pre ++ ".nf", at(xs, (a + 32n : Nat), 32n)) ++ line(pre ++ ".rk", rk)
    ++ line(pre ++ ".cmx", at(xs, (a + 96n : Nat), 32n)) ++ line(pre ++ ".epk", at(xs, (a + 128n : Nat), 32n))
    ++ line(pre ++ ".spend_auth_sig", sig)
    ++ nline(pre ++ ".spend_auth_ok", ok_u32(rp_verify(point(bytes_of(K.G_SPENDAUTH())), rk, sig, sighash)))
    ++ line(pre ++ ".instance[0]", anchor) ++ line(pre ++ ".instance[1]", aff_x(cva)) ++ line(pre ++ ".instance[2]", aff_y(cva))
    ++ line(pre ++ ".instance[3]", at(xs, (a + 32n : Nat), 32n)) ++ line(pre ++ ".instance[4]", aff_x(rka))
    ++ line(pre ++ ".instance[5]", aff_y(rka)) ++ line(pre ++ ".instance[6]", at(xs, (a + 96n : Nat), 32n))
    ++ line(pre ++ ".instance[7]", u32_le32((flags .&. 1 : U32))) ++ line(pre ++ ".instance[8]", u32_le32(((flags >> 1n) .&. 1 : U32)))
    ++ line(pre ++ ".instance[9]", u32_le32(cross))

def actions_report(+k: Nat, +j: Nat, +pool: String, +xs: +List<U32>, +a: Nat, +sigs: Nat, +anchor: +List<U32>,
                   +flags: U32, +cross: U32, +sighash: +List<U32>) -> String:
  match k:
    case 0n:
      ""
    case 1n+p:
      action_report(pool ++ ".a" ++ Nat.show(j), xs, a, at(xs, sigs, 64n), anchor, flags, cross, sighash)
        ++ actions_report(p, (j + 1n : Nat), pool, xs, (a + 820n : Nat), (sigs + 64n : Nat), anchor, flags, cross, sighash)

def bundle_report_any(any: Bool, +xs: +List<U32>, b: Bnd, +branch: U32, +sighash: +List<U32>) -> String:
  match any:
    case True{}:
      Bnd{+f, +n, +acts, +tail, +sigs, +end} = b
      +pool = pool_name(f)
      +flags = byte_at(xs, tail)
      +anchor = at(xs, (tail + 9n : Nat), 32n)
      +bsig = at(xs, Nat.sub(end, 64n), 64n)
      +bk = bvk(xs, n, acts, tail)
      nline(pool ++ ".actions", n) ++ line(pool ++ ".flags", flags <> Nil{}) ++ line(pool ++ ".value_balance", at(xs, (tail + 1n : Nat), 8n))
        ++ line(pool ++ ".anchor", anchor) ++ nline(pool ++ ".proof_len", cs_val(xs, (tail + 41n : Nat)))
        ++ actions_report(n, 0n, pool, xs, acts, sigs, anchor, flags, cross_disabled(is_v3(branch), is_iron(f), flags), sighash)
        ++ line(pool ++ ".bvk", bk) ++ line(pool ++ ".binding_sig", bsig)
        ++ nline(pool ++ ".binding_ok", ok_u32(rp_verify(point(bytes_of(K.R_CV())), bk, bsig, sighash)))
    case False{}:
      ""

def bundle_report(+xs: +List<U32>, +b: Bnd, +branch: U32, +sighash: +List<U32>) -> String:
  bundle_report_any(nat_pos(bnd_n(b)), xs, b, branch, sighash)

def tdig_report(present: Bool, t: TDig) -> String:
  match present:
    case True{}:
      TDig{_, +p, +s, +o} = t
      line("prevouts_digest", p) ++ line("sequence_digest", s) ++ line("outputs_digest", o)
    case False{}:
      ""

def inputs_report(has: Bool, +amounts: +List<U32>, +scripts: +List<U32>) -> String:
  match has:
    case True{}:
      line("amounts_digest", amounts_digest(amounts)) ++ line("scripts_digest", scripts_digest(scripts))
    case False{}:
      ""

def iron_report(v6: Bool, +d: +List<U32>) -> String:
  match v6:
    case True{}:
      line("ironwood_digest", d)
    case False{}:
      ""

def tdig_present(t: TDig) -> Bool:
  TDig{p, _, _, _} = t
  p

# Everything the oracle writes for a transaction (except height / bucket / proof checks).
def report_tx(+xs: +List<U32>, +amounts: +List<U32>, +scripts: +List<U32>, +tx: Tx) -> String:
  Tx{+v6, +branch, _, _, _, _, +sap, +orch, +iron} = tx
  +hd = B.hash32(B.P.ZTxIdHeadersHash(), at(xs, 0n, 20n))
  +td = t_digests(xs, tx)
  +tt = t_txid(td)
  +sd = sap_digest(sap)
  +od = bnd_digest(xs, orch)
  +id = bnd_digest(xs, iron)
  +has = has_t_inputs(xs, tx)
  +ts = t_sig(has, td, amounts, scripts)
  +sighash = root(v6, branch, hd, ts, sd, od, id)
  line("txid", root(v6, branch, hd, tt, sd, od, id))
    ++ line("header", at(xs, 0n, 4n)) ++ line("version_group_id", at(xs, 4n, 4n)) ++ line("branch_id", at(xs, 8n, 4n))
    ++ line("lock_time", at(xs, 12n, 4n)) ++ line("expiry_height", at(xs, 16n, 4n))
    ++ line("header_digest", hd) ++ tdig_report(tdig_present(td), td) ++ line("transparent_digest", tt)
    ++ line("sapling_digest", sd) ++ line("orchard_digest", od) ++ iron_report(v6, id)
    ++ inputs_report(has, amounts, scripts) ++ line("transparent_sig_digest", ts) ++ line("sighash", sighash)
    ++ bundle_report(xs, orch, branch, sighash) ++ bundle_report(xs, iron, branch, sighash)

def report(+xs: +List<U32>, +amounts: +List<U32>, +scripts: +List<U32>) -> String:
  report_tx(xs, amounts, scripts, parse(xs))
