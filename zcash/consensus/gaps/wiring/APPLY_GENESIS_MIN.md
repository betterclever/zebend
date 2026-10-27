# Minimal unblock for the genesis instance: Sprout JoinSplits in the sapling hook

The genesis instance (`node/state/`, `sync.py` with no args) halted at its first fully
validated window (3,522,461+) with `hook sapling: (3522890, 11) / (3522891, 1) / (3522892, 1)
unsupported-joinsplit`. This is the minimal fix. Trees and ZIP 221 come later (`APPLY.md`).

## What changes

| File | Diff | Effect |
|---|---|---|
| `node/hooks/sapling` | `genesis_min/hooks_sapling.diff` | runs `zcash/consensus/gaps/sprout/hook.py`: same Sapling checks as `zcash/sapling/hook.py`, plus for v4 JoinSplits the joinSplitSig (Ed25519, ZIP 215) and every JoinSplit's Groth16 proof, so these txs become PASS |
| `node/rules.py` | `genesis_min/rules.py.diff` | accepts `verdict <h> <i> SKIPPED <reason>` (counted per reason, never PASS). Not needed for these blocks (the new hook prints SKIPPED only for v2/v3 BCTV14 JoinSplits, which cannot occur above the checkpoint), but makes SKIPPED safe |

Runtime dependencies of the new hook (they must stay in place; treat as live once applied):
`zcash/consensus/gaps/sprout/hook.py`, `zcash/consensus/gaps/sprout/tx_main` (Bend binary: stx.bend + JoinSplit
records + Ed25519 from `zcash/consensus/gaps/ed25519`, already compiled in), `zcash/sapling/tx/g16_raw`,
`zcash/sapling/groth16/data/vk_{spend,output,sprout}.bin`.

Both diffs are against the live files as of 19:50 Oct 27 (`patch --dry-run` OK).

## Steps

```sh
cd /Users/betterclever/projects/zecathon/zebend
# the genesis sync is stopped (it exited after the FAIL). Then:
patch -p1 < zcash/consensus/gaps/wiring/genesis_min/hooks_sapling.diff
patch -p1 < zcash/consensus/gaps/wiring/genesis_min/rules.py.diff
# restart the genesis sync exactly as before (no args), e.g.
cd fullnode && nohup python3 -u sync.py >> logs/sync.log 2>&1 &
```

Note: `node/hooks/sapling` is shared by both instances. The running tip instance runs
`hooks/sapling` per window, so it picks up the new hook at its next window without a restart
(that is safe: same verdicts as before for Sapling-only txs; JoinSplit txs now PASS instead of
FAIL, which would have halted it too). Its `rules.py` change takes effect at its next restart.

## Rehearsal (done, on an APFS clone; `node/state/` was not written)

- `zcash/consensus/gaps/genesis_min/`: copies of the live `node/*.py` with only these two changes,
  live `bin/`, live transparent/orchard hooks; `stateG/` = clone of `state/` at its committed tip
  3,522,460; `spoolG/` = clone of the live spool.
- `sync.py --to 3523000 --keep-spool --writer-cache-mb 512` (log: `genesis_min/rehearsal.log`):

```
sync: state tip 3522460, last checkpoint 3522460, ...
anchors: Ironwood 0/0 PASS; SKIPPED (tree builder pending): orchard 23, sapling 63, sprout 4, ironwood 1316
full validation 3522461..3523000: every consensus rule PASS (turnstile checked); hooks: {'transparent': "PASS {'pass': 1790, 'skipped': 0}", 'sapling': "PASS {'pass': 120, 'skipped': 0}", 'orchard': "PASS {'pass': 1319, 'skipped': 0}"}
committed tip 3523000
```

- The JoinSplit txs individually (HOOK_DEBUG): 3,522,890 tx 11, 3,522,891 tx 1, 3,522,892 tx 1
  and tx 3: each `jsig=1` (Ed25519 valid), `groth16=111` (2 Sapling outputs + 1 JoinSplit proof),
  RedJubjub binding valid -> PASS.

Still SKIPPED in the genesis instance after this step (unchanged, labelled): Sprout/Sapling/
Orchard anchors (until `trees_init.py --genesis`), Ironwood anchors (it has no
`ironwood_roots.txt`), ZIP 221.
