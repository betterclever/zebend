# zcash/sapling/groth16: Groth16 on BLS12-381 in Bend

This directory holds the verifier for the Groth16 proofs in Sapling Spend and Output
descriptions and in post-Sapling Sprout JoinSplits. It is written in Bend 2 (the forked
compiler, `U32.mac64`) and differentially tested against the official Rust code: `groth16`
0.2 (the verifier that `sapling-crypto` 0.9 and `zcash_proofs` 0.31 call) on `bls12_381` 0.9.

No Rust is linked into the Bend side. Rust appears only as the oracle (`oracle/`).

Status (Oct 26, 2026): the verifier works on real mainnet data. Every number below came from
the command shown with it, on an Apple M5 Max that other agents' jobs were also using.

## What verifies

**61,168 distinct real mainnet Groth16 proofs** (21,476 Sapling spends, 39,623 Sapling outputs,
69 Sprout JoinSplits), from heights 419,201 to 3,529,205 (Sapling activation to Oct 2026).
Each has one tampered copy. Bend's verdict equals the official one on every record, by all three
Bend paths:

| Set | Real records | Tampered | Single (`verify_main`) | Inputs computed in Bend (`verify_raw_main`) | Batch (`batch_main`) |
|---|---|---|---|---|---|
| `real`: every Sapling description in the 366,418 post-NU6.3 txs of `proofsets` (heights 3,428,144–3,529,855) | 18,523 (3,270 spend, 15,253 output) | 18,523 | 37,046/37,046 | 37,046/37,046 | 37,046/37,046, + `mixed` 18,523/18,523 |
| `old`: 29 windows of 2,000 blocks from 419,200 to 3,401,999, up to 400 Sapling txs each, txs with spends first, ≤ 8 outputs per tx | 30,420 (14,446 / 15,974) | 30,420 | 60,840/60,840 | 60,840/60,840 | 60,840/60,840 |
| `mig`: 23 windows of 1,000 blocks from 600,000 to 1,175,999 (ZIP 308 Sprout→Sapling migration era), output-only txs first | 13,212 (4,327 / 8,816 / **69 Sprout**) | 13,212 | 26,424/26,424 | 26,424/26,424 | 26,424/26,424 |

That is 0 disagreements in 391,453 comparisons. 987 `mig` records repeat `old` ones, because
some windows overlap. The 61,168 count above has the repeats removed.

The **rejection stage** also matches in every case. Rust's stages are: description fields
rejected / `Proof::read` failed / `verify_proof` failed. Bend's are: fields rejected / point
decoding failed / pairing check failed. For example (`python3 diff.py real tamper`):

```
real: 18523 records (3270 spend, 15253 output, 0 Sprout JoinSplit); official valid 18523, Bend valid 18523; agree 18523/18523, disagree 0; stage disagree 0
tamper: 18523 records (3270 spend, 15253 output, 0 Sprout JoinSplit); official valid 0, Bend valid 0; agree 18523/18523, disagree 0; stage disagree 0
   tag  1 random bit flip      1853 records, official valid 0, rejected: decode 1848 / pairing 5; disagree 0 (stage 0)
   tag  2 A sign flip          1853 records, official valid 0, rejected: decode 0 / pairing 1853; disagree 0 (stage 0)
   tag  3 input + 1            1853 records, official valid 0, rejected: decode 0 / pairing 1853; disagree 0 (stage 0)
   tag  4 A<->C swap           1852 records, official valid 0, rejected: decode 0 / pairing 1852; disagree 0 (stage 0)
   tag  5 A off-subgroup       1852 records, official valid 0, rejected: decode 1852 / pairing 0; disagree 0 (stage 0)
   tag  6 B off-subgroup       1852 records, official valid 0, rejected: decode 1852 / pairing 0; disagree 0 (stage 0)
   tag  7 B sign flip          1852 records, official valid 0, rejected: decode 0 / pairing 1852; disagree 0 (stage 0)
   tag  8 A x >= p             1852 records, official valid 0, rejected: decode 1852 / pairing 0; disagree 0 (stage 0)
   tag  9 A = infinity         1852 records, official valid 0, rejected: decode 1852 / pairing 0; disagree 0 (stage 0)
   tag 10 other proof          1852 records, official valid 0, rejected: decode 0 / pairing 1852; disagree 0 (stage 0)
```

### Ground truth

- **Proofs.** `oracle extract` parses each transaction with `zcash_primitives` 0.31 (v4 and v5).
  The `real` set uses `../../../research/proofsets/data/raw.bin` (read only). `old` and `mig` come from
  `oracle fetch`: lightwalletd compact blocks with the Sapling pool, then `GetTransaction`,
  through the zec.rocks mirrors as `proofsets` does. All extracted proofs are used. Every
  real proof is valid per Rust, as consensus requires.
- **Official verdict, inputs given.** The oracle computes the public inputs with the same calls
  `sapling-crypto`'s `check_spend` / `check_output` make (rk, cv affine u, v; anchor; the two
  multipacked nullifier scalars; epk; cmu). For Sprout it packs them as
  `zcash_proofs::sprout::verify_proof` does and asserts that function's verdict. Then
  `groth16::Proof::read` (compressed points, subgroup checks, identity rejected) and
  `groth16::verify_proof` with the prepared VK. Sprout's h_sig is BLAKE2b-256
  ("ZcashComputehSig"), computed by the oracle as zcashd does before calling
  `zcash_proofs`. That every real JoinSplit verifies confirms it.
- **Official verdict from raw fields** (`*_raw` sets): the oracle starts from the bytes, using
  zcash_primitives' field parsing (`ValueCommitment::from_bytes_not_small_order`, `read_base`,
  redjubjub `VerificationKey::try_from`, `ExtractedNoteCommitment::from_bytes`), then
  `check_spend` / `check_output`'s rk / epk decoding and small-order rejection, then the proof.
- **Verifying keys** are read from the official `sapling-spend.params`,
  `sapling-output.params` (SHA-256 `8e48ffd2…`, `2f0ebbcb…`) and `sprout-groth16.params`
  (BLAKE2b-512 `e9b23841…`, equal to `zcash_proofs`' `SPROUT_HASH`).

### Tampered copies (one per real record)

Tags 1–10 apply to every set and tags 11–15 to the `_raw` sets:

| Tag | Tamper | Rust rejects at |
|---|---|---|
| 1 | flip one random bit of the 192-byte proof | decoding, except 22 of 10,361 that still decode and fail the pairing |
| 2, 7 | flip A's / B's sign bit (a valid point, wrong proof) | pairing |
| 3 | input + 1 (raw sets: anchor / cmu + 1; Sprout: a cm1 bit) | pairing |
| 4, 10 | swap A and C; another record's proof | pairing |
| 5, 6 | A / B := an on-curve point outside the prime-order subgroup (G1 / G2) | decoding |
| 8, 9 | A's x ≥ p (non-canonical); A = point at infinity | decoding |
| 11, 12 | flip a bit of cv; of rk (spend) / epk (output). Sprout: rt; randomSeed (changes h_sig) | fields (about half) or pairing |
| 13 | rk / epk := the identity (small order). Sprout: a joinSplitPubKey bit | fields (Sprout: pairing) |
| 14 | anchor / cmu := a value ≥ r (non-canonical). Sprout: a mac1 bit | fields (Sprout: pairing) |
| 15 | flip a bit of nf (spend) / cmu (output). Sprout: vpub_old + 1 | pairing (a cmu flip can make it non-canonical: fields) |

All tampered records are invalid per Rust. For batch verification, `mixed` (`mkmixed.py`) is the
`real` set with every 97th record replaced by its tampered copy. It checks that a batch containing
one bad proof fails and that the per-proof fallback singles that proof out.

## Every layer, against ground truth

| Layer | Test | Result |
|---|---|---|
| Fq (6×64-bit Montgomery): mul, sqr, add, sub, neg, inv, √, canonical test, sign | `t/fq_test.py 20000`: 19 edge values in all pairs + 20,000 random pairs (non-canonical raw inputs < 2^383 included) vs Python integers | 20,361 × 9 ops, 0 mismatches |
| Fq2 / Fq6 / Fq12: mul, sqr, inv, √ (Fq2), Frobenius, conjugate, sparse `mul_by_014` | `t/tower_test.py 300` vs `ref/bls.py` | 900/900 op groups |
| G1 / G2 decoding, [s]P, Miller loop, pairing of random points | `t/pair_test.py 8 11` vs the **bls12_381 crate** (`oracle vectors`) | 40/40 |
| Real proofs: acc = IC0 + Σ inputᵢ·ICᵢ, the 3-term Miller loop, final exponentiation | `t/ml_test.py 20 mig_real real old_real` vs the crate (`oracle dump`), Sprout records included | 180/180 |
| Sprout public inputs (BLAKE2b h_sig + bit packing) computed in Bend | `t/sprout_test.py mig_real`: Bend vs the oracle's packing vs Python hashlib | 69/69 |
| `ref/bls.py`, the Python model used for the tower tests | `python3 ref/bls.py selftest` vs the crate: decoding, [s]P, Miller loops, pairings, real-proof dumps | 32/32 |
| Groth16 verdicts | `diff.py` (above) | 391,453/391,453 |

The Miller loop reproduces the crate step by step: the same doubling/addition formulas and
line scaling. Its outputs are bit-identical, not just equal after the final exponentiation.
That makes bisection with `oracle dump FILE IDX` possible.

## Speed

`python3 bench.py SET REPS`: the same records, interleaved repetitions, medians. All proofs
were valid in every run. Rust is the official crates in release mode, with rayon pools of 1 and 18.

`real` (18,523 proofs: 3,270 spend, 15,253 output), 3 reps, load average 7.0 → 9.9:

| | 1 thread | 18 threads |
|---|---|---|
| Rust: `Proof::read` + `verify_proof` per proof (rayon over proofs) | 2.095 ms/proof (477/s) | 0.164 ms (6,081/s) |
| **Bend `verify_main`** (per proof: decode, MSM, Miller loop, final exp) | **1.782 ms** (561/s) | **0.150 ms** (6,675/s) |
| Rust: `groth16::batch::Verifier::verify_multicore`, one batch per kind | 0.844 ms (1,185/s) | 0.299 ms (3,340/s) |
| Rust: `batch::Verifier::verify`, chunks of 128 in parallel (as Bend) | 0.892 ms (1,121/s) | 0.073 ms (13,741/s) |
| **Bend `batch_main`** (chunks of 128, batch per kind) | **0.666 ms** (1,501/s) | **0.066 ms** (15,233/s) |

A rerun on `real` with the final binaries (3 VKs, Sprout kind; `data/bench_real_final.txt`, load 7.9 → 12.3):
Rust single 2.342 / 0.182 ms, Bend single 1.808 / 0.159 ms, Rust batch chunks 0.897 / 0.076 ms,
Bend batch 0.708 / 0.067 ms (1 / 18 threads). It is consistent with the table above.

`old_real` (30,420 proofs: 14,446 spend, 15,974 output), 2 reps, load average 8.1 → 15.9:

| | 1 thread | 18 threads |
|---|---|---|
| Rust single | 2.230 ms (448/s) | 0.177 ms (5,657/s) |
| **Bend single** | **1.753 ms** (570/s) | **0.156 ms** (6,411/s) |
| Rust batch, `verify_multicore` | 0.813 ms (1,229/s) | 0.301 ms (3,324/s) |
| Rust batch, chunks of 128 | 0.932 ms (1,073/s) | **0.067 ms** (14,832/s) |
| **Bend batch**, chunks of 128 | **0.672 ms** (1,489/s) | 0.081 ms (12,288/s) |

Bend is 1.2–1.4× faster than the official Rust on one thread. On 18 threads, single verification
is 1.1× faster. Batch verification is within ±20% of Rust's chunked batch either way: faster on
`real`, slower on `old_real` (that run had load 16 from other jobs). The reasons are specific:

- `bls12_381` is constant-time. `G1Projective * Scalar` runs 255 doublings and 255
  additions whatever the scalar. Verification data is public, so Bend uses variable-time
  algorithms. The public-input MSM is a 4-bit Straus over tables of 15 multiples of each IC point,
  built once per VK. Faster Rust libraries exist (blst); this compares against the code Zcash
  nodes run through `sapling-crypto` / `zcash_proofs`.
- Bend's batch weights are 128-bit; `groth16` draws full 255-bit scalars. That halves z·A and
  z·C, at the usual soundness (error ≤ 2^-128).
- The field arithmetic itself is not faster. The Miller loop and final exponentiation follow the
  crate step for step.

History: with a double-and-add MSM, single verification ran at 2.30 ms/proof against Rust's 2.20
(first 5,000-proof sample).

## How it works

| File | What |
|---|---|
| `gen_fq.py` → `fq.bend` | Fq: no-carry CIOS Montgomery multiply over 6×64-bit limbs via `U32.mac64` (p's top limb < 2^63 − 1), branch-free add/sub/select, canonical test, window-5 exponent chains split into small defs |
| `gen_tower.py` → `fq2.bend`, `fq6.bend`, `fq12.bend` | the crate's tower (u² = −1, v³ = u + 1, w² = v): Karatsuba, Chung–Hasan squaring, sparse `mul_by_01/1/014`, Frobenius constants, Fq2 √ (eprint 2012/685 Alg. 9) |
| `gen_curves.py` → `g1.bend`, `g2.bend` | complete projective formulas (RCB 2015, incl. mixed addition), decoding as `from_compressed` (flags, canonical coordinates, √, sort bit) with the crate's subgroup tests: G1 φ(P) = −[x²]P, G2 ψ(P) = [x]P |
| `gen_pairing.py` → `pairing.bend` | Miller loop schedule over \|x\|, the crate's `doubling_step` / `addition_step` / `ell`, G2 preparation, 3-term multi Miller loop, the crate's final exponentiation |
| `groth16.bend` | VK preparation (e(α,β); lines of −γ, −δ, −β; IC tables), Straus MSM, decoding, single verification |
| `inputs.bend` | Sapling public inputs from raw description fields (imports `../jubjub`, read-only) |
| `sprout_inputs.bend` | Sprout public inputs: h_sig (imports `../../tx/blake2b.bend`, read-only) + multipacking |
| `batch.bend` | batch verification: one multi Miller loop with on-the-fly B_j lines and three prepared fixed terms, one final exp, Fr combination of inputs (`../jubjub/fr.bend`) |
| `verify_main.bend`, `verify_raw_main.bend`, `batch_main.bend` | drivers: parse record files, balanced parallel tree, verdict digits |
| `enc.bend`, `io.bend` | proof point parsing, file reading, hex output |
| `diff.py`, `bench.py`, `mkmixed.py`, `t/run_all.sh` | differential test, timing, the `mixed` set, every check in order |
| `oracle/` | Rust: `vk`, `extract`, `fetch`, `dump`, `bench`, `vectors` |
| `ref/bls.py` | exact Python model of the crate (checked against it), source of constants and tower vectors |
| `t/` | per-layer tests |
| `data/` (gitignored, ~1 GB with the 725 MB Sprout params) | params, VKs, raw txs, record sets, official verdicts, logs |

Record files (oracle → Bend): u32 kind (0 spend, 1 output, 2 Sprout), u32 tag, the
192-byte proof as on chain, then either the 7 / 5 / 9 public inputs (32-byte canonical Fr) or
the raw fields (spend cv | anchor | nf | rk; output cv | cmu | epk; Sprout rt | randomSeed |
nf1 | nf2 | mac1 | mac2 | cm1 | cm2 | joinSplitPubKey | vpub_old | vpub_new).
`verify_main` prints one digit per record: 1 valid, 0 rejected at point decoding, 2 rejected by
the pairing check, 3 (raw) fields rejected.

Rebuild and rerun everything:

```sh
cd zcash/sapling/groth16
(cd oracle && cargo build --release)
(cd data && curl -O https://download.z.cash/downloads/sapling-spend.params -O https://download.z.cash/downloads/sapling-output.params \
         -O https://download.z.cash/downloads/sprout-groth16.params)
oracle/target/release/groth16-oracle vk
../../../tools/heavy.sh oracle/target/release/groth16-oracle extract 1000000000 1000000000           # real_*, tamper_*
oracle/target/release/groth16-oracle fetch 419200,450000,500000,550000,600000,650000,700000,750000,800000,900000,1000000,1100000,1200000,1300000,1400000,1500000,1600000,1700000,1720000,1800000,1900000,2000000,2200000,2400000,2600000,2800000,3000000,3200000,3400000 2000 400 16 data/raw_old.bin
MAX_O_PER_TX=8 ../../../tools/heavy.sh oracle/target/release/groth16-oracle extract 1000000000 1000000000 4242 data/raw_old.bin old_
FETCH_PREFER=outputs oracle/target/release/groth16-oracle fetch 660000,700000,750000,800000,850000,900000,950000 1000 250 16 data/raw_mig.bin
FETCH_PREFER=outputs oracle/target/release/groth16-oracle fetch 600000,625000,650000,675000,725000,775000,825000,875000,925000,975000,1025000,1050000,1075000,1125000,1150000,1175000 1000 400 16 data/raw_mig2.bin
cat data/raw_mig.bin data/raw_mig2.bin > data/raw_migall.bin
MAX_O_PER_TX=8 ../../../tools/heavy.sh oracle/target/release/groth16-oracle extract 1000000000 1000000000 77 data/raw_migall.bin mig_
python3 gen_fq.py && python3 gen_tower.py && python3 gen_curves.py && python3 gen_pairing.py
t/run_all.sh        # final state: every check passed (data/run_all.log)
HEAVY_MAX_MIN=40 ../../../tools/heavy.sh python3 bench.py real 3
```

`fetch` samples the chain as it is served. The tx set per window is fixed by the cap and the
spend-first / output-first ordering (then height order).

## Bend notes

- A function's parameters (and an unboxed record's fields) are flattened into U32 words, and
  the compiler caps that at 247. An Fq12 is 144 words, so `mul(a, b: Fq12)` would not
  compile. `Fq6`, the Miller loop's term record (`Ps`) and the batch's fixed terms (`Fx`) carry
  a never-built self-referencing constructor (`Fq6B`, `PsB`, `FxB`). That makes Bend store them
  boxed (one word), and each of their destructurings is a `match` with a fallback arm.
- `fq.bend`'s `from_raw` is exact for raw values < 2^383. Every caller passes < 2^381
  (coordinates with the flag bits masked) or checks `lt_p` first: G2's second coordinate can
  be up to 2^384 − 1, and `lt_p` rejects it before the `from_raw` result is used.
- Bug found by the differential test and fixed: the first `verify_raw_main` run disagreed on
  all 31 Sprout records of a first migration sample. Bend packed vpub_new together with the
  next record's bytes (a missing `take`). `t/sprout_test.py` now checks the packing directly.

## Missing / open

- **Sprout sample is small (69 JoinSplits).** Lightwalletd's compact blocks do not show
  JoinSplits, so they were found only through migration txs that also have Sapling outputs. Pure
  Sprout transactions after Sapling activation are not in the sample.
- The raw fields come from the oracle's parse of the transaction. Bend does not parse v4/v5
  transactions here (`../tx` is the Sapling workstream's parser).
- This is proof verification only. Spend-auth and binding signatures and value balance are
  `../sig`'s work.
- `old` and `mig` are samples (capped per window), not every Sapling proof in history.
- Every function is tested differentially; none is proven. No Metal.
