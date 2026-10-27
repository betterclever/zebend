# zcash/sapling/: Sapling cryptography and state in Bend (non-proof part)

Zcash's Sapling pool re-implemented in Bend 2, differentially tested against the official
Rust crates (`bls12_381`, `jubjub`, `sapling-crypto`, `redjubjub`, `zcash_primitives`) on
their own test vectors and on real mainnet data. The Groth16 proof verifier is a separate
workstream (`groth16/`) and is not covered here.

Every number below was produced by the commands in "Run". "Tested" means differential
against the official crates (or the chain), never a proof.

## Results on mainnet (Oct 26, 2026; M5 Max, shared machine)

| Component | Result | Status |
|---|---|---|
| Fields, curve, Pedersen hash, RedJubjub (vectors) | 9,302/9,302 values/verdicts equal the Rust crates (below) | ✅ tested |
| **Sapling note commitment tree, full** | all **73,989,124** leaves (activation 419,200 → 3,528,268): **1,128/1,128** level-16 subtree roots equal the chain's `GetSubtreeRoots`; **13/13** full roots equal `GetTreeState` (incl. the tip, `de891f1e…8205`); **13/13** roots equal `hashFinalSaplingRoot` of the real block headers (P2P-fetched, Equihash-verified by zcash/headers) at heights 419,200–902,999 | ✅ tested |
| Incremental frontier (node's view) | 1,170,431 leaves appended one at a time: root at NU5 activation equals the chain | ✅ tested |
| Sapling nullifier set | all **2,147,491** nullifiers: 0 duplicates (Python set agrees); replaying one is rejected | ✅ tested |
| **RedJubjub on real signatures** | **230,769** mainnet sigs (v4: 53,860 spend-auth + 59,055 binding; v5: 69,334 + 48,520), 29 chunks: Bend batch accepts all, Rust per-signature verdicts all valid, invalid sets equal in **29/29** chunks. **4 tampered chunks (32,766 sigs, 1,448 invalid per Rust): per-signature verdicts 32,766/32,766 equal Rust; batch + bisection finds exactly Rust's invalid set in 4/4** | ✅ tested |
| **Transactions: parsing, txid, sighash** | **107,575** real v4/v5 Sapling txs (59,055 v4 incl. 148 with JoinSplits, 23,899 with transparent inputs; 48,520 v5): txid **107,575/107,575**, ZIP 243/244 shielded sighash = zcash_primitives **107,575/107,575**; description checks pass on all; every spend-auth and binding sig verifies under Bend's own sighash. Detailed sample (400: 200 v4, 200 v5, 30 with JoinSplits, 137 with transparent inputs incl. 40 v5 with prevout context, 46 with Orchard): txid, sighash, counts, valueBalance 400/400 each, 730/730 spend-auth + 400/400 binding valid | ✅ tested |
| Tx negative tests | 1,623 real v4 txs × 3 tampers (enc-ciphertext byte, spend-auth sig byte, valueBalance+1): 4,869/4,869 behave as expected (txid changes; all sigs / exactly sig 0 fail) | ✅ tested (Bend only) |
| **v6 (NU6.3) txs, with spent-output context** | all **2,372** v6 txs of the corpus (793 with transparent inputs; prevouts fetched by the oracle, `data/ctxset/`): txid 2,372/2,372, sighash = zcash_primitives 2,372/2,372, **5,046/5,046 per-signature RedJubjub verdicts equal Rust's**; their 7,616 Groth16 proofs all valid in Bend (`zcash/sapling/groth16`). The earlier v6 "failures" were only the missing transparent context: v6 uses the v5 Sapling layout and the same ZIP 244 sighash structure | ✅ tested |
| **v5 txs with transparent inputs, with spent-output context** | all **20,431** (prevouts fetched by the oracle): txid 20,431/20,431, sighash 20,431/20,431, **21,791/21,791 per-signature verdicts equal Rust's**; their 32,105 Groth16 proofs all valid in Bend | ✅ tested |

### Speed (Bend vs Rust, same machine; load noted because other jobs shared it)

| Workload | Bend | Rust (official crates) |
|---|---|---|
| 1,128 subtree roots (73.9M leaves) | Metal GPU: 357 s (sum of per-chunk compute, ~217 ms/chunk; plus ~0.5 s/chunk file reading); CPU 18 threads ≈ 0.46–0.55 s/chunk measured on samples (full CPU run not done) | 1 thread 1,981 s; 18 threads 182 s |
| per-chunk, 1 thread | ~1.45 s (batched inversion), ~2.0 s (per-hash inversion), load 8 | 1.76 s (1,981/1,128) |
| Incremental frontier, 1 thread | 29 µs/leaf (1.17M leaves, 34 s) | 43 µs/leaf (all leaves, 3,161 s; upper bound) |
| 230,769 RedJubjub sigs, batch, 18 threads | 3.92 s = 58.8k sigs/s (load up to 151 during the run) | 2.84 s = 81.3k sigs/s |
| same, 1 thread | 24.45 s = 9.4k sigs/s | 27.68 s = 8.3k sigs/s |
| per-signature verification | — (used only for vectors/tampers) | 1 thread 4.1k/s, 18 threads 28k/s |
| tx layer, 109,947 txs | 899 s for parse + txid + sighash + description checks + per-signature RedJubjub of every sig | parse + txid + sighash only: 31.4 s (1 thread), 3.9 s (18) — not comparable |

GPU numbers come from the gated build: `tree/gpu_gate.sh` 20 runs × 16 chunks, 1 distinct
output, equal to the CPU output; AIR of the Metal program has 1 function and 0
non-intrinsic calls (`research/gpuv/t/aircalls.sh`).

| Component | Files |
|---|---|
| Fr (= BLS12-381 scalar field), Fs | `jubjub/fr.bend`, `jubjub/fs.bend` (`gen_fields.py`, from field3's 64-bit-limb generator); table square root `jubjub/fr_sqrt.bend` (`gen_sqrt.py`, from research/decomp/gen.py) |
| Jubjub | `jubjub/jubjub.bend`, `jubjub/consts.bend` (`gen_consts.py`, `jj.py`) |
| Pedersen hash, tree, nullifiers | `tree/pedersen.bend`, `tree/stree.bend`, `tree/tree_main.bend`, `tree/nf_main.bend`, `tree/check_tree.py`, `tree/header_roots.py`, `tree/split_leaves.py`, `tree/gpu_gate.sh` |
| RedJubjub | `sig/sig.bend`, `sig/msm_jj.bend`, `sig/sig_main.bend`, `sig/run_sigs.py` |
| Transactions | `tx/stx.bend`, `tx/tx_main.bend`, `tx/check_txs.py`, `tx/check_ctxset.py`, `hook.py` (fullnode hook) |
| Oracle (Rust) | `oracle/` (see its README) |
| Tests | `t/vec_main.bend`, `t/vectors.py`, `t/pyvec.py`, `t/pysig.py` |

## Not done / limits

- Groth16 proofs (separate `groth16/` workstream); Sprout JoinSplit proofs and joinSplitSig.
- Anchors (spend anchor ∈ previous tree roots) are not checked; the tree code provides the roots.
- Raw Pedersen-hash vectors with other personalizations (note commitments) are not run: the
  Bend hash is specialised to MerkleCRH's 516-bit input.
- Generators are labelled constants computed in Python from the spec (GroupHash/BLAKE2s) and
  equal sapling-crypto's; they are not derived in Bend.
- Leaves come from lightwalletd compact blocks (counts checked against the chain's tree size
  per block by the oracle; roots checked against chain and headers).

## fullnode hook (`hook.py`)

`zcash/sapling/hook.py <list file>` implements node/hooks/README's contract (reads P.tx, P.ctx,
P.json; prints `verdict <height> <txidx> PASS|FAIL <reason>`). All checks run in Bend:
`tx/tx_main` (parse v4/v5/v6, txid, ZIP 243/244 sighash with the P.ctx spent outputs,
description checks, every spend-auth and binding RedJubjub signature, and one Groth16
record per spend/output written from its own parse) and `tx/g16_raw` (built from
`groth16/verify_raw_main.bend`: every spend/output proof, public inputs computed in Bend).
PASS = txid equals P.json's and all of the above hold. FAIL reasons: `unsupported-version`,
`txid mismatch`, `unsupported-joinsplit` (v4 Sprout JoinSplits: joinSplitSig/Ed25519 not
implemented), `sapling-description`, `redjubjub <verdicts>`, `groth16 <digits>`.
Anchors are out of scope.

Tests: 2,372/2,372 real v6 txs PASS (with context); 1,429 tampered copies all FAIL at the
right stage (400 proof bit flips -> groth16; 229 spend-auth and 400 binding sig flips and 400
valueBalance flips -> redjubjub); 400-tx v4/v5 sample: 370 PASS + 30 unsupported-joinsplit.
Needs the binaries `tx/tx_main`, `tx/g16_raw` (`./build.sh groth16/verify_raw_main.bend
tx/g16_raw`) and the VKs `groth16/data/vk_{spend,output,sprout}.bin`.

## Test vectors (Bend vs the Rust crates)

`oracle/` (`sapling-oracle vectors`) writes `data/vectors/*.txt` from the official crates;
`t/vectors.py` feeds them to `t/vec_main`, `sig/sig_main` and `tree/tree_main` and diffs:

```
Fr add/sub/mul/sqr/inv/sqrt (bls12_381::Scalar): 2000/2000
Fs from_bytes_wide (jubjub::Fr): 1004/1004
Fs add/mul/neg/inv (jubjub::Fr): 500/500
decode, ZIP 216 (AffinePoint::from_bytes): 1034/1034   (596 rejected by Rust)
add P+Q, double 2P: 500/500
scalar mul [k]P: 500/500
[8]P and is_small_order: 308/308
is_torsion_free ([r_J]P == 0): 308/308
the 8 small-order points decode and are small-order: 8/8
generators used by Bend (jj.py GroupHash) = sapling_crypto constants: 9/9
Jubjub d: 1/1
empty Sapling roots, levels 0..32 (Bend tree_main e): 33/33
MerkleCRH^Sapling (Pedersen hash): 1000/1000
RedJubjub single verify (1000 honest + 1096 tampered; 1064 invalid per Rust): 2096/2096
RedJubjub batch + bisection: invalid set == Rust's: 1/1
TOTAL 9302/9302
```

The square root is compared up to sign (Bend's Tonelli–Shanks may return −r). Inverse of
zero: Rust says "none", Bend returns 0; both are accepted as agreeing.

## Design notes

**Fields.** `fr.bend`/`fs.bend` are field3's generated 64-bit-limb Montgomery code (CIOS via
the fork's `U32.mac64`), instantiated with r_BLS (255 bits) and r_J (252 bits). BLS12-381's
r − 1 = 2^32·t and 5 is a non-residue, so field3's Tonelli–Shanks applies unchanged. Fs has
2-adicity 1; its generated `sqrt` is meaningless and unused.

**Curve.** −u² + v² = 1 + d·u²v² with extended coordinates (X, Y, Z, T). Addition is
add-2008-hwcd-3 (complete: a = −1 is a square, d is not), mixed addition with
precomputed Niels points (v+u, v−u, 2d·u·v) costs 7M, doubling dbl-2008-hwcd 4M+4S.
Decoding follows `jubjub::AffinePoint::from_bytes` (ZIP 216): rejects v ≥ r, non-points
and the non-canonical (u = 0, sign = 1) encodings.

**Fr square root.** Decompression uses Sarkar's table method (research/decomp/), 4-bit windows: sig
preparation −20% vs Tonelli–Shanks on 1 thread.

**Tree on CPU.** Complete chunks are hashed as 256 blocks of 256 leaves in parallel, each level
by level with one batched inversion per level (≈25% faster on 1 thread).

**Pedersen hash.** The 516 message bits (6-bit layer, two 255-bit nodes) are 172 three-bit
chunks; two chunks form a signed base-256 digit d = e₀ + 16·e₁ with |d| ∈ [12, 68] (never
0), and the lone 63rd chunk of segments 1 and 2 is a digit in [1, 4]. Each of the 87
windows has a 68-entry Niels table ([d·256^k]·I_s, built at start-up), walked as a depth-7
tree: a hash is 87 lookups + 87 mixed additions + one inversion for Extract_J.

**RedJubjub batch.** reddsa's equation with the cofactor:
[8](Σ z_i R_i + Σ z_i c_i vk_i − (Σ_SA z_i s_i) G − (Σ_B z_i s_i) R) = 0, one Pippenger MSM
(signed digits, buckets in a Bend `Array`, windows in parallel). Weights z_i are 128-bit,
derived Fiat–Shamir from a Merkle root of per-signature leaves (same construction and
soundness argument as `../../research/sigbatch/README.md`, with Sapling-specific personalizations).
[8] maps into the prime-order subgroup (order r_J ≈ 2^251.9 > 2^128), so the per-query
bound 2^−128 carries over.

## Run

```sh
cd oracle && ../../../heavy.sh cargo build --release --offline   # then: sync, subtrees, trees, vectors, scan, fetch, build, txs
H=../../tools/heavy.sh; B=./build.sh
$H $B t/vec_main.bend t/vec_main; $H $B sig/sig_main.bend sig/sig_main
$H $B tree/tree_main.bend tree/tree_main; $H $B tree/nf_main.bend tree/nf_main; $H $B tx/tx_main.bend tx/tx_main
python3 t/vectors.py                                  # 9302/9302
python3 tree/split_leaves.py
python3 tree/check_tree.py chunks 1                   # GPU (0 = CPU, 2 = CPU batched inversion)
python3 tree/check_tree.py compare; python3 tree/check_tree.py roots; python3 tree/header_roots.py
$H ./tree/gpu_gate.sh 20 16
$H ./tree/nf_main data/sapling_nfs.bin 2147491
python3 sig/run_sigs.py batch 11; python3 sig/run_sigs.py single data/sigs/tampermix_*.bin
python3 tx/check_txs.py raw 0 200000 5000; python3 tx/check_txs.py sample; python3 tx/check_txs.py tamper 0 6000
```
Logs: `data/final_runs.log`, `data/tree_logs/`, `data/gpu/` (git-ignored).
