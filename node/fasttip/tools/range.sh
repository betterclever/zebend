#!/bin/zsh
# Lab benchmark: one block range through fast, base, fast again (fresh golden clone each), same arrivals.
#   range.sh <from> <n> <tag> [gap-min gap-max]
set -e
LAB=/Users/betterclever/projects/zecathon/ftlab; T=/Users/betterclever/projects/zecathon/zebend/node/fasttip/tools
export BEND_NO_TELEMETRY=1
for cfg in fast base fast2; do
  var=${cfg%2}
  $T/mklab.sh $LAB/rng $LAB/golden/state $var > /dev/null
  /opt/homebrew/bin/python3 -u $T/replay.py --lab $LAB/rng/node --variant $var --from $1 --n $2 --gap-min ${4:-0.3} \
      --gap-max ${5:-1.0} --blocks $LAB/blocks --out $LAB/results/rng_$3_$cfg.jsonl > $LAB/results/rng_$3_$cfg.log 2>&1
  echo "$cfg: $(tail -1 $LAB/results/rng_$3_$cfg.log)  [$(grep 'load average' $LAB/results/rng_$3_$cfg.log)]"
  /opt/homebrew/bin/python3 $T/digest.py $LAB/rng/node/state --since $1 | tail -1
done
