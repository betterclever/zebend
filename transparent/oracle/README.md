# tv-oracle: ground truth for transparent-input validation

Per transparent input of a non-coinbase transaction, `tv-oracle` computes what Zebra 14
(`zebra_script::CachedFfiTransaction::is_valid`) computes, and a data set of real mainnet
inputs (all eras) plus a tampered set carries those verdicts for the Bend implementation.

## What is official and what is re-implemented

| piece | source |
|---|---|
| script interpreter (primary) | `zcash_script` 0.6 Rust interpreter, `script::Raw::eval` + `CallbackTransactionSignatureChecker` (official crate; secp256k1 inside) |
| script interpreter (second oracle, `--features cxx`) | zcashd's C++ interpreter via `libzcash_script` 0.2 `CxxInterpreter` (what Zebra 14 runs), with Zebra's failed-sighash shim (random 32 bytes) |
| v3/v4 sighash (ZIP 143/243) | `zcash_primitives` 0.31 `v4_signature_hash` via `PrecomputedSighashData`, `SighashType::from_raw(raw byte)`, branch id = `BranchId::for_height(MAIN_NETWORK, height)` (zebra `sighash_v4_raw`) |
| v5/v6 sighash (ZIP 244) | `zcash_primitives` 0.31 (`SignableInput::Transparent(from_parts(..))`, all spent outputs through a `TransparentAuthorizingContext`); Zebra 14's pre-checks: raw hash type must be in {01,02,03,81,82,83} and SIGHASH_SINGLE needs an output at the input's index, else the callback returns None (check fails) |
| **v1/v2 sighash (pre-Overwinter)** | **RE-IMPLEMENTED here** (`src/raw.rs::legacy_sighash`): zcashd's legacy `SignatureHash` = SHA256d(CTransactionSignatureSerializer output ‖ nHashType as u32 LE), incl. the JoinSplit vector, joinSplitPubKey and 64 zero bytes for joinSplitSig when nVersion >= 2; OP_CODESEPARATORs removed from the scriptCode; SIGHASH_SINGLE with nIn >= #vout = failure (zcashd throws). No official crate implements it (zcash_primitives panics; Zebra checkpoints these heights). It is validated the way the chain validates it: every real v1/v2 input in the data set verifies under it with the official interpreter + secp256k1. |

Flags come from each record (mainnet consensus: `P2SH | CHECKLOCKTIMEVERIFY` = 513 at every height).

## Rebuild

    cd transparent/oracle
    HEAVY_MAX_MIN=30 ../../heavy.sh cargo build --release
    ./target/release/tv-oracle check ../data/real/sapling_0.ztv     # = sapling_0.expect
    ./target/release/tv-oracle stats ../data/real                    # counts, histograms, verdicts
    ./target/release/tv-oracle bench ../data/real                    # throughput
    # second oracle (separate target dir):
    CARGO_TARGET_DIR=target/cxx HEAVY_MAX_MIN=30 ../../heavy.sh cargo build --release --features cxx
    ./target/cxx/release/tv-oracle cxxcompare ../data/real ../data/tampered

Regenerating the data: `python3 sample.py ERA TARGET_INPUTS [CAP]` per era (seed `20261026`,
heights drawn with `random.Random(f"20261026-{era}")`, tip pinned at 3,530,516), then
`tv-oracle tamper 4242 5000 ../data/tampered ../data/real` plus a P2SH top-up
`TAMPER_KINDS=multisig_pubkey_swap,flags_no_p2sh tv-oracle tamper 4343 400 ../data/tampered ../data/real`.
Per-block cap: 300 inputs (whole txs that would exceed it are skipped and counted in `<era>.blocks`). Network: block hashes and prevout
transactions from lightwalletd (na/eu/ap.zec.rocks, zec.rocks; <= 16 requests in flight),
full blocks from mainnet P2P peers (follow/p2pblocks.py `Peer`, imported read-only).

## Data layout (`transparent/data/`, git-ignored)

- `real/<era>_<k>.ztv`: real mainnet records; `tampered/<era>_<k>.ztv`: one mutation each.
  Eras: preoverwinter overwinter sapling blossom heartwood canopy nu5 nu6_0 nu6_1 nu6_2 nu6_3
  (NU6.0 was sampled under the name `nu6`, i.e. RNG key `20261026-nu6`, then renamed).
  Chunks hold <= 400 records and <= ~1 MB.
- ZTV1 format (little-endian): `"ZTV1" ‖ count u32 ‖ record*`,
  `record = height u32 ‖ flags u32 ‖ tx_len u32 ‖ tx ‖ n_prev u32 ‖ prev*`,
  `prev = amount i64 ‖ script_len u32 ‖ scriptPubKey`; n_prev = #transparent inputs.
- `<file>.expect`: `r <k> <verdicts>` (one char per input, 1 valid / 0 invalid).
- `<file>.sighash`: `r <k> in <i> ht <hash-type byte hex> <sighash hex | NONE>`, one line per
  signature check the interpreter made, in call order (the value the callback returned).
- `<file>.meta`: `r <k> h <height> v <tx version> txid <hex> types <k|s|p|m|o per input>`
  (P2PKH, P2SH, P2PK, bare multisig, other); `txerror ...` if the tx could not be checked.
- `tampered/<file>.kinds`: `r <k> <mutation kind> <details> src <real file> r <k>`.
- `real/<era>.blocks`: the sampled heights and per-block counts (txs, inputs, cap skips).
- `blocks/<height>.blk`: raw blocks; `prevtx/<txid>.tx`: cached prevout transactions.
