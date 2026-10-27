# perf4: faster Halo 2 (Orchard/Ironwood) verification in Bend

A drop-in successor to `research/perf3/v64` (the verifier the node runs as
`node/follow/bin/halo2_batch` and through the orchard hook). Same inputs, same output lines,
same verdicts. All Bend: no C post-processing and no Rust in the verifier. It builds with the
fork's `zebend` integration worktree (`bend-fork-zebend`, ≥ 3fbef653, for `File.read_words`).
See `DEPLOY.md` for the swap.

## Results

M5 Max (6 P + 12 E cores). The machine was shared and heavily loaded for the whole session:
load average 10–110 from other agents' rustc/bun builds. Every comparison below was measured
back to back in one session (`t/final_bench.py`, then `t/tput.sh`; logs in `t/final_bench.log`),
and the load is given with each table. "before" = `research/perf3/v64` (its `batch_main` is
byte-identical to `node/follow/bin/halo2_batch`); "after" = this directory, final binaries;
Rust = `halo2_proofs` 0.4 / `orchard` (`zcash/halo2/lib/perf bench-verify`;
`research/proofsets/oracle rust-batch`, a par_chunks(64) BatchVerifier, the setup behind the
brief's 1,068/s).

**Throughput (sync case)**

| Workload | before | after | Rust | after ÷ before | after ÷ Rust |
|---|---|---|---|---|---|
| 10,048-bundle sample, 18T, batches of 3,840, run 1 (load 18→22) | 591/s | **2,028/s** | 821/s | 3.4× | 2.5× |
| same, run 2 (load 22→25) | 527/s | **1,251/s** | 700/s | 2.4× | 1.8× |
| 256 bundles, 1 thread (load 18.5) | 87/s | **176/s** | 94/s | 2.0× | 1.9× |
| **All 392,806 bundles**, 18T, batches of 3,840 | 793/s (brief) | **2,225/s** (176.5 s, load ~20, 0 disagreements) | 709/s (554 s, load 29→42, run on its own minutes earlier); 1,068/s in the brief's session | 2.8× | 2.1× vs the brief's 1,068/s |

An earlier session (load 13–33, a build without the gate CSE) gave the same picture on the
sample: before 465/456, after 1,270/1,284, Rust 459/383 bundles/s. Rust's numbers swing with
the load more than Bend's do (1,068/s in the brief, 383–821/s here). Bend scales worse across
cores, so a busy machine costs it less. after ÷ before is the robust figure; after ÷ Rust on an
idle machine will be lower than in this table.

**Latency (tip case)** (load 18–19; the earlier session, load 13.5, gave the numbers in brackets)

| Workload | before | after | Rust |
|---|---|---|---|
| one 2-action proof, in-process, 1 thread (ms) | 29 [28] | 27 [27] | 21.3 [20.7] |
| one 2-action proof, in-process, 18 threads (ms) | 9 [9] | 8 [7] | 3.2 [3.1] |
| `halo2_batch` process wall time, 1 bundle, 18T (ms) | 16.3 [12.6] | 15.9 [11.2] | — |
| `halo2_batch` process wall time, 10 bundles, 18T (ms) | 19.1 [19.3] | 17.9 [18.1] | — |

Latency improved only 3–15%. A single proof is ~80% one 2,048-term MSM, and that MSM is
now the whole gap to Rust; see "What did not work".

## What changed, lever by lever

| # | Lever | Effect (measured) | Exactness |
|---|---|---|---|
| A | **Fixed bases merged across the batch.** The 46 VK fixed/permutation commitments, W and U were per-proof MSM terms. Now, like G, they carry one summed scalar per batch (`vlib` `ms_fix`, `bt` `fx_dense`). | −37% merged-MSM terms for 2-action bundles | the same sum, regrouped |
| B | **Per-proof work in the parallel tree.** Parsing, weighting (r·scalars) and scalar encoding run inside each leaf. The tree's nodes concatenate list-of-lists and add the 2,094 G/fixed scalars, replacing the old serial K×2,048 `axpy`. | with A and a first chunking, K=1,024 18T: 4.36 → 2.71 s (load 34) | — |
| C | **Chunked final MSM.** About 2,048 terms per chunk, each a full msm9. Per-term cost grows 2.4× from n=2k to 65k in one chunk (list buckets fall out of cache). In the batch, chunks are groups of 20 proofs taken straight from the tree's list of per-proof lists, so the n terms are never flattened and re-split serially. | 262,144 terms, 18T: 1.15 → 0.32 s; 65,536 1T: 1.6–5.0 → 0.8–0.95 s. All equal `best_multiexp` | `msm_par.bend`; `t/msm_main` mode 5 = halo2 at 2k/20k/65k/262k |
| D | **Points decompressed ahead of the transcript**, all at once in a parallel map (`vlib` `pre_items`). Decompression was 19% of per-proof time, serially. | moves ~0.7 ms/proof off the serial chain | `IP` items carry exactly `VD.decompress(w)`; a mis-masked item falls back to decompress-on-read |
| E | **Fixed-base comb tables for the instance commitments** (G_lag_0..9, w = 8, built in Bend at start-up when K ≥ 16; `fixb.bend`) | per-proof work, 1T loop: 4.5 → 3.9 ms (load 46); table build 8 ms at 18T | complete RCB mixed addition, non-identity entries |
| F | **CSE / constant folding of the generated verifier** (`v/opt_gates.py`, item 5). The rewrites: list lookups hoisted; x·1, x·0, x+0 folded; a+(−b) → a−b; common subexpressions shared; dead code dropped. In the batch build the trace logging is also removed (logging is kept in `bundle_ba` for `-v`). 46 → 26 inversions via CSE, and 19 of those batched into 5 inversions. | per-proof 2.45 → 1.75 ms (2-action), 15.0 → 9.1 ms (16-action), 1T | 42/42 `-v` traces (2,516 intermediates each) byte-identical to perf3 |
| G | **I/O.** `params_g.bin` is read with `File.read_words`. Bundle files are read by 64-file groups on `IO.fork`ed actions (read was 0.3 ms/file serially). Batch weights r_i = BLAKE2b(256-bit OS seed ‖ i) truncated to 128 bits, instead of 4 `IO.random_u32` per bundle. | K=3,840: read 1,054 → 150 ms | weights stay unpredictable to the prover |
| H | **Lazy reduction in point add/double** (item 3, `vesta_lz.bend`: `add_nr` as one operand of a mul whose other operand is reduced; the fq64 bound) | 1,000 GLV scalar mults: 91 → 87 ms (−4%), same result. In the verifier: within noise | same group results; GLV/MSM differential tests pass |
| I | **Memory.** Per-proof logs dropped (F) and fixed terms merged (A). | max RSS: 512 bundles 603 → 163 MB; 3,840 bundles 3.7 GB → 620 MB | — |

### What did not work, or was not done

- **Fixed-base table for the 2,048 IPA generators (item 1).** It is implemented and works:
  `lib/gtab.bend`, `v/gtab_gen` writes a 3.8 MB table (2^(9j)·G_i, Bend-computed),
  `File.read_words` loads it, and it is checked against params at load (header, all 2,048
  window-0 entries, 32 random window steps). It equals `best_multiexp` (`t/gtab_test`, 10/10
  runs), and `batch_main` uses it when `<params>.gtab` exists (`gtab 1` in the output).
  **It does not pay:** 18T MSM n=2048 5.2–7.3 ms vs msm9's 5–8 ms; batch latency is within
  noise (1 bundle 14.4 vs 13.5 ms; 10 bundles 31.7 vs 27.0 ms, table slower). The table only
  removes the per-window bucket reductions (~15k of ~74k additions). Each bucket task must keep
  ~2k terms to stay in cache, so most of the saving goes into per-task reductions. The table
  file is therefore **not recommended for deployment**; without it `batch_main` prints
  `gtab 0` and takes the msm path.
- **Special-form reduction for p = 2^254 + c (item 2): not implemented, not measured.** By
  count it cannot win here. The 64-bit-limb Montgomery multiply (fq64/fp64) already uses the
  sparse modulus (limbs p0, p1, 0, 2^62): the reduction is 12 limb products (4 for m, 8 for
  m·p), 28 with the 16 of the schoolbook. Folding 2^256 ≡ −4c needs 4c·H (2×4 = 8 products)
  plus a second fold of the 128-bit overflow (~4): also ~28. On top come signed corrections
  and an extra carry chain. `crypto/field3/README.md` reached the same conclusion for 32-bit
  limbs. I spent the time on the MSM instead (below). This is an estimate, not a measurement.
- **Flat-array bucket accumulation** (`lib/msm_fa.bend`, an experiment, unused). Buckets live
  in one flat `Array<U32>`; pending additions are batched with one inversion, and conflicting
  terms are deferred. It is exact (equals `best_multiexp` at 2,048 and 20,000) but slower:
  33 vs 24 ms at n=2,048, and much slower at 20,000. Every pass gives a bucket at most one
  addition, so terms are revisited about bucket-load times. That is perf3's `msm_arr` finding
  again; flat arrays make the accesses cheap but do not fix the pass count.
- **GPU round 2 (item 6):** not resumed.
- **Latency vs Rust at 18 threads.** The single-proof 2,048-term MSM scales only ~4–5× on 18
  threads (22 ms → 4–6 ms), and Rust's `best_multiexp` takes 1.3 ms. Finer tasks did not
  help (chunks 1/2/4 × c 8/9 all 4–5 ms). Using only the 6 P-cores did not help either. Bend
  deals forks statically, and on 6 P + 12 E cores the E-core tasks set the makespan. Closing
  this needs runtime work (work stealing) in the fork, which was out of scope.

## Exactness evidence (final binaries)

`t/verify_all.sh` (log: `t/verify_all.log`):

| Check | Result |
|---|---|
| `batch_main`, 42-bundle set: 21 honest in one batch → 1; each of 21 tampered bundles inserted into the honest batch → 0; each bundle alone agrees with halo2 (`t/check_batch.py`), without and with the `.gtab` table | PASS, PASS |
| `bundle_ba` (single verifier, → `halo2_one`) vs halo2 (`run_bundles.py`): post-NU6.3, NU6.2, pre-NU6.2 sets | 42/42, 10/10, 8/8 |
| `-v` traces vs the deployed perf3 `bundle_ba`, every bundle of the 42-set | 42/42 byte-identical |
| MSM (`msm_auto`) vs halo2 `best_multiexp`, random bases/scalars, n = 2,048 / 20,000 / 65,536 (1T and 18T) / 262,144 (18T); msm9; fixed-base table | all MATCH |
| 10,048-bundle sample, every verdict vs official (`t/full.py`) | 10,048/10,048 agree, every batch `verified K == K` |
| All 392,806 bundles (`t/full.py`, 103 batches of ≤ 3,840), final `batch_main` | **392,806/392,806 agree, 0 disagree**, 0 batches rejected (`t/full_final.log`; verdicts in `t/full_batch_final_392806.txt`). An earlier build with the `.gtab` table: also 392,806/392,806 |

The batch driver keeps the 9c0b0ec guard: the verdict requires `verified K == K` and no
unreadable bundle. Bundles that run out of tree fuel count as missing.

## Files

| Path | What |
|---|---|
| `v/batch_main.bend` | batch verifier (→ `halo2_batch`); `v/bt.bend` batch accumulator; `v/pio.bend` flat-array I/O |
| `v/orchard_bt.bend` | generated batch verifier after `opt_gates.py` (source before optimisation: `orchard_bt.pre_opt.bend`) |
| `v/bundle_ba*.bend`, `v/orchard_ba*.bend` | single verifier (→ `halo2_one`) and the NU6.2 / pre-NU6.2 variants (`gen_variants.py`) |
| `v/vlib.bend` | verifier runtime: transcript, pre-decompression, fixed-base terms, batched inversions |
| `v/opt_gates.py` | source-level CSE / folding / inversion batching of the generated code |
| `v/gtab_gen.bend`, `lib/gtab.bend` | optional fixed-base G table (not recommended, see above) |
| `lib/msm_ba.bend` | perf3's batch-affine MSM (now on the lazy curve ops) |
| `lib/msm_par.bend` | chunked MSM (`msm_auto`) |
| `lib/fixb.bend` | comb tables for the instance commitments |
| `lib/vesta_lz.bend`, `lib/glv_vesta_lz.bend` | lazy-reduction curve ops / GLV |
| `lib/msm_fa.bend` | flat-array bucket experiment (unused) |
| `v/loop_ba`, `v/loop_bt`, `v/loop_batch` | in-process timing loops (single verify; per-proof batch work; whole batch) |
| `t/` | `check_batch.py`, `verify_all.sh`, `full.py`, `tput.sh`, `final_bench.py`, `lat.py`, `bb.sh`, `msm_main`, `gtab_test`, `smul_cmp`, `wlprof.py` (attributes `sample` profiles to Bend defs) |

## Reproduce

```sh
cd research/perf4                      # on the Mac; builds go through tools/heavy.sh
./build.sh v/batch_main.bend v/batch_main          # ~8 GB peak in bun; HEAVY_MAX_GB=8
./build.sh v/bundle_ba.bend v/bundle_ba            # likewise _nu62, _prenu62
t/verify_all.sh                                    # exactness checks
python3 t/final_bench.py; REPS=2 t/tput.sh         # before/after/Rust, same session
```

`research/proofsets/oracle/target/release/proofsets-oracle` (the Rust BatchVerifier baseline) was
rebuilt in place (`cargo build --release --offline`): the old binary had the pre-reorganisation
data path (`bend-zcash/proofsets/data`) compiled in.

Regenerating the optimised verifier: `python3 v/opt_gates.py v/orchard_bt.pre_opt.bend
v/orchard_bt.bend` and `python3 v/opt_gates.py v/orchard_ba.pre_opt.bend v/orchard_ba.bend
--keep-logs`, then `python3 v/gen_variants.py`.

Profile notes (1 thread, `t/wlprof.py`). Per-proof batch work before F: generated
straight-line code 34%, decompression 19%, runtime free/refcount 16–20%, instance tables 8%,
transcript byte lists ~9%. A single proof is ~75% MSM bucket accumulation
(`rounds` + `rbucket` + window fill), of which ~22% is runtime frees.
