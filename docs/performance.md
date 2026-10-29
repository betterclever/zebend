# Performance

All numbers are from one Apple M5 Max (18 CPU cores, 40-core GPU). Rust is measured twice: with the
upstream crates Zebra uses (`orchard` 0.16, `halo2_proofs` 0.4, `bellman` 0.15, ...) and with the
[Zakura Common](https://github.com/zakura-core/common) forks Zakura actually links (`zakura-orchard`,
`zakura-halo2-proofs`, `zakura-bellman`, ... 4.0.0, with Zakura's features and release profile).
The node itself is compared against Zakura v1.7.0 running beside Zebend on the same live blocks.
The machine was shared with other jobs; each benchmark records its load.

## Cryptography

Measured on 29 Oct 2026, upstream and Zakura Common interleaved in the same session (load 4–17);
ranges are the two clean rounds. Bend figures marked † are from earlier sessions and were not re-run.

| Workload | Zebend | Rust, upstream crates | Rust, Zakura Common |
|---|---|---|---|
| Halo 2 batch, 10,048 mainnet bundles, 18 threads | 2,408–2,520 bundles/s | 806–833/s | **11,367–11,535/s** proofs only; 7,052–7,653/s Zakura's own path (proofs + RedPallas, its batch cut) |
| Halo 2, one 2-action proof, 1 thread | 27 ms † | 20.5 ms | **5.0 ms** |
| Halo 2, one proof, 18 threads | 8 ms † | 3.0 ms | **1.3–1.5 ms** |
| Groth16 (Sapling), single proof, 1 thread | 1.80 ms | 2.06 ms | **1.33–1.47 ms** |
| Groth16, batch, 1 thread | **0.67 ms/proof** | 0.82–0.89 ms | 0.78–0.80 ms |
| Groth16, batch, 18 threads | **17,319 proofs/s** | 14,392/s | ~15,900/s |
| RedJubjub batch, 1 thread | 9.4k sigs/s † | 10.1k/s | **11.2–11.3k/s** |
| RedPallas, all 1,283,411 signatures, 18 threads | ~11 s † | 4.4–4.5 s | 4.3–4.5 s |
| Transparent inputs, 12 processes | 48k/s † | 321k/s | 319k/s (same interpreter and libsecp256k1) |
| Equihash, 16,384 headers, 18 threads | 39–41k headers/s † | 127–134k/s | **234–253k/s** |
| Wallet trial decryption | ~410k outputs/s (GPU) † | 332–340k/s (18 CPU threads) | **492–575k/s** (18 CPU threads) |

**Zakura's cryptography is faster than Zebend's on every row except batch Groth16**, where Bend is
about 15–20% ahead on one thread and about 9% on 18. Earlier versions of this page compared only
against the upstream crates and reported Zebend's batch Halo 2 as faster than Rust; against Zakura
Common it is 3–4.5× slower. Thanks to Dev Ojha of Zakura for pointing out the missing baseline.

The batch Halo 2 verifier is still 3× faster than the upstream crates: it merges more shared work
across proofs, uses batch-affine buckets, signed digits and GLV in the MSM, and runs on gate code
generated for the Orchard circuit and then optimised. Those optimisations are proven to compute the
same values (see [proofs.md](proofs.md)). Single proofs are slower: most of one proof is a
2,048-term MSM that Bend's runtime does not spread across all cores as well as Rust does.

Harnesses, timing script and raw logs: `research/bench/zakura-common/`. Earlier sources:
`research/perf4/`, `zcash/sapling/groth16/`, `zcash/sapling/`, `research/sigbatch/`,
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
