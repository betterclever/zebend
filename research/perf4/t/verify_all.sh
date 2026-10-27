#!/bin/zsh
# verify_all.sh: every exactness check on the current perf4 binaries (v/batch_main, v/bundle_ba*,
# t/msm_main). Run from anywhere. Prints PASS/FAIL lines.
Z=/Users/betterclever/projects/zecathon/zebend; P4=$Z/research/perf4; D=$Z/zcash/halo2/verifier/data
echo "== batch: 42-bundle set, honest/tampered (no table, then with the .gtab table)"
python3 $P4/t/check_batch.py $P4/v/batch_main | tail -1
PARAMS=$P4/data/params_g.bin python3 $P4/t/check_batch.py $P4/v/batch_main | tail -1
echo "== single verifier vs halo2 (run_bundles.py): post-NU6.3, NU6.2, pre-NU6.2 circuits"
(cd $Z/zcash/halo2/verifier && for s in "" _nu62 _prenu62; do python3 run_bundles.py $P4/v/bundle_ba$s data/bundles$s | tail -1; done)
echo "== -v traces (every intermediate) vs the deployed research/perf3/v64/bundle_ba"
n=0; bad=0; cd $D; for b in bundles/*.bin; do
  [ "$($Z/research/perf3/v64/bundle_ba params_g.bin $b -v | md5)" = "$($P4/v/bundle_ba params_g.bin $b -v | md5)" ] || { echo "DIFF $b"; bad=$((bad+1)); }; n=$((n+1)); done
echo "traces identical: $((n-bad))/$n"
echo "== MSM vs halo2 best_multiexp (random bases and scalars; t/vec from zcash/halo2/lib/vectors)"
cd $P4/t; for n in 2048 20000 65536 262144; do
  for t in 1 18; do [ $n = 262144 ] && [ $t = 1 ] && continue
    ./msm_main vec/out/msm_$n.bin 9 5 $n +RTS --threads $t -RTS | head -1 | sed "s/^/T=$t /"; done; done
./msm_main vec/out/msm_2048.bin 9 2 2048 +RTS --threads 18 -RTS | head -1 | sed "s/^/msm9 /"
./gtab_test vec/out/msm_2048.bin 9 0 2048 16 +RTS --threads 18 -RTS
