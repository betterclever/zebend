#!/bin/zsh
# bench.sh N bin...: one batch over the first N bundles of proofsets/data/chunks (sorted).
# Runs from the chunks directory with relative paths (10k absolute paths overflow ARG_MAX).
# Extra runtime flags come from $RTS (e.g. RTS="+RTS --gpu 6GB").
R=/Users/betterclever/projects/zecathon/bend-zcash
P=$R/halo2/verifier/data/params_g.bin; N=$1; shift
cd $R/proofsets/data/chunks
F=(${(f)"$(ls | head -$(( (N+63)/64 )) | while read c; do ls $c | sed "s|^|$c/|"; done | head -$N)"})
echo N=${#F}
for b in "$@"; do
  echo "== $b"
  /usr/bin/time -l $R/heavy.sh $R/$b $P $F ${=RTS} 2>&1 | grep -v -E "^ +[0-9]+  [a-z]"
done
