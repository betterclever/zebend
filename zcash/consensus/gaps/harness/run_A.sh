#!/bin/zsh
# Test A: a fresh assumed-state instance from 3,522,000 with the staged (new) fullnode code over
# real blocks 3,522,000..TO (spool $SPOOL, default data/spoolB = the 9,000 P2P blocks
# 3,522,000..3,530,999 the history work fetched), with the trees seeded at 3,521,999
# (trees/make_seeds.py, NU6.3-era root history) and the ZIP 221 seed. Never touches live state.
# RESUME=1: continue the existing state (no init).
set -e
G=/Users/betterclever/projects/zecathon/zebend/zcash/consensus/gaps
TO=${1:-3524000}
S=${STATE:-$G/harness/stateA}
SD=$G/trees/seeds
export BEND_NO_TELEMETRY=1
cd $G/fullnode
if [ -z "$RESUME" ]; then
  rm -rf $S; mkdir -p $S
  cp /Users/betterclever/projects/zecathon/zebend/node/state-tip/ironwood_roots.txt $S/
  python3 trees_init.py $S --seed sapling=$SD/sapling_3521999.frontier --seed orchard=$SD/orchard_3521999.frontier \
    --seed ironwood=$SD/ironwood_3521999.frontier --seed-height 3521999 \
    --history sapling=$SD/sapling_history.txt --history orchard=$SD/orchard_history.txt --history ironwood=$SD/ironwood_history.txt \
    --origin "seeded at 3,521,999 (zcash/consensus/gaps/trees: Bend frontiers from chunk roots + leaves; root history from 3,428,143); not genesis-verified"
  python3 history_init.py $S --seed $G/history/data/seed_3521999.st --seed-height 3521999
fi
ZEBEND_STATE=$S ZEBEND_SPOOL=${SPOOL:-$G/data/spoolB} python3 -u sync.py --assumed-start 3522000 --to $TO --keep-spool --jobs 8 --window ${WINDOW:-200}
