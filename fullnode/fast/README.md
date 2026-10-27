# fullnode/fast: faster, cheaper genesis sync (drop-in for sync.py / bin/blockdelta / bin/rules)

**Status (Oct 27, 18:25): ready to deploy, not deployed.** Nothing under `fullnode/` outside
`fast/` was edited or rebuilt; no live process was touched. Every number below is measured on
bench copies (APFS clones) with the load average noted; other agents' jobs kept the Mac at load
20–45 the whole time, so wall-clock numbers are noisy and CPU-seconds are the better metric.

## Result

Spam era, 1,800,000–1,802,999 (3,000 blocks, 1,202.9 MB), whole pipeline (`sync.py --keep-spool
--to 1802999` on a clone of the 1,799,999 bench state, CPU of the whole process tree from
`/usr/bin/time -l`: sync, writer, every Bend child):

| Code | Wall | MB/s | blocks/s | CPU-s | **CPU-s / MB** | Peak RSS (largest process) | GPU | Load (1-min, start) |
|---|---|---|---|---|---|---|---|---|
| live code (`fast/base`, run 1) | 144.5 s | 8.33 | 20.8 | 824.7 | 0.686 | 795 MB | 0 | 31 |
| live code (run 2, same session as the last row) | 140.1 s | 8.60 | 21.4 | 900.2 | 0.748 | 808 MB | 0 | 20 → 42 |
| fast (final binaries, run 1) | 54.8 s* | 22.16 | 55.3 | 363.7 | 0.302 | 793 MB | 0 | 23 |
| **fast (final binaries, run 2)** | **62.0 s** | **19.48** | **48.6** | **379.4** | **0.315** | 719 MB | 0 | 26 → 46 |

\* run 1 used the previous blockdelta build (same output, ~2 s/window more Bend CPU).

So in the spam era: **2.2–2.4× fewer CPU-seconds per MB** (stretch target met) and **2.3–2.6×
the throughput at the same load**. Per 100 MB window the critical path is now blockdelta of the
next window (~27 CPU-s; "waited for bend" 2–3 s of a 3.5–4.5 s window); bin/rules went from
~30 CPU-s to ~2.7. At load 20–45 that is 19.5–22 MB/s, just under the downloader's 25 MB/s;
the CPU needed is ~0.3 s/MB × 25 MB/s ≈ 7.5 cores, so on a less loaded machine it keeps up.

Consolidation era, 324,127–328,000 (3,874 blocks, 492.2 MB), same harness on the 324,126 clone:

| Code | Wall | MB/s | CPU-s | CPU-s / MB | Peak RSS | Load |
|---|---|---|---|---|---|---|
| live code (2 runs) | 140.8 / 134.2 s | 3.50 / 3.67 | 409.7 / 397.4 | 0.832 / 0.807 | 3.6 GB (writer) | 16 / 19 |
| fast (2 runs) | 135.9 / 168.5 s | 3.62 / 2.93 | 336.8 / 341.2 | 0.684 / 0.693 | 3.7 GB (writer) | 22 / 25 |

Here the sync is bound by SQLite, not Bend: prevout lookups take 9–41 s per window and the
writer 12–32 s (cold pages of a 7 GB clone; they vary run to run by more than the whole Bend
time), so wall time does not move; CPU drops 14–17%. (The live node is past this era.)

## What changed, and why (profile first)

Profile of the old binaries on one ~100 MB window of each era (15 parts, run one at a time,
CPU-s summed; stages measured by building variants with the stage stubbed, same compiler):

| Stage (CPU-s per window) | blockdelta spam (113 MB) | blockdelta cons (101 MB) | bin/rules spam | bin/rules cons |
|---|---|---|---|---|
| total | 45.2 | 27.8 | 29.6 | 28.0 |
| node/wire gate: Jubjub/Pallas point decoding | **24.7** | ~0 | **~24.7** | ~0 |
| node/wire gate: the rest (structure, canonical scalars) | 2.7 | 2.0 | ~2.2 | ~5 |
| txid hashing (spam: ZIP 244 BLAKE2b; cons: SHA-256d) | 13.4 | 10.8 | — | — |
| output formatting | ~0.8 | 6.9 | — | — |
| parse + rules + rest | ~4 | ~8 | 2.7 | 22.9 |

(Variants: `bend/d_nohash`, `d_nov4hash`, `d_nogate`, `d_nofmt`, `d_nopts`, `rules/r_nogate`;
`bench/cpu.py`.) Two thirds of all spam-era CPU was the same Sapling `cv`/`rk` points being
decompressed twice, once by blockdelta's wire gate and once by bin/rules' copy of it, each
decode costing an inversion plus a constant-time Tonelli-Shanks square root in 16-bit limbs
(~250 µs). Python (parse_delta 0.04 s/window in spam) and Bend process start-up were not
significant. `+RTS --threads 1` made no difference (the binaries run one thread already).

1. **bin/rules does not re-run the wire gate** (`rules.bend`: new flag `--gated`; `rules.py`
   passes it when every block of the part was accepted by blockdelta's gate, which is always
   the case: `checkpoint_checks` raises on `block <h> INVALID wire` before rules run, and the
   bytes are the same `recs`). Without the flag bin/rules behaves exactly as before, so its
   tests, hooks harness and `ZEBEND_RULES_BIN` users are unaffected; an old binary ignores the
   flag. Spam: 29.6 → 2.7 CPU-s per window.
2. **Point decoding deferred and batched, without square roots** (`wire/txv.bend`,
   `bend/pts.bend`). `wire/txv.bend` is node/wire's validator with `jpoint`/`ppoint` only
   consuming their 32 bytes; `pts.bend` lists the same fields (Sapling v4/v5 spend `cv`, `rk`,
   output `cv`; Orchard/Ironwood action `cv`, `rk`, `epk`) for each block the structural gate
   accepted, and blockdelta prints `block <h> INVALID wire` if any fails: since a point check
   never moves the cursor, (structure OK) ∧ (all points OK) is exactly node/wire's verdict.
   The check itself decides existence, not the point: Jubjub `u² = (v²−1)/(1+d v²)` is a square
   iff `num·den` is (Euler's criterion `x^((r−1)/2)`, from the existing `pow_c3` addition
   chain plus 31 squarings), with ZIP 216 (`u = 0`, sign 1) and small order (`x = 0`, `v = 0`
   or `num + v²·den = 0`) decided from the same values; Pallas: `x = 0` (identity iff sign 0)
   or `x³ + 5` a square. No inversion, no Tonelli-Shanks. ~4× cheaper per point.
3. **SHA-256 and ZIP 244 copy each byte once** (`bend/sha.bend`, `bend/zip244.bend`): words
   of a SHA block read in one pass (node/block's code re-dropped from the block start for each
   word: 480 list steps per 64 bytes), round constants built once per message, the padded
   message one copy (`take_onto`) instead of `take` + `append`; ZIP 244's
   `cat(at(xs, p, n), rest)` (two copies) → `onto(xs, p, n, rest)` (one). Cons: blockdelta
   26.7 → 19.0 CPU-s per window; spam 29.2 → 27.1.
4. **bin/rules parts get their own thread pool** in `sync.py`, so they no longer queue
   behind the next window's 15 blockdelta parts (that wait was 2 s of a 4.3 s spam window).

After: blockdelta spam 45.2 → 27.1, cons 27.8 → 19.0 CPU-s per window; bin/rules spam
29.6 → 2.7, cons 28.0 → 23.2.

## GPU: measured, does not pay here

The point batch is a balanced tree of independent field computations, the most GPU-shaped
work in the pipeline, so it was tried first. `bend/gpu_variant.py` writes `delta_gpu.bend`
(the batch under `check!`). Built with stock Bend 2.0.38 (non-inlined Metal, so not
shippable under the Metal rules; for timing only), whole 113 MB spam window in one process,
~100k points:

| Point check of ~100k points | Time |
|---|---|
| CPU, 1 thread, decoding as node/wire (inversion + Tonelli-Shanks) | ~25 s (≈ 4k points/s) |
| Metal GPU, same code, depth 11–14 trees | ≈ 12.6 s wall (≈ 8k points/s) |
| CPU, 1 thread, square-root-free check (shipped) | ≈ 4.3 s (≈ 23k points/s) |
| Metal GPU, square-root-free check | ≈ 8.6 s wall (≈ 12k points/s) |

The GPU ran slower than one CPU core on the shipped predicate (heap-allocated 16-limb field
elements, refcounted list traversal). scan2 measured that the always-inline fork build (the
only one allowed to ship) is a further ~2.3× slower on Metal, so it was not built or gated.
Hashing (txids, ZIP 244, merkle) is list walking over cons cells, which suits the GPU even
less. So the deployed binaries contain no `!` and no `.gpu` program; nothing needs the Metal
gate. What would make the GPU win: 64-bit-limb fields (field3's `U32.mac64`, fork-only) and
array-based block bytes, i.e. a different data representation, not a different kernel.

## Exactness (all on copies)

- **Bin outputs, byte for byte**: new blockdelta = old blockdelta on all 30 bench parts (spam +
  cons), on the 94 test blocks of every era in `bend/data` (v1–v6, 539 Orchard/Ironwood
  actions), CPU and GPU variants; new `rules --gated` = old `rules` on all 30 parts; new
  `rules` without the flag = old `rules`.
- **Point predicate** (`bin/t_pts`, `bend/t_pts.bend`: node/wire's decoders vs the new check,
  point by point): 280,256 random and edge-case encodings (all four kinds; zero, ±1, m−1, m,
  m+1, non-canonical, both sign bits; 132,001 valid) → 0 mismatches; every point of the spam
  window (116,734) and of the 94 era blocks (7,206) → 0 mismatches.
- **Tamper** (`bench/tamper_pts.py`): 100 blocks with one Sapling/Orchard/Ironwood point
  overwritten by a random or edge-case encoding: old blockdelta, new (CPU) and new (GPU variant)
  print identical output in 100/100 (64 of them `INVALID wire`; 60 cases on the build before change 3, 40 on the final one).
- **State digest** (`work/bench/digest.py`: utxo, nf, tx, blk incl. per-block pools, anchor,
  undo, tip, pools, leaf lengths, audit count, leaf logs): identical to the live code on
  1,800,000–1,802,999, on 324,127–328,000 (pools tracked from genesis) and on 12,000–20,000.
  0 `AUDIT:` lines in every run.
- **`test_reorg.py 150`** (fast copy, uses `fast/sync.py`): PASS on the consolidation state
  (pools tracked) and on the spam state.
- **SIGKILL** (`bench/killtest.sh`, the fast copy of `work/bench/killtest.sh`): whole tree
  killed mid-window (6 processes), restart resumed at 13,500, state at 20,000 identical to the
  uninterrupted run, which is identical to the live code's run. PASS.
- **Deployed sources**: `bench/mirror_build.sh` builds the sources exactly as `deploy.sh`
  installs them (imports rewritten for `fullnode/`) and checks the binaries print the same.

## Deploy (controlled restart)

```sh
cd fullnode/fast
./deploy.sh check      # live files still equal what fast/ was cut from; changes nothing
./deploy.sh bins       # phase A, safe while running: bin/blockdelta and bin/rules replaced by
                       # cp to .new + mv (atomic); old files kept as *.pre-fast. Both are drop-ins
                       # for the CURRENT sync.py/rules.py (same CLI, identical output): the
                       # running instances pick them up at their next window and already get
                       # changes 2-3 (blockdelta about 1.7x cheaper in spam).
# at a window boundary: stop the genesis sync (SIGTERM: it exits after the window) and,
# when convenient, the tip instance; then
./deploy.sh py         # phase B: sync.py, rules.py (+ Bend sources for the record, *.pre-fast kept)
# restart both instances exactly as before (no new arguments)
./deploy.sh rollback   # if needed: restores every *.pre-fast file
```

Memory: blockdelta now holds a part's output until its point batch is checked: peak RSS per
process 101 MB (spam parts) and 218 MB (consolidation parts) against 91 / 122 MB before; with
16 parts in flight that is at most ~3.5 GB in consolidation-like windows.

`DEPLOY.diff` has every change (Python and Bend, against the live files and against
node/wire / node/block for the copied modules). `store.py` is unchanged.

Notes: the tip instance (`--assumed-start`, full validation) uses the same `sync.py`/
`rules.py`/binaries; its rules run `--gated` too (its blocks also come from blockdelta). Hooks
are untouched. New source files: `bend/pts.bend`, `bend/sha.bend`, `bend/t_pts.bend`,
`bend/gpu_variant.py`, `wire/blk.bend`, `wire/txv.bend` (fullnode-local copies; node/wire
itself is unchanged).

## Layout

- `sync.py`, `rules.py`, `store.py` (unchanged copy): the code to deploy. `state/hdr`,
  `checkpoints`, `hooks`, `headers.py`, `assumed.py` are symlinks so `fast/` runs as a node dir.
- `bend/`, `wire/`, `rules/rules.bend`: sources (imports one level deeper than in `fullnode/`).
  `bin/blockdelta`, `bin/rules`: the binaries to deploy; `bin/t_pts`: the point test; the
  `bin/d_*`, `bin/r_*` variants are the profiling builds.
- `orig/`: the live files fast/ was cut from (+ MD5SUMS). `base/`: the live code, runnable on
  bench state (the "before" rows).
- `bench/`: `mkparts.py` (cut a range into the live sync's parts), `cpu.py` (CPU/wall/RSS per
  binary over the parts + byte comparison), `e2e.sh` (whole pipeline on a clone, with digest),
  `gen_pts.py`, `tamper_pts.py`, `killtest.sh`, `mirror_build.sh`, `runs/` (logs, `/usr/bin/time`
  output and digests of every run in the tables). Bench base states: clones of
  `work/bench/sspam` and `s324` with `assumed_state` deleted and `addr` deferred (genesis mode,
  as the live genesis instance runs); recreate with `bench/mkbase.sh`
  (`bench/st/` was deleted after the runs to free the disk).

## Not done / next

- Spam-era Bend is now ~27 CPU-s per 100 MB window, of which ZIP 244 hashing ~11 s (mostly
  list traversal: `List.length` and word assembly in node/block's BLAKE2b, `List.drop` with
  Nat positions), points ~4 s, structural gate ~3 s.
- bin/rules still re-parses every transaction (`P.tx`) that blockdelta parsed; in the
  consolidation era that is most of its 23 CPU-s per window. Feeding rules a compact form from
  blockdelta would remove it.
- Consolidation-era wall time is SQLite: prevout lookups and the writer.
