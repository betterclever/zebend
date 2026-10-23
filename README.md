# Zebend

**Zcash, independently re-implemented and verified in Bend.**

Zebend re-implements the core of Zcash's consensus and shielded cryptography in
[Bend 2](https://github.com/HigherOrderCO/Bend), a language with dependent types and
machine-checked proofs that compiles to C, Metal and CUDA. Every component is checked
against the official Rust implementation or live mainnet data. The accounting rules that
keep Zcash's supply sound are proven as theorems. It runs on a laptop GPU, and through
our `bend2wasm` toolchain, in a browser tab.

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
| Header chain + Equihash on GPU | 128,280 mainnet headers | Equihash, target, links, difficulty all match; 6 difficulty laws **proven** | ✅ tested + proven |
| Transactions: v5/v6 parsing, ZIP 244 txid + sighash, RedPallas | 29 mainnet txs | txid 29/29, sighash 29/29, 118 spend-auth + 29 binding sigs, 1180/1180 Halo 2 inputs; 12/12 tampers rejected | ✅ tested |
| Block inclusion: merkle root + ZIP 244 block commitments | 10 mainnet blocks, 90 txs | roots equal the verified headers; ZIP 221 history root oracle-provided | ✅ tested |
| Ironwood note commitment tree (Sinsemilla) + nullifier set | all 838,662 mainnet Ironwood notes | 6/6 chain roots; 0 duplicate nullifiers; 1 set law **proven** | ✅ tested + proven |
| P2P handshake and header sync | live Zebra 7.0 / Zakura 1.7 peers | 480/480 hashes, Zebra checkpoint matched | ✅ tested |
| `bend2wasm`: Bend → WebAssembly | — | small programs run in wasmtime, Node and a browser WASI shim; large ones hit a runtime heap-layout limit (the browser verifier uses Bend's JS target instead) | ⚠️ partial |

**"Tested"** means differential testing against the official implementation, not a proof.
**"Proven"** means a Bend law that `bend PROOF.bend --verdict` accepts.
The Bend compiler itself is young and unaudited (its own README says so).

## Layout

| Directory | What |
|---|---|
| `halo2/` | Halo 2 verifier: `oracle/` (Rust ground truth), `gen/` (generated Orchard circuit), `lib/` (Pasta + MSM), `verifier/` |
| `node/` | `headers/`, `tx/`, `state/`, `p2p/` |
| `turnstile/`, `migration/` | proven consensus and wallet rules |
| `gpu-scan/` | GPU trial decryption |
| `wasm/`, `web/` | `bend2wasm` and the in-browser runner |
