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
