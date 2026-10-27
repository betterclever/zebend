#!/bin/zsh
# Lab benchmark under a shared, noisy machine: base and fast alternated (A B A B ...), each run from
# a fresh APFS clone of the golden state, so both see the same load on average.
#   abba.sh <from> <n> <tag> <rounds> [gap-min gap-max]
#   heavy mode: abba.sh heavy "<h1 h2 ...>" <tag> <rounds>   (each block alone: --from h-1 --n 1)
set -e
LAB=/Users/betterclever/projects/zecathon/ftlab; T=/Users/betterclever/projects/zecathon/zebend/node/fasttip/tools
export BEND_NO_TELEMETRY=1
one() {  # cfg from n out
  local var=$1
  $T/mklab.sh $LAB/abba $LAB/golden/state $var > /dev/null
  /opt/homebrew/bin/python3 -u $T/replay.py --lab $LAB/abba/node --variant $var --from $2 --n $3 \
      --gap-min ${GMIN:-0.3} --gap-max ${GMAX:-1.0} --blocks $LAB/blocks --out $4 > ${4%.jsonl}.log 2>&1
  echo "$var $2+$3: $(tail -1 ${4%.jsonl}.log)  [$(grep 'load average' ${4%.jsonl}.log)]"
}
if [[ $1 == heavy ]]; then
  for r in $(seq 1 $4); do for h in ${=2}; do for v in base fast; do
    one $v $((h - 1)) 1 $LAB/results/abba_$3_${v}_${h}_r$r.jsonl
  done; done; done
else
  GMIN=${5:-0.3}; GMAX=${6:-1.0}
  for r in $(seq 1 $4); do for v in base fast; do
    one $v $1 $2 $LAB/results/abba_$3_${v}_r$r.jsonl
  done; done
fi
