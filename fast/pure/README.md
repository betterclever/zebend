# fast/pure: Pasta in pure Bend on `U32.mul_hi`

The same 8×32-bit-limb fields, curves, MSM and Halo 2 verifiers as `fast/`, with **no C
post-processing**. The four helpers in `intrinsics.bend` are plain Bend: `mulhi` is the
`U32.mul_hi` primitive added in the local Bend fork (`../../../bend-fork`, branch
`u32-mulhi`, see its MULHI.md), and carries are `Bool.to_u32(U32.is_lt(..))`.

Build: `./build.sh prog.bend out` (runs the fork's `bend2/main.ts` with bun; put Homebrew
LLVM first on PATH for the Halo 2 verifiers). Regenerate the fields with `python3 gen_field32.py`.

Verified: fields 116/116, curves 136/136, MSM = `best_multiexp` (n 16/2048/4096, 1T/18T,
Metal), Halo 2 mainnet verdicts = `halo2_proofs` on 42/42 (post-NU6.3), 10/10 (NU6.2),
8/8 (pre-NU6.2). Speed: `python3 bench.py`; at parity with `fast/` (table in the fork's MULHI.md).
