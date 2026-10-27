#!/bin/zsh
# guard.sh <seconds> <max_rss_kb> <cmd...>: run cmd, kill it past the time or RSS limit.
lim=$1; mem=$2; shift 2
"$@" &
pid=$!
for i in $(seq 1 $lim); do
  sleep 1
  kill -0 $pid 2>/dev/null || { wait $pid; exit $?; }
  r=$(ps -o rss= -p $pid 2>/dev/null | tr -d ' ')
  for c in $(pgrep -P $pid); do r=$((r + $(ps -o rss= -p $c | tr -d ' '))); done
  if [ "${r:-0}" -gt $mem ]; then echo "guard: RSS ${r} KB at ${i}s, killed"; pkill -P $pid; kill $pid; exit 99; fi
done
echo "guard: over ${lim}s, killed"; pkill -P $pid; kill $pid; exit 98
