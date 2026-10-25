#!/bin/zsh
R=/Users/betterclever/projects/zecathon/bend-zcash
cd $R/halo2/verifier
for b in $R/halo2/verifier/bundle_main $R/halo2/verifier/bundle_main_fast $R/fast/pure/v32/bundle_main $R/fast/pure/v32/bundle_main_fast $R/perf3/v64/bundle_ba; do
  echo "$b post-NU6.3: $(python3 run_bundles.py $b data/bundles 2>&1 | tail -1)"
done
for b in $R/halo2/verifier/bundle_main_nu62 $R/fast/pure/v32/bundle_main_nu62; do
  echo "$b NU6.2: $(python3 run_bundles.py $b data/bundles_nu62 2>&1 | tail -1)"
done
for b in $R/halo2/verifier/bundle_main_prenu62 $R/fast/pure/v32/bundle_main_prenu62; do
  echo "$b pre-NU6.2: $(python3 run_bundles.py $b data/bundles_prenu62 2>&1 | tail -1)"
done
