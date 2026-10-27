# zebend follow

A daemon that follows Zcash mainnet **live** and validates every new block's shielded parts
with the Bend components of this repo. It persists its state after every window of blocks, so
it can be stopped and restarted at any time.

```sh
python3 node/follow/zebend_follow.py --live --profile             # catch up to the tip, then follow it
python3 node/follow/zebend_follow.py --max-blocks 300 --window 100 # validate the next 300 blocks and stop
python3 node/follow/zebend_follow.py --live --tamper-next          # flip one bit of the next Halo 2 proof
```

Options: `--window N` (blocks per catch-up window, default 200; live windows are one block),
`--jobs N` (parallel Bend processes, default 14), `--peers N` (download peers, default 8),
`--hist-every N` (catch-up sampling of the history-root oracle, default 20), `--profile`.

## Architecture

Three threads form a pipeline, so the network, the per-transaction checks and the
state-dependent checks of consecutive windows overlap:

```
 feeder (transport)                 head (feeder thread 2)               tail + commit (main thread)
 window k+2                         window k+1                           window k
 ─────────────────────────          ─────────────────────────────        ──────────────────────────────────
 Bend P2P client (zcash/p2p):        bin/block_main ×W (14 at once):      bin/equihash: last 28 saved
  getheaders, SHA-256d hashes        wire validator, merkle root,         headers + window: Equihash,
 p2pblocks.Swarm: getdata from       header == P2P client's header        target, links, difficulty
  8 peers, 16 in flight each,       bin/txx ×txs (14 at once): wire      bin/halo2_batch (512 bundles a
  placed by hashPrevBlock            validator, txid == merkle leaf,       run) ║ bin/nfb ║ bin/frontier
 Blockchair history roots for        ZIP 244 sighash, RedPallas           anchors ∈ roots of earlier blocks
  sampled heights (prefetch)         spend-auth + binding, Halo 2         oracle: chain's tree root (last
                                     inputs, nullifiers, cmx               root of the window), sampled
                                    lightwalletd prevouts (one            history roots → block_main
                                     concurrent call) → txx again          commitments
                                     for txs with transparent inputs     commit: nf.bin, roots.txt,
                                                                           nfb/ (append) → frontier.txt,
                                                                           headers.bin → tip.json (atomic)
```

Live (after catch-up), a peer's `inv` announcement is fetched at once and verified as a
one-block window; the oracle-backed checks (block commitments, the chain's tree root) follow
in a background thread as soon as the oracles have the block, and a MISMATCH there stops the
follower and rolls the state back to the snapshot before that block.

Every check above is done by a Bend binary (sources in `zcash/`, `research/blake3x/`, `research/perf3/`,
`node/follow/*.bend`). `zebend_follow.py` moves bytes between them, compares their printed
results, and keeps the state files. It computes no hash, signature, proof or tree.

**Transport** is the one non-Bend network piece: `p2pblocks.py` frames P2P messages (the wire
protocol's 4-byte checksum uses hashlib) and downloads blocks by the hashes the Bend P2P client
computed. Peers answer out of order, so each block is placed by its header's `hashPrevBlock`
field; Bend then checks the block header equals the header at that height that `equihash`
verifies, so a misplaced block cannot pass. In live mode the block is requested by the hash a
peer announced; that hash is only used to ask for it: `equihash` checks the block's header
links to the verified tip, and the next header's link to it is checked the same way.

**Nullifier store** (`node/follow/nfb.bend`, new): the Ironwood nullifier set as 256 bucket files
(`state/nfb/<first byte>.bin`). A window reads only the buckets its nullifiers fall into,
ingests each into zcash/state's nullifier set (`nfset.bend` with `nf_main`'s `ingest`, the code
`node/validate/nf_check` uses) and counts (a) old entries in the wrong bucket, (b) duplicates among
old entries, (c) new nullifiers already in the set or repeated in the window. Only if all are 0
does Bend append the new nullifiers to their buckets. A live block takes 0.03 s instead of
`nf_check`'s 7 s (which reloads and sorts all 860k nullifiers); a window touching every bucket
takes 1.7 s at 15 MB. The store was built from `nf.bin` by `nfb` itself (859,433 nullifiers,
0 duplicates, identical multiset). Tested: a reused nullifier, a repeat within the new ones and
a misrouted store entry are each detected and nothing is appended.

## What is checked, and what is not

| Per block | Checked by | Status |
|---|---|---|
| Equihash (200,9), hash ≤ target, link to the previous header, difficulty | `equihash` (research/blake3x/eqv3) | ✅ every block |
| Block and every transaction well-formed (zcash/wire validators: canonical capped CompactSize, ≤ 2,000,000 bytes, exact end; the same rules as zcash_primitives' readers) | `block_main` (`wire/blk.bend parse_capped`), `txx` (`wire/txv.bend`) | ✅ every block, every v5/v6 tx; malformed input is rejected before any digest code runs |
| Merkle root over txids (ZIP 244 txids for v5/v6, SHA-256d for v4) | `block_main` | ✅ every block |
| ZIP 244 block commitments (`hashBlockCommitments`), including v4 txs (SHA-256d txids, ZIP 244 all-`ff` auth digest) | `block_main` | ✅ whenever the ZIP 221 history root (oracle) is fetched: every live block (a later line, after commit; MISMATCH rolls back), every 20th catch-up block (`--hist-every`, before commit); if the oracle fails, **SKIPPED** is printed |
| Block header bytes == header verified above | `block_main` | ✅ every block |
| v5/v6 txid, ZIP 244 sighash | `txx` | ✅ every v5/v6 tx |
| RedPallas spend-auth (every action) and binding signatures, Orchard and Ironwood bundles | `txx` | ✅ |
| Halo 2 proof of every Orchard and Ironwood bundle (post-NU6.3 circuit) | `halo2_batch` / `halo2_one` | ✅ every bundle, in batches of up to 512 before anything is committed; each block line shows `Halo 2 n/n PASS` |
| Ironwood anchor is the root after some earlier block (or the empty tree) | roots computed by `frontier` | ✅ |
| Ironwood nullifiers: none reused, none repeated within the window, store intact | `nfb` | ✅ every nullifier (see *Nullifier store*) |
| Ironwood note commitments appended; root after each block | `frontier` | ✅ and cross-checked against the chain's root (oracle): the last root of each catch-up window (it commits to every leaf before it), every live block |
| Transparent scripts, transparent amounts, Sapling, Sprout, coinbase and fee rules | — | **not checked**, printed per block as `[not checked: …]` |
| Orchard (legacy pool) anchors and nullifiers | — | **not checked** (no Orchard tree state is kept); its proofs and signatures are checked |

**Labelled oracle inputs** (never trusted for a PASS on their own):
- `hashLightClientRoot`, the ZIP 221 chain history root, from Blockchair. Bend combines it with
  its own auth-data root; a wrong value makes the commitments check fail.
  Computing it in Bend would need the ZIP 221 Merkle mountain range over every block since
  Heartwood (per-block chain work, Sapling/Orchard roots, tx counts), which is not built yet.
  It is unrelated to v4 transactions: blocks of only v4 transactions get `commitments MATCH`.
- The chain's Ironwood tree root (lightwalletd `GetTreeState`), only compared with the root
  Bend computed.
- Spent transparent outputs (lightwalletd `GetTransaction`), for transactions with transparent
  inputs. Bend hashes their amounts and scripts into the ZIP 244 sighash, which every on-chain
  signature must verify against, so wrong data can only cause a FAIL, never a PASS.

## Persistence and failures

`node/follow/state/`: `tip.json` (height, hash, and the byte lengths of every append-only file),
`headers.bin` (the last 29 headers, for difficulty), `frontier.txt` (Ironwood frontier),
`roots.txt` (every Ironwood root since activation: the anchor set), `nf.bin` (every Ironwood
nullifier, in order), `nfb/` (the same nullifiers, bucketed), and `snapshots/` (the last 10
committed tips).

- A window is committed only if every block in it passes. `nfb` appends to its buckets during
  the window (only when its own checks pass); `nf.bin` and `roots.txt` are appended next, then
  `frontier.txt` and `headers.bin` are replaced (temp file + rename), then `tip.json` (atomic
  rename). On start, and after any FAIL, every append-only file is truncated back to the length
  `tip.json` records, so a crash or a failed window leaves the previous consistent state. All
  parallel checks finish before a failure is acted on, so a truncation never races an append.
- On any FAIL the window is not committed, the failing check is printed, and the window's inputs
  stay in `node/follow/work/win/` for inspection.
- Transport: peers that stall (20 s without a block) are dropped and their blocks requeued for
  the others; when the queue is empty, idle peers also ask for blocks still in flight elsewhere.
  Connections are kept open (pings answered while idle) and re-handshakes are rare, because
  peers rate-limit IPs that reconnect often.
- Under parallel load a Bend process occasionally exits 0 having printed nothing (about 1 run
  in 700, never serially; it happens with `--threads 1 --gpu off` and with output to a file, so
  it looks like a runtime output issue). Empty output satisfies no check, so it is rerun (at
  most 3 times; counted in `--profile`). It can turn a PASS into a FAIL, never the reverse.
- Reorgs: if the next header does not link to the tip, the follower restores the previous
  snapshot and refetches; a reorg deeper than the kept snapshots stops it with a message.
  This is a simple rule, not a full fork-choice implementation.

## Bootstrap

The starting state is height 3,528,268, built from this repo's verified data:
- headers from `zcash/headers/data/mainnet.bin` (verified in Bend, see `zcash/headers/history`);
- `frontier.txt` and `roots.txt` from running `bin/frontier` over all 838,662 mainnet Ironwood
  note commitments, block by block since activation (7.2 minutes). The roots match the chain's
  at 3,428,200, 3,448,142, 3,488,142, 3,500,000 and 3,528,268. The empty-tree root, which Bend
  also computes, is included: real transactions use it as an anchor;
- `nf.bin` from `zcash/state/out/nf.bin` (all Ironwood nullifiers to that height, 0 duplicates).

## Results

All numbers are from `node/follow/logs/run.log` (Mac, 18 cores; Zcash mainnet, 25 Oct 2026).

**Coverage.** From the bootstrap point 3,528,268 to 3,530,065 every block passed every check in
the table above. Commitments MATCH on every sampled catch-up block and on every live block
(20 of 20 live oracle checks). No block was skipped: anything not checked is out of scope and
printed per block.

**Before / after, per block** (spam-heavy blocks around 3,528,750: ~250 Ironwood actions and
~100 bundles per block; serial times except where stated):

| Stage | before (25-block batch, serial) | after (100-block window) |
|---|---|---|
| block download | 12,398 ms (one peer, 8-block getdata rounds with 10 s waits) | ~600 ms in the first window, overlapped with verification afterwards (swarm, 8 peers) |
| txx: wire, txid, sighash, signatures | 3,268 ms (5,341 runs: every tx 2–3 times) | 76 ms (14 in parallel, each tx once, plus once more if it has transparent inputs) |
| lightwalletd (prevouts, tree root) | 880 ms (serial gRPC) | 47 ms (concurrent gRPC, one call per window; overlapped) |
| headers (Bend P2P client) | 330 ms | 150 ms (2,080 headers per session; overlapped) |
| nullifiers | 284 ms (`nf_check` reloads and sorts 860k) | 44 ms together with Halo 2 and the tree (`nfb`, 1.7 s per window, parallel) |
| block_main | 184 ms | 17 ms (14 in parallel) |
| history root (Blockchair) | 174 ms | prefetched by the feeder |
| Halo 2 | 128 ms | in the 44 ms above (512-bundle batches) |
| tree, PoW, commit | 30 ms | < 1 ms |
| **total** | **17.4 s per block (0.06 blocks/s)** | **0.19 s per block (5.3 blocks/s) on these spam blocks** |

**Catch-up, end to end** (`--live --profile`, window 200, from 3,529,283 to the tip
3,530,029): 746 blocks in 134 s from a cold start, **5.6 blocks/s**. The verification stages
are no longer the limit. Per 200-block window the tail (PoW, Halo 2, nullifiers, tree,
anchors, oracle waits, commit) took 1.6–3.6 s (**55–106 blocks/s**). The head (block_main and
txx, 14 in parallel) took 1.5–5.6 s of CPU (35–130 blocks/s), overlapped with the tail. The
limit is the network: ~1 MB/s per Zcash peer, and peers that rate-limit reconnecting IPs (the
swarm fell from 8 peers to 3 in one window). On the spam blocks verification alone ran at
5.3 blocks/s; on normal blocks it runs at 55–106 blocks/s.

**Live latency**, from a block's last byte arriving to its verdict line (state committed):
20 live blocks (3,530,030–3,530,045 and 3,530,062–3,530,065). Median **0.55 s**, 19 of 20
under 1 s (0.06–0.91 s). The exception, 29.4 s at 3,530,030, was the first block above the
start-up tip: it was downloaded with the last catch-up window and queued behind it. The
oracle-backed checks followed 1–64 s later, all MATCH:

```
  3530064  00000000005c5f08  txs  18  shielded  10  ironwood actions  20  orchard actions  0  PoW/diff PASS  merkle MATCH  commitments deferred sigs PASS  Halo 2 10/10 PASS  nullifiers PASS  anchors 10/10  root deferred  latency 0.57 s  [not checked: 5 v4 tx (transparent/Sapling), transparent inputs of 2 tx]
  window 3530064..3530064: 1 blocks, 10 Halo 2 bundles, 20 nullifiers, 20 commitments, verified in 0.2 s (6.6 blocks/s)
  3530064 oracle checks (+2 s): commitments MATCH, Ironwood root vs chain MATCH
```

**A real reorg.** The block we verified at 3,530,045 (`000000000057f51f…`; it passed Equihash,
target, link and every shielded check) lost a block race. The chain's 3,530,045 is
`0000000000691a56…`. Peers then answered our header locator with headers that don't link to
it. The follower now treats that as a reorg: it restored the 3,530,044 snapshot (truncating
the nullifier store, `nf.bin` and `roots.txt` to the snapshot's lengths) and verified the
chain's blocks from there.

**Tamper test** (`--live --tamper-next`, on the chain's block 3,530,045 right after that
rollback):

```
    --tamper-next: flipped one bit of the proof in block 3530045, bundle_3_ironwood.bin
FAIL: Halo 2 batch of 31 bundles rejected; failing bundles: ['3530045/bundle_3_ironwood.bin']
  window NOT committed; state stays at tip 3530044.
```

**Problems found and fixed on the way**
- `FAIL: block 3528804 tx 9: Bend txid None != block leaf 086efaf6…`: not a parsing problem.
  Run alone, `txx` prints that txid for that tx (a v6 tx). Under 14 parallel runs, a Bend
  process sometimes exits 0 having printed nothing: 8 of ~3,000 runs, with `--threads 1 --gpu
  off` and with stdout to a file as well, and never in 1,500 serial runs. The driver reruns a
  process whose output is empty (at most 3 times). Block 3,528,804 then verified (217/217
  bundles). This looks like a Bend runtime output issue, worth reporting upstream.
- `FAIL: nullifier check: duplicates 0, 0 reused`: a reporting bug, not a duplicate.
  `node/validate/nf_check` reads at most 4,096 query bytes (128 nullifiers). A window with 298
  nullifiers got 128 answers, and the driver rejected the count mismatch while printing only
  the duplicate counts. Replaced by `nfb`, which checks every nullifier; any failure now prints
  Bend's full line (new / misrouted / old_dups / new_dups).
- Zebra silently drops part of a multi-block `getdata`, so the swarm sends one block per getdata.
- Bend `zebend-p2p`, `block_main` and `txx` were rebuilt from the hardened sources (zcash/wire
  gate). The new `txx` rejects a tx with one trailing byte, which the old one accepted, and
  prints byte-identical reports on real txs.

