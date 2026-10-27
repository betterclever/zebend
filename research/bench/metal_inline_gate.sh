#!/bin/zsh
# metal_inline_gate.sh [scan|eq|tree ...]: determinism + correctness gate for the always-inline
# Metal builds (research/bench/metal_inline_build.sh -> *.inl, then installed under the shipped names; the
# previous non-inlined binaries are kept as *.noinline). Each program runs RUNS times (default 20)
# on identical input, every run through heavy.sh; the checked output is hashed per run and must
# have exactly 1 distinct value, and that value must be correct:
#   scan  research/scan2/scan_main, 262,144 outputs, depth 14: hit list == orchard's expected list
#   eq    research/blake3x/eqv4/verify, 16,384 mainnet headers: valid / target / links all 100%
#   tree  zcash/state/tree_main gpu: 6/6 roots MATCH the chain
# Also prints timing: median and every run (scan: in-process warm scan_ms; eq: sum of the
# per-batch ms; tree: process wall time). BIN_SUFFIX picks other binaries: .inl (fresh builds
# before installing them), .noinline (the old builds).
# Log: research/bench/metal_inline_gate.log (appended).
R=/Users/betterclever/projects/zecathon/zebend
H=$R/tools/heavy.sh
N=${RUNS:-20}; S=${BIN_SUFFIX-}
out=$R/research/bench/metal_inline_gate.log
tmp=$(mktemp -d)
say() { echo "$@" | tee -a $out; }
med() { sort -n | awk '{a[NR]=$1} END {if (NR%2) print a[(NR+1)/2]; else print (a[NR/2]+a[NR/2+1])/2}'; }
load() { sysctl -n vm.loadavg | awk '{print $2}'; }
say "== $(date)  $(sysctl -n machdep.cpu.brand_string)  macOS $(sw_vers -productVersion)  runs $N  binaries *$S"

gate_scan() {
  cd $R/research/scan2; local V=$R/research/gpu-scan/vectors/out bin=./scan_main$S
  local want=$(sed -n 2p $V/expected_262144.txt) ok=0 l0=$(load)
  : > $tmp/h; : > $tmp/t
  for i in $(seq 1 $N); do
    # stdout only: a fresh-compile note on stderr would shift the parsed lines
    $H $bin $V/batch_262144.bin 14 262144 2>/dev/null > $tmp/o
    local got=$(sed -n 3p $tmp/o | sed 's/^ //')
    echo "$got" | shasum | cut -c1-12 >> $tmp/h
    [ "$got" = "$want" ] && ok=$((ok+1))
    awk '/^scan_ms/ {print $2}' $tmp/o >> $tmp/t
  done
  local m=$(med < $tmp/t)
  say "scan  $bin 262144 outputs x$N: hit list MATCH $ok/$N, distinct outputs $(sort -u $tmp/h | wc -l | tr -d ' ')"
  say "scan  warm scan_ms median $m ($(printf '%.0f' $((262144000.0 / m))) outputs/s); all: $(tr '\n' ' ' < $tmp/t); load avg (1m) $l0 -> $(load)"
}

gate_eq() {
  cd $R/research/blake3x/eqv4; local bin=./verify$S l0=$(load)
  : > $tmp/h; : > $tmp/t; : > $tmp/w
  for i in $(seq 1 $N); do
    local t0=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
    $H $bin $R/zcash/headers/data/mainnet.bin 16384 4096 12 > $tmp/o 2>&1
    local t1=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
    grep -E 'valid|target|links|difficulty' $tmp/o | shasum | cut -c1-12 >> $tmp/h
    awk '/^batch/ {s += $3} END {print s}' $tmp/o >> $tmp/t
    echo "$t1 - $t0" | bc >> $tmp/w
  done
  say "eq    $bin 16384 headers x$N: distinct outputs $(sort -u $tmp/h | wc -l | tr -d ' ')"
  grep -E 'valid|target|links|difficulty' $tmp/o | sed 's/^/eq      last run: /' | tee -a $out
  local m=$(med < $tmp/t)
  say "eq    sum of batch ms median $m ($(printf '%.0f' $((16384000.0 / m))) headers/s); wall s median $(med < $tmp/w); batch-ms all: $(tr '\n' ' ' < $tmp/t); load avg (1m) $l0 -> $(load)"
}

gate_tree() {
  cd $R/zcash/state; local bin=./tree_main$S l0=$(load) good=0
  : > $tmp/h; : > $tmp/w
  for i in $(seq 1 $N); do
    local t0=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
    $H $bin out/cmx.bin gpu > $tmp/o 2>&1
    local t1=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
    grep -E '^height' $tmp/o | awk '{print $2, $7, $8}' | shasum | cut -c1-12 >> $tmp/h
    [ $(grep -c '^height.* MATCH ' $tmp/o) -eq 6 ] && good=$((good+1))
    echo "$t1 - $t0" | bc >> $tmp/w
  done
  say "tree  $bin gpu x$N: runs with 6/6 roots MATCH $good/$N, distinct outputs $(sort -u $tmp/h | wc -l | tr -d ' ')"
  grep -E '^height' $tmp/o | sed 's/^/tree    last run: /' | tee -a $out
  say "tree  wall s median $(med < $tmp/w); all: $(tr '\n' ' ' < $tmp/w); load avg (1m) $l0 -> $(load)"
}

for p in ${@:-scan eq tree}; do gate_$p; done
rm -rf $tmp
say "== done $(date)"
