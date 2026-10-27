# Metal lane spill: restore it

## Symptom

A `!` program whose lanes recurse deeply (non-tail) crashes on Metal with

    bend: memory fault (machine stack overflow?)

when many lanes are live at once. It depends on lane count and depth together.
With `deep.bend` (every lane builds a list of length L by non-tail recursion,
`mk(n) = n <> mk(n-1)`, and sums it; 2^d lanes):

| lanes (2^d) | L     | before (u64-rot, no spill)    | after (spill restored)                 |
|-------------|-------|-------------------------------|----------------------------------------|
| 1,024       | 4,096 | ok                            | ok                                     |
| 4,096       | 4,096 | ok                            | ok                                     |
| 16,384      | 1,024 | **memory fault**              | 4286578688 (correct)                   |
| 16,384      | 4,096 | **memory fault**              | 4261412864 (correct, `+RTS --gpu 7GB`) |
| 1,024       | 65,536| (not run)                     | 4261412864 (correct, `--gpu 6GB`)      |

At the default span, 16,384 lanes × L=4,096 runs out of heap, as it should. That
case reports `out of memory: run again with a bigger span` and does not crash.

## Cause

Upstream #1809 (5ce1e07f) removed `lane_spill`, because `bend -o` of a `!` program
built about 17% slower with it. Without the spill, a lane whose stack window
(`STAK_LEN` words per lane, interleaved by `CUBE`) fills up has nowhere to go: the
next push writes past the window into the next region. At a few thousand lanes the
windows happen to have slack. At 16,384 lanes (128 groups × 128 threads) they don't.

## Fix

Commit 0d769b1d reverts 5ce1e07f. That brings back:
- `WL_ROOM(N, D)`: before a segment pushes N words, it checks the room left and calls
  `lane_spill` when the window is full;
- `lane_spill`: moves the lane's words to a heap block under an `FID_EXIT` frame;
- the `FID_EXIT` case in `work_loop`: moves the words back when the frame is reached;
- `tests/compile/bang_lane_spill.bend`.

A second change: `BEND_CUBE_LOG=3..7` (Metal) launches 2^n groups instead of 128.
This is a debugging and tuning knob. The `.gpu` cache is keyed by `CUBE_LOG`, so
changing it recompiles the Metal program.

## Tests (M5 Max, macOS, Metal)

- `tests/compile` with the fork (`forktests.py`: build every test, compare its output
  with the `#|` lines, on the GPU wherever the test uses `!`):
  - patched: **PASS 137, FAIL 0, SKIP 13**;
  - unpatched u64-rot: PASS 136, FAIL 0, SKIP 13. The skips are the same 13: tests
    that import files or have no `#|` lines. The extra pass is the restored
    `bang_lane_spill`.
- The bang-only subset: PASS 29, FAIL 0.
- Real programs rebuilt with the spill:
  - zcash wallet trial-decrypt scan: hit lists identical to CPU at 4,096, 65,536 and
    262,144 outputs;
  - mainnet Ironwood note-commitment tree: 6/6 roots match.

  These two checks predate the always-inline change in METAL_INLINE.md, so they were
  not repeated under the ≥20-run determinism gate.

The always-inline change (METAL_INLINE.md) stacks on top of this commit. Under it,
`lane_spill` and `work_loop` inline into the kernel like every other helper.
