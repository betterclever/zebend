# gpu-scan: Ironwood trial decryption on the GPU, written in Bend

A light wallet learns which shielded outputs are its own by **trial-decrypting every
output on chain** with its incoming viewing key. Every output costs one variable-base
elliptic-curve scalar multiplication, so this is the dominant cost of wallet sync
(the "sync is slow" complaint on every Zcash forum thread), and it is embarrassingly
parallel. `gpu-scan` runs it on the Apple GPU (Metal) from pure Bend 2.

## What it computes

For each compact Ironwood output `(epk, enc_ciphertext[0..52])` and the wallet's `ivk`
(protocol spec §4.20, as implemented by `orchard` 0.16 / `zcash_note_encryption` 0.5.1):

1. decompress `epk` (Pallas, `y² = x³ + 5`): constant-time Tonelli–Shanks (p − 1 = 2³²·t)
2. `shared = [ivk]·epk`: 256-step double-and-add with the **complete** Renes–Costello–Batina
   formulas for a = 0 (Alg. 8 mixed add, Alg. 9 double), then `repr_P`
3. `K = BLAKE2b-256("Zcash_OrchardKDF", repr(shared) ‖ epk)`
4. ChaCha20 (RFC 8439, nonce 0, block counter 1, which skips the Poly1305 key block)
5. **filter:** plaintext lead byte `== 0x03` (Ironwood note plaintext version)

### Two-stage design
The GPU does the expensive part (steps 1–5) for **every** output and returns one bit.
About 1/256 of foreign outputs pass the lead-byte test by chance, so the candidates
(~2% of outputs in our vectors: the true notes plus the false positives) go to the CPU,
where `orchard` does the full check (diversifier → `g_d`, `pk_d`, note commitment).
That CPU step is cheap, and it is the same code wallets already run.

## Implementation

- `gen.py` generates `zcrypto.bend` (6.6k lines, 55 defs) as straight-line Bend:
  - **GF(p) on 16 × 16-bit limbs in Montgomery form.** Bend has only `U32`, and a
    16×16-bit product plus two 16-bit carries fits exactly in 32 bits. CIOS
    multiplication skips the 8 zero limbs of p; `−p⁻¹ mod 2¹⁶ = 0xFFFF`. Inversion
    and the square root use fixed addition chains.
  - **BLAKE2b with 64-bit words as `(lo, hi)` U32 pairs.** One def per round: a
    single straight-line def overflowed the Bend compiler's stack.
  - ChaCha20 quarter-rounds; only keystream word 0 is needed.
  - Every branch is uniform across lanes: the scalar is the wallet's `ivk`, the
    same for all outputs, and selects are masks.
- `scan_main.bend`: reads the batch, builds a balanced tree of 2^depth leaves
  (depth 14 = the 16,384-lane Metal cube), and `Z.scan!(...)` forks to the leaves,
  each a flat loop over its outputs.
- `vectors/` (Rust, orchard 0.16): generates batches of real `IronwoodNoteEncryption`
  outputs (~1.6% to our key, the rest to 8 other wallets), the expected filter hits,
  per-stage intermediates, and the CPU baseline.

## Correctness

- Field: mul, add, sub and inverse vs. pasta_curves, 16/16 (`t/field_test.bend`).
- Stages vs. orchard intermediates, 41/41 (`t/stage_test.bend`): `[ivk]·G`, the
  decompressed `y`, the ECDH shared secret, the KDF key, the keystream and the
  filter bit, for 8 records.
- Generator self-check: for every output, `orchard`'s
  `try_compact_note_decryption` must agree with the independent ECDH/KDF/ChaCha
  pipeline (all ours decrypt; lead byte 0x03).
- **Full batches:** the GPU hit list equals the expected hit indices exactly for
  N = 4,096, 16,384, 65,536 and 262,144 (100 / 299 / 1,300 / 5,215 hits), on
  Metal, on the CPU pool and on one thread, cold and warm (`bench.sh` prints MATCH).

## Benchmarks

Apple M5 Max (18 CPU cores, 40-core GPU), macOS 27.2, Bend 2.0.38, depth 14.
"Warm" is a second scan in the same process; the first ("cold") pays about 150–400 ms
of Metal start-up.

| Backend | N = 16,384 | N = 65,536 | N = 262,144 |
|---|---|---|---|
| **Bend, Metal GPU (warm)** | 87 ms · **188k/s** | 332 ms · **197k/s** | 1,231 ms · **213k/s** |
| Bend, Metal GPU (cold) | 487 ms | 496 ms | 1,406 ms |
| Bend, CPU pool (18 threads) | 810 ms · 20k/s | 3,298 ms · 20k/s | 17,276 ms · 15k/s |
| Bend, 1 CPU thread | 9,585 ms · 1.7k/s | 38,349 ms · 1.7k/s | not recorded |
| Rust (pasta_curves + blake2b_simd + chacha20), 1 thread | 1,550 ms · 10.6k/s | 6,180 ms · 10.6k/s | 24,980 ms · 10.5k/s |
| Rust (same), 18 threads | 126 ms · 130k/s | 491 ms · 133k/s | 2,256 ms · 116k/s |

The Rust baseline runs the same filter pipeline with the crates orchard builds on
(pasta_curves scalar multiplication, blake2b_simd, chacha20), not orchard's batch API,
which adds a wNAF-prepared ivk. Treat it as a strong CPU reference, not orchard's best case.

Takeaways:
- **The GPU path is ~20× one CPU core of optimized Rust and ~1.5× all 18 cores**,
  leaving the CPU free for the wallet. At ~200k outputs/s, one million outputs take
  about 5 s of GPU time.
- Bend's generated CPU code is 6× slower than pasta_curves' hand-tuned 64-bit
  arithmetic on one core. The GPU wins on width, not per-lane speed.
- Throughput saturates near 200k/s from 65k outputs up. Smaller batches leave lanes idle.

## Limitations

- Only the filter runs on the GPU. Full note validation stays on the CPU (by design, see above).
- `epk` canonicity is not checked on the GPU. A non-canonical or off-curve `epk` gives a
  wrong bit, which the CPU stage rejects. The decompression `ok` flag catches non-residues.
- Sapling and Orchard-pool (lead byte 0x02) outputs are not scanned; the change is one constant.
- Metal start-up (~150–400 ms) is paid once per process.
- The vectors are generated locally with orchard; they are not a mainnet replay. The batch
  format (epk + 4 ciphertext bytes) is what lightwalletd compact blocks carry, so a
  mainnet feeder is the obvious next step.
- Bend 2's compiler is young (its own README: "99% AI-written and not yet fully audited").
  The correctness evidence here is differential testing against orchard, not proof.

## Run

```sh
python3 gen.py zcrypto.bend && cp zcrypto.bend t/
(cd vectors && cargo run --release -- gen 65536)
bend scan_main.bend -o scan_main
./bench.sh 65536 14          # GPU, CPU pool, 1 thread, Rust baseline; checks every hit list
python3 mktest.py && bend t/stage_test.bend   # per-stage checks
```
