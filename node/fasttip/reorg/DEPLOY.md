# Deploying node/fasttip/reorg: fast fork choice on the push path (controlled restart)

**Status (Oct 28, 2026): built and tested on lab clones; NOT deployed.** Nothing under
`node/*.py`, `node/fasttip/*.py`, `node/state`, `node/ops` was modified and no live process was
touched. Everything new is under `node/fasttip/reorg/`.

## The bug (from `research/bench/zakura_vs_zebend.md` and `node/logs/sync.log`)

Mainnet 3,532,945: block `5714cf…` (committed by Zebend at 05:01:59 IST) lost to `48cae4…`.
Zakura switched in 133 s; Zebend sat on the stale tip until 05:16:15 and committed the winning
chain at 05:18:30. Cause, in the deployed `tipfeed.py`:

1. follow tap: after its own reorg, zebend_follow.py rewrote `work/win/3532945/block.bin` with
   `48cae4…`; the tap skipped it (`h <= top`, and a height it had already read is never re-read);
2. the child 3,532,946 arrived (tap) with an unknown parent: `_getheaders("follow-tap")` is a
   no-op (no such peer), so the block sat in `orphans` (the status lines show orphans 0 → 9);
3. a push block/headers that did fork only "kicked the fallback"; the fallback ran tiphdr's
   `drop_tip` (cut the last 10 headers blindly, no work comparison), which only happened when
   the 10-minute "push quiet" timer fired. Then sync rolled back 10 blocks (to 3,532,935) and
   download.py fetched 22 blocks over the scarce peers.

Reproduced in the lab with the deployed code (`results/A_oldcode.log`): the real stale block
committed, then the real winning blocks `48cae4…` + 3,532,946 written as follow writes them; after
60 s (fallback disabled in the harness) the node is still on `5714cf…`.

## The fix

`tipfeed.py` (patch) + new `forkswitch.py`; small patches to `sync.py` and `store.py`.

- **Detection, on the push path.** Every block or header that does not extend our verified tip
  goes to a side store (header, block if we have it, source, time) and is walked back through
  the side store to a block of our verified chain (the fork point F). Sources: `inv`'d blocks,
  unsolicited `headers`, getheaders replies (the 5 s header poll and the fork requests), and the
  follow tap, which now re-reads a height at or below our tip when follow rewrites it.
- **Missing links.** If the walk ends at an unknown hash: getheaders with a full locator (our tip,
  16 dense, then doubling, plus the hash 800 below the tip) to the announcing push peer (or another
  connected one). Without push peers, and if follow's files do not fill the gap within 3 s, ONE
  short-lived connection (tiphdr's peer order, at most 2 peers, at most once per 20 s). Full
  replies (160 headers) are continued.
- **Decision (forkswitch.py).** Chain work above F (sum of 2^256/(target+1) from nBits), ours
  from our verified headers, theirs from the competing headers. **Strictly more work required**
  (less or equal: ignored, logged once per branch). Then the competing headers are checked in
  Bend exactly like headers extending our tip (follow's `equihash7`: Equihash, hash <= target,
  links, difficulty by height with the 113 headers below F; `node/hdr/hdrchain`: SHA-256d and the
  link to our hash at F; tiphdr.append's acceptance rule verbatim). A fork deeper than the undo
  depth (600) or below the fixed header files is **refused, loudly**:
  `fasttip: REORG REFUSED: … NOTHING CHANGED: this node stays on its chain and is now on a minority
  fork. Operator: restore a snapshot below F and resync.` (once per fork point per 10 min).
- **Switch.** The header index (`state/hdr/hashes.bin`, `extra.bin`) is switched to F + the
  competing headers, crash-safe (each file replaced atomically: APFS clone, truncate/append, fsync,
  rename; order hashes-cut, extra, hashes-append; `reconcile()` at start-up turns any interrupted
  state into a consistent prefix), while holding the block buffer's lock. Then **sync.py's
  existing reorg path** (unchanged: the tip is off the index → `store.rollback_to` with the undo
  data, `history.window_start_below`) rolls the state back, and the competing blocks come from the
  buffer (blocks already received) or by getdata / follow's files / the gap filler / the fallback.
  Blocks sync handed out are kept (last 64) so a rollback below F needs no download.
- **`sync.py` patch** (`off_index`, only when fed by tipfeed): a window prepared from a block of the
  branch the index just left is dropped ("dropped, not validated") instead of failing the process
  with "hash != verified chain hash".
- **`store.py` patch** (found by the SIGKILL test): the state writer is a separate process; when its
  parent was SIGKILLed it stayed alive forever (and, if killed between apply and commit, kept the
  write lock of an open group, so a restarted node could not write). It now exits within 2 s
  when its parent is gone (SQLite rolls the open group back).
- **Fallback poll kept** (the old live.py cycle, unchanged timers) as a safety net; when it sees
  headers that do not link to our tip it now asks the same fork choice (getheaders + locator, Bend,
  more work) instead of `tiphdr.drop_tip`'s blind 10-header cut. tiphdr.py itself is unchanged.

## Test results (lab clones, real mainnet data)

Final run: `results/summary.jsonl` (19 cases, **all PASS**), one log per case in `results/`.
Machine load average 7-10 (18 cores) during the run. Every reorg case ends at 3,532,957 with
state digest `91a51d58…` (`node/fasttip/tools/digest.py --since 3532935`: meta, blk, **undo**, tx,
nf, anchor, utxo rows, counts, leaf logs) = the reference: a fresh sync of the winning chain
945'..957 from the same 3,532,944 state, one block per window (`rglab/ref`, digest in `rglab/ref_digest_957.txt`).
"announcement" = the moment the competing data reached the node (file written by "follow" / inv or
header reply sent by the mock peer); times are measured by the harness on one clock.

| case | what | announcement -> index switched | -> winning block committed | result |
|---|---|---|---|---|
| A | **the real reorg**: real stale `5714cf…` committed at 3,532,945, then follow writes the real `48cae4…` and 3,532,946 (as it did at 05:0x) | 0.090 s | 0.355 s | switched, digest = ref |
| A_rev | same, child 946 first, its parent 0.5 s later | 0.582 s | 0.832 s | digest = ref |
| A2 | push path: mock peer sends `inv` of 946 only; parent unknown -> getheaders + locator -> fork | 0.034 s | 0.284 s | digest = ref (1 getheaders, 3 getdata) |
| A3 | push path: no inv at all; the getheaders poll (1 s here) gets a reply that forks | 0.738 s | 1.046 s | digest = ref |
| A_offidx | sync took the stale block; its window is held until the index switched | 0.109 s | 0.280 s | window "dropped, not validated" (sync patch), digest = ref |
| A_race@50/120 | winners written 50 / 120 ms after the stale block (stale mid-validation) | 0.102 / 0.089 s | 0.272 / 0.287 s | digest = ref. In this run the switch came before sync took the stale block; in an earlier development run of @120 the stale block was committed 24 ms after the switch and then rolled back (also digest = ref) |
| B2 | **2-block reorg**: our 945x, 946x vs real 945', 946, 947 (follow tap) | 0.210 s | 1.242 s | rolled back 2, digest = ref |
| B3 | **3-block reorg**: our 945x..947x vs real 945'..948 (mock: inv 948, headers, getdata) | 0.033 s | 0.473 s | rolled back 3, digest = ref |
| C0 | **equal work**: real stale 945 vs our real 945' | - | - | ignored ("work 2.881e+12 <= ours 2.881e+12"), state held 6 s, then 946..957: digest = ref |
| C1 | **less work**: real stale 945 (1 block, tap + inv) vs our real 945'..947 | - | - | ignored, held 6 s, digest = ref |
| C2 | **longer but less work**: real 945'..947 (3) vs our 945x, 946x claiming 16x work each | - | - | ignored all 3 prefixes, state digest unchanged |
| C3 | more work but invalid: [real stale 945, 946 re-parented on it (PoW not redone)] | - | - | rejected by Bend (`equihash valid 114/115`), state held, digest = ref |
| E | **deeper than undo**: real headers 3,532,501..3,533,120 (620) vs our 615 relabelled, via 5 getheaders (160 each, continued) | - | - | `REORG REFUSED ... 615 blocks deep` 1.4 s after the first reply; state digest unchanged |
| D_cut | SIGKILL inside the switch after hashes.bin was cut (env crash point) | - | restart -> 957 in 2.19 s | reconcile cut extra.bin; sync rolled back; digest = ref |
| D_extra | SIGKILL after extra.bin was rewritten, before hashes.bin | - | 2.57 s | reconciled; digest = ref |
| D_switch | SIGKILL right after the switch, before sync saw it | - | 2.66 s | digest = ref |
| D_rollback | external SIGKILL on sync's `REORG: tip ... rolling back` line (rollback transaction in flight) | - | 2.02 s | the rollback had not committed: the restart rolled back again; digest = ref |
| D_reapply | external SIGKILL after 3,532,950 of the winning chain committed | - | 0.70 s | digest = ref |

In D_* the restarted node is fed only the winning blocks as follow's files (they stay on disk);
"restart -> 957" is from the second start to 3,532,957 committed. The first D run, before the
`store.py` fix, hung: the orphaned writer process of the killed node kept running (it also held the
test's output pipe); with the fix it exits within 2 s.

**Before (deployed code), same case A** (`results/A_oldcode.log`, fallback off in the harness):
after 60 s still on `5714cf…` ("block 3532946 not committed in 60.0 s").

How the losing branch is made in B/C2/E: mainnet has no 2-3-block stale branch we can fetch, and
valid PoW cannot be produced. So our state is built from REAL blocks (applied by sync.py with
full validation), and then relabelled (`labctl.py relabel`): the header of each of our top blocks
gets one nonce byte flipped (a different hash; no valid PoW: it stands for "a branch this node
accepted earlier"), and the blk rows, tip and header index are rewritten to match. The competing
chain is the real one (real headers, Bend-checked; real blocks, fully validated). The undo data
the rollback uses is the real undo data of those blocks, so "rollback + apply winners = fresh
sync" is a real check. Case A, A_*, C0, C1, C3 use only real, unmodified mainnet data (C3's
second header is deliberately invalid).

## Deploy

Files:
- new: `node/fasttip/reorg/src/forkswitch.py` → `node/fasttip/forkswitch.py`;
- patches (`diff -u` against the live files as of Oct 28 08:40 IST; checked with `patch` on copies):
  `node/fasttip/reorg/patches/{tipfeed,sync,store}.diff` (tipfeed: node/fasttip/tipfeed.py;
  sync, store: node/sync.py, node/store.py). The patched files are byte-identical to
  `node/fasttip/reorg/src/{tipfeed,sync,store}.py`, which the tests ran.

The service definition (`node/ops/zebend.json`, `sync` = `fasttip/tipsync.py --peers 3 --every 60`)
does not change. `node/state` is not touched by the deploy.

`Z=/Users/betterclever/projects/zecathon/zebend`

### 0. Pre-flight (no effect on the running node)

```sh
cd $Z
T=$(mktemp -d); mkdir -p $T/node/fasttip; cp node/sync.py node/store.py $T/node/; cp node/fasttip/tipfeed.py $T/node/fasttip/
(cd $T && for p in $Z/node/fasttip/reorg/patches/*.diff; do patch -p1 --dry-run < $p || echo "PATCH FAILS: $p"; done); rm -rf $T
/opt/homebrew/bin/python3 -m py_compile node/fasttip/reorg/src/*.py
pgrep -fl "node/ops/supervise.py run"; pgrep -fl "fasttip/tipsync.py"
```

### 1. Stop the supervisor WITHOUT stopping its other services

As in `node/fasttip/DEPLOY.md`: SIGKILL ends only the supervisor (its children keep running and
are adopted by the next one).

```sh
kill -KILL $(pgrep -f "node/ops/supervise.py run")
```

### 2. Stop tipsync (sync finishes or drops its current window and commits)

```sh
kill -TERM $(pgrep -f "fasttip/tipsync.py")
while pgrep -f "fasttip/tipsync.py" >/dev/null; do sleep 1; done
tail -3 node/logs/sync.log      # "stopped at committed tip ..." / "fasttip: feed stats ..."
```

### 3. Apply

```sh
cd $Z
cp node/sync.py node/sync.py.pre-reorg; cp node/store.py node/store.py.pre-reorg
cp node/fasttip/tipfeed.py node/fasttip/tipfeed.py.pre-reorg
for p in node/fasttip/reorg/patches/*.diff; do patch -p1 < $p; done
cp node/fasttip/reorg/src/forkswitch.py node/fasttip/forkswitch.py
for f in sync store; do cmp node/$f.py node/fasttip/reorg/src/$f.py; done; cmp node/fasttip/tipfeed.py node/fasttip/reorg/src/tipfeed.py
/opt/homebrew/bin/python3 -m py_compile node/sync.py node/store.py node/fasttip/tipfeed.py node/fasttip/forkswitch.py
```

### 4. Start the supervisor (it starts tipsync with the new code)

```sh
cd $Z && nohup /opt/homebrew/bin/python3 -u node/ops/supervise.py run node/ops/zebend.json >> node/ops/supervisor.log 2>&1 &
sleep 20
/opt/homebrew/bin/python3 node/ops/supervise.py status node/ops/zebend.json   # sync "owned", rpc/mempool/follow "adopted"
tail -20 node/logs/sync.log
```

Expected: the usual start-up (`fasttip: push pickup on 3 peers ...`, `sync: state tip ...`) and per
block `fasttip: block <h> announced ... -> verdict committed in ...` as before. The `fasttip status:`
line every 5 min now also counts `forks seen`, `reorgs`, `forks ignored`, `reorgs refused`.
On a fork: `fasttip: competing chain from <src> (...): ... ignored (more work required)` for an
equal/less-work sibling; on a win `fasttip: REORG: competing chain ... header index switched in N ms:
dropped k header(s), verified tip now H; sync.py rolls the state back to F`, then sync's own
`REORG: tip ... rolling back to F` and the winning blocks' commits. Should a valid heavier fork be
deeper than 600 blocks: `fasttip: REORG REFUSED: ...`; the node then stops following the network, which the supervisor's stall alarms report.

### 5. Rollback

```sh
kill -KILL $(pgrep -f "node/ops/supervise.py run")
kill -TERM $(pgrep -f "fasttip/tipsync.py"); while pgrep -f "fasttip/tipsync.py" >/dev/null; do sleep 1; done
cd $Z && cp node/sync.py.pre-reorg node/sync.py && cp node/store.py.pre-reorg node/store.py
cp node/fasttip/tipfeed.py.pre-reorg node/fasttip/tipfeed.py && rm node/fasttip/forkswitch.py
nohup /opt/homebrew/bin/python3 -u node/ops/supervise.py run node/ops/zebend.json >> node/ops/supervisor.log 2>&1 &
```

State and header index written by the new code have the same format; the old code continues
from them.

## Lab tools (`tools/`) and how to rerun

- `mklab.sh <lab> <golden> old|new`: a lab node root (copies of the live code; `new` overlays `src/`),
  APFS clone of a golden state, own work/spool/logs and its own follow dir (`ZEBEND_FOLLOW_WORK`).
- `labctl.py`: rollback (undo data), set/cut the header index, apply blocks through sync.py (one block
  per window), relabel (test construction for the 2-3 block and less-work cases, see below).
- `scenario.py`: runs the lab's tipsync code (sync.main + tipfeed in one process, as tipsync.py,
  `--window 1`) and plays one case through the follow tap and/or `mockpeer.py` (a local legacy-P2P
  peer serving real headers/blocks: inv, getheaders with locator, getdata). The node under test
  never dials mainnet (`tiphdr.candidate_peers` emptied in the harness).
- `run_tests.py --root <dir> CASE...`: lab + prep + scenario + `node/fasttip/tools/digest.py` vs the
  reference; SIGKILL cases restart the node and check it converges. Output: `results/<case>.log`,
  `results/summary.jsonl`.

Inputs (outside the repo, `/Users/betterclever/projects/zecathon/rglab/`, deletable when done):
`golden` (clone of node/state at 3,533,115 taken right after a commit), `g944` (that clone rolled
back with the undo data to 3,532,935 = window start, then 3,532,936..944 re-applied one block per
window), `blocks/` (real blocks 3,532,920..970 by verified hash, and `stale_5714cf.bin`: the real
stale 3,532,945, obtained by getdata from one mainnet peer, /Zakura:1.6.0/, still holding it at
08:35 IST; SHA-256d `00000000005714cf10a45db2…` and prev = our 3,532,944), `ref/` (reference),
`canon_hdrs_3532380_3533120.bin` (real headers, from the live index).

## Not done / caveats (honest list)

- **Not exercised on mainnet.** Every result above is a lab replay of real data; no live reorg has
  happened under this code. The real stale block came from one peer that still had it.
- **Fork-request connections.** Without a push peer, a missing link costs one short-lived
  connection (tiphdr's peer order: its fixed peers first, which are net.KNOWN and may also be held
  by follow / download; Zebra allows one connection per IP, so one of the two may be reset). At most
  2 peers, at most once per 20 s, only when follow's files did not supply the link within 3 s. In
  the real incident follow's files carried the whole competing chain, so no connection is needed.
- **Fork choice is decided on the Bend-verified headers' work**, before the competing blocks are validated. If
  a heavier chain's blocks then fail validation, sync.py fails closed as before (process exits, the
  supervisor restarts it; it will not commit an invalid block). Zebra instead marks such a chain
  invalid and stays; that is not implemented here.
- **Ties**: equal work is ignored (first seen wins). Among several side children of one header,
  the earliest seen is followed when extending a branch; another child is evaluated when its own
  announcement comes.
- **Names**: hashlib is used only to NAME headers for routing (side store keys, which getdata a
  block answers), as before; what goes into the header index is Bend's hash (hdrchain).
- The writer fix (`store.py`) applies to every SIGKILL of the sync service, not only reorgs.
- Lab leftovers: `/Users/betterclever/projects/zecathon/rglab/` (golden 14 GB APFS clone, g944,
  ref, labs, fetched blocks). Delete when done; nothing there is used by the live node.
