# zebend follow

A daemon that follows Zcash mainnet **live** and validates every new block's shielded parts
with the Bend components of this repo. It persists its state after every batch of blocks, so
it can be stopped and restarted at any time.

```sh
python3 follow/zebend_follow.py --live                     # catch up to the tip, then follow it
python3 follow/zebend_follow.py --max-blocks 10 --batch 5  # validate the next 10 blocks and stop
python3 follow/zebend_follow.py --tamper-next ...          # flip one bit of the next Halo 2 proof
```

## Architecture

```
            Bend P2P client (node/p2p)                 p2pblocks.py (transport only)
  peers ──► getheaders, SHA-256d hashes, links ──► getdata/block, placed by hashPrevBlock
                       │                                      │
                       ▼                                      ▼
   bin/equihash  ◄── last 28 saved headers + new     bin/block_main: merkle root, ZIP 244
   Equihash, target, links, difficulty                 auth root + block commitments,
                                                       block header == verified header
                                                              │ per-tx byte lengths (Bend)
                                                              ▼
                                       bin/txx (follow/txx.bend over node/tx): txid,
                                       ZIP 244 sighash, RedPallas spend-auth + binding,
                                       Halo 2 public inputs, proof bytes, outpoints
                                                              │
        ┌──────────────────────────────┬──────────────────────┼─────────────────────────┐
        ▼                              ▼                      ▼                         ▼
 bin/halo2_batch (perf3/v64)   anchor ∈ roots of earlier   bin/nf_check: no Ironwood   bin/frontier (follow/
 batched Halo 2 per batch;     blocks / empty tree         nullifier reused (set of    frontier.bend over
 bin/halo2_one pinpoints       (roots computed by Bend)    all since activation)       node/state code): one
 a failing bundle                                                                      Ironwood root per block
                                                              │
                                                              ▼
              commit: nf.bin, roots.txt (append) → frontier.txt, headers.bin → tip.json (atomic)
```

Every check above is done by a Bend binary (sources in `node/`, `blake3x/`, `perf3/`,
`validate/`, `follow/*.bend`). `zebend_follow.py` moves bytes between them, compares their
printed results, and keeps the state files. It computes no hash, signature, proof or tree.

**Transport** is the one non-Bend network piece: `p2pblocks.py` frames P2P messages (the wire
protocol's 4-byte checksum uses hashlib) and downloads blocks by the hashes the Bend P2P client
computed. Peers answer out of order, so each block is placed by its header's `hashPrevBlock`
field; Bend then checks the block header equals the verified header at that height, so a
misplaced block cannot pass. Headers come from the Bend P2P client itself.

## What is checked, and what is not

| Per block | Checked by | Status |
|---|---|---|
| Equihash (200,9), hash ≤ target, link to the previous header, difficulty | `equihash` (blake3x/eqv3) | ✅ every block |
| Merkle root over txids (ZIP 244 txids for v5/v6, SHA-256d for v4) | `block_main` | ✅ every block |
| ZIP 244 block commitments (`hashBlockCommitments`) | `block_main` | ✅ when the history-root oracle answers: every live block, every 20th catch-up block; otherwise **SKIPPED** (printed) |
| Block header bytes == header verified above | `block_main` | ✅ every block |
| v5/v6 txid, ZIP 244 sighash | `txx` | ✅ every v5/v6 tx |
| RedPallas spend-auth (every action) and binding signatures, Orchard and Ironwood bundles | `txx` | ✅ |
| Halo 2 proof of every Orchard and Ironwood bundle (post-NU6.3 circuit) | `halo2_batch` / `halo2_one` | ✅ batched per batch of blocks |
| Ironwood anchor is the root after some earlier block (or the empty tree) | roots computed by `frontier` | ✅ |
| Ironwood nullifiers: none reused, none repeated within the batch | `nf_check` | ✅ |
| Ironwood note commitments appended; root after each block | `frontier` | ✅ and cross-checked against the chain's root (oracle) |
| Transparent scripts, transparent amounts, Sapling, Sprout, coinbase and fee rules | — | **not checked**, printed per block as `[not checked: …]` |
| Orchard (legacy pool) anchors and nullifiers | — | **not checked** (no Orchard tree state is kept); its proofs and signatures are checked |

**Labelled oracle inputs** (never trusted for a PASS on their own):
- `hashLightClientRoot`, the ZIP 221 chain history root, from Blockchair. Bend combines it with
  its own auth-data root; a wrong value makes the commitments check fail.
- The chain's Ironwood tree root per block (lightwalletd `GetTreeState`), only compared with the
  root Bend computed.
- Spent transparent outputs (lightwalletd `GetTransaction`), for transactions with transparent
  inputs. Bend hashes their amounts and scripts into the ZIP 244 sighash, which every on-chain
  signature must verify against, so wrong data can only cause a FAIL, never a PASS.

## Persistence and failures

`follow/state/`: `tip.json` (height, hash, and the byte lengths of the append-only files),
`headers.bin` (the last 29 headers, for difficulty), `frontier.txt` (Ironwood frontier),
`roots.txt` (every Ironwood root since activation: the anchor set), `nf.bin` (every Ironwood
nullifier), and `snapshots/` (the last 10 committed tips).

- A batch is committed only if every block in it passes. Append-only files are written first,
  then `frontier.txt` and `headers.bin` (temp file + rename), then `tip.json` (atomic rename).
  On start, append-only files are truncated back to the lengths `tip.json` records, so a crash
  mid-commit leaves the previous consistent state.
- On any FAIL the batch is not committed, the failing check is printed, and the inputs stay in
  `follow/work/` for inspection.
- Peer resets and stalls (a 60 s per-chunk deadline) reconnect to another peer.
- Reorgs: if the next header does not link to the tip, the follower restores the previous
  snapshot and refetches; a reorg deeper than the kept snapshots stops it with a message.
  This is a simple rule, not a full fork-choice implementation.

## Bootstrap

The starting state is height 3,528,268, built from this repo's verified data:
- headers from `node/headers/data/mainnet.bin` (verified in Bend, see `node/headers/history`);
- `frontier.txt` and `roots.txt` from running `bin/frontier` over all 838,662 mainnet Ironwood
  note commitments, block by block since activation (7.2 minutes). The roots match the chain's
  at 3,428,200, 3,448,142, 3,488,142, 3,500,000 and 3,528,268. The empty-tree root, which Bend
  also computes, is included: real transactions use it as an anchor;
- `nf.bin` from `node/state/out/nf.bin` (all Ironwood nullifiers to that height, 0 duplicates).

## Results

RESULTS_PLACEHOLDER
