#!/bin/zsh
# Recreate the genesis-mode bench base states used by e2e.sh (APFS clones of work/bench/sspam
# and s324; assumed_state deleted and the addr index deferred, as the live genesis instance runs).
# usage: mkbase.sh; then e.g.
#   e2e.sh $N/fast $B/st/sspam_g $N/work/bench/spool_spam 1802999 new_spam
#   e2e.sh $N/fast/base $B/st/sspam_g $N/work/bench/spool_spam 1802999 base_spam
#   e2e.sh $N/fast $B/st/s324_g $N/work/bench/spool_n 328000 new_cons
set -e
N=/Users/betterclever/projects/zecathon/zebend/node
B=$N/fast/bench
mkdir -p $B/st
for n in sspam s324; do
  rm -rf $B/st/${n}_g; mkdir $B/st/${n}_g
  cp -c $N/work/bench/$n/chain.sqlite $B/st/${n}_g/; cp -cR $N/work/bench/$n/leaves $B/st/${n}_g/
  sqlite3 $B/st/${n}_g/chain.sqlite "delete from meta where k='assumed_state'; delete from addr;
    insert or replace into meta values('addr_deferred','true'); pragma wal_checkpoint(TRUNCATE);"
done
