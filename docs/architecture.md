# Architecture

Zebend is a set of Bend programs that do all of the consensus and cryptographic work, held
together by a small Python node that moves bytes, keeps state and talks to peers. The Python side
decides nothing about validity: every verdict comes from a Bend program.

## The node

```
 peers ──inv/headers──▶ tipsync (node/fasttip)
                          │ fetch block, check header in Bend (Equihash, target, links, difficulty)
                          ▼
                        sync (node/sync.py)
                          ├─ blockdelta (Bend)      parse, txids, merkle root, state deltas
                          ├─ rules (Bend)           every non-cryptographic consensus rule, pools
                          ├─ hooks (Bend, parallel) transparent · sapling+sprout · orchard+ironwood
                          ├─ trees (Bend)           Sprout, Sapling, Orchard, Ironwood roots → anchors
                          ├─ history (Bend)         ZIP 221 history root vs the header commitment
                          └─ store                  SQLite + leaf logs, one transaction per window
 rpc ◀── state ──▶ mempool (admission = the same Bend checks on a synthetic next block)
 follow: an independent monitor with its own Bend pipeline and peers
```

- **Windows.** Blocks are validated in windows and committed atomically. A crash anywhere resumes at
  the last committed window.
- **Checkpoints.** Below Zebra's last checkpoint (3,522,460), blocks are checked against the
  checkpointed hash chain and audited by the rules engine. Above it, every rule and every
  cryptographic check runs.
- **Reorgs.** A block that does not extend the tip is resolved at once. The competing headers are
  checked in Bend, the node switches only to more work, and rolls back with stored undo data
  (600 blocks deep).
- **Supervisor.** `node/ops/supervise.py` restarts dead services, and alarms on stalls, orphans,
  disk, memory and code edited under a running daemon.

## The protocol in Bend (`zcash/`)

| Directory | What |
|---|---|
| `p2p`, `wire` | the Zcash P2P protocol, and hardened parsers fuzzed against the Rust crates |
| `headers` | Equihash (200,9), targets, difficulty in every era |
| `tx`, `block` | v1–v6 parsing, ZIP 244/243/143 txids and sighashes, merkle roots, block commitments |
| `state` | Ironwood tree and nullifier set |
| `transparent` | secp256k1, ECDSA, the script interpreter |
| `sapling` | Jubjub, RedJubjub, the Sapling tree, `groth16/` on BLS12-381 |
| `halo2` | the Halo 2 verifier generated from Orchard's verifying key, its oracle, and the circuit under-constraint checker |
| `consensus` | anchors, issuance, NU7, Sprout, ZIP 221 |

## Repository layout

```
node/       the full node
zcash/      the protocol in Bend
crypto/     64-bit field arithmetic shared by the curves
proofs/     machine-checked laws
research/   speed and GPU experiments (the deployed fast Halo 2 verifier is research/perf4)
web/        browser verifier (Bend's JS target) and bend2wasm
tools/      CI, fuzzing, heavy.sh, Bend fork notes
docs/       documentation and brand
```
