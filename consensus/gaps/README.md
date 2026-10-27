# consensus/gaps: closing the remaining consensus gaps of the Zebend full node

Status: Oct 27, 2026, end of this session. **Nothing here is applied to the live node.** The
changes to live files are proposed as diffs in `wiring/`; new files are proposed as whole files.
They are meant to be applied with a controlled restart at a window boundary (see "Applying").
Every number below came from a command in this directory; "tested" means differential against
the real chain (headers, accepted transactions, anchors) or the Rust crates.

| Gap | What is here | Result | Status |
|---|---|---|---|
| 1a. Hook verdict `SKIPPED <reason>` | `fullnode/rules.py` (staged), `fullnode/hooks/README` | counted as skipped (per reason), never as passed; does not reject the window | done (code read + used by the staged hook; no live item needs it today) |
| 1b. Sprout joinSplitSig (Ed25519, ZIP 215) | `ed25519/` (Bend: SHA-512, F_p, F_l, edwards25519, ZIP 215 decoding, cofactored check) | 62,830/62,830 verdicts = ed25519-zebra 4.2.0 (incl. the 196 ZIP 215 small-order vectors, non-canonical A/R, S ≥ ℓ, mixed order); **168/168 real joinSplitSigs valid** (157 real mainnet txs) | ✅ tested |
| 1b. Sprout Groth16 proofs | `sprout/stx.bend` (copy of sapling/tx/stx.bend + JoinSplit records), verified by `sapling/tx/g16_raw` | **168/168 real JoinSplit proofs valid**; 157/157 proof tampers rejected (digit 0) | ✅ tested |
| 1b. Sprout hook | `sprout/hook.py`, `fullnode/hooks/sapling` (staged) | 157/157 real v4 txs with JoinSplits PASS (148 from 419,200..3.5M + 9 tip-era, 3,522,155..3,523,680); 471/471 tampered copies FAIL | ✅ tested |
| 1b. Sprout anchors incl. interstitial roots | `trees/sprout_js.bend` (Bend: tree + zcashd/Zebra anchor rule), `fullnode/trees.py` | see "Sprout anchors" (genesis..H: every anchor valid, 0 invalid; tampers rejected) | ✅ tested (genesis instance); **SKIPPED in the tip instance** (no Sprout tree before 3,522,000) |
| 2. Sapling/Orchard anchors in the node | `trees/{sapling,orchard}_frontier.bend`, `fullnode/trees.py`, `trees_init.py`, staged `sync.py`/`store.py` | Test A (fresh assumed-state run 3,522,000..3,530,999 on real blocks): every Sapling and Orchard anchor PASS, 0 SKIPPED | ✅ tested |
| 2. Tip-instance seeds at 3,521,999 | `trees/make_seeds.py`, `trees/seeds/` | Sapling, Orchard, Ironwood roots and sizes = chain (Blockchair) and = the roots authenticated by header 3,522,000's ZIP 221 commitment | ✅ tested |
| 2. Sapling root vs header (pre-Heartwood) | `trees.py` (sync), `trees_init.py --genesis` | see Test B | ✅ tested |
| 3. ZIP 221 history tree in Bend | `history/` (Bend), `fullnode/history.py`, `history_init.py` | 0 mismatches: all of Heartwood + Canopy epochs (784,104 headers), 61-block windows at NU5, NU6, NU6.1, NU6.2, NU6.3, Testnet NU7; tip path 3,522,000..3,530,999 every block MATCH | ✅ tested (see `history/README.md`) |

(The results section below is the authoritative list of numbers.)

## Layout

```
ed25519/        Ed25519 with ZIP 215 rules in Bend (+ Rust oracle, tests)        README.md
sprout/         Sprout-capable copy of the sapling hook: stx.bend, tx_main, hook.py, test_hook.py
trees/          Bend tree tools: sapling_frontier, orchard_frontier (follow/frontier.bend interface
                + "front" lines + seed mode), sprout_js (Sprout tree + anchor rule);
                make_seeds.py, make_history.py, seeds/ (tip seeds), t/ (Sprout chain test)
history/        ZIP 221 history tree in Bend (bin/history, histseed), seed_3521999.st   README.md
fullnode/       STAGED copies of the live fullnode files + new modules; orig/ = the live files as
                copied (the diffs are against these). bin/ links the live binaries + the new tools.
harness/        tests on copies: run_A.sh (Test A), test_rollback.py, test_anchor_tamper.py, logs
data/           test blocks (spools of P2P-fetched blocks), fetch_range.py
wiring/         the proposed changes: *.diff, new_*.diff, APPLY.md
```

## Design

**Trees (`fullnode/trees.py`).** The node keeps one Bend frontier per pool in meta `trees`
(`{pool: {frontier, size, root, origin, history_from?}}`) and advances it every window (all
windows, checkpointed or not) with the Bend tools; the root after every block that appends
leaves goes into the existing `anchor` table (with undo), and the pool's state before each such
block into that block's undo data (`store.py`), so `rollback_to` restores the trees exactly. A
pool absent from meta is not tracked: its anchors are SKIPPED, never PASS.

Anchor rule (protocol spec §4.6, Zebra `zebra-state/src/service/check/anchors.rs`, zcashd
`CCoinsViewCache::HaveShieldedRequirements`), checked for every fully validated block:
- Sapling spend / Orchard bundle: the anchor is the root after a block strictly before the tx's
  block (this window's Bend roots, then the anchor table) or the empty tree's root.
- Sprout: the same, or an interstitial root of the same tx: tree(anchor of an earlier JoinSplit
  of the tx) + that JoinSplit's two commitments. The tree of an older anchor is rebuilt in Bend
  from the leaf log's prefix (`bin/sprout`) and its root re-checked. **Bend decides** (sprout_js
  prints W/E/I/X per JoinSplit).
- An instance whose root history starts at `history_from` (the tip instance: 3,428,143) cannot
  tell an older root from an invalid one: such an anchor is SKIPPED with that reason (none occurred
  in Test A).
- Pre-Heartwood Sapling blocks: header `hashFinalSaplingRoot` == the Bend root after the block
  (Fail otherwise). From Heartwood on, every per-block Sapling/Orchard/Ironwood root enters the
  ZIP 221 node data and is authenticated by the next header (below).

**History (`fullnode/history.py`).** `bin/history` per window with side roots from the trees;
every block from `--history-from` (default 3,428,143, the NU6.3 activation, i.e. the epoch of
the last checkpoint; 903,000 = everything from Heartwood) must MATCH or the window fails. State
(~3 KB of MMR peaks) in meta `history`; the state before a window's first block is in that
block's undo data. Without a state the check is SKIPPED until the next activation (the tree
restarts empty there).

**Hook verdict SKIPPED.** `rules.run_hooks` accepts `verdict <h> <i> SKIPPED <reason>`, counts it
per reason, logs it, records `skipped_reasons` in the window's meta, and never counts it as PASS.
The new sapling hook uses it only for v2/v3 (BCTV14) JoinSplits, which cannot occur above the
checkpoint.

## Applying (controlled restart of the tip instance)

See `wiring/APPLY.md`. In short: stop `sync.py --assumed-start` at a window boundary; apply the
diffs; copy the new modules and tools; run `trees_init.py` (seeds + root history) and
`history_init.py` (seed + roll forward over the blocks since 3,522,000, fetched by P2P); restart.
The genesis instance gets `trees_init.py --genesis` (from its own leaf logs) at its next restart.

## Results (all logs under harness/, sprout/, trees/t/, history/)

**Urgent genesis unblock** (`wiring/APPLY_GENESIS_MIN.md`): rules.py SKIPPED + hooks/sapling
switch only. Rehearsed on an APFS clone of `state/` at 3,522,460: window 3,522,461..3,523,000
every rule PASS, sapling hook 120/120 PASS incl. the JoinSplit txs at 3,522,890-892.

**Sprout hook** (`sprout/test_hook.log`): 157 real v4 txs with 168 JoinSplits (148 from
`sapling/data/sig_raw.bin`, 419,200..3.5M; 9 from 3,522,155..3,523,680): 157/157 PASS, every
joinSplitSig valid, every JoinSplit proof valid. Tampers: joinSplitSig bit 157/157 FAIL
(joinsplitsig), proof bit 157/157 FAIL (proof digit 0; binding sig also fails, the sighash covers
JoinSplits), joinSplitPubKey bit 157/157 FAIL.

**Ed25519** (`ed25519/README.md`): 62,830/62,830 verdicts equal ed25519-zebra 4.2.0.

**Sprout anchors** (`trees/t/test_sprout_js.log`): every JoinSplit from genesis to 323,999
(kept genesis spool, blockdelta): **502,367 anchors, 0 invalid** (467,699 earlier-block roots
in the window, 1,940 roots of earlier windows, **32,728 interstitial**); the commitments equal the
genesis instance's leaf log in 324/324 chunks. Tampers: random anchor 33/33 rejected;
interstitial anchor whose first anchor's tree is withheld 51/51 rejected. Not exercised: the
`trees.py` path that rebuilds an older Sprout tree from the leaf-log prefix (the test supplied
those frontiers itself).

**Test A** (`harness/testA_all.log`, `run_A.sh`): empty state + seeds + root history + ZIP 221
seed, then staged sync.py over the 9,000 real blocks 3,522,000..3,530,999 (24 full-validation
windows): Sapling anchors 752 PASS, Orchard 438 PASS + 1 SKIPPED (anchor older than the root
history, 3,428,143), Ironwood 57,667 PASS, Sprout 8 SKIPPED (no Sprout tree before the start);
hooks transparent 29,816 / sapling 1,480 (incl. the 4 JoinSplit blocks) / orchard 47,734 PASS;
**ZIP 221: 9,000/9,000 MATCH**; no FAIL. (Totals summed from the logs; a window cut by heavy.sh's
10-minute limit and redone may be counted twice in the anchor/hook sums.) Rerun after rebasing on
the live `--gated` change: 3,522,000..3,523,800, same result (`runS_rebased.log`).

**Seeds at 3,521,999** (`trees/seeds/seeds.json`): Sapling 73,986,770 leaves, root 15c6108a…;
Orchard 50,476,948, root 0ce2d551…; Ironwood 800,984, root 41fb9639…: each equal to Blockchair
and to the roots in `history/data/seed_leaves.lv`, which block 3,522,000's header authenticates.

**Test B** (`harness/testB_sapling.log`): the genesis instance's Sapling leaf log (copy), Bend
tree: header hashFinalSaplingRoot == Bend root after the block for **483,799/483,799** blocks
419,200..902,999.

**Anchor negatives** (`harness/anchor_tamper.log`): 100 Sapling + 100 Orchard real roots: valid
in the next block, rejected in their own block, 5 blocks earlier, and as random values
(400/400 each pool); unknown anchor: SKIPPED with history_from, FAIL without.

**Rollback** (`harness/rollback_*.log`): Test A state at 3,530,999 rolled back to a window
boundary (3,530,888) and replayed: utxo, nf, blk, tx, anchor, tip, trees, history, leaf logs all
identical. Rolled back mid-window (3,530,950): everything identical except the history state,
which is dropped as designed (SKIPPED until the next activation or `history_init.py`).

## Limits (honest)

- Tip instance: Sprout anchors SKIPPED (no Sprout tree before 3,522,000); Sapling/Orchard root
  history only from 3,428,143 (older anchors SKIPPED with reason); seeds/root history come from
  lightwalletd leaves (Bend-hashed; authenticated by header commitments), not genesis-verified.
- History state lost on a rollback into the middle of a window (tip windows are 1-2 blocks).
- Genesis instance: trees are opt-in (`trees_init.py --genesis`, not run on the live state);
  Orchard costs ~170 µs/leaf + ~9 ms/block in Bend, which would slow the spam era.
- `trees_init.py` / `history_init.py` were rehearsed on copies only, never on live states.
