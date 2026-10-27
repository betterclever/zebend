#!/bin/zsh
# Keep a rehearsal instance fed with new blocks, as live.py does but WITHOUT tiphdr.py (the live
# node extends the shared verified headers): --from = highest block in state or spool + 1.
# usage: feed.sh STATE SPOOL
F=/Users/betterclever/projects/zecathon/zebend/zcash/consensus/gaps/genesis_full/fullnode
while true; do
  last=$(ZEBEND_STATE=$1 ZEBEND_SPOOL=$2 python3 -c "
import struct, sys; sys.path.insert(0, \"$F\"); import download
last = download.state_tip()
for p in download.SPOOL.glob(\"*.blk\"):
    d = p.read_bytes(); i = 0
    while i < len(d):
        h, k = struct.unpack_from(\"<II\", d, i); last = max(last, h); i += 8 + k
print(last)")
  n=$(python3 -c "import sys; sys.path.insert(0, \"$F\"); import headers; print(headers.Index(__import__(\"pathlib\").Path(\"$F/state/hdr/hashes.bin\")).n)")
  if [ $last -lt $((n - 1)) ]; then
    ZEBEND_STATE=$1 ZEBEND_SPOOL=$2 python3 $F/download.py --from $((last + 1)) --to $n --peers 4 2>&1 | tail -1
  fi
  sleep 60
done
