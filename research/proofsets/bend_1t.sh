#!/bin/zsh
# Bend batch verification on one thread over the first N chunks (N*64 bundles), for the
# single-thread comparison with Rust's BatchVerifier (rust-batch 1 10000).
cd "$(dirname "$0")/data"
N=${1:-157}
G=../../../zcash/halo2/verifier/data/params_g.bin
t0=$(python3 -c 'import time; print(time.time())'); n=0; ok=1
for c in $(ls chunks | head -$N); do
  out=$(../../perf3/v64/batch_main $G chunks/$c/*.bin +RTS --threads ${THREADS:-1} -RTS)
  echo "$out" | grep -q "result 1" || ok=0
  n=$((n + $(ls chunks/$c | wc -l)))
done
python3 -c "import time; s=time.time()-$t0; print(f'bend batch_main threads=${THREADS:-1}: $n bundles, all ok $ok, {s:.1f}s = {$n/s:.0f} bundles/s')"
