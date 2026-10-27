# consensus/gaps/history: the ZIP 221 chain history tree, in Bend

Checks every block header's `hashLightClientRoot` (Heartwood, Canopy) and `hashBlockCommitments`
(NU5 onward) in Bend, without an external history-root oracle. Bend builds the history tree
(a Merkle mountain range), computes its root, and compares it with the header.

**Status: implemented and tested on real blocks. Every check below gives 0 mismatches. It is not wired into the node yet.**

## Files

| File | |
|---|---|
| `hist.bend` | the library: epochs, branch ids, node data V1/V2/V3, serialization, BLAKE2b combine, work from nBits (256-bit division), the MMR (append, root), the binary state format, and the per-block check |
| `history.bend` → `bin/history` | **the node interface**: window + side → one line per block + next state |
| `histseed.bend` → `bin/histseed` | builds or extends a tree from precomputed leaf records (used for seeding and whole-epoch tests) |
| `data/seed_3521999.st` | **seed for the tip instance**: the NU6.3 tree of blocks 3,428,143..3,521,999 (93,857 leaves, 9 peaks, 2,720 bytes) |
| `tools/histdata/` (Rust) | per-block Sapling/Orchard/Ironwood roots and per-pool tx counts from lightwalletd (test and seed inputs only) |
| `tools/mkleaves.py`, `mkwin.py`, `fetch.py`, `tn_blk.py`, `run_chain.sh` | test plumbing: build leaf records, window/side files, P2P block fetch, testnet blocks, chained windows |
| `tools/toposort.py` | puts defs in dependency order (the forked compiler rejects forward references) |
| `build.sh` | Bend → C → clang -O3 (same as `sapling/groth16/build.sh`); run it under `heavy.sh` |

Build: `../../../heavy.sh ./build.sh history.bend bin/history` (the same for `histseed`).

## Interface (`bin/history`)

```
bin/history <state.in | -> <window.bin> <side.bin> <state.out> [main|test]     (default main)
```

- **window.bin**: the full node's window format (`fullnode/sync.py window_file`). Records are
  `u32 LE height | 1487-byte verified header | u32 LE length | raw block`, in height order.
- **side.bin**: one 100-byte record per window block, in the same order:
  `u32 LE height | Sapling root 32 | Orchard root 32 | Ironwood root 32`.
  - Each root is the note commitment tree root after the block. Byte order is the 32-byte
    little-endian field encoding (`Node::to_bytes` / `MerkleHashOrchard::to_bytes`), which is
    the same as anchors in transactions and lightwalletd tree states.
  - **32 zero bytes means unchanged**: Bend reuses the previous leaf's end root. Send zeros for
    any pool the block doesn't add notes to. If a block did add notes and gets zeros, its
    check fails; it never passes wrongly.
  - The tree version decides which roots count: V1 ignores Orchard and Ironwood, V2 ignores
    Ironwood.
- **state** (binary, deterministic; `-` means no history):
  - Header: `"ZHT1" | u32 net (0 main, 1 test) | u32 last height | u32 epoch | u32 npeaks`.
  - Then npeaks 300-byte peak records, leftmost first: `u32 branch | u32 ver | commitment 32 | u32 start/end time | u32 start/end nBits | Sapling start/end 32+32 | work 32 (LE) | u32 start/end height | u32 Sapling tx | Orchard start/end | u32 Orchard tx | Ironwood start/end | u32 Ironwood tx`.
  - It holds only the peaks, like Zebra's persisted tree. Bend recomputes the bags when it loads the state.
  - The network comes from the state file when one is given, otherwise from the last argument.
- **Output**: one line per block.
  ```
  hist <h> MATCH|MISMATCH <header field hex> <computed hex> root <history root hex>
  hist <h> n/a                      pre-Heartwood
  hist <h> SKIP no-history          the state doesn't hold the tree of blocks ..h-1
  hist <h> MISMATCH side-height <n> or block-header    side out of step, or block header != verified header
  ```
  - All hex is in internal (header) byte order. Blockchair's `chainhistoryroot` is the same
    root, byte-reversed.
  - `root` is the root of the tree up to h-1, which is what block h commits to.
- Bend computes everything else from the raw block:
  - the block hash (SHA-256d of the verified header), nTime and nBits
  - the per-pool tx counts, using `fullnode/bend/parse.bend`. A tx counts for Sapling if it has spends or outputs, for Orchard or Ironwood if it has actions (Zebra's `*_transactions_count`).
  - for NU5 onward, the ZIP 244 `hashAuthDataRoot` (`node/block/block.bend` `auth56` + `auth_root`; v4 txs use `[0xff;32]`)
  - `hashBlockCommitments = BLAKE2b-256("ZcashBlockCommit", root || authDataRoot || [0;32])`

`bin/histseed <state.in|-> <leaves.bin> <state.out> [main|test]` does the same over 184-byte
leaf records:
`u32 h | hash 32 | u32 nTime | u32 nBits | header field 32 | 3 roots | u32 Sapling/Orchard/Ironwood tx counts`.
It checks Heartwood and Canopy headers directly. For NU5+ blocks it prints `UNCHECKED no-authroot root <r>`, because it doesn't have the auth data root.

## Design (what Bend computes, with sources)

Sources are zcash_history 0.6.0 (`~/.cargo/registry/src/*/zcash_history-0.6.0/src`, the crate
Zebra pins) and Zebra at `consensus/nu7/data/src/zebra` (commit in `consensus/nu7/README.md`).

- **Epochs and versions** (`history_tree.rs:98,121,176`):
  - Heartwood and Canopy use **V1**.
  - NU5, NU6, NU6.1 and NU6.2 use **V2**.
  - NU6.3 and NU7 use **V3**.
  - Zakura uses the same mapping (`zakura-chain/src/history_tree.rs:164,263`).
  - Branch ids come from `network_upgrade.rs:232-245`. Activation heights for Mainnet and Testnet come from `constants.rs`.
- **Leaf** (`primitives/zcash_history.rs:254-363`): every start/end field is set from the block.
  - commitment = block hash
  - time and nBits from the header
  - Sapling root
  - work = ⌊2^256/(target+1)⌋ (`work/difficulty.rs:389`, computed here by restoring long division on 33-byte LE numbers)
  - height, Sapling tx count
  - V2 adds the Orchard root and count. V3 adds the Ironwood root and count.
- **Serialization** (`node_data.rs:87` V1, `:203` V2, `:265` V3):
  - `commitment | start time | end time | start nBits | end nBits | start Sapling | end Sapling | work (32 LE) | CompactSize(start h) | CompactSize(end h) | CompactSize(Sapling tx)`
  - V2 adds `Orchard start | end | CompactSize(Orchard tx)`.
  - V3 adds `Ironwood start | end | CompactSize(Ironwood tx)`.
- **Combine** (`version.rs:43`): commitment = BLAKE2b-256 with personalization `"ZcashHistory" || branch_id LE` (`version.rs:21`) over `ser(left) || ser(right)`.
  - Start fields come from the left node, end fields from the right.
  - Work and counts are summed.
- **Append** (`tree.rs:143`): the new leaf merges with each rightmost peak of the same leaf count.
- **Root**: the peaks are folded left to right as `combine(combine(p0,p1),p2)…` (`tree.rs:87`, `append_leaf`). The history root is `hash(ser(root node))` (`version.rs:102`).
  - Bend keeps a "bag" (the left fold up to that peak) next to each peak, so a block's root costs O(1) combines amortized instead of O(log n).
- **Resets and what each header commits to** (`history_tree.rs:239`; `zebra-state/src/service/check.rs:137`; `block/commitment.rs:102,300`):
  - Block h's header commits to the tree of blocks up to h−1.
  - The tree resets when block h is an activation block: a fresh tree that contains only h.
  - So an **activation block commits to the full tree of the previous epoch**. The one exception is the Heartwood activation block, whose field is `[0;32]`.

## Tests (real blocks; differential against the chain headers)

Nothing below is skipped and reported as passed. `SKIP` lines are counted separately.

| Boundary / range | What ran | Result |
|---|---|---|
| **Heartwood epoch, all of it**: 903,000..1,046,399 | histseed (activation = `[0;32]`, every block's `hashLightClientRoot`) | **143,400 / 143,400 MATCH** |
| **Canopy epoch, all of it**: 1,046,400..1,687,103 | histseed from the Heartwood state (the activation block commits to the full Heartwood tree) | **640,704 / 640,704 MATCH** |
| Heartwood activation window 903,000..903,060 | `history`, state `-` | 61 / 61 MATCH |
| Canopy activation window 1,046,400..1,046,460 (last Heartwood block = 1,046,399 checked above) | `history` from the full Heartwood state | 61 / 61 MATCH |
| **NU5** 1,687,104..1,687,164 | `history` from the full Canopy state: the activation block's commitment = Canopy root + its authDataRoot | **61 / 61 MATCH** |
| NU6 2,726,400..2,726,460 | `history`, state `-` | 60 / 60 MATCH; activation block SKIP |
| NU6.1 3,146,400..3,146,460 | `history`, state `-` | 60 / 60 MATCH; activation block SKIP |
| NU6.2 3,364,600..3,364,660 | `history`, state `-` | 60 / 60 MATCH; activation block SKIP |
| **NU6.3** 3,428,143..3,428,203 | `history` from the full NU6.2 epoch state (63,543 leaves, histseed) | **61 / 61 MATCH**, activation block included |
| **Testnet NU7** 4,465,026..4,465,300 (`consensus/nu7/data/testnet`) | `history ... test`, state `-` | 274 / 274 MATCH; activation block SKIP (the Testnet NU6.3 epoch is not built) |
| **Tip instance, seeded**: 3,522,000..3,530,000 | `data/seed_3521999.st`, then 21 chained windows of 400 blocks (`tools/run_chain.sh`) | **8,001 / 8,001 MATCH** |

Total: 784,104 Heartwood/Canopy headers by histseed plus 8,821 `history` window-block checks (8,699 distinct runs above + the two full-epoch activation windows below), all MATCH. Activation blocks checked against the full previous epoch: Canopy, NU5, NU6.1, NU6.2, NU6.3.

**NU6 → NU6.1 and NU6.1 → NU6.2, with the full old epoch** (same method as NU6.3):

- histseed built the whole NU6 epoch (420,000 leaves, 2,726,400..3,146,399; 144 s) and the whole NU6.1 epoch (218,200 leaves, 3,146,400..3,364,599; 71 s).
- `history` then ran the activation windows from those states:
  - NU6.1 3,146,400..3,146,460: **61 / 61 MATCH**
  - NU6.2 3,364,600..3,364,660: **61 / 61 MATCH**
- Each activation-block MATCH authenticates every leaf of the previous epoch.
- The NU5 → NU6 activation block (2,726,400) was not checked with history. The NU5 epoch
  (1.04 M blocks, including the 2022 Sapling spam) was not built.

**Tamper tests** (all must fail, and do):

| Tamper | Result |
|---|---|
| NU6.1 window, Sapling root of every block flipped | 60 MISMATCH (from the 2nd block on: block h's leaf is first checked by block h+1) |
| NU6.1, Orchard root of every block flipped | 60 MISMATCH |
| NU6.1, Ironwood root flipped (negative control: V2 ignores Ironwood) | 60 MATCH, as expected |
| NU6.1, Orchard root of block 3,146,420 only | blocks 3,146,421.. MISMATCH (40), earlier blocks MATCH (20) |
| NU6.1, one byte of block 3,146,430's coinbase scriptSig (authorizing data, txid unchanged) | exactly block 3,146,430 MISMATCH (via hashAuthDataRoot) |
| NU6.3, Ironwood root of every block / of block 3,428,170 only | 60 MISMATCH / blocks 3,428,171.. MISMATCH (33) |
| Heartwood leaves, Sapling tx count of block 903,050 +1 | blocks 903,051.. MISMATCH (149) |
| Seed state, one byte of a peak flipped | 400 / 400 MISMATCH |

**Blockchair cross-check** (`api.blockchair.com/zcash/raw/block/<h>` → `chainhistoryroot`,
which equals our `root` byte-reversed): equal at 1,687,150, 2,726,450 and 3,428,200. One more
request (3,364,601) helped find a bug. Four requests in total.

**Bugs these tests caught**: a hand-converted NU6.2 branch id (`0x5437f330`, every NU6.2
block MISMATCH), the state-file magic constant, and output-string accumulation that was
quadratic. Each was fixed and everything was rerun.

## Seed for the tip instance (starts at 3,522,000)

`data/seed_3521999.st` = `histseed - data/seed_leaves.lv`, over 3,428,143 (NU6.3 activation) .. 3,521,999.

Inputs per block:

- **Header fields**: hash, nTime, nBits, from the Bend-verified headers (`fullnode/headers.py`, `state/hdr/hashes.bin`).
- **Oracle-sourced, from lightwalletd (zec.rocks)**, via `tools/histdata`:
  - the final Sapling, Orchard and Ironwood roots
  - the per-pool tx counts
  - Method: start from `GetTreeState(3,428,142)`, then append every compact block's cmu/cmx to the frontiers.
  - Every block's tree sizes must equal the block's `chainMetadata`. The last roots must equal `GetTreeState(TO)`.
  - The lightwalletd block hash must equal the verified header's hash.

**How the oracle inputs are authenticated:** block 3,522,000's header commits to the root of
all 93,857 leaves. Bend computed `c4c66f2b…` and it MATCHes the header. Forging any root or
count would need a BLAKE2b collision. All 8,001 blocks after it MATCH as well.

The same holds for every `side.bin` input in the node: a wrong root can't produce a matching
commitment. **But block h's own roots and counts are only checked by block h+1's header.** The
tip block's side inputs stay unauthenticated until the next block arrives.

## Speed (M5 Max, single thread)

- `history`, tip blocks: 400 blocks / 14.9 MB in 5.2 s user. That is **~13 ms per block** (~2.9 MB/s), almost all of it ZIP 244 auth digests. RSS 12 MB.
- `history`, NU6.1 window of 61 blocks: 0.11 s.
- `histseed`: 143,400 Heartwood leaves in 61 s (0.4 ms/leaf); 640,704 Canopy leaves in 274 s; 63,543 NU6.2 leaves in 20 s.

## Caveats for wiring into `fullnode/sync.py`

- **Order and continuity**: windows must be contiguous and in height order. The state carries
  `last height`, and any gap makes later blocks print `SKIP no-history` until the next activation.
- **NU7 (Mainnet 3,543,405)**: the tree resets automatically. The activation block commits to the full NU6.3 tree, so the tip instance must have run without gaps since the seed.
- **Side roots**:
  - Supply the final roots from the node's tree builders, or zeros for pools the block doesn't touch.
  - Every Ironwood-era block's root matters: Orchard and Sapling roots enter V3 node data too.
  - Because of the h+1 delay above, a node that commits per window should treat the last block's side inputs as checked by the next window.
- **Reorgs**: the state has no undo. Keep the `state.out` of earlier windows (one file per window is about 3 KB) and roll back to the one below the fork.
- **Trust**: `history` does not run the wire validator. Feed it only blocks `blockdelta` accepted. A malformed block can only produce MISMATCH, never MATCH.
- **Untested activation heights**: the Testnet heights below NU7 were not exercised; only heights ≥ 4,465,026 were tested. Branch ids for all epochs from Heartwood to NU6.3 were exercised; NU7's is used only on Testnet and was exercised there.
- **Rerun on an empty-output Bend runtime issue**: `sync.py` already reruns blockdelta on empty output. Treat a missing `hist` line the same way: rerun, never pass.
