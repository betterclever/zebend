# gpuv: Halo 2 batch verification with a Metal GPU MSM (Bend, M5 Max)

Measured on real mainnet Orchard/Ironwood bundles (proofsets) and compared with
Rust's halo2 `BatchVerifier`. Short version:
- the GPU MSM on its own is **3.6× faster** than Bend's CPU Pippenger on 18 threads;
- the whole batch verifier with the merged MSM on the GPU is **not faster** than
  Bend on 18 CPU threads, and not faster than Rust;
- all 392,806 bundles verify, and every verdict equals the official one, on both
  Bend paths.

## Bend fork changes (branch `metal-spill` in bend-fork, not pushed)

- `METAL_SPILL.md`: restores the Metal lane spill (revert of upstream #1809). Without
  it, 16,384 lanes with deep recursion crash with `memory fault`.
- `METAL_INLINE.md`: device code holds **no calls**. Every Metal helper is
  `always_inline`, as a defence against the Apple GPU-compiler call-frame corruption
  that the user found. The doc also covers two Apple compiler crashes that full
  inlining exposes, and the `extract_bits` workaround for them.

## What's here

| file | what |
|---|---|
| `v/msmg.bend` | GPU MSM. Leaves are (point, scalar); each lane does a double-and-add scalar mult using the complete addition law; then a balanced tree of additions. `sum!` runs it on Metal. |
| `v/bt.bend` | Batch checks (from perf3/v64). `batch` = CPU path (merge + `msm_ba.msm9` Pippenger). `prep` + `fin` = GPU path (CPU threads merge the proofs and build the MSM tree, then `sum!` sums it on the GPU). |
| `v/batch_g.bend`, `v/batch_cpu.bend` | Drivers: `<params_g.bin> <bundle.bin>...`, printing `verified K` and `batch K .. result 0/1`. They are identical except for the final MSM. |
| `v/msmbench.bend` | MSM micro-benchmark. Mode 1 = GPU, 2 = CPU Pippenger, 3 = CPU tree; it prints the result point so the modes can be compared. |
| `t/det.sh` | Determinism gate: N runs, outputs compared bit for bit. |
| `t/aircalls.sh` | Emits a program's Metal source, compiles it to AIR and counts non-intrinsic calls. Must be 0. |
| `t/full.py` | All proofsets bundles through a batch binary, with verdicts diffed against the official ones. |
| `t/bench.sh`, `t/small.sh`, `t/gate_batch.sh` | Benchmark and correctness harnesses. |
| `t/forktests.py` | The fork's `tests/compile` suite, built and run (GPU wherever a test uses `!`). |

## Results (M5 Max, 18 CPU threads, shared machine; every GPU number passed the gate)

Determinism gate (≥20 runs, compared bit for bit):
- GPU MSM: 20 runs each at 4,096, 65,536 and 262,144 terms gave 1 distinct output,
  equal to CPU Pippenger and to the CPU tree. At 262,144 terms, `BEND_CUBE_LOG=5` and
  `6` (5 runs each) gave the same output.
- GPU batch: 20/20 runs gave `result 1` on 1,024 real bundles, and 20/20 gave
  `result 0` with one tampered bundle.

**MSM alone** (`msmbench`, random scalars, wall time including input generation):

| terms | GPU (Metal) | CPU Pippenger (msm9, 18T) | CPU tree (18T) |
|---|---|---|---|
| 4,096 | 181 ms | 32 ms | 61 ms |
| 65,536 | 269 ms | 536 ms | 923 ms |
| 262,144 | **649 ms** | 2,358 ms | 3,655 ms |

**Batch verification on real bundles** (`bench.sh`: one batch over the first K bundles):

| K | Bend GPU MSM (batch_g) | Bend CPU (batch_cpu, 18T) |
|---|---|---|
| 1,024 | 1,630 ms (prep 816) | 1,396 ms |
| 3,840 | 5,247 ms (prep 2,650) | 4,886 ms |

At 3,840 bundles, the GPU step (shipping the 480k-leaf tree, then `sum!`) takes about
2.6 s. That is far more than the 262k-term micro-benchmark would predict, so the
host→GPU transfer of the tree, not the arithmetic, is the likely cost. Not profiled
further.

**10,048-bundle sample** (first 157 chunks; Bend in batches of 3,840; same session):

| | bundles/s | wall |
|---|---|---|
| Rust halo2 BatchVerifier, 18 threads | 712 | 14.1 s |
| Rust halo2 BatchVerifier, 1 thread | 64 | 156.4 s |
| Bend CPU (batch_cpu, 18T) | 769 | 13.1 s |
| Bend GPU MSM (batch_g) | 650 | 15.4 s |

**All 392,806 bundles** (6,144 chunks, 103 batches of ≤3,840):

| | bundles/s | wall | verdicts vs official |
|---|---|---|---|
| Rust halo2 BatchVerifier, 18 threads | 1,068 | 367.8 s | all ok |
| Bend CPU (batch_cpu, 18T) | 793 | 495 s | 392,806 / 392,806 agree |
| Bend GPU MSM (batch_g) | 398 | 987 s | 392,806 / 392,806 agree |

The full GPU run (398/s) was much slower than its own 10k sample (650/s). The machine
is shared (a follow daemon and other agents), and this was not repeated, so treat that
row as a lower bound.

## Findings to act on

1. **Soundness bug in `perf3/v64/batch_main`** (and every copy of its `par`).
   `par(12n, k, xs, gs)` drops every bundle past 2^12 = 4,096 when fuel runs out, yet
   it still prints `batch K <k> result 1`:
   - 4,200 real bundles plus 1 tampered → **result 1** (4,000 + 1 tampered → 0);
   - the earlier "Bend CPU 719 bundles/s on 10,048" number came from this truncated
     run and is invalid.

   The full proofsets run (`run_bend.py`, 64 per batch) is unaffected. `gpuv` fixes
   it with fuel 32n, plus a check that the verdict needs `verified K` = K. **perf3
   itself is not changed here.**
2. **GPU bangs only run on the GPU from the sequential top of an evaluation.** A `!` met
   inside a `par` region runs on the CPU pool (`corpus_eval` hands forked work to
   `cube_run(H, false)`). So the GPU MSM must be a separate IO step after the CPU
   phase (`prep` → print digest → `fin`). The first attempt silently ran the "GPU"
   MSM on the CPU.
3. Batches above about 4k bundles do not fit the 8 GB limit (CPU RSS) or the GPU span.
   3,840 per batch is used.
4. The GPU MSM wins on its own (3.6× at 262k terms). End to end it loses, because the
   CPU phase (transcripts, decompression, per-proof checks) dominates, and moving a
   big host tree to the device is expensive. The likely winning shape is the hybrid
   the signature work also points to: build MSM inputs on the GPU directly, and give
   the GPU the polynomial evaluation and the MSM, not just a final sum.

## Reproduce

    # on the Mac, from bend-zcash; everything heavy goes through heavy.sh
    export BEND_NO_TELEMETRY=1
    cd gpuv/v && ../../heavy.sh bun ../../../bend-fork/bend2/main.ts batch_g.bend -o batch_g
    gpuv/t/small.sh gpuv/v/batch_g                       # 21 bundles: result 1, then tampered → 0
    gpuv/t/gate_batch.sh 20                              # determinism gate
    RTS="+RTS --gpu 6GB" gpuv/t/bench.sh 3840 gpuv/v/batch_g gpuv/v/batch_cpu
    ./heavy.sh python3 gpuv/t/full.py gpuv/v/batch_g 60 +RTS --gpu 6GB
