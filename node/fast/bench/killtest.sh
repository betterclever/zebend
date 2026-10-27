#!/bin/zsh
# SIGKILL test: reference run g_new(12000) -> 20000 vs. a run SIGKILLed (whole process tree:
# sync, state writer, Bend children) mid-window and restarted.
W=/Users/betterclever/projects/zecathon/zebend/node/work/bench; mkdir -p /Users/betterclever/projects/zecathon/zebend/node/fast/bench/st; cd /Users/betterclever/projects/zecathon/zebend/node/fast/bench/st
export BEND_NO_TELEMETRY=1 ZEBEND_SPOOL=$W/spool_g
rm -rf k_ref k_kill; mkdir k_ref k_kill
for d in k_ref k_kill; do cp -c $W/g_new/chain.sqlite $d/ && cp -cR $W/g_new/leaves $d/; done
ZEBEND_STATE=$PWD/k_ref python3 ../../sync.py --keep-spool --to 20000 > k_ref.log 2>&1
ZEBEND_STATE=$PWD/k_kill python3 ../../sync.py --keep-spool --to 20000 --window 500 > k_kill.log 2>&1 &
main=$!
# wait until at least one group has committed and the next is in flight, then kill everything
until grep -q "committed tip" k_kill.log; do sleep 0.2; done
sleep ${KILL_DELAY:-1.3}
tree() { echo $1; for c in $(pgrep -P $1); do tree $c; done }
pids=($(tree $main))
kill -9 $pids
echo "SIGKILLed ${#pids} processes: $pids"
wait $main 2>/dev/null
grep "committed tip" k_kill.log | tail -2
sqlite3 "file:k_kill/chain.sqlite?mode=ro" "select v from meta where k='tip'"
ls -la k_kill/leaves/sprout.bin
ZEBEND_STATE=$PWD/k_kill python3 ../../sync.py --keep-spool --to 20000 > k_kill2.log 2>&1
head -3 k_kill2.log | cut -c1-120
python3 $W/digest.py k_ref > k_ref.txt; python3 $W/digest.py k_kill > k_kill.txt
diff k_ref.txt k_kill.txt && echo "SIGKILL TEST PASS (state identical to the uninterrupted run)" || echo "SIGKILL TEST FAIL"
