# transparent/: Zcash transparent-input validation in Bend

Everything a node needs to decide whether a transparent input may spend the output it points
at, written in Bend 2 (forked compiler, `U32.mac64`), checked differentially against the
official Rust code:

| Part | Files | What |
|---|---|---|
| secp256k1 | `secp/gen_secp.py` → `fe.bend`, `sc.bend`, `gtab.bend`; `secp/ec.bend` | base field (4×64-bit limbs, special-form reduction with 2^256 ≡ 2^32+977), scalar field (Montgomery, CIOS), inversion and square-root addition chains (libsecp256k1's), public-key decoding exactly as `secp256k1_ec_pubkey_parse` (02/03 compressed, 04 uncompressed, 06/07 hybrid; x, y < p; on curve), Jacobian arithmetic with every special case, ECDSA verification (Strauss–Shamir 4-bit windows, x-check without inversion incl. the r+n < p case) |
| hashes | `script/gen_hash.py` → `script/rmd_sha1.bend`; `../node/block/sha256.bend` | RIPEMD-160, SHA-1, SHA-256 (reused), HASH160, HASH256 |
| sighash | `sighash/sighash.bend` | legacy v1/v2 (zcashd `SignatureHash`, SHA-256d), ZIP 143 (v3), ZIP 243 (v4) with the raw hash-type byte, ZIP 244 transparent part (v5, v6) with Zebra's rules (hash types 01 02 03 81 82 83 only; SIGHASH_SINGLE needs an output); all hash types incl. ANYONECANPAY; mainnet branch-id table by height |
| interpreter | `script/core.bend`, `script/interp_head.bend` + `interp_tail.bend` → `script/interp.bend` (`gen_interp.py` adds the opcode dispatch) | `zcash_script` 0.6's interpreter: every opcode it accepts, disabled opcodes (fail anywhere, incl. OP_CODESEPARATOR), bad opcodes (fail when executed; VERIF/VERNOTIF always), 520-byte pushes, 10,000-byte scripts, 201 operations, 1,000 stack+altstack items, IF/NOTIF/ELSE/ENDIF, script numbers (4 bytes; 5 for CLTV), BIP66 strict DER (consensus), CHECKSIG / CHECKMULTISIG (with the dummy element), CHECKLOCKTIMEVERIFY, P2SH, and all 9 flags (P2SH, STRICTENC, LOW_S, NULLDUMMY, SIGPUSHONLY, MINIMALDATA, DISCOURAGE_UPGRADABLE_NOPS, CLEANSTACK, CHECKLOCKTIMEVERIFY). Mainnet consensus uses P2SH \| CHECKLOCKTIMEVERIFY (= 513) at every height, as Zebra and zcashd do |
| driver | `tv_main.bend` → `tv` | reads records, gates each transaction through `node/wire/txv.bend` (the hardened v1–v6 validator), prints one verdict per input |

Ground truth: `oracle/` (see its README): zcash_script 0.6 (+ zcashd's C++ interpreter via libzcash_script 0.2 as a second oracle, 100% agreement) with zcash_primitives 0.31 sighashes under Zebra 14's callback rules; the v1/v2 legacy sighash is the oracle's own re-implementation of zcashd's, validated by every real v1/v2 signature verifying under it.

## Results

### Building blocks (differential, Bend vs reference)

| Check | Reference | Result |
|---|---|---|
| base field: mul, sqr, add, sub, neg, inv, sqrt candidate (`secp/t/field_check.py`) | exact Python integers | 20,000 pairs (incl. all 361 pairs of 19 edge values: 0, 1, p−1, (p±1)/2, 2^32, 2^256 boundaries, …) × 7 ops: **0 mismatches** |
| scalar field: Montgomery mul, inversion | exact Python integers | 20,000 pairs × 2 ops: **0 mismatches** |
| public-key decoding + ECDSA verify (`secp/rust` → `secp/t/secp_t`) | libsecp256k1 via rust `secp256k1` 0.33 (`PublicKey::from_slice`, `normalize_s`, `ecdsa::verify`), as zcash_script calls it | 32,000 cases (compressed / uncompressed / hybrid keys, wrong-parity hybrid, x ≥ p, off-curve, bad lengths and prefixes, high S, flipped message / r / s bits, r or s = 0 or ≥ n, message ≥ n, wrong key; 10,000 valid): verdicts and decoded points **identical** on all 32,000 |
| RIPEMD-160, SHA-1, SHA-256, HASH160, HASH256 (`script/t/hash_check.py`) | `hashlib` + a reference RIPEMD-160 checked on the standard vectors | 1,009 messages (0–600 bytes incl. every padding boundary) × 5: **0 mismatches** |

### Interpreter: differential fuzzing against zcash_script 0.6 (`fuzz/`)

`fuzz/` (Rust) builds synthetic v4 (Canopy height) and v5 (NU6 height) transactions with 1–3
inputs, each from a template signed with real keys (P2PKH, P2PK, bare multisig m-of-n incl.
0-of-n and out-of-order signatures, P2SH multisig, P2SH single-key, CHECKLOCKTIMEVERIFY with
lock times around the transaction's, hash locks over all five hash opcodes, IF/ELSE, numeric
puzzles incl. non-minimal encodings, all 1,046 of zcash_script's own test vectors, random
scripts), random hash types (valid and invalid ones, high-S signatures sometimes, compressed /
uncompressed / hybrid keys), then mutates them (bit flips, inserted opcodes, deleted bytes,
truncation, appended/prepended script, hash-type byte). Flags: 60% mainnet (P2SH|CLTV), 40% a
random subset of all nine (CLEANSTACK forces P2SH, as zcash_script requires). The verdict of
each input is zcash_script 0.6's `Raw::eval` with a `CallbackTransactionSignatureChecker`
whose sighash is zcash_primitives 0.31's, under Zebra 14's callback rules.

| Set | Records | Inputs | Valid (oracle) | Mismatches |
|---|---:|---:|---:|---:|
| zcash_script test vectors (their own flags) | 1,046 | 1,046 | 568 | **0** |
| templates, 60% mutated (seeds 1–51) | 202,000 | 403,770 | 151,252 | **0** |
| templates, all mutated 1–4 times (seeds 101–125) | 100,000 | 199,903 | 23,113 | **0** |
| **total** | **303,046** | **604,719** | **174,933** | **0** |

Bend: 48 s of process time for the 604,719 inputs (80 µs per input, 14 processes, peak RSS 47 MiB).

### Mainnet: every transparent input of 30,853 real transactions, all eras

`run_diff.py data/real` (Bend `tv` vs `tv-oracle` verdicts), `sighash_check.py data/real`
(Bend `sh` vs the sighash values zcash_primitives / the legacy oracle fed to zcash_script):

| Era (heights sampled at random, seed 20261026) | Tx versions | Inputs | Valid (oracle) | Valid (Bend) | Mismatches |
|---|---|---:|---:|---:|---:|
| pre-Overwinter | v1 11,362 · v2 491 (116 txs with JoinSplits) | 11,853 | 11,853 | 11,853 | 0 |
| Overwinter | v3 | 12,021 | 12,021 | 12,021 | 0 |
| Sapling | v4 | 11,938 | 11,938 | 11,938 | 0 |
| Blossom | v4 | 12,409 | 12,409 | 12,409 | 0 |
| Heartwood | v4 | 12,763 | 12,763 | 12,763 | 0 |
| Canopy | v4 | 12,239 | 12,239 | 12,239 | 0 |
| NU5 | v4 10,512 · v5 1,141 | 11,653 | 11,653 | 11,653 | 0 |
| NU6 | v4 8,428 · v5 3,165 | 11,593 | 11,593 | 11,593 | 0 |
| NU6.1 | v4 5,803 · v5 5,731 | 11,534 | 11,534 | 11,534 | 0 |
| NU6.2 | v4 7,308 · v5 4,213 | 11,521 | 11,521 | 11,521 | 0 |
| NU6.3 | v4 5,793 · v5 3,126 · v6 2,703 | 11,622 | 11,622 | 11,622 | 0 |
| **total** | | **131,146** | **131,146** | **131,146** | **0** |

- Sighashes: **140,366 / 140,366** equal (every signature check the interpreter made on the
  real set; legacy, ZIP 143, ZIP 243, ZIP 244 v5 and v6).
- Script types: P2PKH 125,634 compressed + 254 uncompressed keys; P2SH 5,228 (4,582 2-of-3 and
  57 2-of-2 multisig, 2 P2SH-P2PK, 587 other redeem scripts incl. 23 with
  CHECKLOCKTIMEVERIFY hash locks); P2PK 30. **No bare multisig was found in the sample**; bare
  multisig is covered by fuzzing only.
- Hash types on chain: 01 everywhere, 03 (Sapling to NU5), 81 and 83 (NU6.x); 833 SIGHASH_SINGLE
  signatures with no matching output (v4, ZIP 143 zero hashOutputs), all valid in both.

### Tampered mainnet transactions (`data/tampered`, one mutation each)

5,400 records / 23,301 inputs: r or s bit flips, hash-type byte, output amount, lock time,
spent amount, scriptPubKey hash, swapped multisig keys, pubkey bit flips, sequence, prevout
index, P2SH flag off. Oracle: 11,274 invalid, 12,027 valid (other inputs of the same tx, the
v1/v2 amount case, P2SH-off). Bend: **identical on all 23,301 inputs**.

### fullnode hook

`t/hook_test.py` on 7 real chunks (pre-Overwinter, Overwinter, Sapling, Canopy, NU5, NU6.1,
NU6.3): 1,050 real transactions → `PASS`; 1,050 copies with one bit of r flipped in the first
input's first signature → `FAIL`, except 7 NU6.1 transactions whose first input is a P2SH
"ord"-style script whose first push is unsigned data: those stay `PASS`, and zcash_script also
accepts them (checked with `tv-oracle check`: identical verdicts on all 200 tampered copies).

### Speed (M5 Max, one process, one thread, same 86 files, `bench.sh`)

| | Bend `tv` | Rust oracle (zcash_script + zcash_primitives + libsecp256k1) |
|---|---|---|
| 131,146 real inputs | 25.5 s (194 µs/input) | 3.6 s (27 µs/input) |
| one ECDSA verification | ~60–80 µs (estimate from the inputs above) | 15.7 µs (`secp-vectors bench`) |

Bend is ~7× slower. Not done: a GLV / wNAF / larger fixed-base table for secp256k1 (the
Strauss–Shamir loop is 256 doublings + 128 additions), a dedicated legacy sighash cache.

### Speed round 2 (`tv.new`: 1.3× faster per input, 1.4–1.5× throughput; the 3–5× goal was not reached)

The new binary is `tv.new`, built from `tv2_main.bend`. `tv`, `hook.py` and the round-1 sources
(`secp/`, `script/`, `sighash/`, `tv_main.bend`) are unchanged. The new sources are copies with
edits: `secp2/` (generator `gen_secp2.py`), `script2/`, `sighash2/`, `sh2_main.bend`. The swap
steps are in `DEPLOY_FAST.md`. One heavy slot rebuilds everything and reruns every test:
`../heavy.sh secp2/build_and_test.sh`.

**1. Profile of round-1 `tv`.** The input is `secp2/prof/big.ztv` (`mk_inputs.py`): every
4th file of `data/real`, 7,928 records, 28,679 inputs. Two methods were used:

- Stub builds (`secp2/prof/mkvar.py`, `build_vars.sh`). Each build replaces one more stage by
  a constant. The stage cost is the difference in CPU cycles (`/usr/bin/time -l`, best of 3,
  load ~12–15).
- macOS `sample` on a build whose specialized C helpers carry their Bend names
  (`mk_named_compiler.sh` makes a patched private copy of the compiler; the fork is untouched).

| Stage (round-1 `tv`) | Gcycles | Share |
|---|---:|---:|
| ECDSA: verify (u1 G + u2 Q, scalar inverse, x-check) + key decoding ¹ | 11.0 | 36% |
| sighash (legacy SHA-256d, ZIP 143/243/244 BLAKE2b, per-tx digests) | 5.0 | 17% |
| script interpreter + HASH160 etc. | 3.5 | 12% |
| wire validator `node/wire/txv` (incl. Pallas/Jubjub point checks) | 3.5 | 11% |
| record parsing, byte-list handling, I/O | 7.4 | 25% |
| total | 30.2 | |

¹ Key decoding could not be separated from verification (the difference was below noise).

The sampler showed something across all stages. 35–39% of all samples were in the runtime's
`term_drop` / `span_fade` / `rfc_wrap`, the atomic reference-count traffic of walking shared
byte lists. Two list-walking hot spots were quadratic:

- SHA-256 (`node/block/sha256.bend`) and RIPEMD-160/SHA-1 (`script/rmd_sha1.bend`) read each
  of a block's 16 words with its own `drop` from the block start: 480 extra cells per 64-byte
  block. This dominated pre-Overwinter inputs, whose legacy sighash hashes the whole
  transaction once per signature.
- The v5/v6 sighash located the shielded bundles with `T.parse`. `T.parse` re-walks the
  transaction from its first byte for every input and output.

**2. What changed.**

| Change | Where |
|---|---|
| GLV endomorphism: u1, u2 each split into two ~128-bit halves (libsecp256k1's `split_lambda` constants, `mul_shift_384` rounding); halves above (n−1)/2 are negated and the sign moved to the digits | `secp2/ec.bend` `split`, `mag`; `secp2/sc.bend` (generated) |
| wNAF: width 8 for G and λG from a constant table of 64 odd multiples of G (dense `match`es → constant arrays; λG = (βx, y) costs one field multiplication), width 5 for Q and λQ (8 odd multiples per call, Jacobian, λQ by β) | `secp2/gtab.bend`, `secp2/ec.bend` `wnaf`, `odd_go` |
| One Strauss loop for all four expansions: the digit lists are merged by position and the accumulator is doubled only between events (~129 doublings instead of 256; ~43 Q additions + ~28 G additions instead of ~60 + ~60) | `secp2/ec.bend` `merge`, `evloop` |
| Scalar inversion by a fixed addition chain (x^(2^k−1) runs + width-5 sliding window; 256 squarings, 49 multiplications) with a dedicated Montgomery squaring; it replaces 4-bit windows over lists (256 squarings + 64 multiplications + list lookups) | `secp2/scinv.bend`, `secp2/sc.bend` `sqr` |
| One-pass field subtraction (`F.sub`); one-pass 32-byte big-endian reads (`from_be`) for keys, r, s and the message | `secp2/fe.bend`, `secp2/gen_secp.py` |
| SHA-256, RIPEMD-160 and SHA-1 read each 64-byte block in one pass and carry the rest of the list (compression functions unchanged) | `sighash2/sha256.bend`, `script2/rmd_sha1.bend` (`secp2/gen_hash2.py`) |
| v5/v6 sighash: Sapling/Orchard/Ironwood digests are read from the bytes after the transparent outputs, which the parser already has, instead of `T.parse(tx)` | `sighash2/sighash.bend` `mk_z` |

The acceptance rules are unchanged:

- key parsing and the x-check are the round-1 code (exact libsecp256k1 rules: 02/03/04/06/07
  keys, x, y < p, on curve, hybrid parity; r + n < p);
- DER, LOW_S, STRICTENC and the hash-type rules sit in `script2/core.bend`, which is
  text-identical to `script/core.bend` apart from its imports.

Not done:

- a larger G table: the compiler needs ~0.6 MB per `match` arm, and the 64-point table already
  takes the `secp_t` build to 1.2 GB;
- "effective affine" Q tables: the estimated gain is ~2% of total time;
- a safegcd inversion;
- batch inversion across inputs: inversions are ~4% of time now.

**3. Exactness (all on the final binaries, `secp2/run_tests.sh`, logs in `secp2/logs/`).**

| Check | Result |
|---|---|
| real mainnet inputs, `run_diff.py --bin ./tv.new data/real` | 131,146 inputs: **0 mismatches** |
| tampered, `data/tampered` | 23,301 inputs: **0 mismatches** |
| fuzz + zcash_script vectors, `data/fuzz` | 604,719 inputs: **0 mismatches** |
| sighashes, `SH_BIN=secp2/t/sh2 sighash_check.py data/real` | 140,366 / 140,366 equal |
| libsecp256k1 vectors (`data/t/ecdsa.bin`, `secp2/t/secp_t` mode 3): verdicts + decoded keys | 32,000: **0 mismatches** |
| new: u1 G + u2 Q vs Python, Q ∈ {G, −G, λG, 2G, 3G, 3λG, (n−1)G, 6 random}; u1, u2 ∈ {0, 1, 2, 3, n−1, n−2, n−3, (n±1)/2, λ, n−λ, λ±1, 2^127, 2^128±1, 2^129, 2^255, ±b1, 15–17, 127–129, 255, 256}; sums that are infinity (u1 = −c·u2 for Q = cG); u1 = u2, u1 = −u2, u1 = c·u2 (equal/opposite points mid-loop); random (`secp2/t/check2.py` mode 4) | 5,494: **0 mismatches** |
| new: GLV split (k1, k2 exactly as libsecp256k1's `split_lambda`, incl. halves 0, ±λ, n−1), Montgomery square, add mod n (mode 5) | 20,232: **0 mismatches** |
| field ops incl. one-pass `sub` (mode 1), scalar inverse chain + product (mode 2) | 20,000 + 20,000: **0 mismatches** |
| RIPEMD-160, SHA-1, SHA-256, HASH160, HASH256 single-pass readers (`script2/t/hash_check.py`) | 509 messages × 5: **0 mismatches** |
| fullnode hook path with `tv.new` (`secp2/t/hook_test_new.py`: hook.py's code with `TV = tv.new`), blossom / NU5 / NU6.1, 150 transactions each | 893 of 900 items as expected. The other 7 are the NU6.1 "ord"-style P2SH inputs already listed above, which zcash_script accepts too |

`gen_secp2.py` also self-tests the split (200,000 random scalars and edge values: |k1|, |k2| <
2^128) and the wNAF recoding in Python before writing any Bend.

**4. Speed.** Measured on the M5 Max on 2026-10-27 with other agents' jobs running. The load
average is given per run.

The CPU-cycle sums over the 86 files of `data/real` are the most load-robust number
(`secp2/bench_cycles.sh`, 2 interleaved rounds, load 8–11):

| | round 1 `tv` | `tv.new` | Rust oracle (`tv-oracle check`, 1 thread) |
|---|---:|---:|---:|
| user time | 190–201 µs/input | 145–152 µs/input | 21–22 µs/input |
| CPU cycles | 815–851 kcycles/input | 619–668 kcycles/input | 111–119 kcycles/input |

Wall time (`bench2.sh`):

| `bench2.sh` | round 1 `tv` | `tv.new` | Rust |
|---|---:|---:|---:|
| 1 process, one file at a time (load 15.7 → 10.0) | 25.3 s, 192.9 µs/input | 20.5 s, 156.3 µs/input | 3.35 s, 25.5 µs/input |
| 12 processes (`xargs -P 12`, one file each) | 34,859 inputs/s | 48,264 inputs/s | 331,856 inputs/s |
| 1 process (load 9.5 → 7.1) | 25.2 s, 192.0 µs/input | 19.0 s, 144.9 µs/input | 3.40 s, 25.9 µs/input |
| 18 processes | 37,197 inputs/s | 55,651 inputs/s | 378,397 inputs/s |

Per era, CPU cycles per input (`secp2/logs/perfile_r2b.txt`):

| Era | `tv` | `tv.new` | Rust | speedup | `tv.new` ÷ Rust |
|---|---:|---:|---:|---:|---:|
| pre-Overwinter (legacy SHA-256d sighash) | 1,916k | 1,170k | 167k | 1.64× | 7.0 |
| Overwinter | 553k | 468k | 145k | 1.18× | 3.2 |
| Sapling | 559k | 443k | 168k | 1.26× | 2.6 |
| Blossom | 635k | 498k | 178k | 1.27× | 2.8 |
| Heartwood | 651k | 511k | 172k | 1.27× | 3.0 |
| Canopy | 582k | 465k | 146k | 1.25× | 3.2 |
| NU5 | 730k | 582k | 170k | 1.25× | 3.4 |
| NU6 | 775k | 635k | 171k | 1.22× | 3.7 |
| NU6.1 | 960k | 760k | 207k | 1.26× | 3.7 |
| NU6.2 | 977k | 804k | 201k | 1.22× | 4.0 |
| NU6.3 | 1,315k | 951k | 205k | 1.38× | 4.6 |
| **all 131,146 inputs** | **873k** | **659k** | **175k** | **1.32×** | **3.8** |

ECDSA on its own: `secp2/prof/ecdsa_valid.bin` holds 30,000 valid libsecp256k1 cases (each
decodes the key twice, verifies once and prints hex). It takes 9.9–10.2 Gcycles with round 1's
`secp/t/secp_t` and 7.3–7.4 with `secp2/t/secp_t`. libsecp256k1 verifies in 13.2 µs
(`secp-vectors bench 30000`, same session). In the final `tv.new` profile, the double-scalar
multiplication is ~20% of samples. That is an estimated ~29 µs per call (20% × ~150 µs per
input ÷ 1.07 signature checks per input). Its parts:

- doublings: 39%;
- Q additions: 38% (full Jacobian adds plus list lookups);
- G additions: 16%.

**Why not 3–5×.** ECDSA was 36% of the time. Making it free would still give at most 1.6×. The
remaining time is spread over list-of-bytes handling in every stage:

- runtime reference counting (`term_drop` / `span_fade` / `rfc_wrap`): ~40% of samples in the
  final profile;
- the wire validator's Pallas point decompression: ~8%;
- BLAKE2b / SHA-256 over lists;
- per-input copies of scripts and amounts.

A 3–5× gain needs bytes stored in flat arrays (or packed words) end to end: parser, hashes,
interpreter and wire validator. That is a rewrite of every stage, not a change to secp256k1.

## Gaps and honesty notes

- Differentially tested, not proven: no Bend laws here.
- The legacy (v1/v2) sighash has no official implementation to diff against: both sides are
  re-implementations of zcashd's `SignatureHash`, and every one of 11,853 real v1/v2 signatures
  verifies under it with the official interpreter. SIGHASH_SINGLE without a matching output in
  v1/v2 is treated as a failure (zcashd throws); no such signature was in the sample.
- ECDSA with r + n < p reached via x(R) ≥ n is implemented (as libsecp256k1) but untested
  (probability ~2^-128; cannot be generated).
- Not in the sample: bare multisig on chain, hash types 02/82 on chain (fuzzed instead).
- Out of scope for `tv`: UTXO existence, amounts/fees, coinbase maturity, block-level sigop limit.

## fullnode hook (`hook.py`)

`hook.py` implements fullnode's verifier-hook interface (`fullnode/hooks/README`) for the
`transparent` hook: it reads the list file, turns each `P.tx` + `P.ctx` (follow layout) +
`P.json` height into a ZTV1 record with flags 513, runs `tv` on chunks of 200 transactions
(`TV_JOBS` processes, default 12) and prints `verdict <height> <txidx> PASS` or
`FAIL transparent input(s) i,j of n invalid` / `FAIL malformed transaction ...`. To wire it
in without changing anything else, create the executable `fullnode/hooks/transparent`:

```sh
#!/bin/sh
exec python3 /Users/betterclever/projects/zecathon/bend-zcash/transparent/hook.py "$@"
```

Tested end to end by `t/hook_test.py` (real records → P.tx/P.ctx/P.json → hook.py): see Results.

## How `follow` should call it

Binary: `transparent/tv` (build: `../heavy.sh ./build.sh tv_main.bend tv`, ~1 min). One process
checks any number of transactions; it is single-threaded, so run several in parallel like `txx`.

Input: one file, little-endian:

```
file   := "ZTV1" || count u32 || record*
record := height u32 || flags u32 || tx_len u32 || tx bytes || n_prev u32 || prev*
prev   := amount i64 || script_len u32 || scriptPubKey bytes      (one per transparent input, in order)
```

- `height`: the block height (selects the consensus branch id for v1–v4 sighashes; a v5/v6
  transaction whose own branch id differs gets all inputs rejected, as Zebra does).
- `flags`: `513` (P2SH | CHECKLOCKTIMEVERIFY), mainnet consensus at every height.
- every non-coinbase transaction with transparent inputs, any version (v1–v6); `prev` comes from
  the spent outputs `follow` already fetches (`prev_outputs`: amount and scriptPubKey per input;
  the only change is the per-input `u32` length instead of a CompactSize).

Output, one line per record: `r <k> <verdicts>` with one character per input (`1` valid,
`0` invalid), or `r <k> INVALID` if the transaction is malformed (rejected by
`node/wire/txv.bend`) or `n_prev` differs from its input count. A block passes the transparent
check iff every line is all `1`s. `sh FILE.ztv` prints the sighashes Bend computes (hash types
01 02 03 81 82 83 per input) for debugging a `0`.

Not covered by `tv`: whether the prevouts exist / are unspent (UTXO set), value balance and
fees, coinbase maturity, `nLockTime`/expiry finality against the block, and the block sigop
limit. Those need chain state `follow` does not keep.
