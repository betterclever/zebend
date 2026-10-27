#!/bin/zsh
# Fetch mainnet headers 1..3,399,999 from live P2P peers in 500k chunks (resumable).
cd "$(dirname "$0")/../../oracle"
for start in 1 500001 1000001 1500001 2000001 2500001 3000001; do
  out=../data/genesis/h_$start.bin
  count=500000; [ $start = 3000001 ] && count=399999
  if [ -f $out ] && [ $(stat -f %z $out) -eq $((count * 1487)) ]; then echo "skip $start"; continue; fi
  for attempt in 1 2 3; do
    echo "$(date +%T) chunk $start count $count attempt $attempt"
    PROTO=170160 ./target/release/headers-oracle fetch $start $count $out && break
    sleep 30
  done
done
echo "$(date +%T) done"
