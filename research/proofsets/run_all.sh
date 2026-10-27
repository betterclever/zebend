#!/bin/zsh
# Full pipeline after scan + fetch: official verification in parts, Bend verification in
# slices, summary. Every heavy step goes through ../../tools/heavy.sh (one heavy job Mac-wide).
set -e
setopt null_glob
cd "$(dirname "$0")"
H="$(cd .. && pwd)/heavy.sh"
O=oracle/target/release/proofsets-oracle
PARTS=${PARTS:-12}
SLICE=${SLICE:-600}            # chunks of 64 bundles per Bend slice (~40k bundles, a few minutes)
(cd oracle && $H cargo build --release -q)
rm -rf data/chunks data/other data/official.txt data/official_p*.txt data/bend_results*.txt data/bend_timing_*.txt
for p in $(seq 0 $((PARTS - 1))); do
  $H $O build 64 $p $PARTS 2>&1 | tail -1
done
n=$(ls data/chunks | wc -l)
for from in $(seq 0 $SLICE $((n - 1))); do
  CHUNK_FROM=$from CHUNK_TO=$((from + SLICE)) $H python3 run_bend.py | tail -3
done
python3 summarize.py | tee data/summary.txt
