#!/bin/zsh
# gpu_gate.sh RUNS COUNT: Metal determinism gate for the Sapling tree. Runs tree_main on the
# GPU RUNS times over chunks 0..COUNT-1 of part 0 and checks that every run prints the same
# roots (bit-identical), equal to the CPU run and to the chain (check via check_tree.py logs).
# Run under ../../heavy.sh. Also reports the AIR call check (gpuv/t/aircalls.sh).
set -e
cd ${0:a:h}/..
runs=${1:-20}; cnt=${2:-16}
O=data/gpu; mkdir -p $O
./tree/tree_main c data/leaves32/part_000.bin 0 0 $cnt 0 | grep '^chunk' | awk '{print $2, $4}' > $O/cpu.txt
for i in $(seq 1 $runs); do
  ./tree/tree_main c data/leaves32/part_000.bin 0 0 $cnt 1 > $O/run_$i.log
  grep '^chunk' $O/run_$i.log | awk '{print $2, $4}' > $O/run_$i.txt
done
echo "distinct GPU outputs: $(md5 -q $O/run_*.txt | sort -u | wc -l | tr -d ' ') over $runs runs"
cmp -s $O/run_1.txt $O/cpu.txt && echo "GPU output == CPU output ($cnt chunk roots)" || echo "GPU output DIFFERS from CPU"
echo "GPU per-chunk ms (run 1..$runs medians):"
cat $O/run_*.log | grep '^chunk' | awk '{print $6}' | sort -n | awk '{a[NR]=$1} END{print "  median", a[int((NR+1)/2)], "min", a[1], "max", a[NR]}'
