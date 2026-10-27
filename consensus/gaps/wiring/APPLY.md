# Applying consensus/gaps to the live node (controlled restart)

All paths relative to `bend-zcash/`. `G=consensus/gaps`. Regenerate the diffs first:
`$G/wiring/make_diffs.sh` (it warns if a live file changed since it was copied to `$G/fullnode/orig/`).

## Files

| Change | Kind | What |
|---|---|---|
| `fullnode/rules.py` | `rules.py.diff` | hook verdict `SKIPPED <reason>` (counted per reason, never PASS) |
| `fullnode/sync.py` | `sync.py.diff` | trees (`trees.py`) every window; Sapling/Orchard/Sprout anchors; ZIP 221 check (`history.py`), `--history-from` |
| `fullnode/store.py` | `store.py.diff` | undo data carries the tree / history state; `rollback_to` restores meta `trees` / `history` |
| `fullnode/hooks/README` | `hooks_README.diff` | documents SKIPPED and the Sprout checks |
| `fullnode/hooks/sapling` | `hooks_sapling.diff` | runs `consensus/gaps/sprout/hook.py` (Sapling + Sprout JoinSplits) |
| `fullnode/trees.py`, `trees_init.py`, `history.py`, `history_init.py` | new files (`new_*.diff`, or copy from `$G/fullnode/`) | |
| `fullnode/bin/{sapling_frontier,orchard_frontier,sprout_js,history}` | new binaries | copy from `$G/trees/` and `$G/history/bin/` (or rebuild: `$G/trees/build.sh X.bend X`, `$G/history/build.sh history.bend bin/history`) |

The new hook keeps running from `consensus/gaps/sprout/` (hook.py, tx_main) and imports
`consensus/gaps/ed25519/`: treat those directories as live once applied (or move them under
`sapling/` and adjust the path in `fullnode/hooks/sapling`).

## Tip instance (`state-tip/`)

```sh
# 1. stop the tip sync at a window boundary (SIGTERM: it exits after the current window)
kill -TERM <pid of sync.py --assumed-start>
# 2. apply the diffs and copy the new files (above)
# 3. blocks 3,522,000..tip for the ZIP 221 roll-forward (3,522,000..3,530,999 are in $G/data/spoolB)
T=$(python3 fullnode/rpccli.py --port 18233 getblockcount)
python3 $G/data/fetch_range.py 3531000 $T $G/data/spoolC
cp $G/data/spoolB/3522000.blk $G/data/spoolC/   # (hard link is fine)
# 4. trees: seeds at 3,521,999 + root history 3,428,143..3,521,999 + the instance's own leaf logs
cd fullnode
SD=../$G/trees/seeds
python3 trees_init.py state-tip --seed sapling=$SD/sapling_3521999.frontier --seed orchard=$SD/orchard_3521999.frontier \
  --seed ironwood=$SD/ironwood_3521999.frontier --seed-height 3521999 \
  --history sapling=$SD/sapling_history.txt --history orchard=$SD/orchard_history.txt --history ironwood=$SD/ironwood_history.txt \
  --origin "seeded at 3,521,999 (consensus/gaps/trees); root history from 3,428,143; not genesis-verified"
# 5. ZIP 221 state: seed + roll forward over 3,522,000..tip (every block must MATCH)
python3 history_init.py state-tip --seed ../$G/history/data/seed_3521999.st --seed-height 3521999 --spool ../$G/data/spoolC
# 6. restart as before
ZEBEND_STATE=$PWD/state-tip ZEBEND_SPOOL=$PWD/spool-tip python3 sync.py --assumed-start 3522000 ...
```

Expected log per window: `anchors: Ironwood n/n PASS; Sapling n/n PASS; Orchard n/n PASS; Sprout 0/0
PASS, k SKIPPED (no Sprout tree before the assumed start)`, `history (ZIP 221): n MATCH`, hooks
`sapling: PASS` for txs with JoinSplits.

Rehearsed in `$G/harness` (Test A: the same init on an empty state, then 9,000 real blocks).
`trees_init.py` / `history_init.py` on the live `state-tip` itself were NOT run (only on copies).

## Genesis instance (`state/`)

Optional; opt-in (a pool absent from meta `trees` stays untracked, exactly as today):
`python3 trees_init.py state --genesis` (builds every pool from the leaf logs since genesis and
checks the header `hashFinalSaplingRoot` of every block 419,200..902,999). Orchard costs
~170 µs/leaf + ~9 ms per block in Bend (single process): ~15 min for today's 4.1M leaves, and
it adds that per-window cost to the spam era. The ZIP 221 check needs no init there: with
`--history-from 3428143` (default) it starts empty at the NU6.3 activation, long before the
checkpoint.
