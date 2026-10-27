#!/bin/zsh
# e2e.sh CODEDIR BASESTATE SPOOL TO NAME [sync args...]: clone BASESTATE (APFS clone), run
# CODEDIR/sync.py --keep-spool --to TO on it under /usr/bin/time -l (CPU of the whole tree:
# sync, writer, Bend children), then digest the result. Output: runs/NAME.{log,time,digest}.
set -e
B=/Users/betterclever/projects/zecathon/zebend/node/fast/bench
code=$1 base=$2 spool=$3 to=$4 name=$5; shift 5
export BEND_NO_TELEMETRY=1 PYTHONDONTWRITEBYTECODE=1 ZEBEND_SPOOL=$spool ZEBEND_STATE=$B/st/$name
mkdir -p $B/runs $B/st; rm -rf $B/st/$name; mkdir -p $B/st/$name
cp -c $base/chain.sqlite $B/st/$name/; cp -cR $base/leaves $B/st/$name/
echo "load before: $(sysctl -n vm.loadavg)" > $B/runs/$name.time
/usr/bin/time -l python3 -u $code/sync.py --keep-spool --to $to "$@" > $B/runs/$name.log 2>> $B/runs/$name.time
echo "load after: $(sysctl -n vm.loadavg)" >> $B/runs/$name.time
python3 /Users/betterclever/projects/zecathon/zebend/node/work/bench/digest.py $B/st/$name --no-addr > $B/runs/$name.digest
tail -n 3 $B/runs/$name.log
grep -E "real|maximum resident|peak memory" $B/runs/$name.time
