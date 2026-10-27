# zebend snapshot: assumeutxo-style fast start, with a Bend state digest

**Status (Oct 27, evening): a real pin exists.** `pinned.json` pins H = **3,532,588**:
- hash `000000000018cb33…4e102a51`;
- digest `2bfdabb6c4f774b567cae753760de40b589e25c6635a398e5ac13237e5512401`.

It was produced from the genesis-synced node (`node/state`) at its live tip, while the node
kept running. A cold start from it reaches "validating at tip" in **4.1 min** (§0).

The 3,522,460 checkpoint entry stays `null`, because it was never produced. The genesis
instance passed that height before anyone captured its state there. It is now ~10k blocks
past, beyond the 600-block rollback fallback.

## 0. Fast start (measured Oct 27, H = 3,532,588)

| | Zebend (this snapshot) | Zakura |
|---|---|---|
| snapshot size | **2.42 GB** zstd -3 (4.42 GB raw) | 11–12 GB pruned |
| what the node checks on import | every byte: Bend digest == pinned; order; chain checks (§4), incl. ZIP 221 at H+1 | none (trusts the publisher) |
| import (unpack + Bend verify ∥ SQLite import) | **171 s** (unpack 2.7, Bend verify 158, rest 10) | |
| sync start → "validating at tip" | +76 s: address index rebuilt from 27.3M UTXOs (35 s), then 45 blocks fully validated (all rules and hooks PASS) | |
| **total, file on disk → validating at tip** | **247.5 s (4.1 min)** | **< 2 min** |
| peak RSS (whole process tree) | 6.3 GB (at 140 s, Bend digest ∥ import) | |

How it was measured (`measure.py --download`, `work/fast/cold/{measure,sync,state.download}.log`):
- **Timer and inputs.** The timer starts with the snapshot file already local. Blocks H..tip
  are downloaded from P2P peers in parallel with the import (42 blocks in 4 s).
- **Start.** consume.py ran with `--history-blocks`, then the committed `sync.py` started on a
  fresh state directory.
- **Stop.** "At tip" means the new node committed 3,532,633, which was the live node's
  committed tip at that moment.
- **Same result as the live node.** After 45 blocks, the new node's value pools equal the live
  genesis node's per-block pools at 3,532,633, in all seven pools.

**Assumed, not measured:**
- The verified header chain (`state/hdr`, shared by instances, as sync.py and download.py
  already do) was already present. A real cold node first syncs ~3.53M headers; Bend Equihash
  verification of those is not part of this number.
- The time to download 2.4 GB from a publisher.

**Why it is slower than Zakura:**
- Bend checks every byte (158 s of 171 s). Zakura's start checks nothing in the snapshot.
- sync.py rebuilds the address index (35 s).
- The first window's rules take 36 s for 41 blocks.

The distance from H to the tip is no longer the problem: with a fresh pin, it is tens of blocks.

**Production of the pin** (`produce.py` on the live node, `work/fast/produce.log`; under
heavy.sh):
- Read-only SQLite transaction: 91 s (UTXO, nullifier and block rows). The live writer kept
  committing meanwhile.
  - Before the run, two read transactions were held on `state/` for 6.5 and 25 min, and the
    writer committed 3 windows during them in 0.0–0.1 s each. sync.py's store uses only
    PASSIVE checkpoints, so a reader can never block it; the WAL only grows.
- Trees in Bend: 52 min (`ptree.py`).
- Digest in Bend: 208 s.
- Total: 57 min. Peak RSS 4.3 GB.
- The leaf logs were read from APFS clones (`cp -c`) taken inside the transaction.

**Trees at H for reuse:** `work/trees_3532588/`, written by `dumptrees.py`:
- `<pool>.frontier`;
- `<pool>_history.txt` (one "height root" line per block that appended notes);
- `trees.json`.

| pool | leaves (tree size) | blocks with notes (roots) | root at H |
|---|---|---|---|
| Sprout | 1,547,344 | 317,275 | (Bend, `../bin/sprout`) |
| Sapling | 73,990,540 | 1,100,063 | `b0c826e5…51eb211a` |
| Orchard | 50,478,807 | 583,279 | `489f6894…ef49dbf39` |
| Ironwood | 947,637 | 66,437 | `c8acf3f5…01b3cf88b09` |

Cross-check against the gaps seeds: their Bend-built root histories in
`zcash/consensus/gaps/trees/seeds/*_history.txt` come from lightwalletd leaves, independently of
this node. They agree at every common height:

| Pool | Common heights | Equal |
|---|---|---|
| Sapling | 15,414 | 15,414 |
| Orchard | 23,383 | 23,383 |
| Ironwood | 59,826 | 59,826 |

**Which roots the consumer checks against the chain at this H:**
- **Roots at H: Sapling, Orchard and Ironwood (the frontiers): CHECKED by ZIP 221.**
  - Bend (`zcash/consensus/gaps/history` bin/history, via `histcheck.py`) builds block H's history
    leaf from three inputs:
    - raw block H: hash, time, nBits, and per-pool tx counts, which Bend parses;
    - the three frontier roots;
    - the MMR peaks of blocks ..H-1, an **untrusted** hint in the manifest.
  - It must MATCH block H+1's `hashBlockCommitments`.
  - Result: `hist 3532589 MATCH`.
  - Tampering is rejected: changing the Sapling, Orchard or Ironwood root at H gives
    MISMATCH, and flipping one byte of the hint gives MISMATCH.
  - The producer built the hint by chaining bin/history from the gaps agent's NU6.3 state at
    3,529,999 over blocks 3,530,000..3,532,587, with the snapshot's own root histories as side
    roots: **2,588 / 2,588 MATCH**. So those ~2.6k blocks of the root histories are
    chain-checked too, at production time.
- **Sapling root history 419,200..902,999: CHECKED** against `hashFinalSaplingRoot` of every
  verified header.
- **Pin only, until confirmation:**
  - all older root-history entries (Sapling ≥ 903,000, Orchard, and Ironwood below H);
  - all Sprout roots;
  - the UTXO and nullifier sets;
  - the value pools.
- **Covered after import:** new Ironwood anchors are checked against the imported history
  plus follow's roots (sync.py). Orchard and Sapling anchors in new blocks are still SKIPPED
  by sync.py (4 Sapling and 1 Orchard in this run), as in the live node.

Zakura publishes ~11–12 GB pruned snapshots. Its nodes trust the publisher. A Zebend node trusts
a digest **pinned in code** instead, as Bitcoin Core's assumeutxo does. It checks the snapshot
against the chain where the chain commits to it. It fully validates every block after H. Its
status stays **snapshot-assumed** until its own genesis sync has recomputed the same digest at
H; then it becomes **confirmed**.

```sh
# producer (a store at its committed tip H; the store is opened read-only, one read transaction)
python3 produce.py STATE out.zsnap [--height H] [--ironwood-follow --follow-snapshots DIR]
# consumer: verify + import into a fresh directory, then full validation from H+1
python3 consume.py out.zsnap NEWSTATE            # digest must equal pinned.json for (H, hash)
ZEBEND_STATE=NEWSTATE ZEBEND_SPOOL=... python3 ../sync.py
# confirmation, when the genesis instance passes H (or watch it, read-only)
python3 confirm.py --target NEWSTATE --genesis ../state --watch
# the pin at 3,532,588 (heavy.sh: ~1 h, 4.3 GB), then the ZIP 221 hint (MMR peaks of ..H-1)
HEAVY_MAX_MIN=180 HEAVY_MAX_GB=8 ../../tools/heavy.sh python3 produce.py ../state g.zsnap --jobs 12 --keep
python3 histcheck.py hint work/export_H HISTSTATE_L SPOOL hint.json   # blocks L+1..H+1 in SPOOL
python3 histcheck.py embed g.zsnap hint.json g.zsnap.h && mv g.zsnap.h g.zsnap
python3 dumptrees.py work/export_H work/trees_H                       # frontiers + root histories
# cold start, timed (downloads H..tip in parallel, ZIP 221 check at H+1)
python3 measure.py g.zsnap NEWSTATE --spool DIR --download --until-live ../state
```

## 1. Format (`snap.py`)

A snapshot is the state at the end of block H, as **13 sections** in this fixed order. Each
section is a sequence of records `u32 LE length || payload`, sorted by payload bytes. Bend
checks that the payloads are strictly increasing, so the order is canonical and there are no
duplicates.

| Section | Record payload | From |
|---|---|---|
| `meta` | `key 0x00 canonical-JSON` for `tip`, `pools` (the value pools, tracked from genesis by bin/rules), `audit_disagreements`, `assumed_state` (present only for the oracle-assisted instance), `snapshot_sources` (where each frontier came from) | `meta` table |
| `blk` | `height u32 BE · hash 32 · prev 32 · time · size · ntx (u32 LE) · len(bits) u8 · bits · info JSON` for the **last 128 blocks** (H−127..H; the median-time-past and difficulty context, and the per-block pools that `rollback_to` uses) | `blk` table |
| `utxo` | `op 36 (txid ‖ vout) · value i64 LE · height u32 · coinbase u8 · script` | `utxo` table |
| `nf.sprout`, `nf.sapling`, `nf.orchard`, `nf.ironwood` | `nullifier 32 · height u32` | `nf` table |
| `frontier` | per pool: `pool u8 · known u8 · depth u8 · size u64 · root 32 · per level (0x00 \| 0x01 ‖ node 32)`; Sprout has depth 29, the other pools 32 | Bend tree programs over the leaf logs (below) |
| `roots.<pool>` ×4 | `height u32 BE · root 32`: the tree root after every block that appended notes. This is the anchor set; the empty root is always valid too | same |
| `oracle_prevout` | `op 36 · height u32` (oracle-assisted instance only; empty otherwise) | `oracle_prevout` table |

The snapshot leaves out the following, on purpose:
- `addr`: sync.py rebuilds it from the UTXO set before its first fully validated window.
- `tx`: RPC-only, refetched by txid. With no tx index below H, `getrawtransaction` does not
  find transactions mined before H.
- `undo`: no reorg can go below a checkpointed H.
- The leaf logs: the frontiers replace them. After the import they start empty, and
  `meta.leaf_base` records the tree size at H.

The file is `MAGIC "ZEBENDSNAP1\n" · u32 len · manifest JSON · one zstd stream of all parts`.
Sections are split into ≤1 GiB parts only at multiples of 2^14 records, because Bend's
`File.read_at` takes a U32 offset. The manifest is **untrusted**. It holds byte lengths so the
consumer can cut the stream; the consumer recomputes everything else.

**Tree frontiers and root histories are computed in Bend from the leaf logs.** Each pool's
logged note commitments are pushed block by block:
- Sprout: `../bin/sprout` (SHA256Compress).
- Sapling: `bin/sapfront` (Pedersen; `bend/sapfront.bend`). This is node/follow/frontier.bend's
  driver with `zcash/sapling/tree/stree.bend`.
- Orchard and Ironwood: `bin/sinfront` (Sinsemilla; `bend/sinfront.bend`). This is a copy of
  node/follow/frontier.bend that also prints a root for a block that appends no notes.

The leaves are read lazily, 1M at a time. A store that was itself started from a snapshot
pushes onto `meta.snapshot_frontier`. The oracle-assisted instance has no complete leaf logs,
so it exports its Sprout, Sapling and Orchard frontiers as **unknown** (`known = 0`). With
`--ironwood-follow` it takes the Ironwood frontier from zebend follow's committed snapshot at
H; follow builds that tree in Bend from NU6.3 activation. Its tree size is follow's nullifier
count, and the frontier's bit pattern matched it exactly (945,920 leaves).

## 2. State digest (Bend: `bin/snapdigest`, `bend/snapdigest.bend`)

- Per section: a binary Merkle tree with SHA-256 and RFC 6962 domain separation:
  `leaf = SHA256(0x00‖payload)`, `node = SHA256(0x01‖l‖r)`. An odd last node is carried up.
  An empty section's root is `SHA256("")`. This pairing gives the same root as RFC 6962's
  power-of-two split.
- The section is cut into chunks of 2^14 records. Each chunk runs as one Bend process (16 in
  parallel) and gets the previous chunk's last record as context for the order check. A
  section's root is the same tree built over the chunk roots (`nodes` mode). A part boundary
  is order-checked by a separate 2-record Bend run.
- **Digest** = `SHA256("zebend-snapshot-v1\0" ‖ H u32 ‖ block hash ‖ n ‖ per section: name ‖
  count u64 ‖ root)`, computed by Bend (`hash` mode).

Python only cuts files at record boundaries, runs Bend and compares what Bend prints. A
hashlib reference (`tests/ref_digest.py`, tests only) agrees on 11 random sections, including
sections cut across chunk and part boundaries. Bend also rejects a duplicate, a swap inside a
chunk, a swap across chunks, a swap across parts and a truncated record
(`tests/test_digest_bend.py`: PASS).

Speed: the 548,303 snapshot (1.77 GB, 23.6M records) digests in **87 s** on 16 processes
(~20 MB/s). Bend SHA-256 runs on byte lists.

## 3. Results

| Snapshot | H | Provenance | Records | Raw | zstd -3 | -9 | -19 |
|---|---|---|---|---|---|---|---|
| (a) `g548303.zsnap` | 548,303 | **genesis-verified** (from a consistent copy of the live genesis instance) | 21,867,020 UTXOs; nf: Sprout 1,363,976, Sapling 47,875; roots: Sprout 273,259, Sapling 32,464 | 1.773 GB | **0.556 GB** (1 s, -T0) | 0.518 GB | 0.444 GB (74 s) |
| (b) `t3532265.zsnap` | 3,532,265 | **ORACLE-ASSISTED, NOT genesis-verified** (copy of state-tip) | 27,765 UTXOs, 34,327 oracle prevouts, 144,936 Ironwood nf (only since 3,522,000), Ironwood frontier from follow, 66,228 Ironwood roots; Sprout/Sapling/Orchard frontiers unknown | 12 MB | 9.8 MB | | |
| bench `g_new` | 12,000 | genesis-verified (bench rebuild) | 912,900 UTXOs | 73 MB | 18 MB | | |

Producer time for (a): 200 s in total (rows 66 s, Bend trees 47 s, Bend digest 87 s), max RSS
5.0 GB. Digest (a) = `dd3dc977fa5a48a1548f0ad8929665b3e44dfe8830b9b0b9b845fbd630684412`.

**Size compared with Zakura (~11–12 GB).** This is an estimate, not a measurement, because the
genesis instance is not at the checkpoint yet. Record sizes are measured: 78 B per UTXO and
40 B per nullifier or root. Counts at the checkpoint, from this repo's earlier work:
- Orchard: ~50.5M note commitments (`zcash/consensus/`), so ~50M nullifiers, ≈ 2.0 GB raw. They are
  random bytes and barely compress.
- Sapling: 2.15M nullifiers (`zcash/sapling/README.md`).
- Ironwood: ~0.95M nullifiers.
- Root histories: ≤ 3.1M + 1.8M entries.
- UTXO set: unknown. It fell from 28.8M at 324k to 21.9M at 548k; 20–40M would be 1.6–3.1 GB
  raw, ~0.5–1 GB zstd.

Estimate: **~4–6 GB raw, ~2.5–3.5 GB zstd**, i.e. 3–4× smaller than Zakura. That comes from
leaving out blocks, the tx index, the address index and undo data, which a node with a pinned
state does not need.

### Start time, measured (`measure.py`; sync is the committed `sync.py`, see §7)

| | (a) genesis-verified, 548,303 | (b) oracle-assisted tip, 3,532,265 |
|---|---|---|
| unpack (zstd -d) | 2.0 s | 0.0 s |
| Bend verification (digest + order + chain checks) | 83 s | 1.8 s |
| SQLite import | 32 s (sequential run) | 0.4 s |
| **import, total** | **117 s** | **2.0 s** |
| first window committed by sync.py | 122.5 s | 3.5 s |
| "validating at tip" | to 560,000 (11,697 checkpointed blocks, end of the kept spool): **138.8 s** | live tip 3,532,273 (8 blocks, every consensus rule PASS, Ironwood anchors 13/13 PASS against the snapshot's root history): **3.5 s** |
| same, current code (HEAD `0c58276`, NU7 deploy) | | import 3.6 s; live tip 3,532,289 (24 blocks, every rule PASS, Ironwood anchors 50/50 PASS): **7.1 s** |

The value pools of the snapshot-started node at 560,000 are identical to the live genesis
instance's per-block pools at 560,000: transparent 651,544,077,227,283, Sprout
15,421,526,062,234 and Sapling 20,520,488,117,331 zatoshi. The pools went into the snapshot at
548,303 and bin/rules then tracked 11,697 more blocks in audit mode, with 0 disagreements.

`consume.py` now runs the SQLite import of the big tables in a separate process **while** Bend
verifies, so the import costs about max(verify, import) instead of their sum. The table above
comes from the sequential first run.

**Compared with Zakura's "under 2 minutes":**
- (b) shows the mechanism at the tip: 3.5 s from file to validating at the tip. But it is a
  12 MB oracle-assisted state.
- (a) is a full genesis-verified state of 22M UTXOs: 117 s to import, of which Bend checked
  every byte for 83 s. Zakura's start includes no verification of the snapshot contents.
- Projection for the pinned checkpoint, ~2× the bytes: about 3–4 min of import plus Bend
  verification. Then **full validation of the ~10,000 blocks from 3,522,461 to the tip**.
  - Our tip instance did that at ~9 blocks/s when blocks were local (3,522,461–3,523,460 in
    ~110 s, `logs/sync-tip.log`), so ~18 min.
  - In practice download caps it at 2–7 blocks/s.
- So "validating at tip" from the last checkpoint is ~20–60 min, against Zakura's <2 min.
  Almost all of the gap is the distance from the checkpoint to the tip, not the snapshot.
- The fix is the one Bitcoin Core uses: pin a fresh (H, digest) in every release, near the
  tip. Measurement (b) shows the start is then seconds plus the import.

## 4. What the consumer checks (`consume.py`), exactly

1. **Digest.** Bend recomputes every section root and the digest from the unpacked bytes. The
   digest must equal `pinned.json`'s digest for (H, block hash), or the `--pin` given. With no
   pin, the snapshot is refused (`--unpinned` exists for tests only and sets status
   `snapshot-unpinned`). The manifest's own claimed digest is compared only after that.
2. **Canonical order**: every record, in Bend (strictly increasing).
3. **Block context vs the chain.** The 128 `blk` rows have hashes equal to the Bend-verified
   header chain (`state/hdr/hashes.bin`: zcash/headers Equihash/PoW, re-hashed by
   `hdr/hdrchain`) and are linked by `prev`. `meta.tip` = (H, hash). If H is a Zebra checkpoint
   height, the hash equals the checkpoint.
4. **Frontier ↔ root.** For each known pool: the levels match the tree size bit for bit. Bend
   recomputes the root from the frontier (same programs as the producer), and it must equal
   the stated root and the last root-history entry. An empty tree must have the empty root.
5. **Sapling against the headers.**
   - For every height from 419,200 to min(H, 902,999), the verified header's
     `hashFinalSaplingRoot` (bytes 68..100) must equal the snapshot's Sapling root history
     (the last root at or before that height, or the empty root).
   - In (a) this held at **129,104 / 129,104 headers**, so for H < 903,000 the Sapling
     frontier at H is itself committed by the chain.
6. **Pools not yet active at H** (Sapling 419,200, Orchard 1,687,104, Ironwood 3,428,143):
   frontier size 0 and no roots. Below Sapling activation the header's reserved field must be
   zero.

**Not checked against the chain; covered only by the pinned digest until confirmation:**
- the UTXO set, the nullifier sets and the value pools;
- Sprout roots (no header commits to them);
- Orchard and Ironwood roots, and Sapling roots at or above 903,000. Exception: the three
  roots at H, which the ZIP 221 check binds to block H+1's header (below and §0).

From Heartwood on, the header commits to those roots only through the ZIP 221 history tree
(`hashLightClientRoot`, and from NU5 `hashBlockCommitments = BLAKE2b("ZcashBlockCommit",
historyRoot ‖ authDataRoot ‖ 0^32)`).

**Built (Oct 27 evening): ZIP 221 check of the roots at H** (`histcheck.py`, `consume.py
--history-blocks SPOOL`).
- **What travels with the snapshot.** The manifest carries `history_hint`: the NU6.3 MMR peaks
  of blocks ..H-1, a ~3 KB bin/history state. It is untrusted and not part of the digest.
- **What Bend builds.** `zcash/consensus/gaps/history` bin/history builds block H's leaf from:
  - the verified header and raw block H (tx counts);
  - the snapshot's Sapling, Orchard and Ironwood frontier roots. V3 node data carries Ironwood.
- **The check.** Bend appends that leaf and checks the result against block H+1's
  `hashBlockCommitments`. A MATCH binds the three roots at H to the chain, whatever the hint
  was.
- **Result at 3,532,588:** MATCH. Tampering with any root or with the hint gives MISMATCH (§0).
- **When a MISMATCH rejects the snapshot.** Only with `--history-blocks` and blocks H, H+1
  available. Without them the check is reported NOT CHECKED, never as a pass.
- **Limits.**
  - Older root-history entries are not covered: only the leaf at H is rebuilt by the consumer.
  - The check needs H inside the NU6.3 epoch and before NU7 activation (3,543,405). An H in
    the NU7 epoch needs a hint built from NU7 activation.

**Checked after the import, by full validation from H+1 (sync.py):**
- every new block's spends against the imported UTXO and nullifier sets;
- Ironwood anchors against the imported root history (consume.py writes
  `ironwood_roots.txt`);
- all consensus rules.

A UTXO missing from a bad snapshot would fail the first block that spends it. An extra or
changed UTXO is caught only by the pin or the confirmation.

## 5. Confirmation (`confirm.py`) and status

`meta.snapshot = {height, hash, digest, status, pinned, provenance, checks, imported_at}`.
`status` moves like this:
- `snapshot-assumed` → `confirmed` when confirm.py recomputes the **same Bend digest** from the
  reference (genesis) instance's state at exactly H;
- otherwise → `CONFIRMATION-FAILED`, and the store must be discarded.

confirm.py gets the reference instance's state at H in one of two ways:
- **`--watch`.** It polls the read-only reference store. When the committed tip is exactly H,
  it opens one SQLite read transaction. Under WAL that reader keeps the state at H however far
  the writer goes, so the reference instance is never stopped. The leaf logs are append-only
  and are read up to the lengths recorded at H.
  - The pinned height is the last checkpoint. sync.py ends a window there and drains before
    its first fully validated window, so the tip rests at 3,522,460 while the address index is
    rebuilt from the UTXO set. No patch is needed for that height.
  - For any other H, `patches/sync_snapshot_hold.patch` adds `--snapshot-at H`: a window ends
    at H, is committed, and sync.py waits up to 120 s for the reader's flag file. Tested: the
    hold patch on a copy at 12,500, with the writer continuing to 13,500 during the export.
    The digest equals the one from a sync stopped at 12,500 (`52cb1f2c…`).
- **Undo-depth fallback.** If the reference has passed H by at most `store.UNDO_DEPTH` blocks (now 600), confirm.py rolls a
  *copy* back to H with `store.rollback_to` and exports that. This is cheap for small stores.

Tests of the flip:
- **Independent, genesis-verified.** A snapshot of bench `g_new` (12,000, new code) was
  imported and confirmed against bench `g_old`, rebuilt independently from genesis by the old
  code: same digest `82a6c863…`, so the status became `confirmed`.
- **Live, oracle-assisted.**
  1. Import (b) at 3,532,265 into `c_t`.
  2. `c_t` validated 8 blocks itself; its Ironwood frontier was advanced in Bend over 28 new
     notes.
  3. Export at 3,532,273 → import into `c_t2`.
  4. Confirm against the **live** tip instance (old code still in memory, read transaction at
     the moment its tip was 3,532,273).
  5. Same digest `a4a6525a…`, so `confirmed`. Labelled a test: that reference is not
     genesis-verified.

**RPC.** `patches/rpc_snapshot_status.patch` adds a `snapshot` field to `getblockchaininfo`
(`git apply --check`: applies). Tested on a patched copy:
- `c_t2` returns `{"status": "confirmed", "height": 3532273, …, "provenance": "ORACLE-ASSISTED, NOT genesis-verified…"}`;
- a store without a snapshot returns `{"status": "none", "provenance": "synced from genesis by this node"}`.

## 6. Tests (`tests/`)

`test_snapshot.py STATE`:

| Test | bench g_new (12,000) | genesis copy (548,303) |
|---|---|---|
| determinism: two exports, digest equal and section files byte-identical | PASS | PASS: three separate exports (producer, `confirm.py --pin-only 548303`, re-export of the imported copy) all give `dd3dc977…` |
| round trip: export → zstd → consume (pinned) → `utxo`, `nf`, `blk` context, meta `tip`/`pools` identical to the source; re-export digest and files identical | PASS | **PASS** (consume 107 s; 21.9M UTXO rows streamed and compared) |
| tamper, one UTXO value +1 zat (file repacked with a consistent manifest) | rejected: digest ≠ PINNED | |
| tamper, one nullifier dropped | rejected: digest ≠ PINNED | |
| tamper, one frontier node changed | rejected: digest ≠ PINNED; **with `--unpinned` also rejected by the Bend root check** | |
| tamper, one bit flipped, original manifest | rejected | |
| interrupted import: SIGKILL during the import transaction, then rerun | PASS: no target directory after the kill; the rerun deletes `.importing`, imports, and the re-export digest is equal | **PASS** |

`test_digest_bend.py`: Bend matches the reference, and order and truncation are rejected (PASS).
The tamper tests ran on the small state only. The mechanism (the digest) is the same at any
size, and on the big state each tamper case would take ~4 min. A killed consumer's bulk-import
process stops by itself: it watches for its parent to change. Stale work directories are
removed on the next run.

## 7. Integration and caveats

- **Patches** (I did not edit existing files):
  - `patches/rpc_snapshot_status.patch` (RPC field);
  - `patches/sync_snapshot_hold.patch` (optional: `--snapshot-at H`, flag directory
    `ZEBEND_SNAPSHOT_FLAGS`, default `node/snapshot/work`).
  - Both pass `git apply --check` against the current tree.
- **Code version during the measurements.** Around 14:40, `rules.py` in the working tree was
  half-edited by the NU7 work, which was not yet committed.
  - Run on a plain copy of state-tip, it failed with `KeyError: 'nsm'`.
  - A run a minute earlier gave false `value_balance` FAILs.
  - So the 14:40–14:53 measurements ran the committed code of `f154a32`, copied to
    `work/frozen/` (since deleted).
  - That work was later committed (`0c58276`, live instances restarted at 15:07). The snapshot
    pipeline re-measured on that code passes (table above), and both patches still apply.
- An imported store's `tree_sizes`/leaf logs start at H (`meta.leaf_base`). A future
  `z_gettreestate` must add the base frontier.
- `UNDO_DEPTH` is now 600 (`0c58276`). confirm.py's rollback fallback reads it from store.py.
- **Tree builds at the tip: the earlier estimate was wrong.**
  - Measured one-process speed: 1M Orchard leaves (with per-block roots) take 6.2 min, so
    sequential Sapling plus Orchard would be ~10 h, not ~1–1.5 h.
  - `ptree.py` cuts the leaves into segments of whole blocks (~2^18 leaves or 20k blocks) and
    runs them as parallel Bend processes (14 jobs).
  - Each segment's start frontier is built by the seed mode of
    `zcash/consensus/gaps/trees/{sapling,orchard}_frontier` (another agent's Bend programs,
    uncommitted at the time; the binaries used are hash-recorded in `work/fast/tools`). It
    starts from level-16 chunk roots: hints from `zcash/sapling/data/bend_chunk_roots.bin` and
    `zcash/consensus/orchard/logs`, or computed when missing.
  - Every segment then runs the same `sapfront`/`sinfront` as the one-process build.
  - **Continuity**: segment k's end frontier, pushed from the leaves, must equal segment k+1's
    start frontier, built from the hints. If it holds at every boundary, the result is exactly
    the one-process result, by induction from the empty tree. A wrong hint fails it.
  - Tests on prefixes: identical roots, frontier and empty root to `run_tree` for Sapling
    (132,432 blocks, 45 segments; 29.6 s against 195 s) and Orchard (3,807 blocks).
  - At 3,532,588: Sapling 288 segments, 8.1 min; Orchard 181 segments, 52 min. Continuity
    holds at every boundary, and all chunk roots came from hints.
  - `ZEBEND_SNAP_PTREE=0` restores the one-process build.
  - `snap.py` also no longer lists every record of a 1 GiB part to find its last one
    (`last_record`), which would have used GBs of RSS on the 50M-record Orchard nullifier
    section.
- **The pinned value for 3,532,588 has not been re-derived independently.**
  - It was produced once, by one run on the genesis instance.
  - A second export at exactly that height is no longer possible from the live node (it moved
    on).
  - The consumer side re-verified it: Bend recomputed the same digest from the file, and the
    chain checks passed.
  - A future genesis re-sync with `confirm.py --pin-only 3532588 --watch` (plus the hold patch)
    would be the independent check.

## 8. Files

- `snap.py`: format, Bend driver, producer core, zstd container.
- `produce.py`, `consume.py`, `confirm.py`, `measure.py`, `pinned.json`.
- `ptree.py` (parallel tree build), `histcheck.py` (ZIP 221 hint, embed, check),
  `dumptrees.py` (frontiers and root histories as plain files).
- Kept in `work/`:
  - `work/fast/g3532588.zsnap`, the pinned snapshot (2.42 GB) with its hint;
  - `work/trees_3532588/`;
  - `work/fast/*.log`.
- `bend/{snapdigest,sapfront,sinfront}.bend` → `bin/`. Built with `../../tools/heavy.sh
  ../../zcash/sapling/build.sh bend/X.bend bin/X`.
- `tests/`.
- `patches/`.
- `tools_linker.py`: hard-links a live spool's chunks for replay tests.
- `work/` (git-ignored by `.gitignore`): copies and logs. Delete it when done.
