#!/bin/zsh
# Lab tool (reorg tests): an isolated node root next to (never inside) the live node.
#   mklab.sh <lab root> <golden state dir> old|new
# As node/fasttip/tools/mklab.sh: COPIES of node/*.py and node/fasttip/*.py (the deployed code),
# symlinks to the read-only parts (bin, hdr, checkpoints, follow, hooks, ...), an APFS clone
# (cp -c) of the golden state (never the live one), own work/ spool/ logs/.
# new: overlays node/fasttip/reorg/src (tipfeed.py, forkswitch.py, tipsync.py into fasttip/,
# sync.py into node/): the code under test.
set -e
LAB=$1; GOLD=$2; VAR=${3:-new}
REPO=/Users/betterclever/projects/zecathon/zebend
[[ -n $LAB && -d $GOLD ]] || { echo "usage: mklab.sh <lab root> <golden state> old|new"; exit 2; }
[[ $(cd $GOLD && pwd -P) != $REPO/node/state ]] || { echo "refusing to use the live state"; exit 2; }
[[ $LAB != $REPO* ]] || { echo "lab must be outside the repo"; exit 2; }
rm -rf $LAB; mkdir -p $LAB/node/fasttip
for d in $REPO/*(/); do [[ ${d:t} == node ]] || ln -s $d $LAB/${d:t}; done
for f in $REPO/node/*.py; do cp $f $LAB/node/; done
for d in bin hdr checkpoints follow hooks rules bend trees wire validate; do ln -s $REPO/node/$d $LAB/node/$d; done
cp $REPO/node/fasttip/*.py $LAB/node/fasttip/
if [[ $VAR == new ]]; then
  S=$REPO/node/fasttip/reorg/src
  cp $S/tipfeed.py $S/forkswitch.py $LAB/node/fasttip/
  cp $S/sync.py $S/store.py $LAB/node/
fi
mkdir -p $LAB/node/work $LAB/node/spool $LAB/node/logs $LAB/followwork/win $LAB/followwork/deferred
cp -cR $GOLD $LAB/node/state
rm -f $LAB/node/state/chain.sqlite-shm
echo "lab $LAB ($VAR) ready"
