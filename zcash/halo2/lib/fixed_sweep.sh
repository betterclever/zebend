#!/bin/bash
# Usage: ./fixed_sweep.sh N "c:cdepth ..."  (GPU then CPU threads: table ms, warm ms, check)
N=$1; shift
one() { ./fixed_main vectors/out/msm_$N.bin "$@" | awk 'NR==1{tb=$2} NR==2{ms=$9} NR==3{ok=$3} END{print "table "tb" ms, msm "ms" ms "ok}'; }
for cfg in $1; do
  c=${cfg%%:*}; d=${cfg##*:}
  printf 'n=%s c=%s cdepth=%s  gpu [%s]  cpu [%s]\n' $N $c $d "$(one $c $d $N)" "$(one $c $d $N +RTS --gpu off -RTS)"
done
