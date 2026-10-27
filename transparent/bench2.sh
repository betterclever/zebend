#!/bin/zsh
# bench2.sh DIR [JOBS] [BINS...]: speed round 2 benchmark on the same files (data/real: 86 files,
# 131,146 inputs). For each Bend binary (default ./tv ./tv.new) and the Rust oracle
# (tv-oracle check, RAYON_NUM_THREADS=1):
#   1 process at a time: wall seconds and us/input;
#   JOBS processes at once (default 12, one file each, xargs -P): wall seconds and inputs/s.
# Prints the load average before and after. Run it under ../heavy.sh.
cd /Users/betterclever/projects/zecathon/bend-zcash/transparent
dir=$1; jobs=${2:-12}; shift; [ $# -gt 0 ] && shift
bins=("$@"); [ ${#bins} -eq 0 ] && bins=(./tv ./tv.new)
fs=($dir/*.ztv)
n=$(cat ${fs[@]/%.ztv/.expect} | awk '{n+=length($3)} END {print n}')
now() { python3 -c "import time;print(time.time())"; }
echo "load before: $(uptime | sed 's/.*load averages*: //')"
echo "${#fs} files, $n inputs"
for b in $bins oracle; do
  if [ $b = oracle ]; then cmd=(env RAYON_NUM_THREADS=1 oracle/target/release/tv-oracle check); else cmd=($b); fi
  s=$(now); for f in $fs; do $cmd $f > /dev/null; done; e=$(now)
  s2=$(now); printf '%s\n' $fs | xargs -P $jobs -n 1 $cmd > /dev/null; e2=$(now)
  python3 -c "
t=$e-$s; t2=$e2-$s2
print(f'{\"$b\":12s} 1 proc: {t:6.2f} s {1e6*t/$n:6.1f} us/input   $jobs procs: {t2:6.2f} s {$n/t2:9.0f} inputs/s')"
done
echo "load after: $(uptime | sed 's/.*load averages*: //')"
