# Performance

All numbers are from one Apple M5 Max (18 CPU cores, 40-core GPU), measured against the Rust crates
that Zebra and Zakura use, and against Zakura v1.7.0 running beside Zebend on the same live blocks.
The machine was shared with other jobs; each benchmark records its load.

## Cryptography

| Workload | Zebend | Rust |
|---|---|---|
| Halo 2, all 392,806 mainnet bundles, 18 threads | **2,225 bundles/s (176 s)** | 1,068/s quiet machine; 709/s same session |
| Halo 2, one 2-action proof, 1 thread | 27 ms | **21 ms** |
| Halo 2, one proof, 18 threads | 8 ms | **3.2 ms** |
| Groth16 (Sapling), 1 thread | **1.78 ms** | 2.10 ms |
| RedJubjub, 1 thread | **9.4k sigs/s** | 8.3k sigs/s |
| RedPallas, all 1,283,411 signatures | ~11 s | **4–7 s** |
| Transparent inputs, 12 processes | 48k/s | **332k/s** |
| Equihash, 18 threads | 39–41k headers/s | **~117k headers/s** |
| Wallet trial decryption, constant-time | **~410k outputs/s (GPU)** | 346k outputs/s (18 CPU threads) |

The batch Halo 2 verifier is faster than Rust's because it merges more shared work across proofs,
uses batch-affine buckets, signed digits and GLV in the MSM, and runs on gate code generated for the
Orchard circuit and then optimised. Those optimisations are proven to compute the same values (see
[proofs.md](proofs.md)). Single proofs are still slower: most of one proof is a 2,048-term MSM that
Bend's runtime does not spread across all cores as well as Rust does.

Sources: `research/perf4/`, `zcash/sapling/groth16/`, `zcash/sapling/`, `research/sigbatch/`,
`zcash/transparent/`, `research/blake3x/`, `research/scan2/`.

## The node against Zakura

141 consecutive live mainnet blocks; headline window of 37 blocks with Zakura's proof cache off.
Full report and per-block data: `research/bench/zakura_vs_zebend.md`.

| Median | Zakura | Zebend |
|---|---|---|
| First announcement on the machine → committed | **0.26 s** | 0.37 s |
| Each node's own announcement → committed | **0.24 s** | 0.31 s |
| Validation only (block in hand → committed) | **0.003 s** | 0.06 s |
| CPU per block | **0.24 s** | 0.52 s |
| Memory | 395 MB | **~209 MB** |
| Chain state on disk | 14.1 GB | 13.9 GB |

## Sync and start-up

| | Zebend | Zakura |
|---|---|---|
| Genesis to the last checkpoint | ≈4.5 h of active sync | 4 h 20 min (published) |
| Snapshot download | **2.4 GB** | 12.1 GB |
| Snapshot import | 171 s, every byte checked in Bend | 61 s |
