#!/bin/bash
# Usage: ./pip_sweep.sh N "c:cdepth ..."  (runs GPU then CPU threads, prints warm ms + check)
N=$1; shift
for cfg in $1; do
  c=${cfg%%:*}; d=${cfg##*:}
  g=$(./msm_fast_main vectors/out/msm_$N.bin $c $d $N | head -1)
  p=$(./msm_fast_main vectors/out/msm_$N.bin $c $d $N +RTS --gpu off -RTS | head -1)
  printf 'n=%s c=%s cdepth=%s  gpu %s ms %s  cpu %s ms %s\n' $N $c $d \
    "$(awk '{print $8}' <<<"$g")" "$(awk '{print $12}' <<<"$g")" "$(awk '{print $8}' <<<"$p")" "$(awk '{print $12}' <<<"$p")"
done
