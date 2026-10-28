<p align="center">
  <img src="docs/brand/icon.svg" width="120" alt="Zebend">
</p>

<h1 align="center">zebend</h1>

<p align="center">
  <strong>Zcash, independently verified.</strong><br>
  A full Zcash node whose consensus and cryptography are written in
  <a href="https://github.com/HigherOrderCO/Bend">Bend</a>, a language with machine-checked proofs.
</p>

<p align="center">
  <img alt="Halo 2 proofs agreeing with halo2_proofs" src="https://img.shields.io/badge/mainnet%20Halo%202-392%2C806%20%2F%20392%2C806-2fbf71">
  <img alt="Machine-checked laws" src="https://img.shields.io/badge/machine--checked%20laws-176-E4573D">
  <img alt="Network" src="https://img.shields.io/badge/network-mainnet%20%2B%20NU7-FFD04D">
  <img alt="Language" src="https://img.shields.io/badge/written%20in-Bend%202-2B100B">
</p>

---

Every Zcash node today, Zebra and Zakura alike, verifies shielded transactions with the same Rust
cryptography crates. When those crates have a bug, as the Orchard circuit did in May 2026, there is
no second implementation to disagree with them.

**Zebend is that second implementation.** It re-implements Zcash's consensus rules and all of its
shielded cryptography (Halo 2, Groth16, RedPallas, RedJubjub, Ed25519, ECDSA, Sinsemilla, Pedersen)
in Bend, and runs as a full node on mainnet. No Rust crate is linked into the Bend side: Rust is
used only as the oracle Zebend is compared against.

## Highlights

- **A working full node.** Synced from genesis, checkpoint-verified to the last Zebra checkpoint and
  fully validated after it, following the live tip with push block pickup and reorg handling.
  Every consensus check Zakura makes is live: all four anchor pools, the ZIP 221 history root,
  NU7, the value-pool turnstile, and transparent, Sapling, Sprout and Orchard/Ironwood cryptography.
- **Agrees with the official code on real data.** 392,806 of 392,806 Orchard/Ironwood Halo 2 bundles
  since NU6.3, 1,283,411 RedPallas signatures, 61,168 Groth16 proofs, 131,146 transparent inputs
  across all eras, every block header in Zcash's history, and the full Sapling (74.0M) and
  Orchard (50.5M) note commitment trees.
- **Proven, not only tested.** 176 laws checked by Bend (`--verdict`, no `@unsafe`): the supply
  turnstile, issuance, NU7, difficulty, parsers, Merkle trees on the running code, real Orchard
  gate soundness, the fix for the May 2026 Orchard bug, and the optimisations of the fast
  Halo 2 verifier.
- **Fast where it counts.** Batch Halo 2 verification of all 392,806 bundles in 176 s, about
  2× the official Rust `BatchVerifier` on the same machine.
- **Finds the May 2026 bug class.** An under-constraint checker re-finds the missing copy
  constraint in the pre-NU6.2 Orchard circuit automatically, and the fix is proven in Bend.

## Quick start

Zebend is developed and tested on Apple Silicon (macOS). The node is Python orchestration around
compiled Bend programs.

```sh
# Run the node (sync, push pickup, RPC on :18233, mempool, live monitor) under its supervisor
nohup python3 -u node/ops/supervise.py run node/ops/zebend.json >> node/ops/supervisor.log 2>&1 &
python3 node/ops/supervise.py status node/ops/zebend.json
python3 node/rpccli.py --port 18233 getblockchaininfo

# Validate one mainnet transaction end to end in Bend: header → block → tx → proof → state
./node/validate/zebend validate
./node/validate/zebend validate --tamper proof     # the same tx with one bit flipped: rejected

# Verify real mainnet Halo 2 proofs in a browser tab
python3 -m http.server -d web 8000                 # then open http://localhost:8000

# Every proof and every differential suite
./tools/harden/ci.sh
```

Building from source, the snapshot start and running against your own peers are in
[docs/getting-started.md](docs/getting-started.md).

## Status

| Area | Status |
|---|---|
| Headers, proof of work, difficulty (pre-Blossom, post-Blossom, NU7) | ✅ live |
| Every non-cryptographic consensus rule, issuance and funding streams, NU7 rules | ✅ live |
| Transparent: script interpreter, ECDSA, every sighash version | ✅ live |
| Sapling and Sprout: Groth16, RedJubjub, Ed25519 | ✅ live |
| Orchard and Ironwood: Halo 2, RedPallas | ✅ live |
| Anchors for all four pools, ZIP 221 history root | ✅ live |
| Sync from genesis with Zebra's checkpoints | ✅ |
| Push block pickup, reorgs, crash recovery | ✅ |
| Mempool, relay, zcashd-compatible RPC subset (works with lightwalletd) | ✅ (no orphan pool, no wallet RPCs) |
| Bend-verified snapshot start | ✅ |
| Serving historical blocks to peers | ❌ pruned node |

"Tested" means differential testing against the official Rust code on real data; "proven" means a
Bend law that `bend PROOF.bend --verdict` accepts. [docs/verification.md](docs/verification.md)
lists exactly which claims are which.

## Performance

Measured on one Apple M5 Max, against the Rust crates Zakura uses and against Zakura itself
on the same live blocks. Full method and data: [docs/performance.md](docs/performance.md).

| | Zebend | Rust / Zakura |
|---|---|---|
| Halo 2, all 392,806 mainnet bundles | **2,225 bundles/s** (176 s) | 1,068/s quiet machine, 709/s same session |
| Sapling Groth16 proof | **1.78 ms** | 2.10 ms |
| Sync from genesis to the last checkpoint | ≈4.5 h of active sync | 4 h 20 min |
| Snapshot to download | **2.4 GB** | 12.1 GB |
| Block validation at the tip (block in hand → committed) | 0.06 s | **0.003 s** |
| Announcement → committed, median | 0.37 s | **0.26 s** |
| Memory | **~209 MB** | 395 MB |

Zakura validates a block in hand faster; Zebend is ahead on batch Halo 2 throughput and snapshot
size. Both nodes agreed on every block in the comparison.

## Documentation

| | |
|---|---|
| [Getting started](docs/getting-started.md) | building, running, snapshot start, RPC |
| [Architecture](docs/architecture.md) | how the node is put together, and the repository layout |
| [Verification](docs/verification.md) | what is tested against the official code, and on which data |
| [Proofs](docs/proofs.md) | every proven law, and what is assumed |
| [Performance](docs/performance.md) | benchmarks against Rust and Zakura |
| [Security](docs/security.md) | threat model, what is not covered, reporting issues |
| [Bend changes](docs/bend.md) | the compiler and runtime improvements Zebend needed |
| [Brand](docs/brand/README.md) | logo, colours, type, voice |

## Repository layout

```
node/       the full node you run: sync, store, rules engine, hooks, RPC, mempool, snapshot, monitor
zcash/      the protocol in Bend: p2p, headers, tx, block, state, transparent, sapling, halo2, consensus
crypto/     shared 64-bit field arithmetic
proofs/     machine-checked laws
research/   speed and GPU experiments behind the numbers above
web/        the in-browser verifier and bend2wasm
tools/      CI, fuzzing, the resource guard, Bend fork notes
docs/       documentation and brand
```

## Related work

- **Zebra** and **Zakura** are the production Rust nodes. Zebend is an independent implementation
  of the same consensus rules, not a fork of either.
- **ChainSafe WebZjs** and the **Zcash MetaMask Snap** run Zcash in the browser by compiling the
  official Rust libraries to WebAssembly. Zebend's browser verifier is a separate implementation.
- **zkSecurity's Orchard/Halo 2 audit** and **Shielded Labs'** formal-verification work are the
  rigorous efforts on the official code; Zebend adds an executable, independent check beside them.

## Security

Zebend is young software and has not been audited. Do not use it as the only validator for funds.
If you find a soundness issue in Zcash itself while using Zebend's tools, report it privately to the
Zcash security contacts first. See [docs/security.md](docs/security.md).
