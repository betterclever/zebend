# Zebend: a Zcash node in Bend (plan and contract)

Every component is checked against real mainnet data or the official Rust
implementation (differential testing), and accounting rules are proven with Bend laws.
Be precise in reports about which is which: "matches the oracle" is not "proven".

## Components (each owns one directory under zcash/)
| dir | component | ground truth |
|---|---|---|
| `headers/` | header chain: SHA-256d block hash, compact target check, Equihash (200,9) on GPU, prev-hash linkage, difficulty adjustment (Blossom 75 s, NU7 25 s) with proven bound laws | real mainnet headers; Rust `equihash` crate |
| `tx/` | transaction layer: v5/v6 parsing, ZIP 244 txid + sighash, Orchard/Ironwood bundle checks (value balance, RedPallas spend-auth + binding signatures), Halo 2 public inputs | real mainnet txs from lightwalletd `GetTransaction`; txids; `orchard`/`zcash_primitives` |
| `state/` | shielded state: Sinsemilla MerkleCRH, Ironwood (and Orchard) note commitment tree rebuilt from mainnet compact blocks, nullifier-set double-spend check | lightwalletd `GetTreeState` roots |
| `p2p/` | Zcash P2P: TCP handshake (version/verack), ping, getheaders/headers with a real mainnet peer, message framing + checksums | live mainnet peers |
| `halo2/` | Halo 2 proof verification (in progress) | official verifier trace |
| `../proofs/turnstile/`, `../proofs/migration/` | proven value-pool and migration laws (done) | Bend proofs |

## Shared, read-only for everyone
- `halo2/lib/`: words, Fp, Fq, Vesta, Pallas, MSM (tested against pasta_curves). Read its README.
- `../research/gpu-scan/zcrypto.bend`: BLAKE2b (personalized), ChaCha20, Pallas.
- Lightwalletd mainnet: `https://zec.rocks:443` (also na./eu.zec.rocks), gRPC
  `cash.z.wallet.sdk.rpc.CompactTxStreamer`; hand-written prost client in
- Rust oracles go in `<component>/oracle/`, built and run on the Mac.

## Rules
Bend/Rust runs on the Mac via `mac zsh -lc '...'`; edit through /Users paths from the VM.
Write only inside your own component directory. Never fake results: if a stage doesn't
match, report exactly where it stops.
