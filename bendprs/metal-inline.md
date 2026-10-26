# Metal: no calls in device code (always inline)

Found by the project's user (credited as the finder; reported to us, not found by this
fork's tests).

## The bug (Apple's GPU compiler)

When a Metal kernel keeps a helper as a real call (not inlined), the compiler emits
call-frame state for the preserved call. Under scheduler residency, that state can
overwrite a 32-bit word of the caller's data. It happens nondeterministically, per
dispatch and per run, so the symptom looks like random noise in results. The only
defence is to leave no helper un-inlined in a Metal kernel. The user has confirmed
that fully inlined kernels do not show the corruption.

Before this change, Bend's device code made calls in three ways:
- `FAR` = `static __attribute__((noinline))`. This covered `DFAR` spins of 8 KB or
  more of source, `lane_spill`, `work_loop`, `term_drop` and `err_claim`.
- `INLINE` = plain `inline`, which Metal is free to keep as a call. It did:
  `heap_alloc`, `ring_push`, `task_deal`, `task_deliver`, `monk_step`, `dev_cut`
  and `bank_pack` were all calls in `deep.bend`'s kernel.
- `OUTLINE` = `static`.

One symptom we probably already saw: a variable-time wallet-scan build (scan2) gave
wrong hit lists on Metal after a fresh GPU compile.

## Fix (always on for Metal, no opt-out)

Under `__METAL_VERSION__`:

    #define INLINE  inline __attribute__((always_inline))
    #define OUTLINE static INLINE
    #define FAR     static INLINE

Other changes:
- `work_loop`'s definition is now `FAR`, matching its declaration.
- Host builds (`FAR` = `static noinline`) and CUDA builds are unchanged.
- No function-pointer tables reach the device: `wl_tab` is host-only, and the device
  dispatches segments through a `switch`.
- No device helper is recursive. `lane_spill` → `work_loop` is not a call cycle,
  because `work_loop` is entered once, from `bend_dev`.

### Verification: zero calls in the AIR

`gpuv/t/aircalls.sh` (in bend-zcash) takes a program and:
1. emits its C, which is also its Metal source (the runtime `#embed`s the file);
2. compiles it to AIR (LLVM IR) with `xcrun metal -S -emit-llvm` and the runtime's
   `-DCUBE_LOG`;
3. counts `call`s to anything other than `air.*` or `llvm.*` intrinsics.

| program                   | before                                          | after                    |
|---------------------------|-------------------------------------------------|--------------------------|
| `deep.bend` (spill probe) | 10 functions, 20 calls (9 helpers, incl. `lane_spill` ×4, `heap_alloc` ×8) | 1 function, **0 calls** |
| `msmbench.bend` (GPU MSM) | n/a                                             | 1 function, **0 calls**  |
| `fork_leaf_handoff.bend`  | n/a                                             | 1 function, **0 calls**  |

With no other function in the AIR module, the native backend has nothing left to call.

## Two Apple compiler crashes that full inlining exposes, and their workarounds

With every helper inlined, `MTLCompilerService` aborted (`XPC_ERROR_CONNECTION_INTERRUPTED`
on our side) on `tests/compile/fork_leaf_handoff.bend`, on the GPU MSM, and on the GPU
batch verifier. The crash reports (`~/Library/Logs/DiagnosticReports/MTLCompilerService-*.ips`,
`termination.reasons`) name GlobalISel legalizer failures in the AGX backend:

1. `unable to legalize instruction: s8 = G_TRUNC s16`. It comes from a `<4 x s8>`
   bitcast of a 32-bit word, with the word made from a 64-bit value AND
   `0xffffff0000000000`. Source: `term_drop`'s `(u8)(cur >> 40)` and `(u8)(cur >> 48)`.
2. `unable to legalize instruction: s31 = ... s32`. LLVM turned `switch (term_tag(t))`,
   with `term_tag(t) = (t >> 56) & 0x7f`, into a switch on `trunc i64 → i63` masked
   with `0xff00000000000000`. The high half of that i63 is an s31.

Both are LLVM narrowing a 64-bit shift-and-mask into an odd-width integer that the
backend cannot legalize. Once everything is inlined, the patterns meet where the
combiner can fold them. Workaround: read the high-word fields with Metal's
`extract_bits` intrinsic, which LLVM cannot narrow:

    #ifdef __METAL_VERSION__
    #define HI_BITS(x, s, n) ((u64)extract_bits((u32)((x) >> 32), (s) - 32, (n)))
    #else
    #define HI_BITS(x, s, n) (((x) >> (s)) & ((1ull << (n)) - 1))
    #endif

Changes made with it:
- `term_tag`, `term_aux` and `term_drop`'s two byte fields use `HI_BITS`.
- `Fid` and `Cid` are word-wide on the device, so there are no byte loads into the
  same folds.

After this, `fork_leaf_handoff`, the GPU MSM and the GPU batch verifier all compile,
in seconds.

Before the workaround existed, a bisection script (`gpuv/t/bisect_fn.py`) found that
leaving any single tiny accessor as plain `inline` also avoided crash 1. That only
moves the pattern around, so `extract_bits` is the real fix.

Kernel size: with full inlining, a `DFAR` spin is copied into every caller. The GLV
scalar-multiplication MSM kernel came to 16.8 MB of AIR, because one field-multiply
spin had 117 call sites. Apple's compiler crashed on it after about 10 minutes (crash
1 again, or resource exhaustion). The GPU MSM now uses double-and-add with the
complete addition law (two point additions in the kernel: 1.6 MB of AIR). That
compiles in about 7 s and is what we measure. Large kernels need to be written with
few call sites of big spins.

## Tests

- `tests/compile` with the fork (spill + always-inline + `HI_BITS`): **PASS 137, FAIL 0,
  SKIP 13**. The 13 skips are the same as on unpatched u64-rot: tests whose source
  does not type-check as a standalone build. Before the `HI_BITS` workaround the
  result was PASS 136 / SKIP 14, the extra skip being `fork_leaf_handoff`
  (Apple compiler crash 1). It now builds and prints its expected `24247809 ×4, 92`.
- Spill probe under always-inline: `deep 1024 14` (16,384 lanes) and `deep 4096 12`
  each ran 20×, 1 distinct (correct) output each. `deep 4096 14 +RTS --gpu 7GB`
  ran 5×, and `BEND_CUBE_LOG=5 deep 1024 14` ran 5×; both gave 1 distinct correct
  output.
- Determinism gate, which every reported GPU number passed: the same workload ≥20
  times, outputs compared bit for bit (`gpuv/t/det.sh`). For the GPU MSM, 20 runs at
  4,096, 65,536 and 262,144 terms each gave 1 distinct output, and that output
  matched both CPU MSMs. At 262,144 terms, `BEND_CUBE_LOG` 5 and 6 (5 runs each, other
  lane counts) gave the same output. For the GPU batch verifier, 20 runs on 1,024 real
  bundles gave `result 1` every time, and 20 runs with one tampered bundle gave
  `result 0` every time.

---

## Notes for the PR branch (`pr/metal-inline`, on `pr/metal-lane-spill`)

- `BEND_CUBE_LOG` is left out of the PR. It is an undocumented environment knob, and `zebend`
  keeps it. The comments were shortened to fit the cap, and the references to METAL_INLINE.md
  are gone.
- comp.ts: 66,000 tokens, exactly at the cap.
- `aircalls.sh` on `tests/compile/bang_lane_spill.bend`: 1 defined function, 0 calls to
  non-intrinsics. The fork suite's bang subset passes 29/29.
- There is still no regression test for the miscompile itself. It is nondeterministic, and
  only Zebend's large kernels show it.
