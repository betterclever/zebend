# A well-formedness validator for Zcash transactions (v1/v2 Sprout, v3, v4, v5, v6) that
# accepts exactly what zcash_primitives 0.31 Transaction::read accepts when it consumes the
# whole input. Every rule below cites the reader it mirrors. Before any vector is read, its
# CompactSize count is checked against the bytes that remain (count * minimum element size),
# so a huge count is rejected without looping or allocating.
import Base
import ../../halo2/lib/words.bend as Wd
import ../../halo2/lib/fp.bend as Fp
import ../../halo2/lib/pallas.bend as P
import ./hb.bend as H
import ./cs.bend as CS
import ./fr.bend as Fr
import ./jj.bend as J

# ---------------------------------------------------------------- encoded values

def keep_s(ok: Bool, s: H.S) -> Maybe<&2, H.S>:
  match ok:
    case True{}:
      Some{s}
    case False{}:
      None{}

def wcheck_pbase(r: H.W) -> Maybe<&2, H.S>:
  H.Wv{+w, +s} = r
  keep_s(Wd.is_lt(w, Fp.modulus()), s)

# A canonical Pallas base field element (orchard Nullifier / ExtractedNoteCommitment / Anchor).
def pbase(+s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    r : H.W <- H.word(s)
    s2 : H.S <- wcheck_pbase(r)
    return s2

def pt_ok(+allow_id: Bool, m: Maybe<&2, P.Pt>, s: H.S) -> Maybe<&2, H.S>:
  match m:
    case None{}:
      None{}
    case Some{p}:
      keep_s(allow_id || Bool.not(P.is_identity(p)), s)

def wcheck_ppoint(+allow_id: Bool, r: H.W) -> Maybe<&2, H.S>:
  H.Wv{+w, +s} = r
  pt_ok(allow_id, P.decompress(w), s)

# A Pallas point encoding (pasta_curves from_bytes); allow_id = False also rejects the identity.
def ppoint(+allow_id: Bool, +s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    r : H.W <- H.word(s)
    s2 : H.S <- wcheck_ppoint(allow_id, r)
    return s2

def wcheck_fr(r: H.W) -> Maybe<&2, H.S>:
  H.Wv{+w, +s} = r
  keep_s(Wd.is_lt(w, Fr.modulus()), s)

# A canonical BLS12-381 scalar (Sapling cmu / anchor).
def frc(+s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    r : H.W <- H.word(s)
    s2 : H.S <- wcheck_fr(r)
    return s2

def jj_ok(+nso: Bool, m: Maybe<&2, J.Jp>, s: H.S) -> Maybe<&2, H.S>:
  match m:
    case None{}:
      None{}
    case Some{p}:
      keep_s(Bool.not(nso) || Bool.not(J.is_small_order(p)), s)

def wcheck_jj(+nso: Bool, r: H.W) -> Maybe<&2, H.S>:
  H.Wv{+w, +s} = r
  jj_ok(nso, J.decode(w), s)

# A Jubjub point encoding; nso = True also rejects small-order points (Sapling cv).
def jpoint(+nso: Bool, +s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    r : H.W <- H.word(s)
    s2 : H.S <- wcheck_jj(nso, r)
    return s2

# A CompactSize-prefixed byte string (Script, proof bytes).
def bytes_vec(+s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    +c : H.V <- CS.read(s)
    s2 : H.S <- H.skip(H.st(c), H.val(c))
    return s2


type Elt is Data:
  KIn{}
  KOut{}
  KSpend5{}
  KOut5{}
  KSpend4{}
  KOut4{}
  KJsPhgr{}
  KJsGroth{}
  KAct{}

def min_size(k: Elt) -> U32:
  match k:
    case KIn{}:
      41
    case KOut{}:
      9
    case KSpend5{}:
      96
    case KOut5{}:
      756
    case KSpend4{}:
      384
    case KOut4{}:
      948
    case KJsPhgr{}:
      1802
    case KJsGroth{}:
      1698
    case KAct{}:
      820

# zcash_transparent TxIn::read: outpoint (36), script_sig, sequence (4).
def txin(+s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    a : H.S <- H.skip(s, 36)
    b : H.S <- bytes_vec(a)
    c : H.S <- H.skip(b, 4)
    return c

# zcash_transparent TxOut::read: Zatoshis (0..=MAX_MONEY), script_pubkey.
def txout(+s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    a : H.S <- H.amount(True{}, s)
    b : H.S <- bytes_vec(a)
    return b

# sapling read_spend_v5: cv (not small order), nullifier, rk.
def spend5(+s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    a : H.S <- jpoint(True{}, s)
    b : H.S <- H.skip(a, 32)
    c : H.S <- jpoint(False{}, b)
    return c

# sapling read_output_v5: cv (not small order), cmu (canonical), epk, enc (580), out (80).
def out5(+s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    a : H.S <- jpoint(True{}, s)
    b : H.S <- frc(a)
    c : H.S <- H.skip(b, 692)
    return c

# sapling read_spend_v4: cv, anchor (canonical), nullifier, rk, zkproof (192), sig (64).
def spend4(+s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    a : H.S <- jpoint(True{}, s)
    b : H.S <- frc(a)
    c : H.S <- H.skip(b, 32)
    e : H.S <- jpoint(False{}, c)
    f : H.S <- H.skip(e, 256)
    return f

# sapling read_output_v4: cv, cmu, epk, enc, out, zkproof (192).
def out4(+s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    a : H.S <- jpoint(True{}, s)
    b : H.S <- frc(a)
    c : H.S <- H.skip(b, 884)
    return c

def js_rest(g: Bool) -> U32:
  match g:
    case True{}:
      1682
    case False{}:
      1786

# sprout JsDescription::read: vpub_old, vpub_new (ZatBalance::from_u64: <= MAX_MONEY), then
# anchor, 2 nullifiers, 2 commitments, ephemeral key, random seed, 2 macs (288 bytes), the
# proof (192 Groth16 or 296 PHGR) and two 601-byte ciphertexts.
def js(+groth: Bool, +s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    a : H.S <- H.amount(True{}, s)
    b : H.S <- H.amount(True{}, a)
    c : H.S <- H.skip(b, js_rest(groth))
    return c

# orchard read_action_without_auth + Action::from_parts: cv (Pallas point), nf (canonical),
# rk (Pallas point, not the identity), cmx (canonical), epk (Pallas point, not the identity),
# enc (580), out (80).
def action(+s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    a : H.S <- ppoint(True{}, s)
    b : H.S <- pbase(a)
    c : H.S <- ppoint(False{}, b)
    e : H.S <- pbase(c)
    f : H.S <- ppoint(False{}, e)
    g : H.S <- H.skip(f, 660)
    return g

def elem(k: Elt, +s: H.S) -> Maybe<&2, H.S>:
  match k:
    case KIn{}:
      txin(s)
    case KOut{}:
      txout(s)
    case KSpend5{}:
      spend5(s)
    case KOut5{}:
      out5(s)
    case KSpend4{}:
      spend4(s)
    case KOut4{}:
      out4(s)
    case KJsPhgr{}:
      js(False{}, s)
    case KJsGroth{}:
      js(True{}, s)
    case KAct{}:
      action(s)

def elems(n: Nat, +k: Elt, +s: H.S) -> Maybe<&2, H.S>:
  match n:
    case 0n:
      Some{s}
    case 1n+m:
      do Maybe<&2, H.S>:
        s2 : H.S <- elem(k, s)
        s3 : H.S <- elems(m, k, s2)
        return s3

def vec_fin(+n: U32, m: Maybe<&2, H.S>) -> Maybe<&2, H.V>:
  match m:
    case None{}:
      None{}
    case Some{s}:
      Some{H.V{n, s}}

def vec_go(fits: Bool, +k: Elt, c: H.V) -> Maybe<&2, H.V>:
  match fits:
    case False{}:
      None{}
    case True{}:
      H.V{+n, +s} = c
      vec_fin(n, elems(U32.to_nat(n), k, s))

# Bound the count by the remaining bytes before reading any element.
def vec_bounded(+k: Elt, c: H.V) -> Maybe<&2, H.V>:
  H.V{+n, +s} = c
  vec_go(U32.is_le(n, (H.rem(s) / min_size(k) : U32)), k, H.V{n, s})

# zcash_encoding Vector::read: a canonical CompactSize count, then that many elements.
# Answers the count and the cursor after the last element.
def vec(+k: Elt, +s: H.S) -> Maybe<&2, H.V>:
  do Maybe<&2, H.V>:
    +c : H.V <- CS.read(s)
    r : H.V <- vec_bounded(k, c)
    return r


def transparent(+s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    +a : H.V <- vec(KIn{}, s)
    +b : H.V <- vec(KOut{}, H.st(a))
    return H.st(b)

def when(b: Bool, +s: H.S, f: H.S -> Maybe<&2, H.S>) -> Maybe<&2, H.S>:
  match b:
    case True{}:
      f(s)
    case False{}:
      Some{s}

def sap5_tail(+ns: U32, +no: U32, +s: H.S) -> Maybe<&2, H.S>:
  +any = Bool.not(U32.is_eq(ns, 0) && U32.is_eq(no, 0))
  do Maybe<&2, H.S>:
    a : H.S <- when(any, s, x => H.amount(False{}, x))
    b : H.S <- when(Bool.not(U32.is_eq(ns, 0)), a, x => frc(x))
    c : H.S <- H.skip(b, (ns * 256 : U32))
    e : H.S <- H.skip(c, (no * 192 : U32))
    f : H.S <- when(any, e, x => H.skip(x, 64))
    return f

# sapling read_v5_bundle: spends, outputs, valueBalance and anchor when present, then the
# spend proofs + spend auth sigs (256 each), output proofs (192 each), binding sig.
def sapling5(+s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    +sp : H.V <- vec(KSpend5{}, s)
    +op : H.V <- vec(KOut5{}, H.st(sp))
    t : H.S <- sap5_tail(H.val(sp), H.val(op), H.st(op))
    return t

# sapling read_v4_components: valueBalance, spends, outputs; returns whether any are present.
type V4 is Data:
  V4{any: Bool, s: H.S}

def sapling4(+s: H.S) -> Maybe<&2, V4>:
  do Maybe<&2, V4>:
    a : H.S <- H.amount(False{}, s)
    +sp : H.V <- vec(KSpend4{}, a)
    +op : H.V <- vec(KOut4{}, H.st(sp))
    return V4{Bool.not(U32.is_eq(H.val(sp), 0) && U32.is_eq(H.val(op), 0)), H.st(op)}

def js_kind(g: Bool) -> Elt:
  match g:
    case True{}:
      KJsGroth{}
    case False{}:
      KJsPhgr{}

# Sprout joinsplits: a vector of JsDescription; when non-empty, pubkey (32) + sig (64).
def joinsplits(+groth: Bool, +s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    +j : H.V <- vec(js_kind(groth), s)
    t : H.S <- when(Bool.not(U32.is_eq(H.val(j), 0)), H.st(j), x => H.skip(x, 96))
    return t

# The Orchard-protocol bundle version a slot uses under a branch (bundle_version_for_branch).
type Bv is Data:
  BvNone{}
  Bv{insecure: Bool, orchard_pool: Bool}

# Flags::from_byte: bits 3..7 must be 0; bit 2 must be 0 for the Orchard pool.
def flags_ok(+b: U32, +orchard_pool: Bool) -> Bool:
  U32.is_eq((b .&. 248 : U32), 0) && (Bool.not(orchard_pool) || U32.is_eq((b .&. 4 : U32), 0))

def flags_check(+orchard_pool: Bool, r: H.V) -> Maybe<&2, H.S>:
  H.V{+b, +s} = r
  keep_s(flags_ok(b, orchard_pool), s)

# validate_proof_size: proof length = 2720 + 2272 * actions, except the InsecureV1 circuit.
def proof_check(+insecure: Bool, +n: U32, r: H.V) -> Maybe<&2, H.S>:
  H.V{+len, +s} = r
  keep_s(insecure || U32.is_eq(len, (2720 + 2272 * n : U32)), s)

def bundle_body(bv: Bv, +n: U32, +s: H.S) -> Maybe<&2, H.S>:
  match bv:
    case BvNone{}:
      None{}
    case Bv{+insecure, +orch}:
      do Maybe<&2, H.S>:
        f : H.V <- H.u8(s)
        a : H.S <- flags_check(orch, f)
        b : H.S <- H.amount(False{}, a)
        c : H.S <- pbase(b)
        +pl : H.V <- CS.read(c)
        e : H.S <- proof_check(insecure, n, pl)
        g : H.S <- H.skip(e, H.val(pl))
        h : H.S <- H.skip(g, (64 * n : U32))
        i : H.S <- H.skip(h, 64)
        return i

def bundle_sel(empty: Bool, bv: Bv, +n: U32, +s: H.S) -> Maybe<&2, H.S>:
  match empty:
    case True{}:
      Some{s}
    case False{}:
      bundle_body(bv, n, s)

def bundle_after(bv: Bv, +n: U32, +s: H.S) -> Maybe<&2, H.S>:
  bundle_sel(U32.is_eq(n, 0), bv, n, s)

# zcash_primitives components::orchard read_bundle: actions; if non-empty, the slot must be
# supported under the branch, then flags, valueBalance, anchor, proof, auth sigs, binding sig.
def bundle(bv: Bv, +s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    +a : H.V <- vec(KAct{}, s)
    b : H.S <- bundle_after(bv, H.val(a), H.st(a))
    return b


def known_branch(+b: U32) -> Bool:
  U32.is_eq(b, 0) || U32.is_eq(b, 1537743641) || U32.is_eq(b, 1991772603) ||
  U32.is_eq(b, 733220448) || U32.is_eq(b, 4122551051) || U32.is_eq(b, 3925833126) ||
  U32.is_eq(b, 3268858036) || U32.is_eq(b, 3370586197) || U32.is_eq(b, 1307332080) ||
  U32.is_eq(b, 1412952880) || U32.is_eq(b, 933566043) || U32.is_eq(b, 1998129881)

def is_nu63_plus(+b: U32) -> Bool:
  U32.is_eq(b, 933566043) || U32.is_eq(b, 1998129881)

def is_nu5_insecure(+b: U32) -> Bool:
  U32.is_eq(b, 3268858036) || U32.is_eq(b, 3370586197) || U32.is_eq(b, 1307332080)

def bv_v2(v2plus: Bool) -> Bv:
  match v2plus:
    case True{}:
      Bv{False{}, True{}}
    case False{}:
      BvNone{}

def orchard_bv_sel(+ins: Bool, +v2plus: Bool) -> Bv:
  match ins:
    case True{}:
      Bv{True{}, True{}}
    case False{}:
      bv_v2(v2plus)

def orchard_bv(+b: U32) -> Bv:
  orchard_bv_sel(is_nu5_insecure(b), U32.is_eq(b, 1412952880) || is_nu63_plus(b))

def ironwood_sel(ok: Bool) -> Bv:
  match ok:
    case True{}:
      Bv{False{}, False{}}
    case False{}:
      BvNone{}

def ironwood_bv(+b: U32) -> Bv:
  ironwood_sel(is_nu63_plus(b))

def keep_v(ok: Bool, v: H.V) -> Maybe<&2, H.V>:
  match ok:
    case True{}:
      Some{v}
    case False{}:
      None{}

def branch_check(r: H.V) -> Maybe<&2, H.V>:
  H.V{+b, +s} = r
  keep_v(known_branch(b), H.V{b, s})

# read_header_fragment: a known consensus branch id, lock_time, expiry_height.
def header_fragment(+s: H.S) -> Maybe<&2, H.V>:
  do Maybe<&2, H.V>:
    r : H.V <- H.u32le(s)
    +b : H.V <- branch_check(r)
    t : H.S <- H.skip(H.st(b), 8)
    return H.V{H.val(b), t}

# read_v5: header fragment, transparent, Sapling v5, Orchard slot.
def tx_v5(+s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    +h : H.V <- header_fragment(s)
    t : H.S <- transparent(H.st(h))
    sp : H.S <- sapling5(t)
    o : H.S <- bundle(orchard_bv(H.val(h)), sp)
    return o

# read_v6: header fragment, transparent, Sapling v5, Orchard slot, Ironwood slot.
def tx_v6(+s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    +h : H.V <- header_fragment(s)
    t : H.S <- transparent(H.st(h))
    sp : H.S <- sapling5(t)
    o : H.S <- bundle(orchard_bv(H.val(h)), sp)
    i : H.S <- bundle(ironwood_bv(H.val(h)), o)
    return i

def v4_binding(r: V4) -> Maybe<&2, H.S>:
  V4{+any, +s} = r
  when(any, s, x => H.skip(x, 64))

def v4_s(r: V4) -> H.S:
  V4{_, +s} = r
  s

def v4_any(r: V4) -> Bool:
  V4{+any, _} = r
  any

# read_v4 for V4: transparent, lock, expiry, Sapling v4 components, Groth16 joinsplits,
# then the binding signature when there are Sapling spends or outputs.
def tx_v4(+s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    t : H.S <- transparent(s)
    a : H.S <- H.skip(t, 8)
    +sap : V4 <- sapling4(a)
    j : H.S <- joinsplits(True{}, v4_s(sap))
    b : H.S <- v4_binding(V4{v4_any(sap), j})
    return b

# read_v4 for V3: transparent, lock, expiry, PHGR joinsplits.
def tx_v3(+s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    t : H.S <- transparent(s)
    a : H.S <- H.skip(t, 8)
    j : H.S <- joinsplits(False{}, a)
    return j

# read_v4 for Sprout(v): transparent, lock; PHGR joinsplits when v >= 2.
def tx_sprout(+v: U32, +s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    t : H.S <- transparent(s)
    a : H.S <- H.skip(t, 4)
    j : H.S <- when(U32.is_le(2, v), a, x => joinsplits(False{}, x))
    return j

def by_v6(m: Bool, +s: H.S) -> Maybe<&2, H.S>:
  match m:
    case True{}:
      tx_v6(s)
    case False{}:
      None{}

def by_v5(m: Bool, +ver: U32, +g: U32, +s: H.S) -> Maybe<&2, H.S>:
  match m:
    case True{}:
      tx_v5(s)
    case False{}:
      by_v6(U32.is_eq(ver, 6) && U32.is_eq(g, 3632576152), s)

def by_v4(m: Bool, +ver: U32, +g: U32, +s: H.S) -> Maybe<&2, H.S>:
  match m:
    case True{}:
      tx_v4(s)
    case False{}:
      by_v5(U32.is_eq(ver, 5) && U32.is_eq(g, 648488714), ver, g, s)

def by_v3(m: Bool, +ver: U32, +g: U32, +s: H.S) -> Maybe<&2, H.S>:
  match m:
    case True{}:
      tx_v3(s)
    case False{}:
      by_v4(U32.is_eq(ver, 4) && U32.is_eq(g, 2301567109), ver, g, s)

def by_group(+ver: U32, r: H.V) -> Maybe<&2, H.S>:
  H.V{+g, +s} = r
  by_v3(U32.is_eq(ver, 3) && U32.is_eq(g, 63210096), ver, g, s)

def overwintered(+ver: U32, +s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    g : H.V <- H.u32le(s)
    t : H.S <- by_group(ver, g)
    return t

def sprout_or_none(ok: Bool, +ver: U32, +s: H.S) -> Maybe<&2, H.S>:
  match ok:
    case True{}:
      tx_sprout(ver, s)
    case False{}:
      None{}

def by_header(ow: Bool, +ver: U32, +s: H.S) -> Maybe<&2, H.S>:
  match ow:
    case True{}:
      overwintered(ver, s)
    case False{}:
      sprout_or_none(U32.is_le(1, ver), ver, s)

def after_header(r: H.V) -> Maybe<&2, H.S>:
  H.V{+h, +s} = r
  by_header(U32.is_eq((h >> 31n : U32), 1), (h .&. 2147483647 : U32), s)

# TxVersion::read, then the version's reader. Answers the cursor after the transaction.
def tx(+s: H.S) -> Maybe<&2, H.S>:
  do Maybe<&2, H.S>:
    +h : H.V <- H.u32le(s)
    t : H.S <- after_header(h)
    return t

def is_some_done(m: Maybe<&2, H.S>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{s}:
      H.is_done(s)

# A whole byte string is exactly one valid transaction.
def valid(+bs: +List<U32>) -> Bool:
  is_some_done(tx(H.start(bs)))
