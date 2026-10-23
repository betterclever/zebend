# node/block: transactions committed to verified headers, in Bend

Given a raw mainnet block, Bend 2:
- splits it into its transactions (v4, v5 and v6, coinbase included)
- recomputes every txid and every ZIP 244 authorizing-data digest
- rebuilds both Merkle trees and checks them against the header's two commitment fields
- checks that the header is byte-identical to the one `../headers` already verified
  (Equihash, target, prev-hash linkage, difficulty)

So these transactions are provably in the chain those headers form.

## Result (10 real mainnet blocks, 90 transactions)

```
$ python3 check.py
3427944: 15 txs  bend==oracle True  merkle MATCH  commitments MATCH  verified_header MATCH
3427953:  7 txs  bend==oracle True  merkle MATCH  commitments MATCH  verified_header MATCH
3427956: 11 txs  bend==oracle True  merkle MATCH  commitments MATCH  verified_header MATCH
3428143:  1 txs  bend==oracle True  merkle MATCH  commitments MATCH  verified_header MATCH
3500000: 12 txs  bend==oracle True  merkle MATCH  commitments MATCH  verified_header MATCH
3527611:  6 txs  bend==oracle True  merkle MATCH  commitments MATCH  verified_header MATCH
3528073: 16 txs  bend==oracle True  merkle MATCH  commitments MATCH  verified_header MATCH
3528076:  6 txs  bend==oracle True  merkle MATCH  commitments MATCH  verified_header MATCH
3528087: 10 txs  bend==oracle True  merkle MATCH  commitments MATCH  verified_header MATCH
3528204:  6 txs  bend==oracle True  merkle MATCH  commitments MATCH  verified_header MATCH
10/10 blocks: every line identical to the oracle, roots MATCH, header = verified header (90 txs)
tamper tx 4, a memo ciphertext byte (effecting data: changes the txid): merkle MISMATCH, commitments MATCH
tamper tx 4, a Halo 2 proof byte (authorizing data: txid unchanged): merkle MATCH, commitments MISMATCH
tamper tx 4, the binding signature's last byte (authorizing data): merkle MATCH, commitments MISMATCH
```

**Blocks:**
- three v5 blocks just before NU6.3: 3,427,944, 3,427,953 and 3,427,956
- the NU6.3 / Ironwood activation block, 3,428,143, whose single tx is a v6 coinbase
- six post-NU6.3 blocks mixing v4, v5 and v6 transactions with Ironwood, withdraw-only Orchard and Sapling bundles

The 90 transactions are 33 v4, 24 v5 and 33 v6, and every block's coinbase is checked.

**Tamper tests:** these show ZIP 244's split between effecting and authorizing data.
- Changing a memo changes the txid, so `hashMerkleRoot` breaks. Memos aren't authorizing data, so `hashBlockCommitments` still matches.
- Changing the proof or a signature leaves the txid alone, and only `hashBlockCommitments` breaks.

Each Bend run takes about 0.03 s per block (native build, M5 Max).

## What Bend computes

| Field | Computation |
|---|---|
| txid, v5/v6 | ZIP 244 digest tree (header, transparent, Sapling, Orchard, Ironwood), from `../tx`'s code |
| txid, v4 | SHA-256d of the raw transaction. Its length comes from a v4 parser here (transparent, Sapling v4 spends/outputs, JoinSplits, binding sig) |
| auth digest, v5/v6 | BLAKE2b-256 `"ZTxAuthHash_" ‖ branch` over: transparent scriptSigs (`ZTxAuthTransHash`); Sapling proofs + sigs, plus the anchor in v6 (`ZTxAuthSapliHash` / `ZTxAuthSapliH_v6`); Orchard proof + sigs (`ZTxAuthOrchaHash`, and in v6 `ZTxAuthOrchaH_v6` plus the anchor); in v6, Ironwood (`ZTxAuthIrnwdH_v6` + anchor) |
| auth digest, v4 | the ZIP 244 placeholder `[0xff; 32]` |
| `hashMerkleRoot` | SHA-256d Merkle tree over txids, last node duplicated on odd levels |
| `hashAuthDataRoot` | BLAKE2b-256 `"ZcashAuthDatHash"` tree over auth digests, padded with `[0; 32]` to a power of two |
| `hashBlockCommitments` | BLAKE2b-256 `"ZcashBlockCommit"`(hashLightClientRoot ‖ hashAuthDataRoot ‖ `[0; 32]`) |
| verified header | the block's first 1,487 bytes equal `../headers/data/mainnet.bin` at that height |

## What is real, tested, or taken from outside

- **Taken from outside (oracle input), labelled:** `hashLightClientRoot`, the ZIP 221 chain
  history root, for each block (`data/<h>.hist`). Computing it needs the per-block history
  tree since NU6.3 activation, which isn't built. Every other value is recomputed from the raw block bytes.
  If the input were wrong, `hashBlockCommitments` would not match the header.
- **Differentially tested, not proven:** every printed line (txid, auth digest, byte length,
  roots) equals the Rust oracle's (`zcash_primitives` 0.31). The oracle itself checks
  its txids against the node's txid list and its roots against the header and the node's
  `authdataroot`. No Bend laws in this component.
- **Data source:** raw blocks and the node's `getblock` fields come from Blockchair's Zcash API
  (`oracle/fetch.py`). Nothing from that source is trusted except `chainhistoryroot`: the bytes
  are checked against our own verified headers.
- **Not checked:** consensus rules beyond the two commitments, such as transaction validity in
  chain context, coinbase amount, fees, block size and sigops. Those belong to `../tx`, `../state`
  and the turnstile. Pre-v4 transactions and Sprout JoinSplits never occur in this sample; the
  JoinSplit branch of the v4 length parser is written but unexercised.

## Files

| File | |
|---|---|
| `block.bend` | v4 length, ZIP 244 auth digests, txids, both Merkle trees, block commitments |
| `block_main.bend` | `block_main <block.bin> <hist.bin> <height> <headers.bin> <first height>`: the oracle's line format plus `verified_header` |
| `tx.bend`, `util.bend`, `consts.bend` | copied from `../tx` (unchanged) |
| `blake2b.bend` | generated by `gen_blake.py` (`../tx`'s generator + the auth and block personalizations) |
| `sha256.bend`, `bytes.bend` | copied from `../p2p` |
| `oracle/` | `fetch.py` (raw blocks + node fields) and the Rust ground truth (`src/main.rs`) |
| `data/` | `<h>.bin`, `<h>.json`, `<h>.hist`, `<h>.expected` |
| `check.py` | the differential and tamper tests |

```sh
python3 oracle/fetch.py 3500000 ...                  # raw blocks (Blockchair)
cd oracle && cargo run --release -- 3500000 ... && cd ..
python3 gen_blake.py && bend block_main.bend -o block_main
python3 check.py
```
