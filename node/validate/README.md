# zebend validate

One command that validates a real Zcash mainnet Ironwood transaction from its block
header down to the shielded state, with **every cryptographic check executed by Bend code**.

```sh
./zebend validate                       # tx_0: 7a8298b6…aca6, mainnet block 3,528,073
./zebend validate --tamper proof        # also: header ciphertext signature note doublespend
```

## What runs where

`zebend_validate.py` is a driver. It slices and copies files, applies the optional tamper to
the copies, runs the Bend binaries below, and compares what they print. **It computes no
hash, signature, proof or tree itself.**

| Step | Bend program | What Bend computes |
|---|---|---|
| 1 Header | `zcash/headers/verify` | Equihash (200,9), SHA-256d hash ≤ target, prev-hash links, difficulty (nBits) for the block and its 28 predecessors |
| 2 Block | `zcash/block/block_main` | every txid / auth digest in the block, the SHA-256d merkle root and ZIP 244 `hashBlockCommitments`, compared with the header verified in step 1 |
| 3 Transaction | `zcash/tx/tx_main` | ZIP 244 txid and sighash, RedPallas spend-auth and binding signatures, the Halo 2 public inputs |
| 4 Proof | `zcash/halo2/verifier/bundle_main_fast` | the Ironwood Halo 2 proof, checked against the public inputs from step 3 (the driver concatenates the proof bytes taken from the transaction with those inputs) |
| 5 State | `zcash/state/tree_main`, `node/validate/nf_check` | the Sinsemilla tree root over all 838,662 mainnet Ironwood leaves at 6 checkpoints (the tx's output commitments sit at positions 837,492–837,493); the nullifier set over all mainnet Ironwood nullifiers: 0 duplicates, each of the tx's nullifiers present exactly once |

`nf_check.bend` is new here; it imports `zcash/state`'s nullifier set and parser.

## Honest run (M5 Max)

```
zebend validate tx_0: 7a8298b6a596e182264c4fcb093d0464c37993434c78f7da92144ef0a140aca6 (mainnet block 3,528,073)
[1] Header: Equihash, target, chain links, difficulty      PASS   equihash 29/29, target 29/29, links 28/28, difficulty 1/1
[2] Block: tx committed to the verified header             PASS   merkle MATCH, commitments MATCH, header MATCH, txid = leaf 1 of 16
[3] Transaction: ZIP 244 txid + sighash, RedPallas         PASS   txid = network txid; spend-auth 2/2; binding valid
[4] Proof: Ironwood Halo 2 proof verifies in Bend          PASS   7,264-byte proof, 20 public inputs from step 3
[5] State: note commitments in the tree, no double spend   PASS   6/6 tree roots MATCH; 0 duplicate nullifiers; each tx nullifier once
VALID: 5/5 steps passed   total 29–76 s (step 5 rebuilds the whole tree on the GPU; the rest takes ~1.3 s)
```

## Tamper runs

| `--tamper` | Byte flipped | Fails | Why |
|---|---|---|---|
| `header` | a nonce byte of the block's header | 1, 2 | Equihash and target fail for that header; the block no longer matches the verified header |
| `ciphertext` | a byte of action 0's note ciphertext | 2, 3 | effecting data: the txid changes (merkle MISMATCH, ≠ network txid), so the sighash changes and all 3 signatures fail |
| `proof` | a byte in the middle of the Halo 2 proof | 2, 4 | authorizing data: txid unchanged (merkle MATCH) but block commitments MISMATCH; the proof is rejected |
| `signature` | a byte of action 0's spend-auth signature | 2, 3 | block commitments MISMATCH; 1/2 spend-auth signatures valid |
| `note` | a byte of the tx's first note commitment in the leaf set | 5 | the commitment is no longer in the leaf set; the tip tree root MISMATCHes the chain's |
| `doublespend` | another nullifier entry replaced by this tx's second nullifier | 5 | the nullifier set reports 1 duplicate; that nullifier occurs twice |

## What is oracle-provided

- **Raw data:** block, transaction and headers came from lightwalletd, live P2P peers and
  Blockchair. They are trusted only because the Bend checks tie them together: the header's
  proof of work, the merkle root and block commitments, the network's txid.
- **ZIP 221 history root** (`zcash/block/data/<h>.hist`): an input to `hashBlockCommitments`,
  not computed in Bend. A wrong value fails step 2.
- **Spent-output context** (`zcash/tx/mainnet/<tx>.ctx`): transparent amounts and scripts for
  the sighash. Empty here, since tx_0 is fully shielded.
- **Expected tree roots:** the chain's `GetTreeState` roots at 6 heights, compiled into
  `zcash/state/checkpoints.bend`.
- **Leaf and nullifier lists:** every Ironwood output from activation to 3,528,268, synced from
  lightwalletd. Locating the tx's commitments in the leaf file is a byte search done by the driver.

## Limitations

- **Tested, not proven:** these checks match the official implementations and the chain. The
  only Bend *proofs* in play are the laws of the components (difficulty bounds, nullifier set).
- **Fixed dataset, not a live fetch:** `--tx` takes any Ironwood tx in `zcash/tx/mainnet` whose block
  is in `zcash/block/data` (tx_0, tx_1, tx_3, tx_4). tx_0 and tx_4 (block 3,528,076, 3 actions:
  VALID 5/5) were run; withdraw-only Orchard bundles are not wired in.
- **Not checked:** the anchor is a valid historical tree root, Sapling and transparent parts,
  fee and size rules, coinbase rules, `expiry_height`. Applying the tx to the proven turnstile
  model (`proofs/turnstile/`) would need invented pool balances, so it is not done.
- Step 5 rebuilds the full tree each run. An incremental frontier would make it instant.
