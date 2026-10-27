# A `!` met by forked work runs on the GPU, not on the CPU pool

Branch `pr/gpu-in-fork` (on `pr/comp-simplify`), one commit, `bend2/comp.ts` plus
`tests/compile/bang_in_fork.bend`.

## Problem

`corpus_eval` sends a `!` call to the GPU only when the sequential top of an evaluation meets
it. Once the program forks, `corpus_eval` hands the work to `cube_run(H, false)` (the CPU
pool), and every `!` met there runs on the CPU, with no warning. A program written as

    def two(+d: Nat) -> U32:
      a b = tree!(d, 1) tree!(d, 2)
      U32.xor(a, b)

or a `par` whose leaves call `msm!(...)` (Zebend's Halo 2 batch verifier) silently gets no GPU
at all. Zebend first measured a "GPU" MSM that had in fact run on the CPU.

## Root cause

Two paths drop the bang:

1. Tasks a fork deals onto the rings run through `monk_step` -> `work_loop` on a CPU worker.
   Nothing checks `fid_bangs`.
2. In the pool's drain mode (`seq` = 1), a bang call site (`if (!seq) return task`) runs the
   call inline on a C-stack frame, so no task ever reaches the scheduler.

## Fix

- `monk_step`: with the GPU on, a task whose def is banged (`fid_bangs`) is not run. The pool
  holds it (`gpu_hold`, a growing array under `pool_lock`).
- `cube_run`: when the CPU frontier drains and held bangs remain, `gpu_flush` runs each one on
  the GPU exactly as the top level does. `gpu_call` is factored out of `corpus_eval` and shared
  by both. The continuations they complete become the pool's next frontier.
- The FID table's `bangs` byte gains bit 1, `fid_bangy`: the banged defs and every segment that
  can reach one (callers' closure, the same `graph_close` as `forky`, factored into `up`).
  With the GPU on, the pool runs such a task forking (`seq` = 0), so its bang call returns a
  task instead of running inline.
- Programs without `!`, and every run with `--gpu off`, are unchanged: bit 1 is 0 and `io_gpu`
  is false. `io_gpu` is `false` on the device.

## Test

`tests/compile/bang_in_fork.bend`: both branches of a fork are bangs (`two`), and a forked
leaf bangs inside a non-tail call (`par` -> `leaf` -> `tree!`). It prints the same two lines on
the GPU, with `--gpu off`, with `--threads 1`, under JS and in the interpreter. Fork suite
(`research/gpuv/t/forktests.py`): 136 pass, 0 fail on the PR branch (run before the test had its `#|` lines); 138 pass, 0 fail, 13 skip on
`zebend`. The bang subset passes 29/29. On `zebend`, `aircalls.sh bang_in_fork.bend` finds 0
non-intrinsic calls, and 20 GPU runs each of `bf` and `bang_in_fork` are bit-identical.

## Measured (M-series Mac, shared machine, medians of 3)

`bf.bend`: `two(20n)` with 2^20 leaves of `mix(20000n, i)`, two bangs inside a fork.

| build | real | user |
|---|---|---|
| before (`!` silently on the CPU pool) | 2.88 s | 40.3 s |
| after (GPU) | 0.16 s | 0.00 s |
| after, `--gpu off` | 2.87 s | 40.3 s |

That is about 18x. The same tree run as a single top-level `!` takes 0.11 s on the GPU and
1.39 s with `--gpu off`.

Cost: each held bang is its own GPU launch, run one after another. A program with many tiny
bangs inside forks now pays a launch per bang. A `par(10n)` of 1,024 leaves, each
`tree!(6n, i)`, went from 0.02 s (CPU) to 0.39–0.58 s. That is what a `!` asks for, and a
top-level `!` in a loop already costs the same. Next step: batch the held bangs into one
launch, which needs one root per held task.

## Tokens

comp.ts 65,987 on this branch (cap 66,000; `pr/comp-simplify` is 65,509).
