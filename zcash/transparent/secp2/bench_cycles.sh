#!/bin/zsh
# bench_cycles.sh DIR REPS BIN...: one process at a time over every DIR/*.ztv, REPS rounds
# (interleaved by binary); per round, the sums of user seconds and CPU cycles (from
# /usr/bin/time -l) per binary; "oracle" means tv-oracle check (RAYON_NUM_THREADS=1).
cd /Users/betterclever/projects/zecathon/zebend/zcash/transparent
dir=$1; reps=$2; shift 2
fs=($dir/*.ztv)
n=$(cat ${fs[@]/%.ztv/.expect} | awk '{n+=length($3)} END {print n}')
echo "load before: $(uptime | sed 's/.*load averages*: //'); ${#fs} files, $n inputs"
for r in $(seq 1 $reps); do
  for b in "$@"; do
    if [ $b = oracle ]; then cmd=(env RAYON_NUM_THREADS=1 oracle/target/release/tv-oracle check); else cmd=($b); fi
    u=0; c=0
    for f in $fs; do
      out=$(/usr/bin/time -l $cmd $f 2>&1 >/dev/null)
      u=$(( u + $(echo "$out" | awk '/ user /{print $3}') ))
      c=$(( c + $(echo "$out" | awk '/cycles elapsed/{print $1}') ))
    done
    python3 -c "print(f'round $r {\"$b\":10s} user {$u:6.2f} s ({1e6*$u/$n:6.1f} us/input)  cycles {$c/1e9:6.1f} G ({$c/$n/1e3:6.1f} kcycles/input)')"
  done
done
echo "load after: $(uptime | sed 's/.*load averages*: //')"
