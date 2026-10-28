# Bend changes

Zebend found real limits in Bend 2 and fixed several of them. The fixes live in a local fork as
separate, upstreamable branches, each with a regression test and a PR note in `tools/bendprs/`.
The fork is not published yet.

| Branch | Change | Effect |
|---|---|---|
| `pr/u32-wide-mul` | `U32.mul_hi`, `add_hi`, `mac_hi`, `mac64`: high halves and multiply-accumulate on 64-bit lanes | 64-bit-limb field arithmetic; proven exact in `proofs/prims` |
| `pr/u64-lane-ops` | `add64`, `xor64`, `rotr64` | BLAKE2b and SHA-512 on 64-bit lanes |
| `pr/file-read-words` | `File.read_words` / `File.write_words`: whole files as one flat `Array<U32>` | SHA-256d of 1 MB 27 → 1.9 ms; reference-counting share 47% → 0% |
| `pr/metal-lane-spill` | restores the Metal lane spill that 2.0.39 removed | GPU programs with deep recursion no longer fault |
| `pr/metal-inline` | every Metal device helper is always inlined | avoids an Apple Metal compiler bug that can corrupt a caller's data across a call |
| `pr/gpu-in-fork` | a GPU call reached from parallel work runs on the GPU | previously it silently ran on the CPU |
| `pr/sched-grow-rotate` | the scheduler looks past a ring head that cannot fork | a pinning case goes 43 → 25 ms on 18 threads |
| `pr/comp-simplify` | `comp.ts` made smaller with identical output | room for the above under upstream's size cap |
| `pr/io-wake-order` | defined order for two calls in the I/O wake-up | correctness |

Every Metal-affecting change is gated on a check that the compiled GPU code contains no
non-intrinsic calls, and on 20 runs with bit-identical output.
