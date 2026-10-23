#!/bin/bash
# Median-of-5 warm timings for the PERF.md table (run from halo2/lib on the Mac).
med() { sort -n | awk '{a[NR]=$1} END{print a[int((NR+1)/2)]}'; }
rep() { for i in 1 2 3 4 5; do "$@"; done | med; }
ms_pip() { ./msm_fast_main vectors/out/msm_$1.bin $2 $3 $1 "${@:4}" | awk 'NR==1{print $9}'; }
ms_fix() { ./fixed_main vectors/out/msm_$1.bin $2 $3 $1 "${@:4}" | awk 'NR==2{print $9}'; }
ms_old() { ./msm_main vectors/out/msm_$1.bin $2 $1 "${@:3}" | awk 'NR==1{print $7}'; }
ms_bat() { ./batch_main perf/out/batch_$1.bin 8 4 +RTS --gpu off -RTS | awk 'NR==1{print $13}'; }
echo "load: $(uptime | sed 's/.*averages: //')"
for n in 2048 4096; do
  echo "n=$n old double-and-add: gpu $(rep ms_old $n 12) ms, cpu $(rep ms_old $n 12 +RTS --gpu off -RTS) ms"
  echo "n=$n pippenger c=4 cd=6 gpu: $(rep ms_pip $n 4 6) ms;  c=8 cd=0 cpu: $(rep ms_pip $n 8 0 +RTS --gpu off -RTS) ms;  c=7 cd=2 cpu: $(rep ms_pip $n 7 2 +RTS --gpu off -RTS) ms"
done
echo "n=2048 fixed-base c=8 cd=4 cpu: $(rep ms_fix 2048 8 4 +RTS --gpu off -RTS) ms;  c=4 cd=8 gpu: $(rep ms_fix 2048 4 8) ms"
for k in 1 8 64; do echo "batch K=$k cpu: $(rep ms_bat $k) ms"; done
echo "load: $(uptime | sed 's/.*averages: //')"
