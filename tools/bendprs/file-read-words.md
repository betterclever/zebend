# File.read_words / File.write_words: whole files as one flat Array<U32>

Branch `pr/file-read-words` (on `pr/comp-simplify`), one commit (61e828f5). Cherry-picked onto
`zebend` as 3fbef653. Worktree: `bend-fork-arr`.

## Problem

Bend reads binary files with `File.read_bytes` / `File.read_at`, which return one `List` cell
per byte. A 3 MB file becomes 3M cons cells (48 MB of heap). Every later walk over the bytes
pays reference counts and frees. In Zebend's transparent validator, 35–40% of samples were in
`term_drop` / `span_fade` / `rfc_wrap`. A 3 MB fixed-base table for Halo 2 was not worth
loading this way.

## What Array<U32> already costs (no compiler change was needed)

Before adding anything we checked how arrays are emitted (`comp.ts` `arr_op`, `blk_*`).
`Array<U32>` is already a flat block of unboxed `u32`s (`TAG_BUF`).

- `a[i]`: one `blk_at` mask (an index wraps, there is no bounds error) and one 32-bit load.
- `a[i] <- v`: one store, in place. Arrays are affine, so there is no copy-on-write and no
  per-element reference count.
- An element of a flat record type (e.g. 8 `U32`s) is stored inline: `Array<F8>` get/set moves
  8 words in one operation.

Measured on M5 Max, 1 thread, medians of 7 (`research/flatio/arr_*_micro.bend`):

- 100 × (2²⁰ sets + 2²⁰ gets) on `Array<U32>`: 34–52 ms (two sessions), minus ~3 ms process start, so
  **0.15–0.25 ns per op**. The range is load (3–14) on a shared machine.
- 100 × 2¹⁷ get+set of 8-word `Array<F8>` elements: 31 ms wall (28 ms over start), about **1 ns per element op**.

So the "8 array ops per field element" in perf3's `msm_arr` cost about 2 ns against an ~18 ns
field multiply. That experiment was slower because of its algorithm (≈3× more inversions,
see perf3/README) and its boxed `ST` / `List<QE>` state, not because of array access. The one
real array cost is splitting by `match ALeaf/ANode`: `blk_half` copies each half. Slices
should be passed as (array, offset) instead. `sha256_arr.hash_at` does this.

What was slow was getting bytes into an array: the only way in was a `List`. This PR adds
that path.

## API (Base)

```python
# Up to max bytes, until max or the end of the file, with no List: packed
# little-endian four to a word (byte i is bits 8*(i%4) of word i/4) in a
# flat Array<U32> of the least power of two words that holds them (at
# least one), zero past them, beside the count of bytes read.
def File.read_words(file: File, max: U32) ->
  IO(File & Result<&1, &1, U32 & String, Array<U32> & U32>)

# The first len bytes of data, packed as File.read_words gives them; a len
# past the array's 4 bytes per word fails with EINVAL before any is written.
def File.write_words(file: File, data: Array<U32>, len: U32) ->
  IO(File & Result<&1, &1, U32 & String, Unit>)
```

- `read_words` loops over `read()` until it has `max` bytes or reaches EOF. `read_bytes` does a
  single `read()`. Errors are reported like `read_bytes`: `Fail{(errno, text)}`, and the handle
  comes back beside the result.
- `write_words` consumes the array. Write it from a clone if you still need it.

## Design

- C (`effs/file_read.c`, `effs/file_write.c`): the helper thread reads into a malloc buffer.
  `pack`, on the loop, allocates one block of class `cls_fit(ceil(n/4))`
  (`heap_alloc(e, blk_wcls(0, c))`), zeroes it, `memcpy`s the bytes in, and returns
  `term_blk(0, c, l)`. The `memcpy` relies on the host being little-endian (arm64, x86-64).
  `write_words` copies `blk_loc(e.mem, a)` out on the loop, `blk_free`s the array, then reuses
  `file_write_call`.
- JS (`effs/file_read.js`, `effs/file_write.js`): `fs.readSync` (into a buffer that doubles from 64 KiB, so a huge `max` costs nothing) and `fs.writeSync` loops. The array
  is a plain JS `Array` of numbers, which is how JS represents `Array<U32>`.
- Effects sit in the runtime's `#if !DEVICE` host section, so Metal and CUDA are unaffected.
  On `zebend` the device AIR of the test has **0 non-intrinsic calls** (aircalls), the same as
  `tests/io/read_bytes`, and no effect symbols. On `pr/comp-simplify` both tests show the same
  7 runtime calls, which predate the always-inline patch.
- **Tokens: comp.ts unchanged**, 65,509 / 66,000 on the PR branch and 68,977 on `zebend`.
  `effs/*` and `base.bend` have no cap.

## Test

`tests/io/file_words.bend` checks:

- packing of 9 bytes into 4 words;
- a capped read (6 bytes);
- `max` 0;
- the empty file (`[0]`, 0);
- a 256-byte file checked word by word;
- a read on a write-only handle (`fail 9`, handle kept);
- a `write_words` / `read_words` round trip of 7 bytes;
- a `len` past the array (`fail 22`).

The output is identical on the interpreter (`bend t.bend`), the C binary (default and
`--gpu off`), and the JS build under bun and node. 20/20 identical runs on `zebend`.

Fork test runner (`research/gpuv/t/forktests.py`, tests/compile): PR branch 136 pass / 0 fail / 13 skip,
the same as before the change; `zebend` after the cherry-pick 139 / 0 / 13 (152 tests on that branch;
the 137 / 13 baseline was taken when it had fewer tests).

## Measurements (M5 Max, 1 thread, medians; machine load 4–14 from other agents)

Process start is ~2.8 ms (`r0`: open + size + print).

| Workload | List (`read_bytes`) | Flat (`read_words`) | |
|---|---:|---:|---|
| read 3 MB + sum bytes (wall, incl. start) | 12.7 ms, 53 MB RSS | **3.6–4.1 ms, 9 MB RSS** | ≈ 10 ms vs 0.8 ms over start |
| read 30 MB + sum bytes | 99 ms, 512 MB RSS | **12.1 ms, 64 MB RSS** | |
| SHA-256d of 1 MB (per hash, from 10 reps) | 27 ms (live `sighash2/sha256.bend`) | **1.9 ms** (`sha256_arr.bend`) | 14× |
| read + one SHA-256d of 1 MB (wall) | 44.6 ms | **5.0 ms** | |
| HASH256 of all 30,853 real mainnet txs (54.5 MB, all eras; per pass, from 3 reps) | 2,734 ms | **104 ms** | 26× |
| read of that 54.5 MB file | 656 ms, 1.3 GB RSS | **14 ms, 118 MB RSS** | |
| runtime refcount/free share (`sample`, top of stack) | 46.8% (`term_drop`, `span_fade`, `rfc_wrap`) | **0%** | |

The 30,853-transaction run is the hashing kernel of the legacy sighash: one SHA-256d over each
serialized transaction. The list side takes each transaction as its own list, as the sighash
builds one. Its checksum (942660629) equals Python `hashlib`'s on both sides.
`check_sha.py`: 612 checks (every length 0–300, plus 4095–4097, 65591 and 1 MiB, both modes)
against `hashlib`, 0 mismatches.

Only SHA-256 was rewritten. BLAKE2b (ZIP 143/243/244) is still the list version. The whole
sighash still serializes into lists; moving it to arrays needs an array-backed serializer.

## Files (Zebend side, research only; live code untouched)

`research/flatio/`:

- `sha256_arr.bend`: SHA-256/SHA-256d over an `Array<U32>` at a word offset. The compression is
  imported unchanged from `sighash2/sha256.bend`.
- `words.bend`: `load(path)`, `byte(a, i)`, `be(a, k)`, `bswap`.
- `hash_bench`, `tx_bench`, `mk_txs.py`, `check_sha.py`.
- `read_list` / `read_words`, `arr_*_micro`, `bench.py`.
