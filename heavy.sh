#!/bin/zsh
# heavy.sh CMD...: run a memory-heavy command (bend compile/check, big verifier run) holding the
# Mac-wide lock, so only ONE heavy job runs across all agents. Kills the job if its RSS
# exceeds HEAVY_MAX_GB (default 6) or it runs longer than HEAVY_MAX_MIN (default 10).
LOCK=/Users/betterclever/projects/zecathon/bend-zcash/.heavy.lock
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
  rss=$(ps -o rss= -g $(ps -o pgid= -p $child | tr -d " ") 2>/dev/null | awk '{s+=$1} END {print s+0}')
  if [ "$rss" -gt $MAXKB ] || [ $t -gt $MAXS ]; then
    echo "heavy.sh: killing '$*' (rss ${rss} KB, ${t}s)" >&2
    kill -9 $child 2>/dev/null; wait $child 2>/dev/null; exit 137
  fi
  sleep 2; t=$((t + 2))
done
wait $child
