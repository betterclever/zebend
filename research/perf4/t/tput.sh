#!/bin/zsh
# tput.sh: same-session throughput on the 10,048-bundle sample (first 157 chunks), batches of
# 3,840 (60 chunks): Rust halo2 BatchVerifier (18 threads, its own par_chunks(64)), the deployed
# Bend batch verifier (research/perf3/v64/batch_main == node/follow/bin/halo2_batch) and perf4.
Z=/Users/betterclever/projects/zecathon/zebend
P4=$Z/research/perf4
ORA=$Z/research/proofsets/oracle/target/release/proofsets-oracle
for r in ${(s: :)${REPS:-1}}; do :; done
uptime
for i in $(seq ${REPS:-1}); do
  (cd $Z/research/proofsets/oracle && $ORA rust-batch 18 10048)
  CHUNKS=157 python3 $P4/t/full.py $Z/research/perf3/v64/batch_main 60 | tail -1
  CHUNKS=157 python3 $P4/t/full.py ${NEW:-$P4/v/batch_main} 60 | tail -1
  uptime
done
