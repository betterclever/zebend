# zcash/block: a raw Zcash block, split into transactions and committed to its header.
#
#  - hashMerkleRoot: Bitcoin-style SHA-256d Merkle tree over txids, the last node
#    duplicated on odd levels. v5/v6 txids are ZIP 244 digests (computed by ./tx.bend);
#    v4 txids are SHA-256d of the raw transaction.
#  - hashBlockCommitments (NU5+, ZIP 244):
#      BLAKE2b-256("ZcashBlockCommit", hashLightClientRoot || hashAuthDataRoot || [0; 32])
#    hashAuthDataRoot: BLAKE2b-256("ZcashAuthDatHash") Merkle tree over each transaction's
#    authorizing-data digest, padded with [0; 32] leaves to a power of two. A v4 (or older)
#    transaction contributes the placeholder [0xff; 32].
#    hashLightClientRoot (the ZIP 221 chain history root) is an INPUT here, not computed.
import Base
import ./tx.bend as T
import ./blake2b.bend as B
import ./sha256.bend as S
import ./bytes.bend as Y

def cat(a: +List<U32>, b: +List<U32>) -> +List<U32>:
  T.cat(a, b)

def fill(+n: Nat, +v: U32) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      v <> fill(p, v)

def is_pos(+n: Nat) -> Bool:
  T.nat_pos(n)

# ------------------------------------------------------------------ v4 (pre-ZIP 225) length

# header 4 | nVersionGroupId 4 | vin | vout | nLockTime 4 | nExpiryHeight 4 | valueBalance 8 |
# vShieldedSpend (CompactSize, 384 each) | vShieldedOutput (CompactSize, 948 each) |
# vJoinSplit (CompactSize, 1698 each, Groth16) | joinSplitPubKey 32 + joinSplitSig 64 (if any) |
# bindingSig 64 (if any spends or outputs)
def if_pos(+k: Nat, +bytes: Nat) -> Nat:
  match k:
    case 0n:
      0n
    case 1n+p:
      bytes

def v4_end(+xs: +List<U32>) -> Nat:
  +nvin = T.cs_val(xs, 8n)
  +vin0 = (8n + T.cs_size(xs, 8n) : Nat)
  +vout_pos = T.vin_end(nvin, xs, vin0)
  +nvout = T.cs_val(xs, vout_pos)
  +sp = (T.vout_end(nvout, xs, (vout_pos + T.cs_size(xs, vout_pos) : Nat)) + 16n : Nat)
  +ns = T.cs_val(xs, sp)
  +op = (sp + T.cs_size(xs, sp) + (ns * 384n : Nat) : Nat)
  +no = T.cs_val(xs, op)
  +jp = (op + T.cs_size(xs, op) + (no * 948n : Nat) : Nat)
  +nj = T.cs_val(xs, jp)
  (jp + T.cs_size(xs, jp) + (nj * 1698n : Nat) + if_pos(nj, 96n) + if_pos((ns + no : Nat), 64n) : Nat)

# ------------------------------------------------------------------ ZIP 244 authorizing digests (v5, v6)

# Transparent: every input's scriptSig, as serialized (CompactSize length + bytes).
def script_sigs(+n: Nat, +xs: +List<U32>, +pos: Nat) -> +List<U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      +sp = (pos + 36n : Nat)
      cat(T.at(xs, sp, (T.cs_size(xs, sp) + T.cs_val(xs, sp) : Nat)), script_sigs(p, xs, T.txin_end(xs, pos)))

# Sapling (v5 layout, also v6): after the outputs come valueBalance (8), anchor (32 if spends),
# then exactly the authorizing data in hashing order: spend proofs (192 each), spend-auth
# sigs (64 each), output proofs (192 each), binding sig (64). v6 also hashes the anchor.
def sap_pers(v6: Bool) -> B.P4:
  match v6:
    case True{}:
      B.P.ZTxAuthSapliH_v6()
    case False{}:
      B.P.ZTxAuthSapliHash()

def sap_v6_anchor(v6: Bool, +ns: Nat, +xs: +List<U32>, +ae: Nat) -> +List<U32>:
  match v6:
    case True{}:
      match ns:
        case 0n:
          Nil{}
        case 1n+p:
          T.at(xs, (ae + 8n : Nat), 32n)
    case False{}:
      Nil{}

def sap_auth_any(any: Bool, +v6: Bool, +ns: Nat, +no: Nat, +xs: +List<U32>, +ae: Nat) -> +List<U32>:
  match any:
    case True{}:
      +start = (ae + 8n + T.sap_anchor_len(ns) : Nat)
      B.hash32(sap_pers(v6), cat(T.at(xs, start, ((ns * 256n : Nat) + (no * 192n : Nat) + 64n : Nat)), sap_v6_anchor(v6, ns, xs, ae)))
    case False{}:
      B.hash32(sap_pers(v6), Nil{})

def sap_auth(+xs: +List<U32>, +pos: Nat, +v6: Bool) -> +List<U32>:
  +ns = T.cs_val(xs, pos)
  +sp = (pos + T.cs_size(xs, pos) : Nat)
  +opos = (sp + (ns * 96n : Nat) : Nat)
  +no = T.cs_val(xs, opos)
  +op = (opos + T.cs_size(xs, opos) : Nat)
  sap_auth_any(T.nat_pos((ns + no : Nat)), v6, ns, no, xs, (op + (no * 756n : Nat) : Nat))

# Orchard / Ironwood: proof bytes (no length prefix) || spend-auth sigs || binding sig,
# plus the anchor for the v6 formats.
def bnd_pers(f: T.Fmt) -> B.P4:
  match f:
    case T.OrchardV5{}:
      B.P.ZTxAuthOrchaHash()
    case T.OrchardV6{}:
      B.P.ZTxAuthOrchaH_v6()
    case T.IronwoodV6{}:
      B.P.ZTxAuthIrnwdH_v6()

def bnd_anchor(f: T.Fmt, +xs: +List<U32>, +tail: Nat) -> +List<U32>:
  match f:
    case T.OrchardV5{}:
      Nil{}
    case _:
      T.at(xs, (tail + 9n : Nat), 32n)

def bnd_auth_any(any: Bool, +xs: +List<U32>, b: T.Bnd) -> +List<U32>:
  match any:
    case True{}:
      T.Bnd{+f, +n, _, +tail, +sigs, _} = b
      +pp = (tail + 41n : Nat)
      B.hash32(bnd_pers(f), cat(T.at(xs, (pp + T.cs_size(xs, pp) : Nat), T.cs_val(xs, pp)),
        cat(T.at(xs, sigs, ((n * 64n : Nat) + 64n : Nat)), bnd_anchor(f, xs, tail))))
    case False{}:
      T.Bnd{+f, _, _, _, _, _} = b
      B.hash32(bnd_pers(f), Nil{})

def bnd_auth(+xs: +List<U32>, +b: T.Bnd) -> +List<U32>:
  bnd_auth_any(T.nat_pos(T.bnd_n(b)), xs, b)

def auth56(+xs: +List<U32>, +tx: T.Tx) -> +List<U32>:
  T.Tx{+v6, +branch, +nvin, +vin0, +nvout, +vout0, _, +orch, +iron} = tx
  +ta = B.hash32(B.P.ZTxAuthTransHash(), script_sigs(nvin, xs, vin0))
  +sa = sap_auth(xs, T.vout_end(nvout, xs, vout0), v6)
  B.hash32(B.P.ZTxAuthHash(branch), cat(ta, cat(sa, cat(bnd_auth(xs, orch), T.iron_part(v6, bnd_auth(xs, iron))))))

def txid56(+xs: +List<U32>, +tx: T.Tx) -> +List<U32>:
  T.Tx{+v6, +branch, _, _, _, _, +sap, +orch, +iron} = tx
  +hd = B.hash32(B.P.ZTxIdHeadersHash(), T.at(xs, 0n, 20n))
  T.root(v6, branch, hd, T.t_txid(T.t_digests(xs, tx)), T.sap_digest(sap), T.bnd_digest(xs, orch), T.bnd_digest(xs, iron))

def end56(t: T.Tx) -> Nat:
  T.Tx{_, _, _, _, _, _, _, _, iron} = t
  T.bnd_end(iron)

# ------------------------------------------------------------------ one transaction

# (byte length, txid, auth digest, version)
type Info is Data:
  Info{+len: Nat, +txid: +List<U32>, +auth: +List<U32>, +ver: U32}

def info56(+xs: +List<U32>, +ver: U32, +tx: T.Tx) -> Info:
  Info{end56(tx), txid56(xs, tx), auth56(xs, tx), ver}

def info4(+xs: +List<U32>, +ver: U32, +len: Nat) -> Info:
  Info{len, S.hash_d(Y.take(xs, len)), fill(32n, 255), ver}

def info_sel(new: Bool, +xs: +List<U32>, +ver: U32) -> Info:
  match new:
    case True{}:
      info56(xs, ver, T.parse(xs))
    case False{}:
      info4(xs, ver, v4_end(xs))

# xs starts at the transaction (and runs on to the end of the block).
def info(+xs: +List<U32>) -> Info:
  +ver = (T.u32_at(xs, 0n) .&. 2147483647 : U32)
  info_sel(U32.is_ge(ver, 5), xs, ver)

# ------------------------------------------------------------------ Merkle trees

def sha_pairs(xs: List<&2, +List<U32>>) -> List<&2, +List<U32>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+a, Nil{}}:
      S.hash_d(cat(a, a)) <> Nil{}
    case Con{a, Con{b, t}}:
      S.hash_d(cat(a, b)) <> sha_pairs(t)

def blake_pairs(xs: List<&2, +List<U32>>) -> List<&2, +List<U32>>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{+a, Nil{}}:
      B.hash32(B.P.ZcashAuthDatHash(), cat(a, fill(32n, 0))) <> Nil{}
    case Con{a, Con{b, t}}:
      B.hash32(B.P.ZcashAuthDatHash(), cat(a, b)) <> blake_pairs(t)

def level_sel(sha: Bool, xs: List<&2, +List<U32>>) -> List<&2, +List<U32>>:
  match sha:
    case True{}:
      sha_pairs(xs)
    case False{}:
      blake_pairs(xs)

# kind 0 = SHA-256d (hashMerkleRoot), 1 = BLAKE2b "ZcashAuthDatHash" (hashAuthDataRoot)
def level(+kind: U32, xs: List<&2, +List<U32>>) -> List<&2, +List<U32>>:
  level_sel(U32.is_zero(kind), xs)

def iter(k: Nat, +kind: U32, xs: List<&2, +List<U32>>) -> List<&2, +List<U32>>:
  match k:
    case 0n:
      xs
    case 1n+p:
      iter(p, kind, level(kind, xs))

def head_l(xs: List<&2, +List<U32>>) -> +List<U32>:
  match xs:
    case Con{a, _}:
      a
    case Nil{}:
      Nil{}

def len_l(xs: List<&2, +List<U32>>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case Con{_, t}:
      1n+len_l(t)

# (2^e, e) with 2^e the smallest power of two >= n (n >= 1), by 64 unconditional steps.
def lstep(less: Bool, +k: Nat, +e: Nat) -> Nat & Nat:
  match less:
    case True{}:
      ((k * 2n : Nat), 1n+e)
    case False{}:
      (k, e)

def lstep_pair(s: Nat & Nat, +n: Nat) -> Nat & Nat:
  (+k, +e) = s
  lstep(Nat.is_lt(k, n), k, e)

def clog2_go(fuel: Nat, s: Nat & Nat, +n: Nat) -> Nat & Nat:
  match fuel:
    case 0n:
      s
    case 1n+p:
      clog2_go(p, lstep_pair(s, n), n)

def pow2_of(s: Nat & Nat) -> Nat:
  (k, _) = s
  k

def log2_of(s: Nat & Nat) -> Nat:
  (_, e) = s
  e

def app_l(xs: List<&2, +List<U32>>, ys: List<&2, +List<U32>>) -> List<&2, +List<U32>>:
  match xs:
    case Nil{}:
      ys
    case Con{h, t}:
      h <> app_l(t, ys)

def zero_leaves(+k: Nat) -> List<&2, +List<U32>>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      fill(32n, 0) <> zero_leaves(p)

def merkle_root(+ids: List<&2, +List<U32>>) -> +List<U32>:
  head_l(iter(log2_of(clog2_go(64n, (1n, 0n), len_l(ids))), 0, ids))

def auth_root(+auths: List<&2, +List<U32>>) -> +List<U32>:
  +n = len_l(auths)
  head_l(iter(log2_of(clog2_go(64n, (1n, 0n), n)), 1, app_l(auths, zero_leaves(Nat.sub(pow2_of(clog2_go(64n, (1n, 0n), n)), n)))))

def block_commitments(+hist: +List<U32>, +aroot: +List<U32>) -> +List<U32>:
  B.hash32(B.P.ZcashBlockCommit(), cat(hist, cat(aroot, fill(32n, 0))))
