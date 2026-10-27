#!/bin/zsh
# Small correctness check: honest batch -> 1, one tampered proof -> 0.
cd /Users/betterclever/projects/zecathon/zebend
P=zcash/halo2/verifier/data/params_g.bin; D=zcash/halo2/verifier/data/bundles
GOOD=(${(f)"$(ls $D/*.bin | grep -v bad)"})
BAD=(${GOOD:s|tx_3.ironwood.bin|tx_3.ironwood.bad.bin|})
echo n=${#GOOD} bad_has=$(print -l $BAD | grep -c bad)
for b in "$@"; do
  echo "== $b"
  HEAVY_MAX_GB=8 HEAVY_MAX_MIN=5 ./heavy.sh ./$b $P $GOOD 2>&1 | tail -2
  HEAVY_MAX_GB=8 HEAVY_MAX_MIN=5 ./heavy.sh ./$b $P $BAD 2>&1 | tail -2
done
