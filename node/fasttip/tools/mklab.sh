#!/bin/zsh
# Lab tool: build an isolated node root for tests, next to (never inside) the live node.
#   mklab.sh <lab root> <golden state dir> [code variant: base|fast]
# <lab root>/node gets COPIES of node/*.py (scripts resolve their own directory, so symlinked
# .py files would point back at the live node), symlinks to the read-only parts (bin, hdr,
# checkpoints, follow, hooks), an APFS clone (cp -c) of the golden state (never the live one),
# and its own work/ spool/ logs/. Every other top-level dir of the repo is a symlink, because
# headers.py and tiphdr.py find zcash/ and node/follow/ relative to the node dir's parent.
# variant fast: also copies node/fasttip/*.py and applies node/fasttip/patches/*.diff.
set -e
LAB=$1; GOLD=$2; VAR=${3:-base}
REPO=/Users/betterclever/projects/zecathon/zebend
[[ -n $LAB && -d $GOLD ]] || { echo "usage: mklab.sh <lab root> <golden state> [base|fast]"; exit 2; }
[[ $(cd $GOLD && pwd -P) != $REPO/node/state ]] || { echo "refusing to use the live state"; exit 2; }
rm -rf $LAB; mkdir -p $LAB/node
for d in $REPO/*(/); do [[ ${d:t} == node ]] || ln -s $d $LAB/${d:t}; done
for f in $REPO/node/*.py; do cp $f $LAB/node/; done
for d in bin hdr checkpoints follow hooks rules bend trees wire validate; do ln -s $REPO/node/$d $LAB/node/$d; done
mkdir -p $LAB/node/work $LAB/node/spool $LAB/node/logs
cp -cR $GOLD $LAB/node/state
rm -f $LAB/node/state/chain.sqlite-shm
if [[ $VAR == fast ]]; then
  mkdir -p $LAB/node/fasttip
  cp $REPO/node/fasttip/*.py $LAB/node/fasttip/
  if [[ -d $REPO/node/fasttip/hooks ]]; then
    rm $LAB/node/hooks; mkdir $LAB/node/hooks
    for f in $REPO/node/hooks/*; do cp -p $f $LAB/node/hooks/; done
    for f in $REPO/node/fasttip/hooks/*(N); do cp -p $f $LAB/node/hooks/; done
  fi
  for p in $REPO/node/fasttip/patches/*.diff(N); do (cd $LAB/node && patch -p2 --quiet < $p); done
fi
echo "lab $LAB ($VAR) ready"
