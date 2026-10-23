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
| Halo 2 verifier for Orchard/Ironwood proofs | real proof from `orchard` 0.16 | stage-by-stage vs. the official verifier's trace (5,487 values) | 🔄 in progress |
| Orchard circuit gates (55 gates, 193 polynomials, generated) | real proof's evaluations | 193/193 equal to `halo2_proofs` | ✅ tested |
| Pasta fields, Vesta/Pallas, GPU MSM | — | 116/116 field, 136/136 curve, MSM n=2048/4096 equal to `pasta_curves` | ✅ tested |
| GPU trial decryption (wallet sync) | generated outputs | hit lists equal to `orchard` at 4k–262k outputs | ✅ tested |
| ZIP 209 turnstile, supply conservation, NU6.3/NU7 pool rules | model | 9 laws: `ALL PROOFS CHECK`, rechecked by the Lean-proven kernel | ✅ **proven** |
| ZIP 318 migration planner (denominations, no transparent outputs, ZIP 317 fee) | model | 6 laws: `ALL PROOFS CHECK` + `--verdict` | ✅ **proven** |
| Header chain + Equihash on GPU | mainnet | vs. block hashes and the Rust `equihash` crate | 🔄 in progress |
| Transactions: v5/v6 parsing, ZIP 244 txid, RedPallas signatures | mainnet | vs. txids and `zcash_primitives`/`orchard` | 🔄 in progress |
| Ironwood note commitment tree (Sinsemilla) | mainnet | root vs. lightwalletd `GetTreeState` | 🔄 in progress |
| P2P handshake and header sync | live mainnet peers | block hashes recomputed in Bend | 🔄 in progress |
| `bend2wasm`: Bend → WebAssembly | — | runs in wasmtime, Node and the browser WASI shim | ✅ works |

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
