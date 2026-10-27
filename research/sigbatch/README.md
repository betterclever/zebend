# sigbatch: batched RedPallas verification in Bend

Every RedPallas signature of every fully shielded mainnet transaction since NU6.3
(276,675 txs: **980,364 spend-auth + 303,047 binding = 1,283,411 signatures**), verified in
Bend by reddsa's batch algorithm. The same signatures are verified by the Rust `reddsa` batch
verifier for comparison.

**Result: Bend accepts all 1,283,411 signatures (157 batches of up to 8,192), and so does
Rust. Every tampered batch is rejected and bisection names exactly the tampered signature.
On the CPU, Bend is 1.4× slower than Rust on 1 thread and 1.7–2.5× slower on 18 threads.
This is about 95× faster than the earlier per-signature Bend run (1,127 s → 11.8 s).
On the Metal GPU, with the inlining workaround below, it is slower than the CPU.**

## Algorithm

A signature (R̄, s) on msg under vk, with base B (G_SPENDAUTH for spend-auth signatures, R_CV for
binding signatures), is valid iff s < q and

    E = R + [c] vk − [s] B = 0,   c = BLAKE2b-512("Zcash_RedPallasH", R̄ ‖ vk ‖ msg) mod q.

Pallas has prime order (cofactor 1), so no cofactor clearing is needed. A batch of n
signatures is accepted iff Σ [z_i] E_i = 0. That is one multiscalar multiplication of 2n + 2 terms:

    Σ [z_i] R_i + Σ [z_i c_i] vk_i + [−Σ_SA z_i s_i] G_SPENDAUTH + [−Σ_B z_i s_i] R_CV = 0.

This is exactly reddsa's `batch::Verifier` equation: separate base coefficients for the two
signature kinds, and 128-bit weights z_i.

Per signature (`sig.bend`, `prep`): s must be canonical. R̄ and vk must decompress
(`pallas.bend`'s `decompress`, which rejects non-canonical x and points not on the curve). For
binding signatures, vk = bvk = Σ cv_net − [valueBalance] V is computed in Bend from the
action's cv_net values and the i64 valueBalance, then encoded for the challenge hash. A
signature that fails any of these checks is rejected on the spot and does not enter the
batch, as in reddsa, where it fails to parse.

The MSM is `msm_pallas.bend`: perf3's signed-digit batch-affine Pippenger
(`research/perf3/lib_64/msm_ba.bend`), with only the imports changed to Pallas. It uses c = 11-bit
windows (window sweep on 1 thread: c = 10/11/12/13/14 → 12.8k/13.3k/13.2k/13.1k/12.1k sigs/s).
Fields are field3's 4 × 64-bit-limb `fp64`/`fq64`.

**Bisection.** If a batch fails, it is split into halves, each half is re-verified as a batch
(with its own derived weights), and the splitting continues until single signatures remain.
The output is the list of indices of invalid signatures. An empty list means that every
signature is valid.

### Deterministic weights (reddsa uses an RNG)

reddsa draws the z_i from an RNG. Bend has `IO.random_u32`, but verification is a pure
function here, so the weights are derived from the batch itself, Fiat–Shamir style:

    leaf_i = BLAKE2b-256(pers_kind, R̄_i ‖ vk_i ‖ msg_i ‖ s_i)       pers_kind = "ZebendSigBatLfSA" / "ZebendSigBatLfBd"
    seed   = Merkle root of the leaves (inner nodes BLAKE2b-256("ZebendSigBatNode", left ‖ right),
             balanced split, computed in parallel)
    z_i    = low 128 bits of BLAKE2b-256("ZebendSigBatchZ_", seed ‖ le32(i))

For a binding signature, vk_i is the derived bvk. Each leaf therefore commits to everything
that determines E_i: R, the vk point, c (a function of R̄, vk and msg), s, and the base (via the
personalization). The seed commits to the whole ordered batch, because leaves and inner nodes
use different personalizations, so a leaf cannot be passed off as a node.

**Soundness.** Model BLAKE2b as a random oracle. Fix any batch containing an invalid
signature j (E_j ≠ 0). The z_i are then uniform 128-bit values that the adversary cannot see
before fixing the inputs. Condition on all z_i with i ≠ j. The group has prime order q > 2^128,
so Σ [z_i] E_i = 0 holds for at most one residue of z_j mod q, and therefore for at most one of
the 2^128 possible z_j. Each attempt passes with probability ≤ 2^−128, and an attacker making
Q oracle queries (grinding over batch contents) succeeds with probability ≤ Q · 2^−128. This
is the same bound as reddsa's random weights. The difference is that the attacker can grind
offline instead of facing fresh randomness, and 2^−128 per query covers that. (z_i = 0 has
probability 2^−128 and is covered by the same bound.) Weights are a function of order. The
GPU path keeps input order, so it derives the same weights and digests as the CPU path.

## Data and what is oracle-provided

`oracle/` (Rust; reddsa 0.6, orchard and halo2_proofs from the patched vendor tree):

- `extract 8192` parses every tx in `../proofsets/data/sigs` and writes
  `data/chunk_XXXX.bin`, with at most 8,192 signatures per chunk and no tx split across
  chunks. The result is 157 chunks plus `data/manifest.txt` (chunk, index → tx, kind). The
  message is the txid: none of these txs has transparent inputs, so their ZIP 244 shielded
  sighash equals the txid. **The extraction, including the txid/sighash, is Rust.** Bend's
  `zcash/tx` independently recomputed the txid of all 276,675 txs in the proofsets run
  (276,675/276,675 match). This batch program reads (R̄, s, msg, rk) or (R̄, s, msg, cv_net…,
  valueBalance) and does everything else itself: decompression, bvk, challenges, weights and
  the MSM.
- `rust THREADS`: reddsa batch verification of every chunk (`batch::Verifier<SpendAuth,
  Binding>`, one verifier per chunk, chunks in parallel on a rayon pool). Decoding is untimed.
  bvk is computed inside the timed region, as Bend does.
- `tamper K FIELD I`: chunk K with one byte of item I flipped (FIELD = R, s, msg, vk,
  vb (valueBalance), or cv), plus Rust's verdict.

Item record (u32 LE): `kind (0 spend-auth, 1 binding) | ncv | vb_lo | vb_hi | R̄[32] | s[32] |
msg[32] | vk[32] | cv[32]·ncv`, after a u32 item count.

## Correctness

| Check | Result |
|---|---|
| All 157 chunks, Bend CPU 18T / 1T / GPU / GPU+GPU-MSM | **1,283,411 / 1,283,411 accepted** in every configuration |
| All 157 chunks, Rust reddsa batch | accepted (no chunk rejected) |
| 10 tampered chunks: R (items 0, 5), s (0, 5, 4097), msg (0, 8183), vk (0), valueBalance (5), cv (5) | Rust rejects all 10; **Bend rejects all 10 and bisection returns exactly the tampered index** (R/vk tampers that no longer decompress are caught in preparation; the others by the batch equation) |
| Differential | same verdicts on all 167 inputs (157 real chunks + 10 tampered); Rust's verdict is per batch, Bend's is per signature |

Items 5 and 8183 of chunk 0 are binding signatures, so the valueBalance and cv tampers test
the in-Bend bvk derivation.

## Speed

Apple M5 Max, all 1,283,411 signatures. Times count verification only (parse/decode untimed
for both), summed over the 157 chunks; Bend runs one process per chunk (see below).
Two back-to-back sessions (`bench.sh`; load average 6–17 from other jobs on the machine, so
the ranges are wide):

| | 1 thread | 18 threads | Metal GPU |
|---|---|---|---|
| **Bend batch** (this) | 74.9–89.7 s = **14.3k–17.1k sigs/s** | 10.7–11.8 s = **109k–120k sigs/s** | 68.2 s = 18.8k sigs/s (prep on GPU, MSM on 18 CPU threads); 67.4 s with the MSM also on the GPU |
| Rust `reddsa` batch | 52.7–63.1 s = 20.3k–24.4k sigs/s | 4.3–6.9 s = 185k–297k sigs/s | — |
| Bend / Rust | 1.42× slower (both sessions) | 1.7–2.5× slower | — |
| old per-signature Bend (`research/proofsets/run_sigs.py`) | | 1,127 s (12 parallel `zcash/tx/tx_main` processes; that time also includes parsing and txid hashing) | |

Where Bend's time goes (per 8,192-signature chunk, 1 thread): preparation ≈ 2/3
(≈ 340 ms; mostly the 2+ square roots per signature, Tonelli–Shanks with 2-adicity 32, plus
three BLAKE2b calls on byte lists), batch equation ≈ 1/3 (≈ 170 ms, of which the 16,386-term
MSM is most). On 18 threads, preparation scales about 13× (≈ 25 ms) but the equation only
about 4× (≈ 45 ms): the MSM parallelizes over its ~24 windows only, and the one shared
inversion and the list appends are sequential. Next steps: a table-based square root
(as in pasta_curves: about 3× fewer squarings) and parallel normalization in the MSM.

Wall time including process start and file reading: 18.6 s (18T), 97.6 s (1T),
83.8 s (GPU).

### GPU

`batch_gpu C L M`: per-signature preparation runs on the GPU as `prep_tree!` over a tree with
one leaf of L items per lane (tail-recursive leaf walks: Bend 2.0.39 lanes fault past ~1,023
frames of non-tail recursion). The batch equation runs on CPU threads (M = 0), or on the GPU
with msm_fast's Pippenger (`msm_fast_pallas.bend`, copied from field3 with Pallas imports;
c = 8, 2^M chunks per window).

- **Apple Metal compiler bug workaround.** Non-inlined helper calls can corrupt a word of the
  caller's data. `build.sh` therefore makes every `noinline` device helper (`FAR`, and `DFAR`,
  which is `FAR` on the device) `always_inline` under `__METAL_VERSION__`. Forcing *all*
  helpers inline (`INLINE`/`OUTLINE` too) made the Metal compiler service crash
  (`XPC_ERROR_CONNECTION_INTERRUPTED` after ~3.5 min, twice, for both the full program and a
  preparation-only program), so those remain inline hints. The `.gpu` archive grows from
  3.3 MB to 29 MB.
- **Determinism gate** (`determinism.sh`): 20 runs at L = 1 and 20 at L = 4 on 3 real chunks
  plus a tampered one. The verdicts, bisection output and a digest of the preparation (leaf
  Merkle root, Σ(R_i + vk_i), Σ c_i) are compared bit for bit, against each other and against
  the CPU build. Results:
  - inlined build, CPU MSM: 40/40 identical and equal to the CPU build;
  - inlined build, GPU MSM (M = 4): 40/40 identical and equal to the CPU build;
  - the same program *without* the inlining fix: also 40/40 identical (no corruption
    reproduced on this program).
  Only numbers from the inlined, gated builds are reported above.
- **The GPU is not faster here.** Preparation on the inlined GPU build takes ~350 ms per chunk,
  about as long as 1 CPU thread (the build without the fix took ~60–170 ms, which is still
  slower than 18 threads at ~25 ms). Several things were tried and made it slower: forking the
  cv sum, [valueBalance]V and the two hashes inside each item; a constant-time square root,
  to remove SIMD divergence; and grouping spend-auth and binding items into separate lanes. So
  the GPU program keeps the simple per-item code. Unlike scan2's fixed ladder, this workload
  allocates many short lists per item (byte lists for BLAKE2b, point lists).
- The GPU MSM equation takes ~60 ms per chunk (c = 8, M = 4), against ~45 ms on 18 CPU
  threads. Bisection with the GPU MSM is slow (~5 s for one bad signature: many small GPU
  dispatches).

### In-process slowdown

When one process verifies many chunks, each chunk takes longer than the last. On 18 threads
it goes from 67 ms to ~200 ms after 150 chunks, and RSS stays at ~200 MB. The cause is the
same chunk getting slower (chunk 150 / 0 / 150 / 0 / 150 → 67 / 96 / 113 / 130 / 140 ms), not
the data. This looks like a Bend runtime effect (heap reuse/locality) and is not diagnosed
further. The benchmark therefore runs one process per chunk; verification time per chunk is
measured inside the process, as for Rust.

## Files

- `sig.bend`: parsing, preparation, weights, batch equation, bisection, GPU tree, digest
- `batch_main.bend` (CPU) and `batch_gpu.bend` (GPU preparation; MSM mode M): drivers that
  print per chunk `n`, `ms`, `prep_ms`, the number of good signatures and the invalid indices
- `msm_pallas.bend`, `msm_fast_pallas.bend`: Pallas copies of perf3's batch-affine MSM and
  field3's GPU Pippenger
- `build.sh` (forked Bend `u64-rot` worktree → C → clang, plus the Metal inlining patch),
  `bench.sh`, `determinism.sh`
- `oracle/`: extraction, Rust baseline, tampering
- `data/` (git-ignored): chunks, manifest, tamper files, benchmark logs (`bench_*.txt`,
  `bench_session.txt`)

```sh
(cd oracle && cargo build --release && ./target/release/sigbatch-oracle extract 8192)
../../tools/heavy.sh ./build.sh batch_main.bend batch_main
../../tools/heavy.sh ./build.sh batch_gpu.bend batch_gpu && ./batch_gpu +RTS --gpu-build -RTS
./batch_main 11 data/chunk_0000.bin                     # all valid: "invalid" list empty
./oracle/target/release/sigbatch-oracle tamper 0 s 5    # Rust: false
./batch_main 11 data/tamper_s_5.bin                     # "invalid 5"
../../tools/heavy.sh ./determinism.sh batch_gpu 20               # GPU gate
HEAVY_MAX_MIN=40 ../../tools/heavy.sh ./bench.sh                 # full table
```

Built with the forked Bend at `ad0523fa` (branch `u64-rot`: `U32.mac64` etc.), from a private
worktree (`../../../bend-fork-sig`).
