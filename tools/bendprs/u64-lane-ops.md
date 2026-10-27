Add U32.add64, U32.xor64, U32.rotr64: 64-bit lane ops on U32 halves

Each returns word k of a 64-bit add, xor or rotate of (lo, hi) operands. Defined
in Base via Nat; lowered to one 64-bit instruction in C/Metal/CUDA (inlined with a
constant k, the halves re-merge for free) and BigInt in JS. tests/base/u64_lanes:
edges + 2^16 random tuples, 0 mismatches on CPU, Metal and JS.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>


## Notes for the PR branch (`pr/u64-lane-ops`, on `pr/u32-wide-mul`)

Base defines each op via Nat: word k (0 = low, 1 = high) of the 64-bit result. C, Metal and
CUDA lower `add64` and `xor64` to macros over `U32_W64` / `U32_HALF`, and `rotr64` to one
inline. JS uses BigInt (`u32_lane`). C now returns 0 for k > 1, as Base does; before, it
returned the high word. tests/base/u64_lanes passes on C, JS and the interpreter.
comp.ts: 66,705 tokens, 705 over the cap. Still open.
