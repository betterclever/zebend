# Zebend

**A second, independent implementation of Zcash's core, in a proof language, that agrees
with the official one on real mainnet data.**

Every Zcash node today, Zebra and Zakura alike, verifies shielded transactions with the same
Rust cryptography crates (`orchard`, `halo2_proofs`). When those crates have a bug, as the
Orchard circuit did in May 2026, there is no independent implementation to disagree with them.

Zebend is that independent implementation. It re-implements Zcash's consensus and shielded
cryptography in [Bend 2](https://github.com/HigherOrderCO/Bend), a language with dependent
types and machine-checked proofs that compiles to C, Metal, CUDA and JavaScript. None of the
Rust crates is linked into the Bend side; Rust is used only as the oracle we compare against.

## What it has checked on mainnet

- **Every Orchard/Ironwood proof since NU6.3:** 392,806 Halo 2 bundles (1,155,249 actions,
  366,418 transactions). Bend's verdict equals the official verifier's on 392,806 of 392,806.
- **1,283,411 RedPallas signatures** (980,364 spend-auth + 303,047 binding) in the 276,675
  transactions without transparent inputs: all valid; a single flipped byte is found and
  pinpointed to the exact signature.
- **Every block header in Zcash's history** (heights 1 to 3,528,279): Equihash, target,
  prev-hash links, and difficulty in both eras (653,571 pre-Blossom + 2,874,680 post-Blossom).
- **The full note commitment trees:** all 50,478,033 Orchard leaves since NU5 (770/770 subtree
  roots, 6/6 full roots equal the chain) and all 838,662 Ironwood leaves (6/6 roots).
- **Consensus rules:** anchor validity (13/13 Ironwood, 16/16 Orchard real anchors; forged
  ones rejected), issuance in every era (260/260 coinbase blocks, 410/410 required outputs).
- **Live:** `zebend follow` follows mainnet over the P2P network (its own Bend P2P client) and validates each new
  block's shielded parts, with a median of 0.55 s from block arrival to verdict.

And **76 theorems** checked by Bend (`bend PROOF.bend --verdict`, no `@unsafe`): Zcash's supply
turnstile and NU6.3/NU7 pool rules, ZIP 318 migration, issuance and anchor rules, difficulty in
both eras, parser round-trips and rejection of malformed input, Merkle frontier/path laws about
the running tree code, the new Bend arithmetic primitives, and **soundness of real Orchard
circuit gates** (value balance, anchor, enable flags, booleanity, bit decomposition,
conditional swap) on the exact generated gate polynomials.

Differential testing against the official code is how every component earned its ✅; it is not a
proof of correctness, and the table below says exactly which claims are proven.

## Try it

Binaries are built from the `.bend` sources (see each directory's README; most need the
forked Bend compiler described under "Bend changes" below).

```sh
./node/validate/zebend validate                 # one mainnet tx: header → block → tx → proof → state, all in Bend
./node/validate/zebend validate --tamper proof  # same, with one bit flipped: rejected at the right step
python3 node/follow/zebend_follow.py --live     # follow mainnet live
./tools/harden/ci.sh                             # 31 checks: every proof, every differential suite, fuzzing
python3 -m http.server -d web 8000         # then open localhost:8000: real mainnet Halo 2 proofs verified in the tab (~1 s each)
```

## What is real, tested, proven

| Component | Real data? | How we know it is right | Status |
|---|---|---|---|
| **Halo 2 verifier for Orchard/Ironwood proofs** (`zcash/halo2/`) | **every bundle since NU6.3: 392,806**; plus 29 txs across all 3 circuit versions | 392,806/392,806 verdicts equal `halo2_proofs`; 2513/2513 intermediate values equal; 60/60 honest + tampered verdicts across circuit versions | ✅ tested |
| **RedPallas signatures** (`research/sigbatch/`, `zcash/tx`) | **1,283,411 mainnet signatures** | all valid; 10/10 tamper files pinpoint the tampered signature | ✅ tested |
| Transactions: v5/v6 parsing, ZIP 244 txid + sighash (`zcash/tx`) | 29 txs in detail; 276,675 txids in the signature run | txid 29/29, sighash 29/29, 1180/1180 Halo 2 public inputs; 12/12 tampers rejected | ✅ tested |
| Header chain: Equihash, target, links, difficulty (`zcash/headers`) | **all 3,528,279 mainnet headers** | every check passes at every height (difficulty from height 29); 8 difficulty laws **proven**, one about the running verifier code | ✅ tested + proven |
| Block inclusion: merkle root + ZIP 244 block commitments (`zcash/block`) | 10 blocks in detail; every block `follow` has seen | roots equal the verified headers; ZIP 221 history root is oracle-provided | ✅ tested |
| Ironwood note commitment tree + nullifier set (`zcash/state`) | all 838,662 Ironwood notes | 6/6 chain roots; 0 duplicate nullifiers; frontier = full tree and path soundness **proven about the running code** | ✅ tested + proven |
| Orchard note commitment tree (`zcash/consensus/orchard`) | **all 50,478,033 Orchard notes** | 770/770 subtree roots, 6/6 full roots equal the chain | ✅ tested |
| Anchor validity (`zcash/consensus/anchors`, `zcash/consensus/orchard`) | 13 Ironwood + 16 Orchard real anchors | all valid; forged and tampered anchors rejected; 3 laws **proven** | ✅ tested + proven |
| Issuance: subsidy, founders' reward, funding streams, lockbox, ZIP 271 (`zcash/consensus/issuance`) | 260 coinbase txs covering every era | 260/260 blocks, 410/410 outputs exact; 5 laws **proven** | ✅ tested + proven |
| ZIP 209 turnstile, supply conservation, NU6.3/NU7 pool rules (`proofs/turnstile/`) | model | 9 laws | ✅ **proven** |
| ZIP 318 migration planner (`proofs/migration/`) | model | 6 laws | ✅ **proven** |
| Orchard circuit gate soundness (`proofs/orchard`) | 7 gates of the real circuit | on the generated polynomials (386/386 translator match); p prime and selector invertibility are hypotheses | ✅ **proven** |
| Parsers reject malformed input (`proofs/parse`) | — | 11 laws incl. non-canonical encodings and over-cap lengths rejected | ✅ **proven** |
| Bend arithmetic primitives (`mul`, `mul_hi`, `add_hi`, `mac_hi`, 64-bit lanes) | — | word splits equal the exact Nat product/sum for all inputs | ✅ **proven** |
| Orchard circuit gates, generated (55 gates, 193 polynomials) | real proof's evaluations | 193/193 equal to `halo2_proofs` | ✅ tested |
| Pasta fields and curves, MSM, square roots | — | 116/116 field, 136/136 curve, MSM equal to `best_multiexp`; square root equal to `pasta_curves` on 2,097,152 inputs per field | ✅ tested |
| Wallet trial decryption on the GPU (`research/scan2/`) | generated outputs | hit lists equal to `orchard` at 4k–262k outputs; key handling constant-time | ✅ tested |
| P2P handshake, header and block sync (`zcash/p2p`) | live Zebra 7.0 / Zakura 1.7 peers | 480/480 hashes, Zebra checkpoint matched; used by `follow` | ✅ tested |
| **Live follower** (`node/follow/`) | mainnet, live | each block: PoW/difficulty, merkle, commitments, txids, sighash, signatures, Halo 2, nullifiers, anchors, Ironwood root vs chain; reorg handling | ✅ running |
| Hardening (`tools/harden/`) | — | 803,000 differential fuzz cases against the Rust crates, 0 mismatches for the hardened parsers (now merged; the bugs it found are fixed); 16/16 resource-limit probes | ✅ tested |
| In-browser verification (`web/`, Bend → JS) | 4 mainnet txs | headless Chrome: all valid, all tampered copies rejected, ~1 s each | ✅ tested |
| `bend2wasm`: Bend → WebAssembly (`web/wasm/`) | — | small programs run; large ones hit a runtime heap-layout limit (the browser verifier uses Bend's JS target instead) | ⚠️ partial |

**"Tested"** means differential testing against the official implementation, not a proof.
**"Proven"** means a Bend law that `bend PROOF.bend --verdict` accepts.
An earlier boolean-gate law (`proofs/gadget`) turned out to be vacuous (its no-zero-divisors
hypothesis is unsatisfiable over all Nats; `proofs/orchard/gadget_vacuous.bend` proves it) and is not
counted; `last_window_bit` is the sound version, on a real Orchard gate.
Field multiplication's correctness is tested, not proven (Bend's checker evaluates Nat in unary).

## What it does not do

Zebend is not a replacement node. It does not validate Sapling, Sprout or transparent scripts,
or signatures of transactions with transparent inputs (89,743 of the post-NU6.3 set: their
ZIP 244 sighash needs the spent outputs, which this pipeline does not fetch). The ZIP 221
history root comes from an external oracle (Blockchair), sampled. `follow` prints every check it
skips for each block. It keeps no full chain state and relays nothing.

The Bend compiler itself is young and unaudited (its own README says so).

## Speed

Apple M5 Max (18 CPU cores, 40-core GPU), against the official Rust crates on the same machine.
Rust is faster in most rows; the point is that an independent, proof-carrying implementation
is fast enough to check the whole chain.

| Workload | First Bend version | Zebend now | Rust |
|---|---|---|---|
| Field multiplication, 10⁶, 1 thread | 91 ms | 18 ms | 14 ms |
| Halo 2 verify, one 2-action proof, 1 thread | 167 ms | 26.6 ms | 20.7 ms |
| Halo 2 batch, all 392,806 bundles, 18 threads | ~23 bundles/s | 793 bundles/s (495 s) | 1,068 bundles/s (368 s) |
| All 1,283,411 RedPallas signatures, 18 threads | 1,127 s (one at a time) | ~11 s (batched) | 4–7 s |
| Equihash, 18 threads | 1,973 headers/s | 40,857 headers/s | ~117,000 headers/s |
| `follow`, per block verified | 17.4 s | 0.19 s | — |
| Wallet trial decryption, Metal GPU, constant-time | 301,662 outputs/s | ~410,000 outputs/s | orchard batch API, 18 CPU threads: ~346,000 outputs/s |

GPU numbers are counted only from builds where every Metal helper is inlined, after at least 20
runs with bit-identical output (see "Bend changes"). The GPU Halo 2 batch verifier works and
agrees on all 392,806 bundles but is not faster than the CPU one (`research/gpuv/`).
Forcing the inlining costs the wallet scan 2.3× (the non-inlined build ran ~892k–958k outputs/s
but is exposed to the compiler bug); Equihash on the GPU (~20,900 headers/s) and the Ironwood
tree on the GPU (~21 s for 838,662 notes) did not slow down. Gate logs: `research/bench/metal_inline_gate.log`.

## Bend changes

Some components use a local fork of the Bend compiler (`bend-fork`, not upstreamed yet):
- `U32.mul_hi`, `add_hi`, `mac_hi`, `mac64` and 64-bit rotate/xor primitives; each one's word
  split is proven equal to the exact Nat result (`proofs/prims`).
- The Metal lane spill restored (upstream removed it in 2.0.39; without it GPU lanes crash past
  ~1,023 recursion levels).
- Every Metal device helper always inlined: Apple's Metal compiler can nondeterministically
  corrupt a caller's 32-bit word across a non-inlined helper call.

## Layout

| Directory | What |
|---|---|
| `zcash/halo2/` | Halo 2 verifier: `oracle/` (Rust ground truth), `gen/` (generated Orchard circuit), `lib/` (Pasta + MSM), `verifier/` |
| `zcash/` | `p2p/`, `headers/` (+ `history/`: every header), `tx/`, `block/`, `state/`, `wire/` |
| `zcash/consensus/` | anchors, the full Orchard tree, issuance |
| `research/proofsets/` | every Orchard/Ironwood proof and signature since NU6.3, Bend vs official |
| `node/follow/`, `node/validate/` | `zebend follow` (live daemon) and `zebend validate` (one tx, end to end) |
| `proofs/`, `proofs/turnstile/`, `proofs/migration/` | theorems |
| `tools/harden/` | differential fuzzing, resource limits, constant-time scan, `ci.sh` |
| `crypto/field3/`, `research/perf3/`, `research/algo/`, `research/decomp/`, `research/sigbatch/`, `research/blake3x/`, `research/gpuv/`, `research/bench/` | speed work: 64-bit fields, MSM, batching, square roots, Equihash, GPU |
| `research/scan2/`, `research/gpu-scan/` | wallet trial decryption (GPU) |
| `web/`, `web/wasm/` | in-browser verifier and `bend2wasm` |

## Related work

- **ChainSafe WebZjs / Zcash MetaMask Snap** already run Zcash in the browser, by compiling the
  official Rust libraries to WebAssembly (including in-browser Halo 2 proving). Zebend's browser
  verifier is a different implementation, not a different compilation target of the same code.
- **The `orchard` crate's verifier "fingerprint" fixtures** export transcripts and MSM data from a
  Rust verifier run so that the Lean model of Ironwood can reproduce it. Our Rust oracles follow
  the same idea, applied to a full re-implementation instead of a model.
- **Zebra, Zakura** are the production nodes. Zebend checks a subset of what they check (see
  "What it does not do").
- **zkSecurity's Orchard/Halo 2 audit** and Shielded Labs' formal-verification work on Ironwood
  are the rigorous efforts; Zebend complements them with an executable independent check.
