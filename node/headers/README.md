# node/headers: Zcash header chain, verified in Bend

Every check a node runs on a block header, written in Bend 2 and run on real mainnet
data: Equihash on the Metal GPU, and the difficulty-adjustment bounds proven as laws.

## Result

**128,280 real mainnet headers, heights 3,400,000 … 3,528,279** (spanning NU6.3 /
Ironwood activation at 3,428,143), verified entirely in Bend on an M5 Max:

```
$ ./verify data/mainnet.bin 128280 4276 12
headers 128280
equihash valid 128280/128280
hash <= target 128280/128280
prev-hash links 128279/128279
difficulty (nBits == expected) 128252/128252
verify time 52549 ms
```

The difficulty check needs the 28 previous headers, so it applies from the 29th header on.

| What | Status | Evidence |
|---|---|---|
| SHA-256d block hash | **tested** | identical to Rust (`sha2`) on all 128,280; 130/130 hashes match lightwalletd spot checks |
| hash ≤ target(nBits) | **tested** | identical to Rust on all 128,280 |
| prev-hash linkage | **tested** | 128,279/128,279; the P2P component's independently fetched 480 headers are byte-identical to ours |
| Equihash (200, 9) | **tested** | identical verdicts to the official Rust `equihash` crate on all 128,280 valid headers **and** 10 adversarial variants (flipped solution bits at 5 positions, swapped solution halves, changed nonce, changed time, harder nBits): all rejected by both |
| Difficulty adjustment | **tested** | the nBits Bend computes equals the nBits mainnet consensus produced, 128,252/128,252 |
| Difficulty timespan bounds | **proven** | 6 laws, `bend PROOF.bend` and `--verdict` (Lean-proven kernel): ALL PROOFS CHECK, no `@unsafe` |

## Proven laws (`LAWS.bend`, `PROOF.bend`)

These are stated about `D.timespan` / `D.clamp`, the functions `main.bend` executes, for **all** inputs:

- `timespan_ge_min` / `timespan_le_max`: whatever the block timestamps say, the bounded
  actual timespan stays within [1071 s, 1683 s] = [84%, 132%] of 1275 s. Difficulty can move at
  most PoWMaxAdjustUp = 16% / PoWMaxAdjustDown = 32% per block, the anti-time-warp guarantee.
- `on_schedule`: blocks exactly 75 s apart leave the timespan at 1275 s, so the target is only re-averaged.
- `clamp_ge_min`, `clamp_le_max`, `clamp_id`: the clamp is bounded, and the identity inside the bounds.

```
$ bend PROOF.bend            → ALL PROOFS CHECK
$ bend PROOF.bend --verdict  → ALL PROOFS CHECK
```

The 256-bit target arithmetic (sum of 17 targets, /17, /1275, ×timespan, powLimit, compact
re-encoding) is **tested, not proven**: it reproduces every mainnet nBits above.

## Throughput (M5 Max; machine shared with other work)

| Implementation | headers/s |
|---|---|
| Bend, Metal GPU, 4096 headers/batch, depth 12 (warm) | ~5,700 |
| Bend, Metal GPU, whole range (4276/batch: 180 lanes take 2 headers) | 2,441 |
| Bend, CPU, 18 threads (4096 headers) | 1,973 |
| Bend, CPU, 1 thread (1024 headers) | 757 |
| Rust `equihash` crate, 1 thread | 7,005 |
| Rust `equihash` crate, 18 threads (rayon) | 37,975 |

Bend on the GPU is about 0.8× one Rust core. Per header the work is 512 BLAKE2b-400
compressions (every solution index hashes a different `g`) plus 25 SHA-256 compressions, all as
interpreted U32 term reductions. The first GPU call in a process pays Metal setup. Depth 13
needs `+RTS --gpu 8GB` and was slower (3,800/s).

## How it works

- `gen.py` → `hashes.bend` (generated, 4,456 lines): BLAKE2b with full 128-byte blocks,
  64-bit words as U32 pairs, one def per round; SHA-256 in 4 × 16-round defs.
- `pow.bend`:
  - Block hash: SHA-256d over the 1487-byte header.
  - Target: compact nBits → 8 LE words; hash ≤ target.
  - Equihash:
    - BLAKE2b-400, personalized `ZcashPoW‖LE32(200)‖LE32(9)`. The first 128 header bytes are one shared midstate.
    - Each of the 512 indices costs one final-block compression of `header[128..140] ‖ LE32(x/2)`.
    - Unpack 21-bit indices.
    - Run the 9-level tree: each merge needs the next 20-bit chunk to collide and the left subtree's first index to be smaller. The root's last chunk must be zero.
    - Index distinctness is checked globally (sort, then no adjacent duplicates), which is equivalent to zcashd's per-merge disjointness.
- `diff.bend`: zcashd's `GetNextWorkRequired` / `CalculateNextWorkRequired`, post-Blossom mainnet.
  - Inputs: 17-block averaging window, median-time-past of 11.
  - The damped and clamped timespan runs on `Nat`. That's the proven part.
  - Targets use 16 × 16-bit limbs.
  - The signed MTP difference is capped at 100,000 s before damping. Any |actual| that large is clamped to the same bound anyway.
- `main.bend`:
  - Streams batches with `File.read_at` and builds a balanced tree with 2^d leaves.
  - `verify!` runs every header's self-contained checks on the GPU.
  - A sequential fold then checks linkage and difficulty.
- `oracle/`: Rust.
  - `fetch` pulls headers from live mainnet peers over P2P (version/verack + `getheaders`, protocol 170160; Zebra 7.0 / Zakura peers).
  - `check` runs the Rust reference (`sha2`, `equihash`, linkage, target, lightwalletd spot checks).
  - `lines` / `tamper` generate the comparison and adversarial inputs.

```sh
cd oracle && cargo build --release
PROTO=170160 ./target/release/headers-oracle fetch 3400000 140000 ../data/mainnet.bin   # stops at the tip
./target/release/headers-oracle check ../data/mainnet.bin 3400000
cd .. && bend main.bend -o verify && ./verify data/mainnet.bin 128280 4276 12
bend t/pow_test.bend data/tampered.bin 10      # vs: oracle lines data/tampered.bin 10
bend PROOF.bend --verdict
```

## Gaps

- Only 128,280 recent headers, not genesis to tip. The difficulty code has **post-Blossom
  constants only** (75 s spacing), so heights below Blossom (653,600) would need the
  150 s branch. NU7's 25 s spacing (ZIP 218) isn't implemented; it isn't active on mainnet.
- The difficulty check is against consensus-produced nBits rather than a second implementation.
  Every match equals the value Zebra/zcashd computed, but a Rust `GetNextWorkRequired` oracle wasn't built.
- Header fields beyond PoW and linkage (merkle root, `hashBlockCommitments`, time vs. MTP and
  future-drift rules, version) aren't checked. They need transaction data or a local clock.
- Testnet's minimum-difficulty rule isn't modeled (mainnet only).
- Proven = the timespan bound laws. Hashing, Equihash and target arithmetic are differential-tested.
