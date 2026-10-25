# Every Orchard/Ironwood proof since NU6.3, verified in Bend

Every mainnet transaction with an Orchard or Ironwood bundle from Ironwood activation
(height 3,428,143) to the tip at the time of the run, with each bundle's Halo 2 proof checked
twice: by the official `orchard` verifier (`Bundle::verify_proof`) and by the Bend verifier.
The two verdicts are diffed bundle by bundle.

## Results (run of Oct 25, 2026; M5 Max)

**Halo 2 proofs: every bundle since NU6.3, Bend agrees with the official verifier on all of them.**

```
txs 366418; bundles 392806 (ironwood 352141, orchard 40665); actions 1155249; heights 3428144..3529855
by circuit: {'PostNu6_3': 392806}
official verifier valid 392806/392806
Bend valid 392806/392806; agree with official 392806/392806; disagree 0; not run 0
Bend batch verification: 6144 batches of 64 (0 rejected), 579 s process time = 679 bundles/s
```

- Coverage: the compact-block scan found 366,418 txs with 250,416 Orchard + 904,833 Ironwood
  actions; the verified bundles carry exactly 1,155,249 = 250,416 + 904,833 actions.
- Every bundle used the post-NU6.3 circuit (no older-circuit bundles exist after activation).
- Batch soundness check: a chunk with one bundle's proof byte flipped is rejected, and the
  per-bundle fallback (`perf3/v64/bundle_ba`) singles out exactly that bundle.

**RedPallas signatures: every fully shielded tx (no transparent inputs), via node/tx's Bend code.**

```
txs 276675: txid match 276675/276675; spend-auth sigs verified 980364; binding sigs verified 303047; all valid True
tamper control (a0 spend_auth_sig byte flipped): txid unchanged; spend-auth checks 5 with 1 failing; binding 1 with 0 failing
tamper control (binding_sig byte flipped):       txid unchanged; spend-auth checks 5 with 0 failing; binding 1 with 1 failing
```

The 89,743 txs with transparent inputs were not signature-checked here: their ZIP 244
sighash needs the spent outputs' amounts and scripts, which this pipeline does not fetch.
Their Halo 2 proofs are included above.

**Throughput on identical bundles** (the first 10,048 bundles of part 0, same machine, run back
to back; load average 14–22 from other jobs; both batch 64 bundles at a time):

| | 1 thread | 18 threads |
|---|---|---|
| Bend `perf3/v64/batch_main` (process time incl. file reads) | 133 bundles/s | 719 bundles/s |
| Rust halo2 `BatchVerifier` (vendored halo2_proofs 0.4, instance computation included) | 94 bundles/s | 1,260 bundles/s |

On this set Bend is faster single-threaded and Rust is 1.75× faster on 18 threads. Treat the
single-thread result with care: an earlier comparison on 2-action bundles against orchard's
`BatchValidator` had Rust ahead (155 vs 113 bundles/s), and the machine was shared.
Official verification for the whole set (parse + single `verify_proof` per bundle, all cores):
870 s wall.

## Pipeline

| Step | Command | What it does |
|---|---|---|
| 1. scan | `oracle/target/release/proofsets-oracle scan` | lightwalletd compact blocks (Orchard + Ironwood pools) from 3,428,143 to the tip → `data/txids.txt` |
| 2. fetch | `... fetch 32` | raw transactions via `GetTransaction`, 32 workers over zec.rocks mirrors, per-request timeouts, retries, resumable → `data/raw.bin` |
| 3. build | `... build 64` | parse each tx (`zcash_primitives`), compute each action's 10 Halo 2 public inputs exactly as `node/tx` does, run the official verifier, write Bend inputs in 64-bundle chunks → `data/chunks/`, `data/official.txt` |
| 4. Bend | `python3 run_bend.py` | `perf3/v64/batch_main` per chunk (one merged final MSM with random weights); a rejected chunk is re-checked bundle by bundle with `perf3/v64/bundle_ba`; verdicts diffed against `official.txt` |
| 5. signatures | `... sigsample N SEED` then `python3 run_sigs.py` | fully shielded txs (no transparent inputs) through `node/tx/tx_main`: Bend recomputes the network txid and checks every spend-auth and binding RedPallas signature |
| 6. Rust timing | `... rust-batch THREADS LIMIT` | halo2 `BatchVerifier` over the same bundles, for the throughput comparison |

Older circuit versions (pre-NU6.2, NU6.2) would go to `data/other/` and the matching
`fast/pure/v32` single-bundle verifiers; see the results for how many there were.

## What this does and does not show

- **Tested, not proven:** agreement between two independent implementations on real data.
- The public inputs are computed by our own code (as in `node/tx`); the official verifier
  accepting the proof with those inputs is what confirms them.
- Signatures: mainnet consensus already accepted every one of these transactions, so the
  reference verdict is "valid"; the tamper control shows the Bend checks can fail.
- Not checked here: anchors against the tree history, nullifier uniqueness, value balance
  (`node/state`, `validate/` and the turnstile laws cover those elsewhere).
- Raw data (~11 GB) is not in git; the commands above re-fetch it.
