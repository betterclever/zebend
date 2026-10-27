#!/bin/zsh
# One heavy.sh slot: build_all.sh then run_tests.sh.
cd /Users/betterclever/projects/zecathon/zebend/zcash/transparent
secp2/build_all.sh || { echo BUILD FAILED; exit 1; }
secp2/run_tests.sh
