#!/bin/zsh
# bench.sh [JOBS] [ERA_GLOB]: tv-oracle (upstream zcash_primitives 0.31) vs tv-zakura (Zakura
# v1.7.0 zakura-script/zakura-chain) on the same files, in zcash/transparent/bench2.sh's shape:
# RAYON_NUM_THREADS=1, one process per file, first one at a time, then JOBS at once (xargs -P).
# Default files: data/real minus preoverwinter (v1/v2, which Zakura does not script-check), so
# both sides do identical work. ERA_GLOB='*' includes them (tv-zakura then skips 11,853 inputs).
cd /Users/betterclever/projects/zecathon/zebend/zcash/transparent
jobs=${1:-12}; glob=${2:-'[!p]*'}
fs=(data/real/${~glob}.ztv)
n=$(cat ${fs[@]/%.ztv/.expect} | awk '{n+=length($3)} END {print n}')
Z=../../research/bench/zakura-common/transparent/target/release/tv-zakura
now() { python3 -c "import time;print(time.time())"; }
echo "load before: $(uptime | sed 's/.*load averages*: //')"
echo "${#fs} files, $n inputs"
for b in oracle zakura; do
  if [ $b = oracle ]; then cmd=(env RAYON_NUM_THREADS=1 oracle/target/release/tv-oracle check); else cmd=(env RAYON_NUM_THREADS=1 $Z check); fi
  s=$(now); for f in $fs; do $cmd $f > /dev/null; done; e=$(now)
  s2=$(now); printf '%s\n' $fs | xargs -P $jobs -n 1 $cmd > /dev/null; e2=$(now)
  python3 -c "
t=$e-$s; t2=$e2-$s2
print(f'{\"$b\":8s} 1 proc: {t:6.2f} s {1e6*t/$n:6.1f} us/input   $jobs procs: {t2:6.2f} s {$n/t2:9.0f} inputs/s')"
done
echo "load after: $(uptime | sed 's/.*load averages*: //')"
