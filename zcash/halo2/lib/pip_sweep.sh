#!/bin/bash
# Usage: ./pip_sweep.sh N "c:cdepth ..."  (GPU then CPU threads: warm ms and result check)
N=$1; shift
one() { ./msm_fast_main vectors/out/msm_$N.bin "$@" | awk 'NR==1{ms=$9} NR==2{ok=$3} END{print ms" ms "ok}'; }
for cfg in $1; do
  c=${cfg%%:*}; d=${cfg##*:}
  printf 'n=%s c=%s cdepth=%s  gpu %s  cpu %s\n' $N $c $d "$(one $c $d $N)" "$(one $c $d $N +RTS --gpu off -RTS)"
done
