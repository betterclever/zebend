#!/bin/zsh
# gpu_gate.sh [RUNS]: Metal determinism gate and timing for t/gpu_dec (built by ../build.sh,
# which forces every FAR/DFAR device helper always_inline). For each mode (0 field3,
# 1 table sqrt, 2 fixed-work table sqrt) at depth 14 x 8 per leaf (131,072 Vesta
# encodings): RUNS GPU runs must print identical valid counts and digests, equal to the
# 18-thread CPU run and across modes. Run under ../../heavy.sh.
cd ${0:a:h}
runs=${1:-20}
D=14; L=8
for m in 0 1 2; do
  cpu=$(./gpu_dec $m $D $L +RTS --gpu off -RTS | sed -E 's/ ms [0-9]+//')
  echo "mode $m CPU 18T: $cpu"
  : > ../data/gate_$m.txt
  for i in {1..$runs}; do ./gpu_dec $m $D $L +RTS --gpu on -RTS 2>/dev/null | grep '^mode' >> ../data/gate_$m.txt; done
  n=$(sed -E 's/ ms [0-9]+//' ../data/gate_$m.txt | sort -u | wc -l | tr -d ' ')
  same=$(sed -E 's/ ms [0-9]+//' ../data/gate_$m.txt | sort -u)
  [ "$same" = "$cpu" ] && eq=yes || eq=NO
  ms=$(awk '{print $NF}' ../data/gate_$m.txt | sort -n | awk '{a[NR]=$1} END {print a[1] "/" a[int((NR+1)/2)] "/" a[NR]}')
  echo "mode $m GPU x$(wc -l < ../data/gate_$m.txt | tr -d ' '): distinct outputs $n, equal to CPU: $eq, ms min/median/max $ms"
  for t in 18 1; do
    echo "mode $m CPU ${t}T: $(./gpu_dec $m $D $L +RTS --gpu off --threads $t -RTS | grep -o 'ms [0-9]*')"
  done
done
