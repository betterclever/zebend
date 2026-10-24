# blake3x: faster BLAKE2b and Equihash in Bend

Goal: close the gap to Rust (`blake2b_simd`, the `equihash` crate) on BLAKE2b and Equihash(200, 9)
header verification. M5 Max, medians of 3–5 runs. Load average 3–13 (another agent was compiling);
compare ratios measured at the same moment, not absolute numbers across tables.

## Result

| BLAKE2b, 10⁵ compressions, 1 thread | ms | compressions/s |
|---|---|---|
| node/headers original (5-op carry) | 35 | 2.9 M |
| field3 `U32.add_hi` carry (baseline here) | 23 | 4.3 M |
| + 64-bit lane primitives `add64`/`xor64`/`rotr64` | 31 | 3.2 M (slower, not used) |
| + 2–6 rounds per generated def | 23 | 4.3 M (no change) |
| **Equihash leaf compression** (zero message words and constants folded) | **18** | **5.6 M** |
| Rust `blake2b_simd` (64 MiB in 1 MiB messages: 524,288 compressions in ~49 ms) | ~9.3 | ~10.7 M |

| Equihash(200, 9) header verification | 1 thread | 18 threads | Metal GPU |
|---|---|---|---|
| node/headers original (Bend 2.0.38) | 1,283/s | 11,762/s | 6,775/s |
| field3 `add_hi` (baseline here) | 1,417/s | 16,804/s | — |
| + list-free leaves / tree / index unpacking (`eqv2`) | 4,312/s | — | — |
| **+ leaf compression (`eqv3`, Bend fork)** | **4,194/s** | **40,857/s** | (fork Metal faults) |
| same, stock Bend 2.0.38, portable carries (`eqv4`) | 3,610/s | 37,751/s | **21,500/s** |
| Rust `equihash` crate (Equihash only) | ~9,000/s | ~117,000/s | — |

Bend's numbers time the whole header check: SHA-256d block hash, hash ≤ target, prev-hash links and
the difficulty adjustment, as well as Equihash. Rust's time only `equihash::is_valid_solution`.
Measured on the same 16,384 mainnet headers (Equihash 1-thread row for `eqv2` on 4,096).

All 128,280 mainnet headers (3,400,000–3,528,279): `eqv3` on 18 CPU threads in **5.3 s**, `eqv4` on
the GPU in 11.0 s (the original GPU run took 52.5 s). Equihash, target, links and difficulty: 100%.

Net: Equihash went from 1,417 to 4,194 headers/s single-threaded (3.0×) and from 16,804 to 40,857
on 18 threads (2.4×). Rust is still 2.1× (1 thread) and 2.9× (18 threads) ahead; a BLAKE2b
compression is 1.9–2.5× behind.

## What was done, and what each step found

1. **Midstate: already there.** The original verifier compresses the first 128 header bytes once per
   header (`ec_of`) and does one final compression per index. No change needed.
2. **The real cost was lists, not hashing.** `sample` on the original verifier: ~60% of time in
   `List.take`, reference counting (`rfc_wrap`), `term_drop` (each of 512 leaves built a 50-byte
   list, took/dropped 25 bytes, unpacked 20-bit chunks through a bit buffer, and XORed chunk lists
   up the tree); BLAKE2b ~29%. `gen_eq.py` regenerates the Equihash section with no byte lists:
   chunks computed straight from the digest words, a fixed 12-field node record merged per level,
   indices unpacked 21 bytes at a time. 3.0× on one thread.
3. **64-bit rotate primitives cannot help.** The assembly of the existing BLAKE2b already has one
   `EXTR` per 32-bit half of every rotate (576 = 12 rounds × 8 G × 3 non-trivial rotates × 2; the
   rotate by 32 is a free swap). Adding `U32.add64` / `U32.xor64` / `U32.rotr64` (Bend fork, branch
   `u64-rot`) halves the `EXTR`s, but LLVM narrows the 64-bit adds back to 32-bit `add`/`adc` pairs
   because every intermediate is a `u32` local, and the extra merges/splits made a compression
   slower (31 vs 23 ms). A minimal C reproduction shows the same narrowing. The primitives are
   correct and kept on the branch (useful for SHA-512/Keccak-style code), but BLAKE2b doesn't use them.
4. **Function boundaries are not the cost.** 1, 2, 3, 4 or 6 rounds per generated def: different C,
   identical speed.
5. **Leaf specialization.** For Equihash's leaf hashes 14 of 16 message words are zero, t = 144 and
   the final flag is set: `b2_leaf` folds them away (−22% per compression, −7% on Equihash).
6. **Parallelism.** Headers already verify as a balanced parallel tree; 1 → 18 threads scales 9.7×
   (Rust 13×). The fork's Metal build of the verifier faults (known upstream issue); the same
   generated code built with the installed Bend 2.0.38 and portable carries runs on the GPU.

What's left: per header, BLAKE2b is now ~41% and reference counting/allocation from byte-list
conversions (`List.append`, `le_words`, SHA-256 over word lists) ~26%, sorting the 512 indices ~11%.
Getting BLAKE2b itself to Rust speed needs 64-bit values that survive between operations, i.e. a
`U64` type in Bend (or a whole-compression primitive, which would be trusted C, not Bend).

## Correctness

- **Adversarial set** (`adversarial.py`): 300 real mainnet headers + 1,800 mutations (solution bit
  flip, header bit flip, swapped solution halves, swapped level-0 pair order, duplicate index,
  wrong index). Bend's per-header output (block hash, Equihash verdict, target verdict) is
  **byte-identical to the Rust `equihash` crate on all 2,100 lines** for `eqv2`, `eqv3` and `eqv4`;
  every mutation is rejected by both.
- **All 128,280 mainnet headers** valid, with target, links and difficulty at 100%, for `eqv3` and `eqv4`.
- **Lane primitives** (`bend-fork/tests/base/u64_lanes.bend`): edge cases + 2¹⁶ random tuples ×
  3 ops, 0 mismatches against 32-bit references on CPU, Metal and JS.

## Layout

- `gen_hashes.py`: BLAKE2b/SHA-256 generator (`RPD`, `LANES=1`, `PORTABLE=1`; always emits `b2_leaf`)
- `gen_eq.py`: list-free Equihash section (`LEAF=1` uses `b2_leaf`)
- `adversarial.py`: adversarial header generator
- `base/` (field3 baseline), `lanes/`, `rpd*/`, `eqv2/`, `eqv3/`, `eqv4/`: generated variants
- `build.sh` / `guard.sh`: build with the Bend fork, kill runaway compiles

Bend fork: `/Users/betterclever/projects/zecathon/bend-fork`, branch `u64-rot`, commit `ad0523fa`
(local, not pushed).
