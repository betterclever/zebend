# Zebend

**A second, independent implementation of Zcash's core, in a proof language, that agrees
with the official one on real mainnet data.**

Every Zcash node today, Zebra and Zakura alike, verifies shielded transactions with the same
Rust cryptography crates (`orchard`, `halo2_proofs`). When those crates have a bug, as the
Orchard circuit did in May 2026, there is no independent implementation to disagree with them.

Zebend is that independent implementation. It re-implements Zcash's consensus and shielded
cryptography in [Bend 2](https://github.com/HigherOrderCO/Bend), a language with dependent
types and machine-checked proofs that compiles to C, Metal, CUDA and JavaScript:

- **Halo 2 proof verification for Orchard/Ironwood**, generated from the verifying key, which
  verifies real mainnet transactions and agrees with `halo2_proofs` on every intermediate value.
- **The chain around it:** P2P with live Zebra/Zakura peers, Equihash and difficulty on the GPU,
  block inclusion, ZIP 244 txids and sighashes, RedPallas signatures, and the full mainnet
  Ironwood note commitment tree.
- **66 theorems**, all checked by Bend and rechecked by a Lean-proven kernel: Zcash's supply
  turnstile and NU6.3/NU7 pool rules, ZIP 318 migration, difficulty in both eras, parser
  round-trips, Merkle frontier/path laws about the running tree code, the correctness of the
  new Bend arithmetic primitives, and **soundness of real Orchard circuit gates** (value
  balance, anchor, enable flags, booleanity, bit decomposition, conditional swap), proven on the
  exact generated gate polynomials.
- **Every header in Zcash's history** (heights 1 to 3,528,279): Equihash, target, links and
  difficulty all verified in Bend.
- One codebase on CPU threads, the Metal GPU, and in a browser tab (real mainnet proofs verify
  in about a second in Chrome).

Differential testing against the official code is how every component earned its ✅; it is not a
proof of correctness, and the table below says exactly which claims are proven.

> Status: work in progress for Zecathon 2026. The table below is the source of truth for
> what is real, what is tested against an oracle, what is proven, and what is mocked.

## What is real, tested, proven

| Component | Real data? | How we know it is right | Status |
|---|---|---|---|
| **Halo 2 verifier for Orchard/Ironwood proofs** | **29 mainnet txs, 133 actions, all 3 circuit versions** | 2513/2513 intermediate values equal the official verifier; 42/42 mainnet verdicts (honest + tampered) agree with `halo2_proofs` | ✅ tested |
| **In-browser verification** (Bend → JS) | 4 mainnet txs | headless Chrome: all valid, all tampered copies rejected, ~1 s each | ✅ tested |
| Orchard circuit gates (55 gates, 193 polynomials, generated) | real proof's evaluations | 193/193 equal to `halo2_proofs` | ✅ tested |
| Pasta fields, Vesta/Pallas, GPU MSM | — | 116/116 field, 136/136 curve, MSM n=2048/4096 equal to `pasta_curves` | ✅ tested |
| GPU trial decryption (wallet sync) | generated outputs | hit lists equal to `orchard` at 4k–262k outputs | ✅ tested |
| ZIP 209 turnstile, supply conservation, NU6.3/NU7 pool rules | model | 9 laws: `ALL PROOFS CHECK`, rechecked by the Lean-proven kernel | ✅ **proven** |
| ZIP 318 migration planner (denominations, no transparent outputs, ZIP 317 fee) | model | 6 laws: `ALL PROOFS CHECK` + `--verdict` | ✅ **proven** |
| Header chain: Equihash, target, links, difficulty | **all 3,528,279 mainnet headers** | every check passes for every height (difficulty from height 29); 8 difficulty laws **proven**, one equal to the running verifier code | ✅ tested + proven |
| Transactions: v5/v6 parsing, ZIP 244 txid + sighash, RedPallas | 29 mainnet txs | txid 29/29, sighash 29/29, 118 spend-auth + 29 binding sigs, 1180/1180 Halo 2 inputs; 12/12 tampers rejected | ✅ tested |
| Block inclusion: merkle root + ZIP 244 block commitments | 10 mainnet blocks, 90 txs | roots equal the verified headers; ZIP 221 history root oracle-provided | ✅ tested |
| Ironwood note commitment tree (Sinsemilla) + nullifier set | all 838,662 mainnet Ironwood notes | 6/6 chain roots; 0 duplicate nullifiers; frontier = full tree and path soundness **proven about the running code**; 1 set law **proven** | ✅ tested + proven |
| Orchard circuit gate soundness | 7 gates of the real circuit | value balance, anchor-or-zero, enable flags, booleanity, bit decomposition, conditional swap, on the generated polynomials (386/386 translator match); p prime and selector invertibility are hypotheses | ✅ **proven** |
| Bend arithmetic primitives (`mul`, `mul_hi`, `add_hi`, `mac_hi`, 64-bit lanes) | — | word splits equal the exact Nat product/sum for all inputs (stated on the defining expressions) | ✅ **proven** |
| P2P handshake and header sync | live Zebra 7.0 / Zakura 1.7 peers | 480/480 hashes, Zebra checkpoint matched | ✅ tested |
| `bend2wasm`: Bend → WebAssembly | — | small programs run in wasmtime, Node and a browser WASI shim; large ones hit a runtime heap-layout limit (the browser verifier uses Bend's JS target instead) | ⚠️ partial |

**"Tested"** means differential testing against the official implementation, not a proof.
**"Proven"** means a Bend law that `bend PROOF.bend --verdict` accepts.
An earlier boolean-gate law (`proofs/gadget`) turned out to be vacuous (its no-zero-divisors
hypothesis is unsatisfiable over all Nats; `proofs/orchard/gadget_vacuous.bend` proves it) and is not
counted; `last_window_bit` is the sound version, on a real Orchard gate.
The Bend compiler itself is young and unaudited (its own README says so).

## Layout

| Directory | What |
|---|---|
| `halo2/` | Halo 2 verifier: `oracle/` (Rust ground truth), `gen/` (generated Orchard circuit), `lib/` (Pasta + MSM), `verifier/` |
| `node/` | `headers/`, `tx/`, `state/`, `p2p/` |
| `turnstile/`, `migration/` | proven consensus and wallet rules |
| `gpu-scan/` | GPU trial decryption |
| `wasm/`, `web/` | `bend2wasm` and the in-browser runner |

## Related work

- **ChainSafe WebZjs / Zcash MetaMask Snap** already run Zcash in the browser, by compiling the
  official Rust libraries to WebAssembly (including in-browser Halo 2 proving). Zebend's browser
  verifier is a different implementation, not a different compilation target of the same code.
- **The `orchard` crate's verifier "fingerprint" fixtures** export transcripts and MSM data from a
  Rust verifier run so that the Lean model of Ironwood can reproduce it. Our Rust oracles follow
  the same idea, applied to a full re-implementation instead of a model.
- **Zebra, Zakura** are the production nodes. Zebend is not a replacement node: it does not
  validate Sapling, Sprout or transparent scripts, keep full chain state, or relay transactions.
- **zkSecurity's Orchard/Halo 2 audit** and Shielded Labs' formal-verification work on Ironwood
  are the rigorous efforts; Zebend complements them with an executable independent check.
