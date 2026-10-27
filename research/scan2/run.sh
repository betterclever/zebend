#!/bin/zsh
# run.sh BIN N DEPTH [RTS...]: one scan of vectors batch N; prints timing and MATCH/MISMATCH
# against orchard's expected hit list.
bin=$1; N=$2; D=$3; shift 3
V=${VDIR:-../gpu-scan/vectors/out}
want=$(sed -n 2p $V/expected_$N.txt)
out=$($bin $V/batch_$N.bin $D $N "$@" 2>&1)
got=$(echo "$out" | sed -n 3p | sed 's/^ //')
ms=$(echo "$out" | awk '/^scan_ms/ {print $2}'); cold=$(echo "$out" | awk '/^scan_ms/ {print $4}')
[ "$got" = "$want" ] && ok=MATCH || ok=MISMATCH
printf 'N=%-7s depth=%-3s warm %7s ms  %9.0f outputs/s  cold %6s ms  %s %s\n' $N $D "$ms" $(( N * 1000.0 / ${ms:-1} )) "$cold" $ok "$*"
[ $ok = MATCH ] || { echo "$out" | head -5; }
