#!/bin/zsh
# Lab benchmark: the same blocks through base and fast code, and fast with each change turned off.
#   ablate.sh <from> <n> <tag> [gap-min gap-max]
# Each run starts from a fresh APFS clone of the golden state (mklab.sh). Results: ftlab/results/abl_<tag>_<config>.jsonl
set -e
FROM=$1; N=$2; TAG=$3; GMIN=${4:-0.3}; GMAX=${5:-1.0}
LAB=/Users/betterclever/projects/zecathon/ftlab; T=/Users/betterclever/projects/zecathon/zebend/node/fasttip/tools
export BEND_NO_TELEMETRY=1
run() {  # config variant env...
  local cfg=$1 var=$2; shift 2
  $T/mklab.sh $LAB/abl $LAB/golden/state $var > /dev/null
  env "$@" /opt/homebrew/bin/python3 -u $T/replay.py --lab $LAB/abl/node --variant $var --from $FROM --n $N \
      --gap-min $GMIN --gap-max $GMAX --blocks $LAB/blocks --out $LAB/results/abl_${TAG}_$cfg.jsonl > $LAB/results/abl_${TAG}_$cfg.log 2>&1
  echo "$cfg: $(tail -1 $LAB/results/abl_${TAG}_$cfg.log)"
  /opt/homebrew/bin/python3 $T/digest.py $LAB/abl/node/state --since $FROM | tail -1
}
run base base X=1
run fast fast X=1
run fast_noinproc fast FT_INPROC=0
run fast_noparallel fast ZEBEND_PARALLEL_HOOKS=0
run fast_nooverlap fast ZEBEND_OVERLAP=0
run fast_seq fast FT_INPROC=0 ZEBEND_PARALLEL_HOOKS=0 ZEBEND_OVERLAP=0
