# sapling-oracle

Rust ground truth for Zebend's Sapling work (Jubjub, RedJubjub, Sapling note-commitment tree,
v4/v5 Sapling transactions). Every verdict and every value here comes from the official Zcash
crates: sapling-crypto 0.9.0, redjubjub 0.9.0 (on reddsa 0.6.1), jubjub 0.11.1, bls12_381 0.9.0,
zcash_primitives 0.31.0, incrementalmerkletree 0.9.0. Mainnet data comes from lightwalletd
(zec.rocks, na.zec.rocks, eu.zec.rocks). All outputs go to `../data/` (git-ignored).

Build/run on the Mac: `../../heavy.sh cargo build --release --offline`, then
`target/release/sapling-oracle CMD`.

## Byte-order conventions (read this first)

* Field elements (Fq = bls12_381::Scalar = Jubjub base field; Fr = jubjub::Fr) and point
  encodings: the crates' own 32-byte **little-endian** `to_bytes()` / `to_repr()`, as hex.
  A Jubjub point encoding is LE(v) with the sign of u in bit 255 (bit 7 of byte 31).
* cmu, nullifiers, tree roots, subtree roots: exactly the 32 bytes on the wire (= Fq LE repr for
  cmu/roots).
* txids, sighashes, digests: the raw 32 hash-output bytes ("internal order", the same bytes
  lightwalletd's CompactTx.txid carries). Block explorers / RPC show the txid **byte-reversed**.
* Integers in binary files: little-endian.

## Commands and outputs

| command | output |
|---|---|
| `sync FROM TO [WORKERS]` | `sapling_leaves.bin` 36-byte records `u32 height | cmu[32]` in tree order; `sapling_nfs.bin` 36-byte records `u32 height | nf[32]` in chain order; `sapling_sync.progress` (resume point). Chunk-atomic: a chunk is appended only if, for every block, chain `saplingCommitmentTreeSize` = previous size + outputs in that block, and the chunk's starting size equals the leaf count already on disk. Concurrent fetch, in-order append, resumable (env `STEP` = blocks per chunk). |
| `subtrees` | `sapling_subtrees.txt`: `index completing_height roothex` (GetSubtreeRoots, sapling, level 16) |
| `trees H...` | `sapling_trees.txt`: `height size roothex` (GetTreeState saplingTree parsed into `incrementalmerkletree::frontier::CommitmentTree<sapling::Node,32>`; root via `Hashable::combine`) |
| `rebuild` (env `FRONTIER_ONLY=1` skips the subtree part) | rebuilds the tree from `sapling_leaves.bin` in Rust, checks it against subtree roots + tree states, prints timings |
| `vectors [SEED]` | `vectors/*.txt` (below) |
| `scan FROM TO WINDOW STRIDE` | appends `sig_txids.txt`: `height txid n_spends n_outputs n_vin` for txs with >=1 Sapling spend or output, in windows of WINDOW blocks every STRIDE blocks |
| `fetch [CONC]` | `sig_raw.bin`: records `u32 height | txid[32] | u32 len | raw tx` (GetTransaction; resumable) |
| `build [MAXSIGS]` | `sigs/chunk_XXXX.bin`, `sigs/verdicts_XXXX.txt`, `sigs/manifest.txt` |
| `tamper K FIELD I [BYTE] [MASK]` | `sigs/tamper_<FIELD>_<K>_<I>.bin`; prints the Rust verdict of item I |
| `tampermix [N] [SEED]` | `sigs/tampermix_XXXX.bin` + `tampermix_verdicts_XXXX.txt` + `tampermix_flips_XXXX.txt` |
| `rust THREADS` | prints batch and single-signature verification throughput over all chunks |
| `parsetime THREADS` | times Transaction::read + txid + shielded sighash over all of sig_raw.bin |
| `txs [PER_VERSION]` | `txs/tx_N.bin`, `txs/tx_N.ctx`, `txs/expected.txt` |

## Data formats

### Chain (`sync`, `subtrees`, `trees`, `rebuild`)

* `sapling_leaves.bin`: 36-byte records `u32 LE height | cmu[32]` (cmu exactly as on the wire = Fq LE repr), in note-commitment-tree order, Sapling activation 419200 through 3528268.
* `sapling_nfs.bin`: 36-byte records `u32 LE height | nf[32]`, in chain order (no chain-side count to check against; block-range completeness is checked).
* `sapling_subtrees.txt`: `index completing_height roothex` — level-16 roots (2^16 leaves each).
* `sapling_trees.txt`: `height size roothex`. Root = MerkleCRH^Sapling tree root (Node LE bytes; depth 32; empty leaf = 1).
* `sapling_trees_header_check.txt`: the tree-state roots compared with the block header field at bytes 68..100 (raw blocks from api.blockchair.com). That field is `hashFinalSaplingRoot` only before Heartwood (903000); afterwards it is hashLightClientRoot / hashBlockCommitments, so only pre-Heartwood heights are compared (6/6 match: 419200, 419201, 500000, 653600, 900000, 902999). Later heights are cross-checked by our own rebuild from the leaves instead.

### Vectors (`vectors/`, seed 2026, ChaCha20Rng)

All values 32-byte LE hex unless stated. Each file starts with `#` header lines describing the columns.

* `fr.txt` (bls12_381::Scalar = Jubjub base field Fq): 2000 lines `a b a+b a-b a*b a^2 inv(a)|none sqrt(a)|none` (200 from edge values 0,1,2,3,-1,-2, 2^-1, -2^-1, root of unity, generator, p-1, 2^64-1, 2^k; 1800 random). `sqrt` is the root `Scalar::sqrt` returns (compare up to sign, or reproduce its Tonelli–Shanks choice). Then `canon bytes 1|0` lines (`Scalar::from_bytes` canonicity; p-2..p+2 and random 255-bit values).
* `fs.txt` (jubjub::Fr): `wide wide64hex reducedhex` (`Fr::from_bytes_wide`, 4 edge + 1000 random); `canon bytes 1|0` (`Fr::from_bytes`, r-2..r+2 + 1000 random with mixed top bytes, ~half canonical); `arith a b a+b a*b -a inv(a)|none` (500).
* `points.txt`:
  * `decode bytes zip216|none pre_zip216|none` — `AffinePoint::from_bytes` (ZIP 216 enforced) and `from_bytes_pre_zip216_compatibility`, result = re-encoding. 1000 random strings, plus identity, (u=0,v=1) with sign bit set (ZIP 216 rejects, pre-216 accepts), v=-1 with/without sign, v = q+k for k in {0,1,2,3,100} (non-canonical v, both sign bits), and 20 encodings v+q of valid points (all rejected: jubjub requires canonical v).
  * `add P Q P+Q 2P` (500, random full-curve points incl. torsion components).
  * `mul P k [k]P` (500; k a canonical Fr; P alternately full-curve and prime-order subgroup).
  * `order P [8]P is_small_order is_torsion_free` (300 + the 8 torsion points).
  * `torsion u v encoding` — the 8 points of order dividing 8.
* `consts.txt`: `name u v encoding` for SPENDING_KEY_GENERATOR (spend-auth base G), VALUE_COMMITMENT_VALUE_GENERATOR (V), VALUE_COMMITMENT_RANDOMNESS_GENERATOR (R), NOTE_COMMITMENT_RANDOMNESS_GENERATOR, NULLIFIER_POSITION_GENERATOR, PROOF_GENERATION_KEY_GENERATOR, PEDERSEN_HASH_GENERATORS[0..5] (all 6); `EDWARDS_D` (= -10240/10241, checked against the curve equation), `FQ_MODULUS`, `FR_MODULUS` (LE), `EMPTY_ROOT level hex` for levels 0..32 (level 0 = 1; level 32 = fbc2f430…493e = the chain's empty-tree root).
* `merkle.txt`: `merkle level lhs rhs out` (1000; levels 0..31; `Node::combine`, asserted equal to `sapling_crypto::merkle_hash`; note MerkleCRH uses only the low 255 bits of each input, LSB-first). `pedersen pers nbits bits01 u v` (200): `pedersen_hash(pers, bits)`; pers 0..62 = MerkleTree(pers) (6 bits LSB-first), 63 = NoteCommitment (bits 111111); `bits01` = message bits in order as a 0/1 string AFTER the 6 personalization bits (`-` if empty); max 1128 message bits (6 generators × 63 chunks × 3 bits − 6).
* `sig.txt`: `kind vk R s msg valid` — 500 spendauth + 500 binding fresh signatures (redjubjub `SigningKey::new` + `sign`, 32-byte random msg; all valid), each followed by a tampered copy (`tamper=<R|s|vk|msg>:<bit>`, one bit flipped; all 1000 rejected), plus 96 `edge=` lines: `manual` (our own H*/sign construction with T=0 → valid, cross-checks the challenge), `R=[n]G+T` (hand-made signature whose R has a nonzero small-order component: **valid** under cofactored verification), `s+r` (s + r_J, non-canonical → invalid), `vk+T` (→ invalid).
  * Verdict API: `redjubjub::VerificationKey::<T>::try_from(vk_bytes)` (fails → 0) then `.verify(msg, &Signature::<T>::from(R||s))`. That is reddsa 0.6.1: c = BLAKE2b-512("Zcash_RedJubjubH", R̄ || vk̄ || msg) reduced mod r_J (`Fr::from_bytes_wide`); s must be canonical (< r_J); R and vk must decode (ZIP 216 canonical); accept iff [8]([s]B − [c]vk − R) = 0 (implemented as `is_small_order` of `sB − cA − R`). B = SPENDING_KEY_GENERATOR for spend-auth, VALUE_COMMITMENT_RANDOMNESS_GENERATOR for binding. Small-order vk is NOT rejected by this API (Zcash rejects small-order rk separately in consensus).

### Signature chunks (`sigs/`)

`chunk_XXXX.bin` (≤ 8192 items, no tx split across chunks), all integers u32 LE:

```
u32 item_count
per item:
  u32 kind            0 = spend-auth, 1 = binding
  u32 ncv             n_spend_cv | (n_output_cv << 16); 0 for spend-auth
  u32 vb_lo, u32 vb_hi   valueBalanceSapling as i64 two's complement (0 for spend-auth items)
  R̄[32] s[32]         the signature (R̄ = point encoding, s = Fr LE)
  msg[32]             the shielded sighash (SIGHASH_ALL, SignableInput::Shielded)
  vk[32]              rk for spend-auth; zeros for binding (not used)
  cv[32] * (n_spend + n_output)   spends' cv first, then outputs' cv (binding only)
```

Binding key: bvk = Σ cv_spend − Σ cv_output − [valueBalance] V (V = VALUE_COMMITMENT_VALUE_GENERATOR; negative valueBalance → [|vb|](−V)), encoded and fed to `VerificationKey::<Binding>::try_from`.

* `verdicts_XXXX.txt`: one `0|1` per item, from per-signature verification of the parsed tx: spend-auth = `spend.rk().verify(sighash, spend.spend_auth_sig())`; binding = redjubjub `VerificationKey::<Binding>::try_from(bvk)` + `verify(sighash, binding_sig)`. Each item's encoded bytes were also re-decoded and re-verified (same verdict asserted).
* `manifest.txt`: `chunk index txid height version kind` per item (txid internal byte order).
* Sighash: `zcash_primitives::transaction::sighash::PrecomputedSighashData::new(tx).signature_hash(&SignableInput::Shielded)` — ZIP 243 for v4, ZIP 244 for v5. The transparent spent-output context is supplied through a custom `TransparentAuthorizingContext` (empty for the chunks). zcash_primitives' txid is asserted equal to lightwalletd's for every tx.
* Exclusions: v5 txs with transparent inputs (their ZIP 244 shielded sighash needs the spent outputs; prevouts were not fetched for the 20,431 such txs) and v6 txs (post-NU6.3, 2,372).
* `tamper_<F>_<K>_<I>.bin`: copy of chunk K with one byte of item I's field F (R|s|msg|vk|vb|cv) XORed; the command prints the Rust verdict (verify from the item bytes). Flipping `vk` of a binding item or `vb` of a spend-auth item does not change the verdict (field unused). Files present: fields R,s,msg,vk,vb,cv on chunk 0 item 0 (binding; byte 5 ^ 0x10: verdicts 0,0,0,1,0,0) and R,s,msg,vk,vb on chunk 3 item 1 (spend-auth; byte 7 ^ 0x01: verdicts 0,0,0,0,1).
* `tampermix_XXXX.bin` (chunks 0..3, seed 2026): ~5% of items get one random bit flipped in a random field; `tampermix_verdicts_XXXX.txt` = Rust per-item verdict; `tampermix_flips_XXXX.txt` = `item field byte mask`. Counts: 0000: 8191 items/451 flipped/372 invalid; 0001: 8191/474/399; 0002: 8192/396/318; 0003: 8192/412/359.

### Tx sample (`txs/`)

`tx_N.bin` raw tx; `tx_N.ctx` = node/tx's format: `u32 len | amounts (i64 LE each) | u32 len | scripts (compactsize||scriptPubKey each)` — exactly the bytes ZIP 244 hashes for amounts/scripts; `00000000 00000000` when there are no transparent inputs (always for v4). `expected.txt`:

```
N height version branch_id txid sighash n_spends n_outputs value_balance n_tin n_tout n_joinsplit has_orchard | v4: hashPrevouts hashSequence hashOutputs hashJoinSplits hashShieldedSpends hashShieldedOutputs | v5: sapling_digest
```

branch_id is the u32 as 8 hex digits (e.g. 76b809bb Sapling, c2d6d0b4 NU5); txid/sighash/digests are raw hash bytes (internal order); value_balance signed decimal. v4 ZIP 243 digests are computed by an independent raw-byte parser in `txs.rs` (zero digest where ZIP 243 says so, BLAKE2b of the empty string for prevouts/sequence/outputs with no transparent inputs/outputs) and the resulting sighash is asserted equal to zcash_primitives'. v5 `sapling_digest` = ZIP 244 T.3 from zcash_primitives' `TxIdDigester`. v5 txs with transparent inputs are included (40), with prevouts fetched from lightwalletd into `.ctx`. Every Sapling signature of every sample tx verifies under the listed sighash.

## What was run (2026-10-26, Mac, 18 cores) — exact results

**Sync** `sync 419200 3528268` (STEP 1000 then 100; 6 then 12 workers; 5655 s wall in the final resumed run, ~1.6 h total, network-bound in the 2022 spam era): **73,989,124 leaves** (= chain `saplingCommitmentTreeSize` at 3528268, checked per block) and **2,147,491 nullifiers**. `sapling_leaves.bin` 2.66 GB, `sapling_nfs.bin` 77 MB.

**Subtrees**: 1,128 level-16 roots (index 0 completes at 558822, index 1127 at 3390009).
**Trees**: 13 heights (419200, 419201, 500000, 653600, 900000, 902999, 1000000, 1046400 Canopy, 1687104 NU5, 2000000, 2500000, 3000000, 3528268); size at 3528268 = 73,989,124, root de891f1e…8205.

**Rust tree baseline** (`rebuild`, sapling_crypto `Node::combine` = Pedersen MerkleCRH):
* 1,128 level-16 subtree roots (73,924,608 leaves, 73.9 M hashes): **1 thread 1980.6 s**, **18 threads (rayon, one subtree per task) 182.2 s**; **1128/1128 equal the chain's GetSubtreeRoots**.
* Full sequential `Frontier<Node,32>` append of all 73,989,124 leaves, roots checked at every tree-state height: **3161.1 s single thread (23,406 leaves/s)** (`FRONTIER_ONLY=1 rebuild`; ran alone under heavy.sh but the process showed low CPU share at times, so this is an upper bound); final root de891f1e…8205 = the chain's root at 3528268; **12/12 non-empty tree-state roots matched** (the 13th, 419200, is the empty tree).

**Vectors**: fr 2000 + 205 canon; fs 1004 wide + 1005 canon + 500 arith; points 1036 decode + 500 add + 500 mul + 308 order + 8 torsion; consts 6 generators + 6 Pedersen generators + d + moduli + 33 empty roots; merkle 1000 + 200 Pedersen; sig 1000 valid + 1000 tampered (all rejected) + 96 edge (32 accepted, 64 rejected).

**Signature corpus**: scan windows — 420000–1699999 (2000 blocks every 40000), 1700000–1949999 (100 every 25000, spam era), 1950000–2726399 (2000 every 25000), 2726400–3528268 (2000 every 8000): 130,378 txs with Sapling spends/outputs, all fetched (885 MB raw, `sig_raw.bin`). `build`: **29 chunks, 230,769 signatures, 0 officially invalid**:

| version | txs | spend-auth | binding | total |
|---|---|---|---|---|
| v4 | 59,055 | 53,860 | 59,055 | 112,915 |
| v5 | 48,520 | 69,334 | 48,520 | 117,854 |
| all | 107,575 | 123,194 | 107,575 | 230,769 |

Excluded: 20,431 v5 txs with transparent inputs (no prevouts fetched), 2,372 v6 txs. Heights 420066 … 3528212.

**Rust signature baseline** (`rust THREADS`, all 29 chunks; batch = `redjubjub::batch::Verifier` per chunk, rayon over chunks; decoding untimed, bvk inside timing):
* 1 thread: batch 27.68 s = **8,336 sigs/s**; single 56.17 s = **4,108 sigs/s**.
* 18 threads: batch 2.84 s = **81,280 sigs/s** (29 chunks over 18 threads, so the tail is imbalanced); single 8.25 s = **27,963 sigs/s** (an earlier run on a 12-chunk partial set measured 56,463 sigs/s single at 18 threads; the sync was competing for the machine during this one, so treat it as noisy).

**Rust parse baseline** (`parsetime THREADS`: `Transaction::read` + `txid()` (asserted = lightwalletd's) + shielded sighash, over all 130,378 txs / 885 MB of `sig_raw.bin`; 21,224 v5/v6 txs with transparent inputs get parse+txid only): 1 thread 31.37 s = **4,156 tx/s**; 18 threads 3.91 s = **33,375 tx/s**.

**Tx sample** (`txs 200`): 400 txs (200 v4, 200 v5), heights 460290 … 3527005. v4: 30 with Sprout JoinSplits, 40 with transparent inputs, 30 transparent-out only, 20 spends-only, 30 outputs-only, 30 with ≥5 spends, 10 with ≥20 outputs, 10 fully shielded. v5: 40 with transparent inputs (prevouts in `.ctx`), 30 transparent-out, 20 spends-only, 30 outputs-only, 30 ≥5 spends, 10 ≥20 outputs, 20 with an Orchard bundle too, 20 fully shielded. All 730 spend-auth + 400 binding signatures verify; all 200 independent ZIP 243 sighashes equal zcash_primitives'.

Not done: hashFinalSaplingRoot check after Heartwood (header field changes meaning; covered by the leaf rebuild instead); v5 transparent-input txs in the signature chunks; v6 txs.

## ctxset (v6 txs and v5 txs with transparent inputs, with spent-output context)

`ctxset`: from `sig_raw.bin`, selects every v6 tx and every v5 tx with non-coinbase transparent inputs, fetches the prev txs (GetTransaction, 32 concurrent, resumable cache `ctxset/prev.bin`, txids checked) and writes per part (`v6`, then `v5t`):

* `ctxset/txs_<part>.bin`: `u32 count`, then per tx `u32 height | u32 len | raw tx | u32 ctx_len | ctx`; ctx = node/tx layout `u32 len | amounts i64 LE | u32 len | CompactSize-prefixed scriptPubKeys` in input order (both lengths 0 when there are no transparent inputs).
* `ctxset/expected_<part>.txt`: `i height version txid sighash n_spends n_outputs verdicts`; verdicts = official per-signature results (spend-auth in order, then binding; empty if no Sapling bundle), with the sighash from `PrecomputedSighashData` + our `TransparentAuthorizingContext` carrying the fetched amounts/scripts.
* Rust timing printed per part: parse + txid + sighash (contexts prebuilt, untimed), 1 and 18 threads.

Results: v6: 2,372 txs, 5,046 Sapling signatures, 0 invalid, 90,163 prev txs; parse+txid+sighash 1 thread 0.607 s (3,905 tx/s), 18 threads 0.076 s (31,402 tx/s).
