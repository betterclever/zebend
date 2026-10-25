# Every Orchard/Ironwood proof since NU6.3, verified in Bend

Every mainnet transaction with an Orchard or Ironwood bundle from Ironwood activation
(height 3,428,143) to the tip at the time of the run, with each bundle's Halo 2 proof checked
twice: by the official `orchard` verifier (`Bundle::verify_proof`) and by the Bend verifier.
The two verdicts are diffed bundle by bundle.

RESULTS_PLACEHOLDER

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
