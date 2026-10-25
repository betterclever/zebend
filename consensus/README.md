# consensus/: more Zcash consensus rules in Bend, checked on mainnet

Three rules a full node enforces, implemented in Bend and run on real mainnet data. Each part
has runtime checks against the chain (**tested**) and, where stated, laws about the exact
functions the checker runs that pass `bend PROOF.bend --verdict` (**proven**, no `@unsafe`).

| Part | Real data | Result | Status |
|---|---|---|---|
| Anchor validity, Ironwood (`anchors/`) | 13 real Ironwood anchors from `node/tx`, the full Ironwood tree | 13/13 VALID; 2 forged anchors INVALID; 416/416 per-block roots equal the Rust `orchard` frontier | ✅ tested + 3 laws **proven** |
| Orchard tree from NU5 (`orchard/`) | **all 50,478,033 Orchard leaves**, heights 1,687,104 to 3,528,268 | **770/770** level-16 subtree roots and **6/6** full roots equal the chain | ✅ tested |
| Anchor validity, Orchard (`orchard/`) | 16 real Orchard anchors from `node/tx` (v5 and v6 txs) | 16/16 VALID; 3 tampered cases INVALID | ✅ tested |
| Issuance: subsidy, founders' reward, funding streams, lockbox, ZIP 271 (`issuance/`) | 260 coinbase txs in 26 ranges covering every era | 260/260 blocks, 410/410 required outputs (exact value and script); total issued is consistent with zcashd's supply checkpoint; 2 tampers caught | ✅ tested + 5 laws **proven** |

## Anchor validity (`anchors/`)

The rule (protocol spec §4.6; ZIP 229 for Ironwood): a shielded bundle's anchor must equal
the note commitment tree root at the end of some block **before** the transaction's block.

`anchors_main.bend` builds the Ironwood frontier at block 3,527,599 from parallel subtree roots
(one per set bit of the leaf count, using `node/state/sinsemilla.bend`), replays blocks
3,527,600–3,528,268 one at a time to build the per-block root history, and searches that
history (`hist.bend`'s `find`) for each anchor. Ironwood activated at 3,428,143, so the
history starts with the empty-tree root at 3,428,142.

- 13/13 real Ironwood anchors are VALID. They point 1–10 blocks back, and two (tx_2, tx_19) use
  the empty root at 3,428,142.
- A random anchor and a root used in its own block are INVALID.
- All 416 history entries in the window equal the Rust oracle's (`oracle/out/iw_hist.txt`,
  built with the `orchard` crate's `Frontier`).

Laws (`anchors/LAWS.bend`, proofs in `PROOF.bend`, `--verdict` passes):
- `find_sound`: if `find(xs, a, b) == Some{e}`, then `hits(a, b, e)` (e's root equals `a` and
  e's height is below `b`) and `e` is in `xs`.
- `snoc_keeps`: appending a block's root keeps every earlier entry (the history is append-only).
- `snoc_has`: the appended root is in the history.

## Orchard tree (`orchard/`)

`orchard_main.bend` streams the 1.8 GB leaf file (36-byte records: u32 height, cm_x) from disk
with `File.read_at`, 2^16 leaves at a time, and uses the same Sinsemilla code as `node/state`:
- **Chunk runs:** the root of each complete 2^16-leaf chunk is computed on the Metal GPU
  (`subroot!`) and compared with the chain's level-16 subtree root (`GetSubtreeRoots`). That
  gives **770/770 MATCH**, covering leaves 0..50,462,719, in batches of at most 200 chunks
  (about 165 s per 100 chunks) so that each run stays under the 10-minute heavy-job limit.
  The logs are in `logs/chunks_*.log`.
- **Checkpoints:** `gen_got.py` collects the roots Bend printed into `got_roots.bend`. The
  upper tree (levels 16–31) is built from those roots plus the checkpoint's partial chunk, giving
  6/6 MATCH against `GetTreeState` at 1,687,200, 2,000,000, 2,500,000, 3,000,000, 3,428,142
  and 3,528,268 (`logs/checkpoints.log`).
- **Orchard anchors:** for each anchor, `find_hints.py` asks the chain which earlier block ends
  with that root, and how many leaves the tree has then. Bend treats this hint as untrusted.
  It recomputes the root of the first *n* leaves, checks that *n* is exactly the leaves through
  that block (height(n−1) ≤ h < height(n), read from the file), and checks `H.hits` (root ==
  anchor, h < block). Results:
  - 16/16 VALID. Three v5 transactions at 3,363,40x use the empty Orchard root; tx_13's anchor
    is 7,660 blocks old.
  - A random anchor, a root used in its own block, and a hint whose size is one leaf short are
    all INVALID (`logs/anchors.log`).
  - With a hint, INVALID means "this hint does not witness the anchor", not a search of every
    block. The Ironwood check above does the full search.

The leaf file comes from lightwalletd (`oracle sync orchard`, compact blocks, `zec.rocks`). The
sync is chunk-atomic: a 5,000-block chunk is kept only if its leaf count equals the chain's
`orchardCommitmentTreeSize` at that chunk's last block.

## Issuance (`issuance/`)

`issuance.bend` implements, from the ZIPs and zcashd's `chainparams.cpp`:
- The block subsidy with slow start, the Blossom halving-interval change and halvings.
- The founders' reward (20%, 48 addresses, before Canopy).
- ZIP 207/214 funding streams: Canopy BP/ZF/MG, NU6 ZCG plus the 12% lockbox, and NU6.1 ZCG
  plus its lockbox share.
- The ZIP 271 one-time disbursement of 10 × 7,875 ZEC at 3,146,400.

`cb_main.bend` checks that every required output is present in the real coinbase transaction
(exact value and script, multiset matching):
- **260/260 blocks and 410/410 outputs**, 10 blocks around each of 26 heights across every era.
- The sum of block subsidies over 1..3,146,400 is at least zcashd's
  `nChainSupplyCheckpointTotalSupply`. The difference is 368.58 ZEC, and an independent Python
  computation gives the same number.
- Tamper run (`cb_tamper.bend`): ZCG paid 1 zat short at 3,528,200 and a founders' reward sent to
  the wrong script at 100,000. **Both are caught** (258/260).

Laws (`issuance/LAWS.bend`, `--verdict` passes; `Le(a, b)` is "a ≤ b" witnessed by the gap):
- `halve_succ`: `halve(k+1, m) == div(halve(k, m), 2)`.
- `halve_step_le`: `halve(k+1, m) ≤ halve(k, m)`.
- `halve_le`: `halve(k, m) ≤ m`.
- `total_le`: `total(K, m) ≤ 2m` for every number of eras K.
- `cap`: `n · total(K, m) ≤ n · 2m`. With n = 1,680,000 blocks per era and m = 625,000,000 zat,
  this is the 21M ZEC cap. That instantiation is arithmetic we state; the checker does not
  compute it.

## Not checked / gaps

- **The miner's share and fees.** The coinbase checker checks the required outputs only, not
  that miner outputs ≤ subsidy − required + fees. Compact blocks carry no fees.
- **A law that funding-stream shares sum to at most the subsidy.** We have no such law yet. The
  percentages are tested on mainnet only.
- **NU7** is not active on mainnet and is not modelled.
- **Orchard anchors use chain-supplied hints** (see above). The Orchard tree itself is
  recomputed from leaves, but the leaves come from lightwalletd compact blocks. Their count is
  checked against the chain's tree size, and the roots built from them match the chain.
- Sprout and Sapling anchors, nullifiers and transparent rules are out of scope here.

## Run

```
cd oracle && cargo build --release
./target/release/consensus-oracle sync orchard 1687104 3528268 out/orchard_leaves.bin   # ~1 h
./target/release/consensus-oracle subtrees orchard out/orchard_subtrees.txt
./target/release/consensus-oracle trees orchard 1687200 2000000 2500000 3000000 3428142 3528268 > out/orchard_trees.txt
cd ../orchard && python3 find_hints.py && python3 gen_inputs.py
H=../../heavy.sh; L=../oracle/out/orchard_leaves.bin
$H bend orchard_main.bend -o orchard_main
$H ./orchard_main $L 0 200 1 > logs/chunks_000.log      # ... through chunk 769
python3 gen_got.py && $H bend orchard_main.bend -o orchard_main
$H ./orchard_main $L 1 > logs/checkpoints.log; $H ./orchard_main $L 1 a > logs/anchors.log
cd ../anchors && $H bend PROOF.bend --verdict; cd ../issuance && $H bend PROOF.bend --verdict
```
