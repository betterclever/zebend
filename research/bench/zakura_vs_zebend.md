# Zebend vs Zakura: live-tip block validation, same Mac, same mainnet blocks

Measured 2026-10-28, 03:16–06:28 IST, on mainnet heights **3532866..3533006 (141 consecutive blocks)**.
Both nodes ran side by side on one Apple M5 Max (18 cores, 48 GB) behind a phone hotspot (NAT, no inbound).
All times come from one wall clock.

## Verdict

**On these data, Zebend is not the fastest. Zakura is faster on every quantile of every comparable metric.**

| best comparable window (fasttip, 37 blocks 3532970..3533006) | Zakura 1.7.0 (proof cache **off**) | Zebend fasttip |
|---|---|---|
| first announcement on this machine → committed: median / p90 / max | **0.262 / 0.536 / 2.68 s** | 0.368 / 1.277 / 37.4 s |
| node's own inv → committed: median / p90 / max | **0.243 / 0.519 / 0.70 s** | 0.308 / 0.505 / 0.56 s |
| validation only (block bytes in hand → verdict committed): median / p90 / max | **0.003 / 0.006 / 0.013 s** | 0.060 / 0.143 / 0.219 s |
| CPU-seconds per block (whole node, incl. mempool and networking) | **0.24** | 0.52 (tipsync 0.41) |
| RSS | 395 MB (one process) | **209 MB** (sum of 4 services) |
| disk, chain state | 14.1 GB (pruned, tx_retention 10000) | **13.9 GB** (`node/state`) |

- **Own inv → commit is nearly a tie, but only because fetch dominates.** Zakura spends about 0.24 s fetching the block over P2P and 3 ms validating it. Zebend spends 0.22 s fetching and 60 ms validating. The p90 values are equal (0.519 vs 0.505 s), and Zebend's max is lower in this window.
- **Pure validation: Zakura is about 20× faster.** The medians are 3 ms vs 60 ms. This is a Rust node with batched Halo 2 verification, against Bend processes plus Python orchestration.
- **Before fasttip, end to end was not close.** Zebend as deployed (live.py polling every 60 s, then sync.py polling the spool) took a median of 136 s, against 0.26 s for Zakura.
- **Agreement and validity.** Both nodes agree on all 141 canonical hashes (checked through both RPCs). Neither rejected any block: no FAIL, MISMATCH or invalid-block lines.
- **Reorg at 3532945.** Both nodes first took block `5714cf…`, which was orphaned for `48cae4…`. Zakura moved to the new branch within 133 s, when the child block arrived. Zebend stayed on the stale tip from 05:01:59 to 05:18:30 (about 16.5 min), because the push path went quiet and only the 60 s fallback found the reorg. During that time Zebend did not commit 3532946..3532957 either (lags of 104–890 s).

## Method

### Zakura setup
- **Build.** v1.7.0 from git tag `v1.7.0`, `cargo build --release -p zakura`, under `tools/heavy.sh`. It took 2 min 23 s; incremental rebuilds took 1–1.5 min. There is no macOS release binary: the release assets are Linux x86_64/aarch64 only.
- **Instrumentation patch.** I added 4 log lines and 1 env switch to the source:
  - `crates/zakurad/src/components/inbound/downloads.rs` logs three things at info level: the inv hash queued for download (first seen), the block downloaded, and verified+committed (now with the hash).
  - `crates/zakura-consensus/src/primitives/cache.rs`: when `ZKBENCH_NO_PROOF_CACHE=1` is set, every lookup in the shielded proof-verification cache misses.
  - Default behaviour is unchanged when the env var is unset. Source and diff: `~/zakura-bench/src/zakura` (`git diff`).
- **Snapshot.** Official pruned snapshot `zakura-mainnet-pruned-20261027T061807Z-3532115.tar.zst` (12.1 GB, sha256 `dfb67c15…79be`, verified).
  - Download: about 25 min (about 7–8 MB/s on this link).
  - Extract: 61 s (`zstd -T0 | tar`).
  - The snapshot's state tip was **3531115**. From start (03:08:48 IST) Zakura caught up 1,745 blocks to the tip (3532860) in **7.7 min**.
  - For comparison, Zebend's start from its own 2.4 GB snapshot was 4.1 min, excluding the download (figure supplied by the coordinator, not measured here).
- **Config** (`~/zakura-bench/zakura.toml`):
  - Legacy P2P only (the Mainnet default); listener on `127.0.0.1:28233`, so no inbound.
  - RPC on `127.0.0.1:28232`, Prometheus on `127.0.0.1:29999`.
  - Pruned storage. Data dir `~/zakura-bench/cache`.
  - `peerset_initial_target_size = 8` until 03:22, then **4** (outbound cap 6; 4–6 peers in practice).

### What was timed (per canonical block hash)
- **t0, first announcement on this machine.** The earliest of three inv times:
  - Zakura's own inv, from the patched log, by hash;
  - Zebend fasttip's `t_inv` from `node/logs/fasttip_latency.jsonl`;
  - an independent 1-slot observer (`tools/observer.py`), a passive legacy-P2P connection that logs block invs.

  If a node committed the block before any inv was seen (it arrived through the syncer or fallback), t0 is bounded by that commit (`t0_src=commit_bound`; 9 blocks).
- **Zakura committed.** The patched "downloaded and verified gossiped block" line. For the 23 blocks that came in through the syncer instead of gossip, a 200 ms RPC tip poller (`zk_tip.tsv`) is used instead.
- **Zakura validation-only.** Verified line minus block-downloaded line. That interval covers coinbase-height checks, the full block verifier (transactions, proofs, signatures) and the state commit.
- **Zebend committed.**
  - After 04:27:28 (fasttip): `t_commit` in `fasttip_latency.jsonl`.
  - Before that: the "committed tip N" line in `node/logs/sync.log`, time-stamped on arrival by a 50 ms file tailer.
- **Zebend validation-only.**
  - fasttip: `t_commit − t_recv` (header check + queue + validate + commit). `validate_commit_s` alone has a median of 0.048 s.
  - live+sync era: spool chunk appearance (50 ms directory watcher) → commit. This includes sync.py's 5 s spool poll.
- **CPU and RSS.** `ps -S` every 10 s, which folds reaped children into the parent, so the short-lived Bend helper processes are counted. Groups:
  - zakurad;
  - Zebend: tipsync/sync tree, mempool, follow, rpc (some of these were re-parented to pid 1 by the supervisor restart and matched by command line).
- **Disk.** `du -sk` every 10 min.

All tooling is in `~/zakura-bench/tools/` (`benchmon.py`, `observer.py`, `zk_tip.py`, `analyze.py`, `resources.py`); raw monitor output is in `~/zakura-bench/mon/`.

## Results by era

Zebend changed under the benchmark at 04:27:28 IST: live.py+sync.py were replaced by `node/fasttip/tipsync.py`, which has push pickup. Zakura was switched to cold-cache mode at 05:29–05:32. The eras are reported separately; blocks are assigned to an era by announcement time.

| era | blocks | metric (s) | Zakura median / p90 / max | Zebend median / p90 / max |
|---|---|---|---|---|
| live+sync (Zakura proof cache on) | 3532866..3532910 (45) | t0 → committed | 0.255 / 1.56 / 5.41 | 135.6 / 312.5 / 428.0 |
| | | validation only | 0.006 / 0.037 / 0.064 | 3.27 / 6.59 / 7.18 (spool → commit; sync.py window compute median 0.6 s) |
| transition (announced before switch, committed after) | 3532911..3532917 (7) | t0 → committed | 0.201 / 0.275 / 0.978 | 469 / 491 / 549 |
| fasttip, Zakura proof cache **on** | 3532918..3532964 (47) | t0 → committed | 0.229 / 0.366 / 133.5 (orphan reorg) | 32.0 / 334.2 / 890.5 |
| | | validation only | 0.004 / 0.007 / 0.014 | 0.109 / 0.269 / 2.70 (35 push blocks) |
| | | Zebend inv lag behind t0 | – | 20.0 / 75.5 / 93.3 |
| Zakura restarting | 3532965..3532969 (5) | (excluded) | | |
| fasttip, Zakura proof cache **off** | 3532970..3533006 (37) | t0 → committed | **0.262 / 0.536 / 2.68** | 0.368 / 1.277 / 37.4 |
| | | own inv → committed | 0.243 / 0.519 / 0.699 | 0.308 / 0.505 / 0.560 |
| | | fetch (own inv → bytes in hand) | 0.240 / 0.512 / 0.694 | 0.222 / 0.426 / 0.482 |
| | | validation only | **0.003 / 0.006 / 0.013** | 0.060 / 0.143 / 0.219 |

Zebend follow (the shielded-only validator, separate from the full node), verified minus download-complete: median 0.57 s and p90 0.81 s in the last window; median 1.3 s and p90 4.6 s in the first.

**Why Zebend lagged in the warm fasttip window:**
- Until 05:37:54, every fasttip push peer it obtained dropped it within 2–8 s ("gone after 2 s, 0 block invs"), so invs reached Zebend 20 s (median) to 93 s after they reached Zakura.
- From 05:37:54 it held a stable push peer (34.91.248.94, Zebra 7.0.0). After that, Zebend heard first on 23 of 37 blocks, usually by milliseconds.

**Was Zakura's peer use the cause? I found no evidence of it.**
- The improvement happened while Zakura was running with the same peer settings.
- At the end of the run, Zakura and 3 Zebend processes were all connected to 34.91.248.94 at the same time. The peers in use here do not enforce one connection per IP against our NAT address.
- Zebend's download delays before Zakura existed (15–150 s per live.py round, in today's `live.log`) look the same as during the run, apart from one 374 s round that started just before Zakura launched.
- I cannot fully exclude short-lived contention, because Zakura's peer addresses are redacted in its logs.

### Resources (cold window, 3200 s, 37 blocks)
- **CPU-seconds per block, whole node, all idle work included:**
  - Zakura: **0.24** (9.0 s).
  - Zebend: **0.52** (19.3 s). Split: tipsync/sync 0.41, mempool 0.09, follow 0.02, rpc 0.00.
  - Zakura's figure includes mempool verification of the proofs it then re-verifies in blocks (the cache was off).
  - Zakura's CPU was not captured in the warm windows (a monitor bug matched the wrong process name), so the CPU figures cover this window only.
- **RSS:**
  - Zakura: 395 MB median, 410 MB max.
  - Zebend: sync/tipsync 102 MB, mempool 52 MB, follow 48 MB, rpc 8 MB, about 209 MB in total.
- **Disk:**
  - Zakura chain state: 14.1 GB (13.5 GiB, pruned).
  - Zebend `node/state`: 13.9 GB, plus follow state 68 MB. The whole `zebend/node` dir is 71 GB, because it holds older instances and spools.
  - Benchmark extras: snapshot archive 11.8 GB (`~/zakura-bench/dl`, deletable), build tree 2.2 GB (`~/zakura-bench/target`).
- **Machine load (1-min loadavg on 18 cores):**
  - live+sync era: median 28.5, max 145.
  - warm fasttip era: median 14.8, max 50.
  - cold window: median 4.5, max 11.

  Other agents' jobs ran during the first two eras, including a `bend-zcash` txpolicy process at 800 CPU-min, so those latencies are noisier. The headline (cold) window had the lightest load.

## Caveats (read before quoting any number)
1. **Not a pure compute benchmark.** "t0 → committed" includes each node's position in the gossip network: peer count, which peers, IPv4 or IPv6.
   - Zakura had 4–6 outbound legacy peers.
   - Zebend fasttip had 1–3 push peers, plus its follow tap.
   - Neither node accepted inbound connections.
2. **The Zakura validation split depends on where I put the log line.** "Downloaded" is logged after the P2P fetch and deserialization, before the height checks and `verifier.oneshot(Commit)`.
   - The 3 ms figure for blocks with up to 10 Halo 2 bundles is remarkably small. Still, the cold-cache counters confirm real proof work in the cold window: 173 Halo 2 verifications against 93 block bundles; the rest are mempool verifications; 0 cache hits.
   - Zebend's "validation-only" includes header/Equihash check, queue handoff and commit; Zakura's includes the state commit.
3. **Proof cache.** By default Zakura caches shielded proofs it already verified in its mempool and skips re-verifying them in blocks (`zakura_consensus_cache_hit`; 24 hits against 26 misses early on). The cold-cache window removes this. For these small blocks, the validation time hardly changed (4 ms → 3 ms).
4. **Small blocks.** The blocks are small: 1–26 txs, 0–17 shielded bundles. Worst-case (sandblast-size) blocks were not exercised. Zakura claims a large advantage there; this run does not test that claim.
5. **Zebend changed mid-run.** The live+sync and transition numbers describe the old pipeline, which no longer runs.
6. **Zakura was restarted twice** (peer target 8 → 4 at 03:22; cold mode at 05:29–05:32). Blocks announced during restarts are excluded.
7. **Zakura instrumentation.** Its numbers come from a patched build: four log lines plus one env-gated cache switch. Logging cost is negligible next to the measured intervals.
8. **t0 source.** t0 is the earliest inv seen by any process on this Mac, not by "the network". The independent observer ran with 1 slot, to save scarce peer slots, and set t0 for only 2 blocks.
9. **Hash agreement** was checked against the canonical chain at analysis time. For orphan height 3532945, each node's commit time is for the canonical block, `48cae4…`.

## Raw data

The full per-block CSV (31 columns: every timestamp, its source, and derived intervals) is in `research/bench/zakura_vs_zebend_blocks.csv`.

The compact CSV is below. Times are seconds:
- `zk_*` is Zakura and `zb_*` is Zebend;
- `t0_src` names the first-seen source;
- `zk_mode` is warm (proof cache on), down (restarting) or cold (cache off);
- `zb_validate` is spool→commit in the live+sync era and push t_recv→t_commit in the fasttip era;
- `zb_inv_lag` is Zebend's own inv minus t0.

```csv
height,hash16,txs,shielded_bundles,era,zk_mode,t0_src,zk_t0_to_commit,zb_t0_to_commit,zk_validate,zb_validate,zb_inv_lag,zb_hash_match
3532866,0000000000617e0f,5,3,live+sync,warm,zakura_inv,0.323,324.624,0.037,1.928,,True
3532867,00000000001a67dc,5,1,live+sync,warm,zakura_inv,0.675,312.468,0.011,1.928,,True
3532868,00000000001e7303,4,1,live+sync,warm,zakura_inv,0.357,216.196,0.015,1.928,,True
3532869,000000000059ae9c,2,0,live+sync,warm,zakura_inv,0.403,199.805,0.002,1.928,,True
3532870,00000000000f692b,19,9,live+sync,warm,zakura_inv,0.504,42.565,0.009,5.310,,True
3532871,000000000040f136,7,2,live+sync,warm,zakura_inv,0.214,180.951,0.006,4.193,,True
3532872,00000000004e609f,1,0,live+sync,warm,zakura_inv,0.138,165.260,0.005,4.193,,True
3532873,00000000005ce757,1,0,live+sync,warm,commit_bound,0.000,128.791,,4.193,,True
3532874,0000000000113636,11,4,live+sync,warm,zakura_inv,0.309,67.792,0.014,4.193,,True
3532875,00000000002f6073,3,1,live+sync,warm,zakura_inv,0.301,153.540,0.006,1.964,,True
3532876,0000000000003824,1,0,live+sync,warm,zakura_inv,0.473,118.315,0.001,1.964,,True
3532877,00000000006e3c5d,20,5,live+sync,warm,zakura_inv,0.258,428.027,0.006,3.271,,True
3532878,00000000002b9e3c,2,0,live+sync,warm,zakura_inv,0.293,389.228,0.001,3.271,,True
3532879,0000000000687a28,14,5,live+sync,warm,commit_bound,0.000,244.568,,3.271,,True
3532880,000000000007718a,1,0,live+sync,warm,zakura_inv,0.247,224.493,0.001,3.271,,True
3532881,00000000005c8638,1,0,live+sync,warm,commit_bound,0.000,218.032,,3.271,,True
3532882,00000000002cccf7,1,0,live+sync,warm,zakura_inv,0.246,183.633,0.001,3.271,,True
3532883,000000000021a089,12,6,live+sync,warm,commit_bound,0.000,210.307,,4.571,,True
3532884,00000000003ae50c,6,3,live+sync,warm,zakura_inv,0.151,135.623,0.002,4.571,,True
3532885,000000000000f41b,1,0,live+sync,warm,zakura_inv,0.140,103.937,0.001,4.571,,True
3532886,00000000005188a3,2,0,live+sync,warm,zakura_inv,0.225,89.575,,4.571,,True
3532887,000000000055ac42,6,3,live+sync,warm,zakura_inv,0.314,41.246,0.002,2.779,,True
3532888,000000000029c00d,12,5,live+sync,warm,zakura_inv,0.223,121.657,0.012,2.644,,True
3532889,000000000034567b,1,0,live+sync,warm,zakura_inv,0.234,85.413,0.001,2.644,,True
3532890,00000000003d924f,7,4,live+sync,warm,zakura_inv,0.225,109.166,0.006,1.409,,True
3532891,00000000006388cf,12,5,live+sync,warm,zakura_inv,0.537,80.167,0.008,2.990,,True
3532892,0000000000416b8d,1,0,live+sync,warm,zakura_inv,0.211,28.998,0.002,2.990,,True
3532893,0000000000256407,5,3,live+sync,warm,zakura_inv,0.223,84.048,0.003,3.516,,True
3532894,000000000006ae46,1,0,live+sync,warm,zakura_inv,0.248,60.918,0.003,3.516,,True
3532895,00000000002ff459,1,0,live+sync,warm,zakura_inv,0.255,38.388,0.001,3.516,,True
3532896,00000000006f4188,1,0,live+sync,warm,zakura_inv,0.425,31.242,,3.516,,True
3532897,00000000003058bc,8,4,live+sync,warm,zakura_inv,0.224,102.483,0.007,0.791,,True
3532898,000000000027f64d,1,0,live+sync,warm,zakura_inv,0.273,93.523,0.001,0.791,,True
3532899,00000000000a58c1,5,0,live+sync,warm,commit_bound,0.000,155.889,,3.253,,True
3532900,00000000001dfe7c,1,0,live+sync,warm,zakura_inv,0.243,132.425,0.002,3.253,,True
3532901,000000000018d9a5,13,4,live+sync,warm,zakura_inv,0.214,97.665,0.006,4.084,,True
3532902,00000000000369d3,226,216,live+sync,warm,zakura_inv,2.055,349.715,0.064,2.927,,True
3532903,00000000004b5fa0,223,217,live+sync,warm,zakura_inv,5.408,248.729,0.062,2.927,,True
3532904,000000000054dae5,5,1,live+sync,warm,zakura_inv,0.268,175.298,0.002,2.927,,True
3532905,0000000000121221,226,218,live+sync,warm,zakura_inv,1.560,201.000,0.061,6.593,,True
3532906,00000000004da4d1,1,0,live+sync,warm,zakura_inv,0.214,179.578,0.001,6.593,,True
3532907,00000000004a1dab,219,217,live+sync,warm,zakura_inv,1.549,157.855,,6.593,,True
3532908,0000000000254572,221,218,live+sync,warm,zakura_inv,2.905,199.829,0.043,7.181,,True
3532909,00000000001e377e,221,217,live+sync,warm,zakura_inv,1.923,124.148,0.035,7.181,,True
3532910,00000000005aee8b,220,217,live+sync,warm,zakura_inv,0.980,100.726,0.036,5.700,,True
3532911,0000000000202a21,222,217,transition,warm,zakura_inv,0.978,549.402,0.052,,,True
3532912,0000000000597c4f,3,2,transition,warm,zakura_inv,0.234,490.652,0.006,,,True
3532913,0000000000097636,1,0,transition,warm,zakura_inv,0.201,475.620,0.001,,,True
3532914,000000000025ee9a,1,0,transition,warm,zakura_inv,0.147,469.136,0.001,,,True
3532915,000000000035dd53,118,112,transition,warm,commit_bound,0.000,397.001,,,,True
3532916,0000000000582b44,1,0,transition,warm,zakura_inv,0.275,392.205,0.001,,,True
3532917,00000000004e74b7,2,0,transition,warm,commit_bound,0.000,383.618,,,,True
3532918,0000000000420a15,26,17,fasttip,warm,zakura_inv,0.256,9.443,0.011,2.697,6.698,True
3532919,00000000002d8da2,2,0,fasttip,warm,zakura_inv,0.147,80.186,0.004,0.057,80.090,True
3532920,00000000004b07a3,8,2,fasttip,warm,zakura_inv,0.229,22.464,0.005,0.098,22.320,True
3532921,000000000023329f,5,2,fasttip,warm,zakura_inv,0.349,14.077,0.004,0.083,13.944,True
3532922,00000000005fd083,18,6,fasttip,warm,zakura_inv,0.217,17.731,0.005,0.127,17.554,True
3532923,00000000004f558f,2,1,fasttip,warm,zakura_inv,0.210,75.595,0.001,0.073,75.470,True
3532924,0000000000310d43,2,0,fasttip,warm,commit_bound,0.000,73.426,,0.131,73.264,True
3532925,000000000045c491,6,2,fasttip,warm,zakura_inv,0.260,4.198,0.002,0.100,4.049,True
3532926,00000000003e0c84,7,2,fasttip,warm,zakura_inv,0.286,87.572,0.011,0.127,87.404,True
3532927,00000000001922f0,2,1,fasttip,warm,zakura_inv,0.201,65.403,0.004,0.096,65.262,True
3532928,00000000005e11b1,3,1,fasttip,warm,zakura_inv,0.215,25.742,0.002,0.109,25.590,True
3532929,00000000006472fb,1,0,fasttip,warm,zakura_inv,0.209,2.917,0.001,0.055,2.809,True
3532930,0000000000164280,5,1,fasttip,warm,zakura_inv,0.159,93.425,0.002,0.058,93.323,True
3532931,000000000022a21a,3,0,fasttip,warm,zakura_inv,0.144,57.951,0.003,0.034,57.872,True
3532932,0000000000559b3e,7,1,fasttip,warm,zakura_inv,0.293,13.229,0.001,0.058,13.129,True
3532933,000000000064afde,8,2,fasttip,warm,zakura_inv,0.329,70.451,0.011,0.122,70.279,True
3532934,00000000004beabd,13,5,fasttip,warm,zakura_inv,0.589,23.862,0.005,0.363,23.456,True
3532935,00000000003006b6,10,4,fasttip,warm,zakura_inv,0.276,38.356,0.003,0.127,38.185,True
3532936,0000000000238d18,7,0,fasttip,warm,zakura_inv,0.366,15.591,0.004,0.251,15.286,True
3532937,00000000004a06de,5,0,fasttip,warm,zakura_inv,0.216,20.229,0.005,0.202,19.994,True
3532938,000000000020a08f,1,0,fasttip,warm,zakura_inv,0.210,6.574,0.001,0.034,6.497,True
3532939,00000000000c55fc,1,0,fasttip,warm,zakura_inv,0.213,0.895,0.001,0.036,0.821,True
3532940,00000000004599d3,21,8,fasttip,warm,zakura_inv,0.306,46.449,0.014,0.284,46.119,True
3532941,0000000000148255,15,5,fasttip,warm,zakura_inv,0.269,29.136,0.006,0.227,28.864,True
3532942,0000000000505d87,3,1,fasttip,warm,zakura_inv,0.357,12.385,0.007,0.154,12.190,True
3532943,0000000000616cc5,13,3,fasttip,warm,zakura_inv,0.394,60.217,,0.269,59.902,True
3532944,00000000002d9ac8,6,0,fasttip,warm,zakura_inv,0.217,27.375,0.003,0.194,27.139,True
3532945,000000000048cae4,7,1,fasttip,warm,zakura_inv,133.532,31.997,,0.097,31.830,True
3532946,00000000001711e9,7,2,fasttip,warm,zakura_inv,0.278,890.457,0.003,,,True
3532947,00000000001bbb37,13,3,fasttip,warm,zakura_inv,0.263,675.211,0.006,,,True
3532948,0000000000419a05,1,0,fasttip,warm,zakura_inv,0.205,666.974,0.001,,,True
3532949,00000000004f8d7c,1,0,fasttip,warm,zakura_inv,0.141,660.877,0.002,,,True
3532950,000000000056c8e8,17,6,fasttip,warm,zakura_inv,0.238,420.468,0.003,,,True
3532951,000000000046d024,4,2,fasttip,warm,zakura_inv,0.370,334.181,0.002,,,True
3532952,0000000000681f6b,8,3,fasttip,warm,zakura_inv,0.213,226.452,0.006,,,True
3532953,00000000004470db,6,3,fasttip,warm,zakura_inv,0.224,198.148,0.004,,,True
3532954,0000000000542bec,5,2,fasttip,warm,commit_bound,0.000,191.040,,,,True
3532955,00000000002fa79c,1,0,fasttip,warm,zakura_inv,0.223,141.677,0.001,,,True
3532956,000000000038055b,1,1,fasttip,warm,zakura_inv,0.224,120.532,0.004,,,True
3532957,0000000000600f9f,7,1,fasttip,warm,zakura_inv,0.250,104.048,0.002,,,True
3532958,000000000043dc0c,9,2,fasttip,warm,zakura_inv,0.579,0.391,0.006,0.078,0.271,True
3532959,000000000056acf5,1,0,fasttip,warm,zakura_inv,0.212,0.296,0.001,0.036,0.222,True
3532960,0000000000218c79,12,4,fasttip,warm,zakura_inv,0.309,0.414,,0.150,0.223,True
3532961,000000000048e8a9,7,1,fasttip,warm,zakura_inv,0.221,0.420,0.002,0.154,0.227,True
3532962,00000000003b0d1b,20,10,fasttip,warm,zakura_inv,0.282,0.508,0.007,0.168,0.287,True
3532963,00000000000db04e,1,0,fasttip,warm,zakura_inv,0.208,0.303,0.001,0.043,0.216,True
3532964,000000000063f80e,7,4,fasttip,warm,zakura_inv,0.270,0.280,0.005,0.083,0.150,True
3532965,00000000004bacf1,8,3,fasttip,down,zebend_inv,121.811,0.142,,0.101,0.000,True
3532966,00000000005ef45f,4,0,fasttip,down,zebend_inv,132.630,0.100,,0.056,0.000,True
3532967,0000000000011f59,14,6,fasttip,down,zebend_inv,2.146,0.111,,0.071,0.000,True
3532968,0000000000520ca3,2,0,fasttip,down,observer,0.701,280.603,,0.050,280.312,True
3532969,000000000014a9c1,5,1,fasttip,down,zakura_inv,0.225,215.024,0.003,214.766,0.219,True
3532970,0000000000618da3,9,3,fasttip,cold,zakura_inv,0.240,37.406,0.004,0.050,36.892,True
3532971,0000000000234f38,17,10,fasttip,cold,zakura_inv,0.536,0.464,0.006,0.119,0.002,True
3532972,000000000013a460,2,0,fasttip,cold,zebend_inv,0.207,0.343,0.001,0.143,0.000,True
3532973,000000000052dc1a,8,4,fasttip,cold,zebend_inv,0.215,0.300,0.005,0.090,0.000,True
3532974,0000000000164bf6,1,0,fasttip,cold,zebend_inv,0.461,0.512,0.001,0.054,0.000,True
3532975,00000000005ecf71,8,3,fasttip,cold,zebend_inv,2.681,0.288,,0.065,0.000,True
3532976,00000000004b5daf,4,2,fasttip,cold,zebend_inv,0.223,0.283,0.003,0.071,0.000,True
3532977,00000000000b69ca,8,5,fasttip,cold,zebend_inv,0.238,0.446,0.006,0.219,0.000,True
3532978,00000000000f52ca,3,1,fasttip,cold,zakura_inv,0.507,0.351,0.005,0.097,0.039,True
3532979,000000000062262b,1,0,fasttip,cold,zebend_inv,0.212,0.238,0.001,0.032,0.000,True
3532980,00000000001c934a,3,0,fasttip,cold,zakura_inv,0.262,2.379,0.001,0.035,2.073,True
3532981,00000000005675ce,1,0,fasttip,cold,zebend_inv,0.226,0.258,0.001,0.032,0.000,True
3532982,0000000000333f01,1,0,fasttip,cold,zebend_inv,0.429,0.461,0.001,0.035,0.000,True
3532983,000000000001cd8b,6,1,fasttip,cold,zakura_inv,0.274,0.655,0.006,0.132,0.128,True
3532984,00000000002ffa6a,1,0,fasttip,cold,zakura_inv,0.260,1.277,0.001,0.030,1.193,True
3532985,000000000065b72a,7,4,fasttip,cold,zebend_inv,0.294,0.286,0.004,0.076,0.000,True
3532986,00000000003a9056,3,1,fasttip,cold,zebend_inv,0.411,0.448,0.003,0.040,0.000,True
3532987,00000000003d204a,1,0,fasttip,cold,zebend_inv,0.310,0.347,0.001,0.040,0.000,True
3532988,00000000001802f7,6,1,fasttip,cold,zakura_inv,0.192,0.378,0.003,0.073,0.258,True
3532989,0000000000414d17,2,0,fasttip,cold,zebend_inv,0.225,0.261,0.002,0.048,0.000,True
3532990,0000000000505044,4,0,fasttip,cold,zebend_inv,0.765,0.254,0.001,0.042,0.000,True
3532991,00000000006f3682,13,3,fasttip,cold,zakura_inv,0.226,0.447,0.011,0.015,0.170,True
3532992,0000000000304843,4,1,fasttip,cold,zakura_inv,0.213,3.494,0.003,0.038,2.989,True
3532993,00000000004d6fc6,13,6,fasttip,cold,zakura_inv,0.432,0.368,0.009,0.144,0.005,True
3532994,000000000033c38d,12,9,fasttip,cold,zebend_inv,0.519,0.414,0.006,0.194,0.000,True
3532995,00000000005e5134,6,2,fasttip,cold,zakura_inv,0.144,0.360,0.003,0.059,0.199,True
3532996,000000000051a68a,3,1,fasttip,cold,zebend_inv,0.219,0.267,0.002,0.054,0.000,True
3532997,00000000002daf1b,1,0,fasttip,cold,zakura_inv,0.267,3.836,0.000,0.014,3.432,True
3532998,000000000056b4b2,13,5,fasttip,cold,zebend_inv,0.549,0.374,,0.094,0.000,True
3532999,00000000000f82dc,5,0,fasttip,cold,zebend_inv,0.217,0.252,0.001,0.041,0.000,True
3533000,00000000005e4103,6,2,fasttip,cold,zakura_inv,0.266,0.370,0.003,0.022,0.127,True
3533001,00000000005a9bfd,17,4,fasttip,cold,zakura_inv,0.271,0.436,0.013,0.158,0.064,True
3533002,0000000000049a97,6,4,fasttip,cold,zebend_inv,0.243,0.325,0.004,0.090,0.000,True
3533003,00000000001d7309,1,0,fasttip,cold,zebend_inv,0.241,0.297,0.001,0.060,0.000,True
3533004,000000000037e78e,9,6,fasttip,cold,zebend_inv,0.701,0.560,0.005,0.078,0.000,True
3533005,0000000000464ded,5,2,fasttip,cold,zebend_inv,0.215,0.275,0.004,0.066,0.000,True
3533006,00000000001a14c5,13,6,fasttip,cold,zebend_inv,0.445,0.308,0.004,0.078,0.000,True
```
