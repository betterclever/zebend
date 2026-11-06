# perf5: Halo 2 batch verification, second optimisation pass

The successor to `research/perf4`, written after the 29 Oct correction: Zakura Common's crates verify
the 10,048-bundle sample 4.6× faster than perf4 did. perf5 closes part of that gap; Zakura is still
ahead. Same inputs, output lines and verdicts as perf4. All Bend: no C post-processing and no Rust in
the verifier.

**Not deployed.** The node still runs the perf4 build (`node/follow/bin/halo2_batch` is
byte-identical to `research/perf4/v/batch_main`). `DEPLOY.md` (written for perf4) describes the
swap; the same steps apply with this directory.

## Results

Apple M5 Max (6 P + 12 E cores), 10,048 mainnet bundles, every build run interleaved in the same
session (`t/tput.sh`, `research/bench/zakura-common/timing/`).

| Build | 18 threads | 1 thread (1,024 bundles) | Session |
|---|---|---|---|
| Upstream Rust crates (`halo2_proofs` 0.4) | 823–846/s | | 29 Oct, load ~4 |
| perf4 (as published in `docs/performance.md`) | 2,408–2,520/s | | 29 Oct, load ~4 |
| **perf5**, mac64 field code | **4,413–4,459/s** | 313–343/s | 29 Oct, load ~4 |
| Zakura Common (`zakura-halo2-proofs`) | 11,514–11,546/s | 942–957/s | 29 Oct, load ~4 |
| perf5, mac64 field code | 4,963–5,439/s | 360–394/s | 30 Oct, load 12–14 |
| **perf5 + `U32.mont64`** | **5,784–6,361/s** | **418–477/s** | 30 Oct, load 12–14 |
| Zakura Common | 10,099–11,954/s | 952–1,023/s | 30 Oct, load 12–14 |

Against perf4, perf5 is about 1.8× faster; `U32.mont64` adds about 1.17×. Zakura is still about
1.8× faster at 18 threads and 2.2× at 1 thread. Logs: `halo2-headtohead-perf5-*.log`,
`halo2-headtohead-perf5b-*.log`, `halo2-headtohead-mont64-*.log`.

## What changed

| Step | Change | Measured effect |
|---|---|---|
| 1 | **Instance commitments:** the fixed-base comb tables are one flat array read by index (`lib/fixb.bend`), the anchor row is computed once per bundle, 0/1 flag rows cost nothing, and results are normalised together | about 3% from sharing; the flat table cut the stage from ~25% to ~16% of proof time |
| 2 | **Transcript:** points and scalars go into BLAKE2b as 64-bit words, not byte lists (`v/vlib.bend`) | merged with step 5, below |
| 5 | **Final MSM:** signed-digit buckets on flat arrays with shared inversions (`lib/msm_sb.bend`) | final MSM 2.12 → 0.67 ms per bundle at 1 thread; steps 1+2+5 together 1,761–1,918 → 3,183–3,217 bundles/s (load ~19) |
| 6 | **Two-lane point decompression:** `lib/gen_fq2.py` writes `lib/fq2.bend`, which decompresses two points side by side so their dependent squaring chains overlap | 14–49% at 18 threads, ~16% at 1 thread over steps 1–5 |
| 7 | **`U32.mont64`:** each Pasta multiply is one 4×64-bit CIOS Montgomery product, a new primitive in Zebend's Bend fork (`crypto/field3/gen_field64.py`) | 281 → 198 instructions per multiply; ~1.17× overall |

Step 3 (table square root) was already done before perf5; step 4 (gate code) did not give a
measurable gain on its own. Tried and dropped: a 64-bit final subtraction (2–3%, within noise), a
128-bit accumulate in the multiply (no change), wider table windows (no better).

## Exactness

| Check | Result |
|---|---|
| `t/check_batch.py`: honest batch accepted, each tampered bundle rejected, each bundle alone agrees with halo2 (with and without the `.gtab` table) | PASS |
| Single verifiers vs halo2 (post-NU6.3, NU6.2, pre-NU6.2 sets) | 42/42, 10/10, 8/8 |
| All 42 `-v` traces vs the deployed verifier | byte-identical |
| MSM vs halo2 `best_multiexp` at every size | MATCH |
| `t/dec2_test.bend`: two-lane decompression vs the original, 81 edge-case pairs and 2^18 random encodings | 0 mismatches |
| `U32.mont64` vs Bend's previous multiply, 200,000 cases per input class | 0 mismatches |
| All 392,806 mainnet bundles, perf5 (`t/full_batch_main_392806.txt`) and perf5 + mont64 (`t/full_bm_mont2_392806.txt`) | **392,806/392,806 agree**, 0 disagree |

The optimised gate and MSM functions are also covered by the laws in `proofs/opt_gates`,
`proofs/msm_chunk` and `proofs/msm_bucket`.

## Build

The committed field code (`crypto/field3/fp64.bend`, `fq64.bend`, `lib/fq2.bend`) uses `U32.mac64`
and builds with the fork's `zebend` branch. `U32.mont64` is not in upstream Bend; for the faster
build, regenerate the field code with it and build with the fork's `mont64` branch (not yet
published, see `docs/bend.md`):

```sh
FIELD_MUL=mont64 python3 crypto/field3/gen_field64.py   # mul / sqr_d as U32.mont64
python3 research/perf5/lib/gen_fq2.py                   # fq2.bend follows fq64.bend
cd research/perf5
BEND_FORK=/path/to/bend-fork-mont ./build.sh v/batch_main.bend v/batch_main
t/verify_all.sh                                         # exactness checks
python3 t/full.py                                       # all 392,806 bundles (needs research/proofsets data)
```

Files are laid out as in `research/perf4` (see its README); new here: `lib/msm_sb.bend`,
`lib/fq2.bend` + `lib/gen_fq2.py`, `t/dec2_test.bend`, `t/micro/` (field micro-benchmarks),
`t/b5.py`, `t/stage.py` (per-stage timer), `t/mkph.py`.
