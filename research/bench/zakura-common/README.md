# Rust baselines on the Zakura Common crates

The Rust baselines behind `docs/performance.md` were built on the upstream crates (`orchard` 0.16,
`halo2_proofs` 0.4, `reddsa` 0.6). Zakura links its own forks from
[zakura-core/common](https://github.com/zakura-core/common) (`zakura-orchard`,
`zakura-halo2-proofs`, `zakura-reddsa`, ... all 4.0.0). These harnesses are copies of the
originals rebuilt on those crates, with the dependency names, features and release profile from
Zakura's workspace `Cargo.toml` (thin LTO, codegen-units 4, 1 per dependency; no asm or `orbits`
features, as Zakura). The originals are unchanged. Build each with
`cargo build --release --offline`.

| Harness | Original | Workloads |
|---|---|---|
| `halo2_batch/` | `research/proofsets/oracle rust-batch` | `rust-batch` (proofs only, par_chunks(64), as the original); `actions-batch` (proofs only, Zakura's ≥64-action batches); `zakura-batch` (Zakura's whole path: BatchValidator, proof + RedPallas, ≥64-action batches; fully shielded txs only); `check N` |
| `halo2_perf/` | `zcash/halo2/lib/perf bench-verify` | single proof (as the original) and Zakura's one-bundle BatchValidator; K-bundle BatchValidator |
| `redpallas/` | `research/sigbatch/oracle rust` | `rust THREADS` (unchanged); `verify FILE...` |

`halo2_batch/vendor/zakura-orchard` is zakura-orchard 4.0.0 plus one additive type, `ProofBatch`
(the proof half of `BatchValidator`), because the crate exposes no proofs-only batch: the halo2
key and parameters are `pub(crate)`. See its `ZEBEND_NOTICE`.

Every verifying key is armed as Zakura arms it (`prepare_batch_validation()`); in Zakura's build
that is a no-op and returns false.

## Timing commands (same shapes as the originals)

```sh
Z=research/bench/zakura-common
# Halo 2, all post-NU6.3 mainnet bundles, 18 threads (original: proofsets-oracle rust-batch 18)
$Z/halo2_batch/target/release/zc-halo2-batch rust-batch 18
$Z/halo2_batch/target/release/zc-halo2-batch actions-batch 18
$Z/halo2_batch/target/release/zc-halo2-batch zakura-batch 18
# perf4 sample shapes: 10,048 bundles at 18T; 256 bundles at 1T
$Z/halo2_batch/target/release/zc-halo2-batch rust-batch 18 10048
$Z/halo2_batch/target/release/zc-halo2-batch rust-batch 1 256
# one 2-action proof, 1 and 18 threads (original: RAYON_NUM_THREADS=T bend-halo2-perf bench-verify 1,
# repeated, median across runs)
RAYON_NUM_THREADS=1  $Z/halo2_perf/target/release/zc-halo2-perf bench-verify 1
RAYON_NUM_THREADS=18 $Z/halo2_perf/target/release/zc-halo2-perf bench-verify 1
# RedPallas, every signature (original: sigbatch-oracle rust 18 / rust 1)
$Z/redpallas/target/release/zc-redpallas rust 18
$Z/redpallas/target/release/zc-redpallas rust 1
```

## What a library harness does not capture of Zakura's node

- The verification cache (`Cached`, keyed by wtxid, sighash and pool): at the tip, transactions
  already verified from the mempool are not verified again.
- The tower batch service: the 100 ms latency flush (a lone bundle waits up to 100 ms for company),
  the cap on concurrent batches, and the fallback that re-verifies each item when a batch fails.
- The rayon global pool sized by `sync.parallel_cpu_threads`, shared with Groth16, transparent and
  other verification.
- `zakura-batch` covers fully shielded transactions only; the others need spent outputs for the
  sighash.

## Results (29 Oct 2026)

`timeall.sh` runs every workload upstream-then-Zakura (order flipped each round) for three rounds,
plus the deployed Bend Halo 2 batch verifier and `transparent/bench.sh 12`. Round 1 ran at load
21–93 from other jobs; rounds 2–3 at load 4–17 are the ones quoted. Raw logs in `timing/`
(`run-20261029-1750.aborted.log` is a first attempt with stale upstream binaries, kept for the
record). Groth16 against Bend: `zcash/sapling/groth16/bench.py real 2` plus the Zakura harness at
18 threads, `timing/groth16-*.log`.

| Workload | Upstream | Zakura Common | Bend (same session) |
|---|---|---|---|
| Halo 2 batch, 10,048 bundles, 18T, par_chunks(64) | 806–833/s | 11,367–11,535/s | 2,408–2,520/s |
| Halo 2 batch, Zakura's >=64-action cut | | 7,862–9,272/s | |
| Halo 2, Zakura's BatchValidator (proofs + RedPallas) | | 7,052–7,653/s | |
| Halo 2, one proof, 1T / 18T | 20.5 / 2.9–3.0 ms | 5.0–5.1 / 1.3–1.5 ms | |
| RedPallas, 1,283,411 sigs, 18T | 283–292k/s | 286–300k/s | |
| Groth16 single, 1T | 2.0–2.2 ms | 1.33–1.47 ms | 1.80 ms |
| Groth16 batch (chunks of 128), 1T | 0.82–0.89 ms | 0.78–0.80 ms | 0.67 ms |
| Groth16 batch (chunks of 128), 18T | 14,392/s | 15,899–15,956/s | 17,319/s |
| RedJubjub batch, 1T | 10.1k/s | 10.6–11.3k/s | |
| Equihash, 16,384 headers, 18T / 1T | 127–134k / 10.4k/s | 234–253k / 20.1–21.9k/s | |
| Trial decryption, 262,144 outputs, 18T / 1T | 332–340k / 26k/s | 492–575k / 50.5–50.9k/s | |
| Transparent, 119,293 inputs, 12 procs | 321k/s | 319k/s | |

Sanity: `zc-halo2-batch check 10048` accepts all 10,048 bundles in every mode, and rejects the
batch in every mode when one proof byte is flipped or one sighash changed.

`transparent/` builds against a local Zakura v1.7.0 checkout (`~/zakura-bench/src/zakura`) because
it calls Zakura's own sighash and script path (`zakura-script`), not a crates.io library.
