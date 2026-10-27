#!/bin/zsh
# Regenerate the wiring diffs: staged copies (consensus/gaps/fullnode) vs the live files they
# were copied from (consensus/gaps/fullnode/orig, checked equal to fullnode/ by md5 first).
set -e
G=/Users/betterclever/projects/zecathon/bend-zcash/consensus/gaps
L=/Users/betterclever/projects/zecathon/bend-zcash/fullnode
cd $G/wiring
for f in rules.py sync.py store.py; do
  if ! cmp -s $G/fullnode/orig/$f $L/$f; then echo "WARNING: live fullnode/$f changed since it was copied; rebase the diff"; fi
  (cd /Users/betterclever/projects/zecathon/bend-zcash && diff -u --label a/fullnode/$f --label b/fullnode/$f $G/fullnode/orig/$f $G/fullnode/$f) > $f.diff || true
done
cmp -s $G/fullnode/orig/hooks_README $L/hooks/README || echo "WARNING: live hooks/README changed"
cmp -s $G/fullnode/orig/hooks_sapling $L/hooks/sapling || echo "WARNING: live hooks/sapling changed"
diff -u --label a/fullnode/hooks/README --label b/fullnode/hooks/README $G/fullnode/orig/hooks_README $G/fullnode/hooks/README > hooks_README.diff || true
diff -u --label a/fullnode/hooks/sapling --label b/fullnode/hooks/sapling $G/fullnode/orig/hooks_sapling $G/fullnode/hooks/sapling > hooks_sapling.diff || true
for f in trees.py trees_init.py history.py history_init.py ptree.py trees_transfer.py; do
  [ -f $G/fullnode/$f ] && (diff -u --label a/fullnode/$f --label b/fullnode/$f /dev/null $G/fullnode/$f > new_$f.diff || true)
done
wc -l *.diff
