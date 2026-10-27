# Genesis instance: Sapling, Orchard, Sprout anchors and the ZIP 221 history check go live

Target: the genesis instance (`fullnode/state/`, `sync.py` with no args). It is synced from
genesis, checkpoint-verified to 3,522,460 and fully validated since then. Today its anchors
line reads `anchors: Ironwood n/n PASS`. Sapling, Orchard and Sprout anchors are SKIPPED, and
ZIP 221 is not checked.

After this change it reads:

```
anchors: Ironwood n/n PASS; Sapling n/n PASS; Orchard n/n PASS; Sprout n/n PASS
history (ZIP 221): n MATCH  [trees+anchors x s, history y s]
```

With that, every block above the last checkpoint gets every check Zakura makes.
(Zakura is the reference; the mempool's own admission checks are not part of this change, see
the end of this file.)

All paths below are relative to the repo root `/Users/betterclever/projects/zecathon/zebend`.
`bend-zcash` is a symlink to it (renamed at 23:05 on Oct 27). `G=consensus/gaps`.
`R=$G/genesis_full`: the rehearsal (clone `stateF/`, its spool `spoolF/`, logs `logs/`).

## How: slow work on a clone, minutes of downtime

The one-time init takes about 70 minutes of Bend and runs on an APFS clone while the live node
keeps syncing:
- trees from genesis for all four pools;
- the ZIP 221 history state at the clone's tip.

The clone then follows the tip with the new `sync.py`. At the switch, three things happen:
1. both processes stop at the same committed height (a window boundary, SIGTERM);
2. `trees_transfer.py` copies only the tree data into `state/`;
3. live restarts.

The transfer copies the anchor rows, the tree and history state in the undo records, and meta
`trees` / `history`. Before it writes, it checks that the two states are the same chain state
apart from that data.

Downtime: the stop of the current window, a few seconds of patching, about 5 s of transfer,
and the restart. That is about a minute, plus at most a few windows of clone catch-up.

## Status of the clone (done; rehearsal)

| Step | Command (in `$R/fullnode`) | Result |
|---|---|---|
| clone | `cp -c` of `state/chain.sqlite*`, `leaves/*` and `peers.txt` right after a live commit | `stateF/` at **3,532,556** (21:06) |
| trees | `HEAVY_MAX_MIN=150 HEAVY_MAX_GB=8 heavy.sh python3 -u trees_init.py ../stateF --genesis --ptree 8` | see below |
| history | `heavy.sh python3 -u history_init.py ../stateF --seed ../../history/data/seed_3521999.st --seed-height 3521999 --spool ../spoolHist --origin "..."` | **10,557/10,557 MATCH** (3,522,000..3,532,556), 3.6 min |
| follow tip | `ZEBEND_STATE=../stateF ZEBEND_SPOOL=../spoolF python3 -u sync.py --keep-spool` plus `../tools/feed.sh` (download.py loop, no tiphdr) | running; log `$R/logs/rehearsal.log` |

Results of `trees_init.py --genesis` (log `$R/logs/trees_init.log`):

| Pool | Leaves | Blocks with leaves | Final root | Time |
|---|---|---|---|---|
| Sprout | 1,547,344 | 317,275 | 92ea4f11169eeba7 | 3.3 min |
| Sapling | 73,990,534 | 1,100,060 | 8f995938c0e447a7 | 16 min, 287/287 boundaries equal |
| Orchard | 50,478,799 | 583,276 | 23959b6971f5491d | 43 min, 180/180 boundaries equal |
| Ironwood | 947,448 | 66,415 | cdf34ea28b553635 | 3 min, 3/3 boundaries equal |

How the pools were built:
- **Sprout** used `sprout_js`, sequentially.
- **Sapling, Orchard and Ironwood** used `ptree.py` (8 Bend jobs, continuity-checked segments)
  for every block below the 600-block undo range. The undo-range blocks then ran sequentially,
  because the undo records need each one's before-state.
- **Header check:** for 483,799/483,799 blocks (419,200..902,999), the header's
  hashFinalSaplingRoot equals the Bend Sapling root after the block.
- **Commit:** 2,067,026 anchor rows, plus tree state in the 376 undo records whose blocks
  append leaves, in one transaction.
- **Load:** the timings are under a load average of about 37, with other agents running.

What authenticates these trees:
1. **Pre-Heartwood headers:** the Sapling header check above.
2. **ZIP 221:** the history roll-forward matched 10,557/10,557 header commitments, and each
   commitment covers the Sapling, Orchard and Ironwood root after every block from 3,522,000
   on.
3. **Follow's roots:** the own Ironwood roots equal follow's committed roots at **66,415/66,415**
   heights.
4. **Sprout:** the anchors were already tested from genesis to 323,999 (`trees/t`); the
   Sprout-era headers carry no tree root.

## Source of truth for Ironwood anchors: the node's own tree

With these changes, `anchor_checks` lets the node's own trees decide every pool they track,
**Ironwood included**. Follow's roots remain a fallback, used only when an instance has no own
Ironwood tree. That fallback is the audit's code path, unchanged: committed `roots_bytes`
prefix, re-read on a miss, FAIL only if follow is on the same chain at h-1 or above, otherwise
SKIPPED. The two coexist.

Why the own tree:
1. **Same chain, same transaction.** It is built from this instance's own leaf logs, advanced
   in the same window, committed in the same transaction and rolled back with the same undo
   data. Follow is a separate process that can lag behind or be on another branch, which is
   why the audit had to add the SKIPPED case.
2. **Authenticated every block.** Its roots feed the ZIP 221 node data, so every MATCH also
   proves them. Follow's roots enter no commitment check here.
3. **No runtime dependency on follow.** Anchors are never SKIPPED because follow is behind.

Follow is kept as an independent cross-check: 66,415/66,415 equal roots, above. The log
labels which source was used: `Ironwood n/n PASS` for the own tree,
`Ironwood n/n PASS (follow's roots)` for the fallback.

## Files

| Live file | Change | Source |
|---|---|---|
| `fullnode/sync.py` | trees every window; own-tree anchors for all 4 pools (follow fallback kept); ZIP 221 per window; `--history-from`; per-instance work dirs `work/{trees,history}/<state>`; trees/history timings in the history line; on a reorg, the rollback goes down to a window start so the ZIP 221 state survives | `$G/wiring/sync.py.diff` (rebased on the live file after c1a27aa + 5984f6b) |
| `fullnode/store.py` | undo records carry the tree / history state; `rollback_to` restores meta `trees` / `history` | `$G/wiring/store.py.diff` |
| `fullnode/hooks/README` | documents SKIPPED and the Sprout checks (text only) | `$G/wiring/hooks_README.diff` |
| `fullnode/{trees,history,trees_init,history_init,ptree,trees_transfer}.py` | new | `$G/wiring/new_*.diff` (= `$G/fullnode/*.py`) |
| `fullnode/bin/{sapling_frontier,orchard_frontier,sprout_js,history}` | new Bend binaries (sha256 prefix 482c1c07be48f988, 60b4cb09dfde984f, b7ab503461db6175, 8b6d7398e5bce742) | `$G/trees/`, `$G/history/bin/` |

`rules.py` and `hooks/sapling` need nothing: SKIPPED and the Sprout hook are already live.
`wiring/rules.py.diff` and `wiring/hooks_sapling.diff` were removed, since they are applied.
Every diff passes `patch --dry-run -p1` against the live tree as of 23:10 Oct 27.
`wiring/make_diffs.sh` regenerates the diffs, and warns if a live file changed since then.

## Cutover (exact commands)

```sh
cd /Users/betterclever/projects/zecathon/zebend
G=consensus/gaps; R=$G/genesis_full
```

### 0. Preconditions (live keeps running)

```sh
tail -5 $R/logs/rehearsal.log      # clone at the tip, last lines "history (ZIP 221): n MATCH", "committed tip N"
tail -2 fullnode/logs/sync.log     # live: "committed tip M" with M close to N
cat $R/logs/rehearsal.pid $R/logs/feedF.pid   # clone sync and its feeder; both must be alive
```

If the clone sync is not running, restart it (it catches up from its tip on its own):

```sh
cd $R && (pgrep -F logs/feedF.pid >/dev/null || { nohup tools/feed.sh $PWD/stateF $PWD/spoolF > logs/feedF.log 2>&1 & echo $! > logs/feedF.pid; })
cd fullnode && BEND_NO_TELEMETRY=1 ZEBEND_STATE=$PWD/../stateF ZEBEND_SPOOL=$PWD/../spoolF nohup python3 -u sync.py --keep-spool >> ../logs/rehearsal.log 2>&1 & echo $! > ../logs/rehearsal.pid
cd ../../../..
```

Wait until it logs `committed tip` at the live height.

### 1. Stop the clone at a window boundary

```sh
kill -TERM $(cat $R/logs/rehearsal.pid)
# expect: "stop requested: exiting after this window" then "stopped at committed tip Tc"
until ! pgrep -F $R/logs/rehearsal.pid >/dev/null; do sleep 1; done; tail -1 $R/logs/rehearsal.log
Tc=$(sqlite3 "file:$R/stateF/chain.sqlite?mode=ro" "select json_extract(v,'\$.height') from meta where k='tip'"); echo $Tc
```

### 2. Stop live at a window boundary, at or above Tc (downtime starts)

```sh
LIVE=$(pgrep -fx '.*Python -u sync.py'); lsof -p $LIVE | grep cwd   # must be .../fullnode
# wait for live's committed tip >= Tc (a new block every ~75 s)
until [ $(sqlite3 "file:fullnode/state/chain.sqlite?mode=ro" "select json_extract(v,'\$.height') from meta where k='tip'") -ge $Tc ]; do sleep 2; done
kill -TERM $LIVE
until ! kill -0 $LIVE 2>/dev/null; do sleep 1; done; tail -2 fullnode/logs/sync.log
# expect: "stop requested: exiting after this window" / "stopped at committed tip T1"
T1=$(sqlite3 "file:fullnode/state/chain.sqlite?mode=ro" "select json_extract(v,'\$.height') from meta where k='tip'"); echo $T1
```

### 3. If T1 > Tc: the clone catches up to exactly T1 (seconds per window; the feeder supplies the blocks)

```sh
[ $T1 -gt $Tc ] && (cd $R/fullnode && BEND_NO_TELEMETRY=1 ZEBEND_STATE=$PWD/../stateF ZEBEND_SPOOL=$PWD/../spoolF \
   python3 -u sync.py --to $T1 --keep-spool >> ../logs/rehearsal.log 2>&1; tail -3 ../logs/rehearsal.log)
# expect: anchors / history lines as below, then "stopped at committed tip T1"
```

### 4. Apply the code (seconds)

```sh
patch -p1 < $G/wiring/sync.py.diff
patch -p1 < $G/wiring/store.py.diff
patch -p1 < $G/wiring/hooks_README.diff
for f in trees history trees_init history_init ptree trees_transfer; do patch -p1 < $G/wiring/new_$f.py.diff; done
cp $G/trees/sapling_frontier $G/trees/orchard_frontier $G/trees/sprout_js fullnode/bin/
cp $G/history/bin/history fullnode/bin/
python3 -m py_compile fullnode/sync.py fullnode/store.py fullnode/trees.py fullnode/history.py fullnode/trees_transfer.py && echo compiled
```

### 5. Transfer the tree data into `state/` (about 5 s; one transaction)

```sh
cd fullnode
python3 -u trees_transfer.py ../$R/stateF state --dry-run
python3 -u trees_transfer.py ../$R/stateF state
```

Expected output (rehearsed on a clone of live at 3,532,652):

```
src tip 3532652 00000000003a4dc3; dst tip 3532652 00000000003a4dc3
sprout: leaf logs identical (1547344 leaves, sha256 7f0a44eafc60ce68); tree root 92ea4f11169eeba7
sapling: leaf logs identical (73990562 leaves, ...); tree root fe45faae864efe55
orchard: leaf logs identical (50478809 leaves, ...); tree root 6387db5dd72e918c
ironwood: leaf logs identical (948050 leaves, ...); tree root 9b6c28d2737e87b1
undo: 600 blocks 3532053..3532652 identical apart from the tree state (tree state in 389, history state in 3)
anchor rows: src 2067109, dst 0
committed: 2067109 anchor rows, 600 undo records, meta trees/history at 3532652
```

`REFUSED: ...` means nothing was written, and the reason is printed:
- tips differ: redo step 3;
- a leaf log or undo record differs: the chains diverged, so stop and investigate.

### 6. Restart live (downtime ends)

```sh
echo "=== restart $(date +%H:%M): Sapling/Orchard/Sprout/Ironwood anchors from own Bend trees, ZIP 221 (consensus/gaps APPLY_GENESIS_FULL)" >> logs/sync.log
nohup python3 -u sync.py >> logs/sync.log 2>&1 &
```

Expected log (seen on the transferred clone `$R/stateL`, log `$R/logs/cutover_L.log`):

```
history: state at T1 (seeded at 3,521,999 (...seed_3521999.st, NU6.3-epoch tree, validated by header 3,522,000); rolled forward with this instance genesis-built tree roots); checked from 3428143
trees: sprout size ... root ... (built from this instance's leaf logs since genesis); sapling size ...; orchard size ...; ironwood size ...
sync: state tip T1, last checkpoint 3522460, verified headers to ..., 16 Bend jobs
  anchors: Ironwood 49/49 PASS; Sapling 1/1 PASS; Orchard 0/0 PASS; Sprout 0/0 PASS
  full validation 3532647..3532660: every consensus rule PASS (turnstile checked); hooks: {...}
  history (ZIP 221): 14 MATCH  [trees+anchors 0.20 s, history 0.06 s]
committed tip 3532660: ...
```

For comparison, the old code logged `anchors: Ironwood 49/49 PASS; SKIPPED: sapling 1` for
that same window, 3,532,647..3,532,660. Sprout is `0/0 PASS` at the tip, because there has
been no JoinSplit since 3,523,680. When one comes, sprout_js decides it, interstitial roots
included.

### 7. After the switch

```sh
kill $(cat ../$R/logs/feedF.pid)     # the clone's feeder; the clone sync already stopped in step 1
# optional: same state digest on both sides (about 3.5 min each, read-only)
python3 ../$R/tools/digest_full.py state > /tmp/d_live.txt; python3 ../$R/tools/digest_full.py ../$R/stateF > /tmp/d_clone.txt; diff /tmp/d_live.txt /tmp/d_clone.txt && echo IDENTICAL
# (only meaningful before live commits a new block; otherwise compare tables except tip/blk/undo)
# then free the clones:  rm -r $R/stateF $R/stateF0 $R/stateL $R/spoolF $R/spoolHist $R/spoolH
```

### Back-out

The old code runs unchanged on a transferred state:
- it never reads meta `trees` / `history`;
- it ignores the extra undo keys;
- its `rollback_to` deletes the anchor rows listed in undo, as before.

So back-out is the code only:

```sh
git checkout fullnode/sync.py fullnode/store.py fullnode/hooks/README
rm fullnode/{trees,history,trees_init,history_init,ptree,trees_transfer}.py
```

Then restart `sync.py` as in step 6.

### Fallback if the clone is lost (no transfer possible)

Run the same init on a fresh clone. It is the same as step 0 with a new clone:
1. `cp -c` of `state/` right after a commit;
2. `trees_init.py <clone> --genesis --ptree 8` under `heavy.sh`: about 70 min;
3. `history_init.py <clone> --seed ../$G/history/data/seed_3521999.st --seed-height 3521999 --spool <spool>`.
   The spool must hold blocks 3,522,000..clone tip:
   - `$G/genesis_min/spoolG` has 3,522,000..3,532,464;
   - `$R/spoolHist` has up to 3,532,556;
   - fetch the rest with `ZEBEND_STATE=<clone> ZEBEND_SPOOL=<dir> python3 download.py --from A --to B --peers 4`.
     `$G/data/fetch_range.py` only knows heights below 3,528,280, because it reads `routing.bin`.
4. Follow the tip, then steps 1-7.

Do not run the init on `state/` itself. It works, but the node would be down for the whole
build.

## Rehearsal results (all on clones; `fullnode/state/` never written)

1. **Window after window to the tip** (`$R/logs/rehearsal.log`).
   - The clone at 3,532,556 runs the new `sync.py`.
   - Its first window was 3,532,557..3,532,649 (93 blocks):
     `anchors: Ironwood 259/259 PASS; Sapling 6/6 PASS; Orchard 4/4 PASS; Sprout 0/0 PASS`,
     `history (ZIP 221): 93 MATCH`.
   - Then one window per new block, every one all PASS / MATCH.
2. **A real reorg in the middle of the rehearsal.** At 23:18 the verified header chain was cut
   back to 3,532,646. Live itself rolled back from 3,532,656 to 3,532,646.
   - The clone was at 3,532,652. Its last window start with a ZIP 221 state in undo was
     3,532,557, so the new reorg path rolled back to **3,532,556 instead of 3,532,646**:
     `history: rolling back to 3532556 instead (...)`.
   - It then replayed 3,532,557..3,532,660 with every anchor PASS and 90 + 14 MATCH.
   - The ZIP 221 state survived the reorg. The old rollback would have dropped it until the
     NU7 activation.
3. **Cutover dress rehearsal** (`$R/stateL`):
   - live was cloned at 3,532,652, the clone was stopped at 3,532,652, and the transfer
     committed in 3.6 s;
   - `tools/digest_full.py` on both states was **IDENTICAL**: utxo, nf, tx, addr, blk, anchor
     (2,067,109 rows) and undo tables, tip, pools, leaf lengths, leaf files, meta trees and
     history;
   - the new `sync.py` on `stateL` then went through the reorg above and produced the
     expected lines.
4. **Tampering** (`$R/tools/test_tamper.py`, log `$R/logs/tamper.log`): **24/24 as expected.**
   - **(A) Old roots, all eras.** 25 random real roots per pool: Sprout from 29,920, Sapling
     from 428,269, Orchard from 1,708,990, Ironwood. Each is a valid anchor in h+1 and rejected
     in h and in h-5; random values are rejected (4 × 100 checks).
   - **(B) `check_anchors`, the sync path.** An anchor equal to a root from 419,212 (Sapling),
     1,687,209 (Orchard) or 3,428,154 (Ironwood) PASSES; a random anchor FAILS.
   - **(C) Sprout, the real JoinSplit blocks 3,522,890..892.**
     - The tree before them was rebuilt in Bend from the leaf-log prefix (`bin/sprout`; this
       `trees.py` path had not been exercised before).
     - The 4 real JoinSplit anchors PASS.
     - Each anchor replaced by a random value FAILS (4/4), and by the root after its own
       block FAILS (4/4).
   - **(D) ZIP 221.** 3,522,000..3,522,019 from the seed with the genesis-built roots:
     20 MATCH. One Sapling, Orchard or Ironwood root altered: MISMATCH at the next block (3/3).
5. **Rollback and re-apply** (`$R/tools/rollback_test.py`, log `$R/logs/rollback_test.log`), on
   the transferred live clone `stateL` at 3,532,667.
   - The test asked for a rollback to 3,532,655, which is mid-window. `window_start_below`
     aligned it to 3,532,646, and the ZIP 221 state was restored from undo.
   - The test then replayed 3,532,647..3,532,667 with the original window cuts
     (14 + 2 + 2 + 3 blocks): every anchor PASS, 21 MATCH.
   - **Result: identical state digest.** Every table, including the anchor table
     (2,067,122 rows) and the 600 undo records, plus tip, pools, leaf logs and meta
     trees/history, is equal.
   - The undo records carry the history state at window starts. Replaying with different
     window cuts therefore gives an equal chain state but a different undo digest. A first run
     showed exactly that and nothing else.

## Cost

One-time:
- **trees_init**, with load average ~37: 66 min wall (Sprout 3.3, Sapling 16, Orchard 43,
  Ironwood 3 min). It holds `.heavy.lock` for that whole time, with RSS at most about 5 GB
  (8 Bend jobs).
- **history_init:** 3.6 min.

At the switch:
- `trees_transfer.py`: 3.6 s (dry run 5.8 s);
- patching and copying: seconds;
- live restart: about 1 s more, for 4 empty-root Bend runs.

Per window at the tip (the bracket in the history line):

| Window | trees+anchors | history |
|---|---|---|
| 1 block | 0.00-0.03 s | 0.01 s |
| 14 blocks | 0.19-0.20 s | 0.05-0.06 s |
| 90-93 blocks | 0.60-0.65 s | 0.45-0.50 s |

In a 1-block window that is under 0.05 s next to rules and hooks of about 0.2-0.4 s, and
blocks arrive every ~75 s. In the spam era a block can add hundreds of Orchard leaves, at
roughly 0.1-0.2 ms per leaf plus about 6 ms per block that appends.

## Limits (honest)

- **History is seeded, not built from activation.** The ZIP 221 state is seeded at 3,521,999.
  The seed is the NU6.3-epoch tree from 3,428,143 (`seed_3521999.st`), which block 3,522,000's
  header commitment proves. From there it is rolled forward with this instance's own roots.
  It was not rebuilt from the NU6.3 activation inside this instance: that would mean fetching
  ~94k spam-era blocks.
- **Deep reorgs drop the history state.** A reorg deeper than the first window after the
  switch has no ZIP 221 state in undo. The history state is then dropped, logged, and SKIPPED
  until the NU7 activation at 3,543,405 or a new `history_init.py`. Undo records written
  after the switch carry it, so this only applies right after the switch.
- **The mempool is not covered.** `mempool/admit.py` still checks only Ironwood anchors against
  follow and reports Sapling, Orchard and Sprout anchors SKIPPED. Block validation does not
  depend on it, but it could now use the `anchor` table. That is a follow-up.
