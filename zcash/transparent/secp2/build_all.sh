#!/bin/zsh
# Run under ../../../tools/heavy.sh from anywhere: builds the speed-round-2 binaries.
#   tv.new          <- tv2_main.bend   (the deliverable; same compiler and flags as tv)
#   secp2/t/secp_t  <- secp2/t/secp_t.bend (field/scalar/GLV/ecmult/ECDSA test driver)
#   secp2/t/sh2     <- sh2_main.bend   (sighash dumper on sighash2, for sighash_check.py)
#   script2/t/hash_t <- script2/t/hash_t.bend (RIPEMD-160/SHA-1/SHA-256 test driver)
# PROF=1 also builds secp2/prof/tv2_named (spins named after their defs, for `sample`).
cd /Users/betterclever/projects/zecathon/zebend/zcash/transparent
./build.sh tv2_main.bend tv.new || exit 1
./build.sh secp2/t/secp_t.bend secp2/t/secp_t || exit 1
./build.sh sh2_main.bend secp2/t/sh2 || exit 1
./build.sh script2/t/hash_t.bend script2/t/hash_t || exit 1
[ -n "$PROF" ] && BEND_FORK=$PWD/secp2/prof/fk ./build.sh tv2_main.bend secp2/prof/tv2_named
exit 0
