# A growing lane moves a fork-free head behind its ring, so forks queued after it still grow

Branch `pr/sched-grow-rotate` (on origin/main, commit `aecf5615`). It changes `monk_step` in
comp.ts and adds the test `tests/compile/grow_past_leaf.bend`. On `zebend` it is `54b4e3b8`.
That commit is the same change, applied by hand because the surrounding context differs:
zebend has `gpu_hold` just above `monk_step`.

## How the CPU scheduler works

A turn is a grow followed by a drain. All tasks sit in per-lane rings, laid out as rows of 128
lanes.

- **Grow.** One thread per row (or the main thread, when the frontier has fewer tasks than
  `want`) runs ring heads in non-sequential mode until they fork. The children are dealt into
  the row's rings. The grow stops when the row has 128 non-empty rings or when nothing grew.
- **Drain.** The pool takes the rings unit by unit. Each ring's tasks run to completion in
  sequential mode (`seq`), and a fork met in sequential mode runs inline. So a drain gets
  parallelism only from tasks the grow put into separate rings.
- **Skipping.** A growing lane skips a ring whose head task is fork-free (`fid_nofk`), because
  growing a leaf is useless. The skip covers the whole ring, not just the head.

## The pinning

A grow deals children starting at its row's lane 0. Those rings already hold the frontier's
own tasks. After a narrow fork such as `a b = cheap_leaf(x) big(y)`:

1. The fork-free `cheap_leaf` heads a ring.
2. Children of `big` (or of other grown tasks) get dealt behind it, into the same ring.
3. The grow skips that ring from then on, so those forking tasks never grow.
4. The drain runs them in sequence on one thread. Their whole subtrees run there too, including
   every wide fork after them, while the other threads idle.

Per-turn counters (a measurement-only patch, never committed;
`bendwork/sched/tools/statpatch.py`) show it on the repro below at 18 threads. One drain turn
runs 18.7 ms of wall time, 24.8 ms of busy time, with one thread busy for 18.7 ms. With the fix,
the same turn takes 2.5 ms of wall time and 23.7 ms of busy time.

## Fix

On the host, a growing lane that meets a fork-free head:

1. pops it;
2. pushes it back at the ring's tail, past this pass's `put0`, so the drain still runs it;
3. looks at the next task.

`monk_step` loops until it finds a task that can fork, or until every task below `put0` has
moved. A ring of leaves therefore costs one push per leaf per grow pass.

The device keeps its old behaviour: under `DEVICE` the skip still returns at once. The drain
(`seq`) is unchanged. Single-thread runs never grow, so they are unchanged too.

## Repro (`bendwork/sched/repro/pin3.bend`)

```
def wide(+d: Nat, +i: U32) -> U32:      # 2^d leaves of mix(200000n, ·)
  ...binary fork...
def chain(+k: Nat, +x: U32) -> U32:     # k wide(7n) forks in sequence
  ...
def half(+i: U32) -> U32:
  chain(8n, mix(3000000n, i))           # a serial prefix, then 8 wide forks
def top(+x: U32) -> U32:
  a b = mix(100n, x) half(U32.add(x, 1)) # the narrow fork: one side is a leaf
  U32.xor(a, b)
```

Wall times in ms, medians of 7 interleaved runs. Load average 7.4–8.0. The output is the same in
every run.

| threads | 1 | 2 | 4 | 8 | 18 |
|---|---|---|---|---|---|
| before (zebend) | 202.3 | 106.1 | 58.5 | 37.5 | **43.4** |
| after | 203.0 | 106.4 | 57.8 | 34.0 | **24.6** |

Before the fix, 18 threads were slower than 8. Per-thread busy time at 18 threads, from one
run with the counters, at load 6:

- **Before:** thread 0 was busy 32.0 ms, and the others 7–12 ms. Utilisation 0.32.
- **After:** the busiest thread was busy 14.8 ms, and the others 8.6–13.4 ms. Utilisation 0.58.

`pin.bend` is the control: the same chain with no narrow fork. It is unchanged: 35.6 vs 36.0 ms
at 18 threads, 400.8 ms at 1 thread both before and after.

## Zebend workloads (before → after)

These were measured in the same session as the repro. Each pair was run interleaved. Load
averages are shown in the table.

| workload | before | after | load |
|---|---|---|---|
| Halo 2 verify, 2-action, 1T (`loop_ba`, ms/proof, 7 runs) | 27.23 | 27.19 | 8.0–8.4 |
| Halo 2 verify, 2-action, 18T (ms/proof, 7 runs) | 8.99 | 9.09 | 7.8–9.3 |
| batch verifier, 10,048 bundles in 3 batches, 18T (bundles/s, 3 runs) | 694.5 | 695.5 | 11.7–18.5 |
| RedPallas batch (`sigbatch`, 3 chunks, 24,5xx sigs), 1T (sigs/s, 5 runs) | 19,361 | 19,593 | 17.9–21.5 |
| RedPallas batch, 18T (sigs/s, 5 runs) | 125,995 | 125,352 | 16.7–17.9 |
| Equihash `eqv3`, 16,384 headers, 1T (headers/s, 5 runs) | 4,233 | 4,242 | 11.6–16.7 |
| Equihash `eqv3`, 18T (headers/s, 5 runs) | 38,642 | 39,385 | 10.9–11.6 |

None of these changes beyond noise, and that is expected: the shipped Zebend code never hits
this case. The counters show **0 rotations** in `loop_ba`, because the verifier's early fork was
already widened by hand (the algo/README "Bend scheduler" workaround). A variant with the old
narrow instance-commitment fork (one task per proof) does rotate, 5 times per proof. There, the
CPU-time critical path drops about 3%, and the wall time is unchanged within noise (11 ms/proof
both ways, load 13–14). The README's 15 → 43 ms pinning does not reproduce on the current
runtime with that narrow variant: it runs at the same 9 ms/proof as the wide one.

## Where the 18-thread Halo 2 time goes now (zebend, counters, load 6–8)

Each proof in `loop_ba` takes two drain turns:

1. **Serial (~3 ms).** The continuation after the instance commitments runs on one thread up to
   the final MSM: `rd_sgroups` transcript reads (~1–1.5 ms), `normalize` (a batch inversion,
   ~0.5 ms) and more. The CPU-time maximum equals the turn's wall time, so this is program-level
   serial work, not a scheduling problem.
2. **MSM (~4.7–5.9 ms).** The longest unit is 3.3–4.4 ms of CPU time: one `wrange9` task covers
   1–3 windows of about 1.5–3 ms each. The parallelism is limited by window granularity, and the
   join chain of `dbl_n` doublings.

A second runtime tweak was tried and is **not** in this PR. A grow pass ends (`return 2`) when a
lane pushes a fork-free continuation; the tweak lets the pass go on instead. It cut the MSM
turn's longest unit from 3.3 to 2.3 ms and the CPU-time critical path of `loop_ba` by 15%. But
the wall time did not move (s0 11.79, fix 12.06, fix+tweak 12.11 ms/proof, load 13–18), so it
is left for later. Removing the main thread's pre-grow was also tried: it helps when two tasks
with long serial prefixes start together, but in one repro it made the critical path 8×
longer. Dropped.

## Checks

- **Tokens:** comp.ts 66,053 on origin/main alone, which is **over** the 66,000 cap. It needs
  `pr/comp-simplify`. Stacked on that, it is **65,568** (cap 66,000; comp-simplify alone is
  65,509), so this change costs 59 tokens.
- **Fork test suite** (`research/gpuv/t/forktests.py`) on the branch: PASS 137, FAIL 0, SKIP 13, both
  CPU-only and Metal-enabled. The 13 skips are tests that also fail to build on origin/main.
- **New test** `grow_past_leaf.bend` gives the same output at 1, 2, 3 and 18 threads, before
  and after the fix. With the counters, it makes 25–40 rotations, so it exercises the new path.
- **Metal:** the device source changed shape, though not its behaviour. AIR still has 1 function
  and 0 calls to non-intrinsics for `bang_in_fork`, `bang_lane_spill` and `grow_past_leaf`.
  The same holds for the Equihash kernel (`research/blake3x/eqv3/main.bend`), whose AIR has 1 function
  and 0 calls to non-intrinsics both before and after.
- **Metal determinism gate**, all with the fixed build on the GPU:
  - Equihash `eqv3`: 20 runs over 16,384 mainnet headers gave 1 distinct output (valid
    16,384/16,384, target 16,384/16,384, links 16,383/16,383, difficulty 16,356/16,356).
  - `bang_in_fork` and `bang_lane_spill`: 20 runs each gave 1 distinct output, equal to the
    tests' `#|` lines.
  - The sigbatch GPU gate cannot run on zebend-built binaries. Both the before and after builds
    of `research/sigbatch/batch_gpu` fail to compile on Metal: `XPC_ERROR_CONNECTION_INTERRUPTED` after
    about 3 minutes. This happens without the fix too, so it is not caused by this change.

## Reproduce

Everything is in `bendwork/sched/`:

- `tools/bench.py` runs the interleaved before/after benchmarks.
- `tools/statpatch.py` adds the counters, enabled with `BEND_SCHED_STATS=1|2|3`.
- `tools/metaldet.sh` is the GPU determinism gate.
- `bin/{cb,cf}` hold the binaries. `cb` is zebend `6fec4533`; `cf` is the same plus this fix,
  which matches zebend `54b4e3b8`.
