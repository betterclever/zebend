#!/bin/zsh
# Rebuild perf3/v64 and sigbatch with decomp's decompression, then check them.
cd /Users/betterclever/projects/zecathon/bend-zcash
export BEND_NO_TELEMETRY=1 PATH=/opt/homebrew/opt/llvm/bin:$PATH HEAVY_MAX_GB=8
set -e
for p in batch_main bundle_ba; do ./heavy.sh perf3/build.sh perf3/v64/$p.bend perf3/v64/$p; done
(cd sigbatch && ../heavy.sh ./build.sh batch_main.bend batch_main)
set +e
echo "== halo2 batch (honest / tampered)"; zsh gpuv/t/small.sh perf3/v64/batch_main
echo "== halo2 42 bundles one by one with bundle_ba"
P=halo2/verifier/data/params_g.bin; ok=0; n=0
for b in halo2/verifier/data/bundles/*.bin; do
  r=$(HEAVY_MAX_MIN=5 ./heavy.sh perf3/v64/bundle_ba $P $b 2>&1 | grep -o "result [01]" | tail -1)
  case $b in *bad*) want="result 0";; *) want="result 1";; esac
  n=$((n+1)); [ "$r" = "$want" ] && ok=$((ok+1)) || echo "DISAGREE $b: $r"
done; echo "bundle_ba expected verdicts $ok/$n"
echo "== sigbatch tamper files"
D=sigbatch/data
for f in $D/tamper_*.bin; do want=${${f:t:r}##*_}
  got=$(./heavy.sh sigbatch/batch_main 11 $f | grep '^sigbatch/' | sed 's/.* invalid//' | tail -1)
  [ "$got" = " $want" ] && echo "${f:t} ok" || echo "${f:t} MISMATCH got:$got want:$want"; done
echo "== sigbatch all chunks 18T"
: > decomp/data/integ_sig.txt
for f in $D/chunk_*.bin; do ./heavy.sh sigbatch/batch_main 11 $f | grep '^sigbatch/' >> decomp/data/integ_sig.txt; done
awk '{n += $3; ms += $5; if (NF > 10) bad += NF - 10} END {printf "%d signatures, %d invalid, verify %.2fs = %.0f sigs/s\n", n, bad, ms/1000, n*1000/ms}' decomp/data/integ_sig.txt
