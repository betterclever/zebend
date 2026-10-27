#!/bin/zsh
# Rebuild every gated Halo 2 entry point (zcash/wire/bundle.bend in front of parse_bundle),
# one heavy build at a time through heavy.sh.
export BEND_NO_TELEMETRY=1 PATH=/opt/homebrew/opt/llvm/bin:$PATH
R=/Users/betterclever/projects/zecathon/zebend; H=$R/heavy.sh
cd $R/halo2/verifier
for n in bundle_main bundle_main_fast bundle_main_nu62 bundle_main_prenu62; do
  echo "$(date +%T) zcash/halo2/verifier/$n"; $H ~/.bend/bin/bend $n.bend -o $n 2>&1 | tail -2
done
cd $R/fast/pure/v32
for n in bundle_main bundle_main_fast bundle_main_nu62 bundle_main_prenu62; do
  echo "$(date +%T) research/fast/pure/v32/$n"; $H ../../build.sh $n.bend $n 2>&1 | tail -2
done
cd $R/perf3/v64
echo "$(date +%T) research/perf3/v64/bundle_ba"; $H ../../build.sh bundle_ba.bend bundle_ba 2>&1 | tail -2
echo "$(date +%T) done"
