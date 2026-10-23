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

# CompactSize: one byte below 253, else a 0xfd/0xfe/0xff marker and 2/4/8 LE bytes.
# (Values here always fit in 32 bits; an 0xff prefix reads its low word.)
def cs_wide(+k: U32, +xs: +List<U32>, +pos: Nat) -> Nat:
  match U32.is_eq(k, 253):
    case True{}:
      U32.to_nat(u16_at(xs, (pos + 1n : Nat)))
    case False{}:
      U32.to_nat(u32_at(xs, (pos + 1n : Nat)))

def cs_pick(small: Bool, +k: U32, +xs: +List<U32>, +pos: Nat) -> Nat:
  match small:
    case True{}:
      U32.to_nat(k)
    case False{}:
      cs_wide(k, xs, pos)

def cs_val(+xs: +List<U32>, +pos: Nat) -> Nat:
  +k = byte_at(xs, pos)
  cs_pick(U32.is_lt(k, 253), k, xs, pos)

def cs_size_k(+k: U32) -> Nat:
  match U32.is_lt(k, 253):
    case True{}:
      1n
    case False{}:
      cs_size_w(k)

def cs_size_w(+k: U32) -> Nat:
  match U32.is_eq(k, 253):
    case True{}:
      3n
    case False{}:
      cs_size_x(k)

def cs_size_x(+k: U32) -> Nat:
  match U32.is_eq(k, 254):
    case True{}:
      5n
    case False{}:
      9n

def cs_size(+xs: +List<U32>, +pos: Nat) -> Nat:
  cs_size_k(byte_at(xs, pos))

# First byte after a CompactSize-prefixed byte string starting at pos.
def after_bytes(+xs: +List<U32>, +pos: Nat) -> Nat:
  (pos + cs_size(xs, pos) + cs_val(xs, pos) : Nat)

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

def is_coinbase(+nvin: Nat, +xs: +List<U32>, +pos: Nat) -> Bool:
  match nvin:
    case 1n:
      coinbase_one(xs, pos)
    case _:
      False{}

# ------------------------------------------------------------------ Sapling (v5 layout)

# Spend: cv (32) || nullifier (32) || rk (32).  Output: cv || cmu || epk || enc (580) || out (80).
def sap_nf(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      cat(at(xs, (pos + 32n : Nat), 32n), sap_nf(p, xs, (pos + 96n : Nat)))

# v5 hashes (cv, anchor, rk); v6 (ZIP 229) hashes (cv, rk).
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
      cat(at(xs, (pos + 32n : Nat), 116n), sap_out_c(p, xs, (pos + 948n : Nat)))

def sap_out_m(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      cat(at(xs, (pos + 148n : Nat), 512n), sap_out_m(p, xs, (pos + 948n : Nat)))

def sap_out_n(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      cat(at(xs, pos, 32n), cat(at(xs, (pos + 660n : Nat), 96n), sap_out_n(p, xs, (pos + 948n : Nat))))

type Sap is Data:
  Sap{+digest: +List<U32>, +end: Nat}

def sap_spends_digest(+ns: Nat, +xs: +List<U32>, +sp: Nat, +anchor: +List<U32>, +v6: Bool) -> +List<U32>:
  match ns:
    case 0n:
      B.hash32(B.P.ZTxIdSSpendsHash(), Nil{})
    case _:
      B.hash32(B.P.ZTxIdSSpendsHash(), cat(B.hash32(B.P.ZTxIdSSpendCHash(), sap_nf(ns, xs, sp)), sap_noncompact(v6, ns, xs, sp, anchor)))

def sap_noncompact(v6: Bool, +ns: Nat, +xs: +List<U32>, +sp: Nat, +anchor: +List<U32>) -> +List<U32>:
  match v6:
    case True{}:
      B.hash32(B.P.ZTxIdSSpendNH_v6(), sap_spend_n(ns, xs, sp, Nil{}))
    case False{}:
      B.hash32(B.P.ZTxIdSSpendNHash(), sap_spend_n(ns, xs, sp, anchor))

def sap_outputs_digest(+no: Nat, +xs: +List<U32>, +op: Nat) -> +List<U32>:
  match no:
    case 0n:
      B.hash32(B.P.ZTxIdSOutputHash(), Nil{})
    case _:
      B.hash32(B.P.ZTxIdSOutputHash(), cat(B.hash32(B.P.ZTxIdSOutC__Hash(), sap_out_c(no, xs, op)),
        cat(B.hash32(B.P.ZTxIdSOutM__Hash(), sap_out_m(no, xs, op)), B.hash32(B.P.ZTxIdSOutN__Hash(), sap_out_n(no, xs, op)))))

def nat_pos(+n: Nat) -> Bool:
  match n:
    case 0n:
      False{}
    case _:
      True{}

# Bytes after the Sapling outputs: valueBalance (8, if any), anchor (32, if spends), the
# spend proofs (192 each) and auth sigs (64 each), the output proofs (192 each), binding sig (64).
def sap_tail(any: Bool, +ns: Nat, +no: Nat) -> Nat:
  match any:
    case True{}:
      (8n + sap_anchor_len(ns) + (ns * 256n : Nat) + (no * 192n : Nat) + 64n : Nat)
    case False{}:
      0n

def sap_anchor_len(+ns: Nat) -> Nat:
  match ns:
    case 0n:
      0n
    case _:
      32n

def sap_digest_any(any: Bool, +ns: Nat, +no: Nat, +xs: +List<U32>, +sp: Nat, +op: Nat, +ae: Nat, +v6: Bool) -> +List<U32>:
  match any:
    case True{}:
      +anchor = at(xs, (ae + 8n : Nat), 32n)
      B.hash32(B.P.ZTxIdSaplingHash(), cat(sap_spends_digest(ns, xs, sp, anchor, v6), cat(sap_outputs_digest(no, xs, op), at(xs, ae, 8n))))
    case False{}:
      B.hash32(B.P.ZTxIdSaplingHash(), Nil{})

def sapling(+xs: +List<U32>, +pos: Nat, +v6: Bool) -> Sap:
  +ns = cs_val(xs, pos)
  +sp = (pos + cs_size(xs, pos) : Nat)
  +opos = (sp + (ns * 96n : Nat) : Nat)
  +no = cs_val(xs, opos)
  +op = (opos + cs_size(xs, opos) : Nat)
  +ae = (op + (no * 948n : Nat) : Nat)
  +any = nat_pos((ns + no : Nat))
  Sap{sap_digest_any(any, ns, no, xs, sp, op, ae, v6), (ae + sap_tail(any, ns, no) : Nat)}

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

# Which bundle format: personalizations and whether the anchor is in the txid digest.
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

# A parsed bundle: positions into the transaction, so fields are read on demand.
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
  +sigs = after_bytes(xs, (tail + 41n : Nat))
  Bnd{f, n, acts, tail, sigs, bnd_after(nat_pos(n), xs, n, tail)}

# flags (1) || valueBalance (8) || anchor (32) follow the actions.
def bnd_digest_any(any: Bool, +xs: +List<U32>, b: Bnd) -> +List<U32>:
  Bnd{+f, +n, +acts, +tail, _, _} = b
  match any:
    case True{}:
      B.hash32(p_bundle(f), cat(B.hash32(p_c(f), act_c(n, xs, acts)), cat(B.hash32(p_m(f), act_m(n, xs, acts)),
        cat(B.hash32(p_n(f), act_n(n, xs, acts)), cat(at(xs, tail, 9n), anchor_in_txid(f, at(xs, (tail + 9n : Nat), 32n)))))))
    case False{}:
      B.hash32(p_bundle(f), Nil{})

def bnd_n(b: Bnd) -> Nat:
  Bnd{_, n, _, _, _, _} = b
  n

def bnd_end(b: Bnd) -> Nat:
  Bnd{_, _, _, _, _, e} = b
  e

def bnd_digest(+xs: +List<U32>, +b: Bnd) -> +List<U32>:
  bnd_digest_any(nat_pos(bnd_n(b)), xs, b)

# ------------------------------------------------------------------ the transaction

type Tx is Data:
  Tx{+v6: Bool, +branch: U32, +header_digest: +List<U32>, +nvin: Nat, +vin0: Nat, +nvout: Nat, +vout0: Nat,
     +sap: Sap, +orch: Bnd, +iron: Bnd}

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
  Tx{v6, u32_at(xs, 8n), B.hash32(B.P.ZTxIdHeadersHash(), at(xs, 0n, 20n)), nvin, vin0, nvout, vout0, sap, orch, iron_or_empty(v6, xs, bnd_end(orch))}

def sap_end(s: Sap) -> Nat:
  Sap{_, e} = s
  e

def sap_digest(s: Sap) -> +List<U32>:
  Sap{d, _} = s
  d

# ------------------------------------------------------------------ ZIP 244 digests

type TDig is Data:
  TDig{+present: Bool, +prevouts: +List<U32>, +sequence: +List<U32>, +outputs: +List<U32>}

def t_digests(+xs: +List<U32>, +tx: Tx) -> TDig:
  Tx{_, _, _, +nvin, +vin0, +nvout, +vout0, _, _, _} = tx
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

def t_txid(+t: TDig) -> +List<U32>:
  TDig{+present, +p, +s, +o} = t
  t_txid_present(present, p, s, o)

# Transparent part of the shielded (SIGHASH_ALL) signature digest, ZIP 244 S.2.
# ctx carries the spent outputs' amounts and scriptPubKeys exactly as hashed.
def t_sig_inputs(has_inputs: Bool, +t: TDig, +amounts: +List<U32>, +scripts: +List<U32>) -> +List<U32>:
  TDig{_, +p, +s, +o} = t
  match has_inputs:
    case True{}:
      B.hash32(B.P.ZTxIdTranspaHash(), cat(1 <> Nil{}, cat(p, cat(B.hash32(B.P.ZTxTrAmountsHash(), amounts),
        cat(B.hash32(B.P.ZTxTrScriptsHash(), scripts), cat(s, cat(o, B.hash32(B.P.Zcash___TxInHash(), Nil{}))))))))
    case False{}:
      t_txid(t)

def nvin_of(t: Tx) -> Nat:
  Tx{_, _, _, n, _, _, _, _, _, _} = t
  n

def vin0_of(t: Tx) -> Nat:
  Tx{_, _, _, _, p, _, _, _, _, _} = t
  p

def has_t_inputs(+xs: +List<U32>, +tx: Tx) -> Bool:
  +n = nvin_of(tx)
  nat_pos(n) && Bool.not(is_coinbase(n, xs, vin0_of(tx)))

def root(+v6: Bool, +branch: U32, +h: +List<U32>, +t: +List<U32>, +s: +List<U32>, +o: +List<U32>, +i: +List<U32>) -> +List<U32>:
  B.hash32(B.P.ZcashTxHash(branch), cat(h, cat(t, cat(s, cat(o, iron_part(v6, i))))))

def iron_part(v6: Bool, +i: +List<U32>) -> +List<U32>:
  match v6:
    case True{}:
      i
    case False{}:
      Nil{}

# ------------------------------------------------------------------ RedPallas (Pallas, cofactor 1)

def w_of(+bs: +List<U32>) -> Wd.W:
  Wd.W{le_u32(at(bs, 0n, 4n)), le_u32(at(bs, 4n, 4n)), le_u32(at(bs, 8n, 4n)), le_u32(at(bs, 12n, 4n)),
       le_u32(at(bs, 16n, 4n)), le_u32(at(bs, 20n, 4n)), le_u32(at(bs, 24n, 4n)), le_u32(at(bs, 28n, 4n))}

def bytes_of(w: Wd.W) -> +List<U32>:
  Wd.W{a, b, c, d, e, f, g, h} = w
  B.b2_w4(a, B.b2_w4(b, B.b2_w4(c, B.b2_w4(d, B.b2_w4(e, B.b2_w4(f, B.b2_w4(g, B.b2_w4(h, Nil{}))))))))

# [S]B == R + [c]vk, with c = BLAKE2b-512("Zcash_RedPallasH", R̄ || vk || msg) mod q
# and S canonical: reddsa's check for a prime-order group.
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

def pt_or_id(m: Maybe<&2, Pa.Pt>) -> Pa.Pt:
  match m:
    case Some{p}:
      p
    case None{}:
      Pa.identity()

def hex_point(+w: Wd.W) -> Pa.Pt:
  pt_or_id(Pa.decompress(w))

# Orchard generators (GroupHash^P), from the oracle's constants.txt (labelled constants,
# not recomputed here): G = "z.cash:Orchard"/"G", V and R = "z.cash:Orchard-cv"/"v","r".
def G_SPENDAUTH() -> Wd.W:
  Wd.W{GSA0(), GSA1(), GSA2(), GSA3(), GSA4(), GSA5(), GSA6(), GSA7()}
