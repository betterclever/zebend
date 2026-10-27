#!/bin/zsh
# Run under ../../../../tools/heavy.sh from zcash/transparent/: builds secp2/prof/main_v*.bend -> secp2/prof/tv_v*.
cd /Users/betterclever/projects/zecathon/zebend/zcash/transparent
for k in "$@"; do ./build.sh secp2/prof/main_v$k.bend secp2/prof/tv_v$k || echo "build v$k failed"; done
