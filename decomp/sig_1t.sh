#!/bin/zsh
# sig_1t.sh [N] [REPS]: one-thread paired comparison on the first N chunks, base and new
# alternating per chunk (so load drifts hit both equally), REPS passes. Run under ../heavy.sh.
cd ${0:a:h}
N=${1:-40}; uptime
for rep in {1..${2:-3}}; do
  : > data/s1_base.txt; : > data/s1_new.txt
  for f in $(ls ../sigbatch/data/chunk_*.bin | head -$N); do
    sig/batch_main_base 11 $f +RTS --threads 1 -RTS | grep '^\.\./' >> data/s1_base.txt
    sig/batch_main 11 $f +RTS --threads 1 -RTS | grep '^\.\./' >> data/s1_new.txt
  done
  for b in base new; do
    awk -v t="pass $rep $b" '{n += $3; ms += $5; p += $7; if (NF > 10) bad += NF - 10} END {printf "%-12s %d sigs, %d invalid, verify %.2fs (prep %.2fs, equation %.2fs) = %.0f sigs/s\n", t, n, bad, ms/1000, p/1000, (ms-p)/1000, n*1000/ms}' data/s1_$b.txt
  done
done
uptime
