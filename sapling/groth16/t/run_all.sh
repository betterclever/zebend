#!/bin/zsh
# Every check of sapling/groth16, in order (run from anywhere; heavy steps take the lock).
# Expects data/ prepared (params, oracle vk + extract); see ../README.md.
set -e
cd "$(dirname "$0")/.."
H=../../heavy.sh
for t in fq_test tower_test pair_test ml_test sprout_test; do $H ./build.sh t/$t.bend t/$t; done
for m in verify_main verify_raw_main batch_main; do $H ./build.sh $m.bend $m; done
python3 ref/bls.py selftest
python3 t/fq_test.py 20000
python3 t/tower_test.py 300
python3 t/pair_test.py 8 11
$H python3 diff.py real tamper real_raw tamper_raw
python3 mkmixed.py
$H python3 diff.py real mixed tamper --batch 128
for p in old_ mig_; do
  if [ -f data/${p}real.bin ]; then
    $H python3 diff.py ${p}real ${p}tamper ${p}real_raw ${p}tamper_raw
    $H python3 diff.py ${p}real ${p}tamper --batch 128
  fi
done
python3 t/ml_test.py 20 mig_real real old_real
python3 t/sprout_test.py mig_real
