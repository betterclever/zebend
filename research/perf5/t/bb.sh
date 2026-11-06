#!/bin/zsh
zmodload zsh/datetime
# bb.sh N THREADS bin...: one batch over the first N bundles of research/proofsets/data/chunks
# (sorted), from the chunks dir with relative paths. Prints the binary's lines + wall ms.
R=/Users/betterclever/projects/zecathon/zebend
P=${PARAMS:-$R/zcash/halo2/verifier/data/params_g.bin}; N=$1; T=$2; shift 2
cd $R/research/proofsets/data/chunks
F=(${(f)"$(ls | head -$(( (N+63)/64 )) | while read c; do ls $c | sed "s|^|$c/|"; done | head -$N)"})
for b in "$@"; do
  s=$EPOCHREALTIME
  out=$( { /usr/bin/time -p $b $P $F +RTS --threads $T -RTS; } 2>&1 | tr '\n' ' ')
  e=$EPOCHREALTIME
  echo "$(basename $b) N=${#F} T=$T :: $out wall_ms $(( (e-s)*1000 ))"
done
