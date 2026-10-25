#!/bin/zsh
export BEND_NO_TELEMETRY=1 PATH=/opt/homebrew/opt/llvm/bin:$PATH
R=/Users/betterclever/projects/zecathon/bend-zcash; H=$R/heavy.sh
export HEAVY_MAX_GB=8
cd $R/halo2/verifier; echo "$(date +%T) halo2/verifier/bundle_main"; $H ~/.bend/bin/bend bundle_main.bend -o bundle_main 2>&1 | tail -2
cd $R/fast/pure/v32
for n in bundle_main bundle_main_fast bundle_main_nu62; do echo "$(date +%T) fast/pure/v32/$n"; $H ../build.sh $n.bend $n 2>&1 | tail -2; done
cd $R/scan2; echo "$(date +%T) scan2/scan_main"; rm -f scan_main.gpu; $H ./build.sh scan_main.bend scan_main 2>&1 | tail -2
echo "$(date +%T) done"
