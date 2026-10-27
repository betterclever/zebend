#!/bin/zsh
# tools/harden/ci.sh [--rebuild] [--no-validate]: Zebend's regression gate, run on the Mac.
#   1. every LAWS/PROOF directory: bend PROOF.bend --verdict (Lean-kernel recheck)
#   2. field/curve suites (zcash/halo2/lib/t), pasta_curves-generated vectors
#   3. Halo 2: run_bundles on the 42 bundles + nu62 + prenu62 sets; the hardened verifier on
#      the 42 and on the malformed-input probes
#   4. node/validate/zebend validate (header -> block -> tx -> proof -> state)
#   5. fuzz smoke: fresh oracle corpora for every parser vs ./fz, plus the resource limits
#   6. constant-time scan: hit lists MATCH at 4,096 and 262,144 outputs (Metal)
# Every heavy step (compiles, proof checks, the verifier and validate runs) goes through
# ../heavy.sh (one heavy job Mac-wide, RSS/time caps); light runs (< 150 MB) do not.
# Prints a summary table; exits non-zero if any step fails.
emulate -L zsh
setopt pipefail
export BEND_NO_TELEMETRY=1
PATH=/opt/homebrew/opt/llvm/bin:$HOME/.bend/bin:$PATH
HERE=${0:A:h}
ROOT=${HERE:h:h}
H=$ROOT/tools/heavy.sh
FORK=${BEND_FORK:-/Users/betterclever/projects/zecathon/bend-fork}
REBUILD=0; VALIDATE=1
for a in "$@"; do
  case $a in
    --rebuild) REBUILD=1 ;;
    --no-validate) VALIDATE=0 ;;
  esac
done
LOG=$HERE/data/ci; mkdir -p $LOG
typeset -a ROWS
FAILS=0
T0=$SECONDS

# step NAME CMD...: run CMD (a shell function), record PASS/FAIL, its detail line and time.
step() {
  local name=$1; shift
  local t=$SECONDS out rc
  out=$("$@" 2>&1); rc=$?
  print -r -- "$out" > $LOG/${name//[^A-Za-z0-9]/_}.log
  local detail=$(print -r -- "$out" | grep '^DETAIL ' | tail -1 | cut -c8-)
  local res=PASS; [ $rc -eq 0 ] || { res=FAIL; FAILS=$((FAILS + 1)); }
  ROWS+=("$(printf '| %-34s | %-4s | %5ss | %s |' $name $res $((SECONDS - t)) "$detail")")
  printf '%-36s %s %5ss  %s\n' $name $res $((SECONDS - t)) "$detail"
}

# ---------------------------------------------------------------- 1. proofs

proof_dir() {
  cd $ROOT/$1 || return 1
  local out
  # A directory with its own chk.sh (proofs/prims) needs the forked Bend and a large stack.
  if [ -x ./chk.sh ]; then
    out=$($H ./chk.sh $PWD/PROOF.bend --verdict 2>&1 | grep -v 'bend update')
  else
    out=$($H bend PROOF.bend --verdict 2>&1 | grep -v 'bend update')
  fi
  print -r -- "$out"
  print -r -- "$out" | grep -q 'ALL PROOFS CHECK' && ! print -r -- "$out" | grep -qi 'fail' || return 1
  grep -q '@unsafe' PROOF.bend LAWS.bend && { echo "DETAIL @unsafe present"; return 1; }
  echo "DETAIL ALL PROOFS CHECK (--verdict)"
}

# ---------------------------------------------------------------- 2. suites

suite() {
  cd $ROOT/zcash/halo2/lib/t || return 1
  if [ $REBUILD = 1 ] || [ ! -x ./$1 ]; then $H bend $1.bend -o $1 >/dev/null 2>&1 || return 1; fi
  local out=$(./$1 2>&1)
  local ok=$(print -r -- "$out" | grep -c '^ok ') bad=$(print -r -- "$out" | grep -vc '^ok ')
  echo "DETAIL $ok ok, $bad not ok"
  [ $ok -gt 0 ] && [ $bad -eq 0 ]
}

# ---------------------------------------------------------------- 3. Halo 2

bundles() {
  cd $ROOT/zcash/halo2/verifier || return 1
  local out=$($H python3 run_bundles.py ./$1 data/$2 2>&1)
  print -r -- "$out"
  local last=$(print -r -- "$out" | tail -1)
  echo "DETAIL $last"
  print -r -- "$last" | grep -qE 'agrees with halo2 on ([0-9]+)/\1$'
}

hardened_verifier() {
  cd $HERE || return 1
  if [ $REBUILD = 1 ] || [ ! -x ./bundle_main_h ]; then $H bend bundle_main_h.bend -o bundle_main_h >/dev/null 2>&1 || return 1; fi
  cd $ROOT/zcash/halo2/verifier
  local last=$($H python3 run_bundles.py $HERE/bundle_main_h data/bundles 2>&1 | tail -1)
  cd $HERE
  python3 tools/probes.py > /dev/null || return 1
  local bad=0 n=0 f want got
  for f in data/bprobe/*.bin; do
    want=0; [ ${f:t:r} = ok ] && want=1
    got=$(timeout 60 ./bundle_main_h $ROOT/zcash/halo2/verifier/data/params_g.bin $f 2>/dev/null | tail -1)
    n=$((n + 1)); [ "$got" = "result $want" ] || { bad=$((bad + 1)); echo "probe ${f:t}: $got"; }
  done
  echo "DETAIL ${last#42 bundles: }; malformed probes $((n - bad))/$n"
  print -r -- "$last" | grep -q '42/42' && [ $bad -eq 0 ]
}

# ---------------------------------------------------------------- 4. validate

validate() {
  cd $ROOT/node/validate || return 1
  local out=$($H ./zebend validate 2>&1)
  print -r -- "$out"
  echo "DETAIL $(print -r -- "$out" | grep -E '^(VALID|INVALID)' | tail -1 | cut -c1-90)"
  print -r -- "$out" | grep -q '^VALID: 5/5'
}

# ---------------------------------------------------------------- 5. fuzz smoke

fz_build() {
  cd $HERE || return 1
  if [ $REBUILD = 1 ] || [ ! -x ./fz ]; then $H bend fz_main.bend -o fz > $LOG/fz_build.log 2>&1 || return 1; fi
  if [ $REBUILD = 1 ] || [ ! -x oracle/target/release/harden-oracle ]; then
    (cd oracle && $H cargo build --release -q) || return 1
  fi
  echo "DETAIL fz + oracle ready"
}

fuzz_smoke() {
  local mode=$1 n=$2 cc=$3
  cd $HERE/oracle || return 1
  HARDEN_SEED=${SMOKE_SEED:-$RANDOM} ./target/release/harden-oracle $mode $n ../data/smoke_$mode 2>&1 | tail -1
  cd $HERE
  local out=$(python3 fuzz.py $mode --src smoke_$mode --jobs 6 --chunk-cases $cc --show 2 2>&1)
  local rc=$?
  print -r -- "$out"
  rm -f data/smoke_$mode.*
  echo "DETAIL $(print -r -- "$out" | head -1 | sed -E 's/^[a-z_]+: //; s/ in [0-9]+ chunks//; s/, peak RSS/; RSS/')"
  return $rc
}

fuzz_bundle() {
  cd $HERE || return 1
  python3 tools/bgen.py $1 ${SMOKE_SEED:-$RANDOM} data/smoke_bundle | tail -1
  local out=$(python3 fuzz.py bundle --src smoke_bundle --jobs 6 --chunk-cases 250 --show 2 2>&1)
  local rc=$?
  print -r -- "$out"; rm -f data/smoke_bundle.*
  echo "DETAIL $(print -r -- "$out" | head -1 | sed -E 's/^[a-z_]+: //; s/ in [0-9]+ chunks//; s/, peak RSS/; RSS/')"
  return $rc
}

limits() {
  cd $HERE || return 1
  local out=$(python3 tools/limits.py 2>&1); local rc=$?
  print -r -- "$out"
  local n=$(print -r -- "$out" | grep -c '^| [a-z]')
  local worst=$(print -r -- "$out" | grep '^| [a-z]' | awk -F'|' '{gsub(/ MiB.*/, "", $8); if ($8 + 0 > m) m = $8 + 0} END {print m}')
  echo "DETAIL $((n - $(print -r -- "$out" | grep -c FAIL)))/$n adversarial inputs give the expected verdict; max RSS ${worst} MiB"
  return $rc
}

# ---------------------------------------------------------------- 6. constant-time scan

scan_ct() {
  cd $HERE/scan_ct || return 1
  if [ $REBUILD = 1 ] || [ ! -x ./scan_main_ct ]; then
    $H env BEND_NO_TELEMETRY=1 bun $FORK/bend2/main.ts scan_main.bend -o scan_main_ct > /dev/null 2>&1 || return 1
  fi
  local out=$(VDIR=$ROOT/research/gpu-scan/vectors/out; for n in 4096 262144; do VDIR=$VDIR $ROOT/research/scan2/run.sh ./scan_main_ct $n 14; done 2>&1)
  print -r -- "$out"
  echo "DETAIL $(print -r -- "$out" | grep -c MATCH | tr -d ' ')/2 hit lists MATCH; $(print -r -- "$out" | tail -1 | awk '{print $6}') outputs/s Metal"
  [ $(print -r -- "$out" | grep -c ' MATCH') -eq 2 ]
}

# ---------------------------------------------------------------- run

echo "tools/harden/ci.sh  $(date '+%Y-%m-%d %H:%M')  rebuild=$REBUILD"
for d in $(cd $ROOT && print -l */PROOF.bend(N) */*/PROOF.bend(N) */*/*/PROOF.bend(N) | xargs -n1 dirname | grep -v '^tools/harden' | sort); do
  step "proof $d" proof_dir $d
done
step "suite field (Fp/Fq)" suite field_tests
step "suite curve (Pallas/Vesta)" suite curve_tests
step "halo2 bundles (42)" bundles bundle_main bundles
step "halo2 bundles nu62" bundles bundle_main_nu62 bundles_nu62
step "halo2 bundles prenu62" bundles bundle_main_prenu62 bundles_prenu62
step "halo2 hardened verifier" hardened_verifier
[ $VALIDATE = 1 ] && step "validate zebend" validate
step "fuzz build" fz_build
step "fuzz cs" fuzz_smoke cs 20000 4000
step "fuzz header" fuzz_smoke hdr 20000 2000
step "fuzz p2p frame" fuzz_smoke frame 20000 4000
step "fuzz tx" fuzz_smoke tx 10000 500
step "fuzz block" fuzz_smoke block 500 30
step "fuzz halo2 bundle input" fuzz_bundle 10000
step "resource limits" limits
step "constant-time scan" scan_ct

echo
echo "| step | result | time | detail |"
echo "|---|---|---:|---|"
for r in $ROWS; do print -r -- "$r"; done
echo
echo "$(( ${#ROWS} - FAILS ))/${#ROWS} steps passed in $((SECONDS - T0)) s; logs in $LOG"
exit $(( FAILS > 0 ))
