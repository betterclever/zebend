#!/bin/zsh
# guard.sh LIMIT_MB LIMIT_S cmd...: runs cmd, killing it (and its children) if their
# combined resident memory exceeds LIMIT_MB or it runs past LIMIT_S seconds.
lim_mb=$1; lim_s=$2; shift 2
"$@" &
pid=$!
start=$(date +%s)
tree() { local p=$1; echo $p; for c in $(pgrep -P $p 2>/dev/null); do tree $c; done; }
while kill -0 $pid 2>/dev/null; do
  pids=($(tree $pid))
  rss=$(ps -o rss= -p ${(j:,:)pids} 2>/dev/null | awk '{s+=$1} END {print int(s/1024)}')
  now=$(date +%s)
  if [ "${rss:-0}" -gt $lim_mb ] || [ $((now - start)) -gt $lim_s ]; then
    echo "guard: killing $* (rss ${rss} MB, $((now - start)) s)" >&2
    kill ${pids[@]} 2>/dev/null; sleep 1; kill -9 ${pids[@]} 2>/dev/null
    exit 99
  fi
  sleep 1
done
wait $pid
