#!/bin/zsh
# heavy.sh CMD...: run a memory-heavy command (bend compile/check, big verifier run) holding the
# Mac-wide lock, so only ONE heavy job runs across all agents. Kills the job if its RSS
# exceeds HEAVY_MAX_GB (default 6) or it runs longer than HEAVY_MAX_MIN (default 10).
LOCK=/Users/betterclever/projects/zecathon/zebend/.heavy.lock
MAXKB=$(( ${HEAVY_MAX_GB:-6} * 1024 * 1024 )); MAXS=$(( ${HEAVY_MAX_MIN:-10} * 60 ))
until mkdir $LOCK 2>/dev/null; do
  # break a stale lock whose owner died
  if [ -f $LOCK/pid ] && ! kill -0 $(cat $LOCK/pid) 2>/dev/null; then rm -rf $LOCK; continue; fi
  sleep 3
done
echo $$ > $LOCK/pid
trap 'rm -rf $LOCK' EXIT INT TERM
"$@" &
child=$!; t=0
while kill -0 $child 2>/dev/null; do
  # RSS of the job's own process tree. (Not its process group: under OrbStack's `mac`, every
  # command shares OrbStack Helper's group, which would count unrelated processes.)
  rss=$(ps -A -o pid=,ppid=,rss= | awk -v root=$child '
    { pp[$1] = $2; r[$1] = $3 }
    END { for (p in pp) { q = p; while (q != "" && q != root && q in pp && q != 1) q = pp[q]; if (q == root) s += r[p] } print s + 0 }')
  if [ "$rss" -gt $MAXKB ] || [ $t -gt $MAXS ]; then
    echo "heavy.sh: killing '$*' (rss ${rss} KB, ${t}s)" >&2
    # Kill the whole tree, not just the direct child: a wrapper's grandchild (e.g. the bun
    # compiler under build.sh) would otherwise survive as an orphan outside the lock.
    kids=$(ps -A -o pid=,ppid= | awk -v root=$child '
      { pp[$1] = $2 }
      END { for (p in pp) { q = p; while (q != "" && q != root && q in pp && q != 1) q = pp[q]; if (q == root) print p } }')
    kill -9 ${=kids} $child 2>/dev/null; wait $child 2>/dev/null; exit 137
  fi
  sleep 1; t=$((t + 1))
done
wait $child
