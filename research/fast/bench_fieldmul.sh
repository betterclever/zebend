#!/usr/bin/env zsh
# 1e6 chained Fq multiplications, one thread: Bend 16-bit limbs, Bend 32-bit + mulhi
# intrinsic, Bend 32-bit pure (no intrinsic), Rust pasta_curves. Median of 7.
set -e
cd "$(dirname "$0")"
./build.sh t/mulbench32.bend t/mulbench32
BEND_NO_TELEMETRY=1 ~/.bend/bin/bend t/mulbench32.bend -o t/mulbench32_pure >/dev/null
(cd ../bench/fieldmul && cargo build --release -q 2>/dev/null)
med() { sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}'; }
run() { for i in 1 2 3 4 5 6 7; do "$@" | awk '/Fq.mul/ {gsub("ms",""); print $3}'; done | med; }
echo "load $(sysctl -n vm.loadavg)"
echo "bend 16-bit limbs        $(run ../../zcash/halo2/lib/t/mulbench +RTS --threads 1 -RTS) ms"
echo "bend 32-bit, pure mulhi  $(run ./t/mulbench32_pure +RTS --threads 1 -RTS) ms"
echo "bend 32-bit + intrinsic  $(run ./t/mulbench32 +RTS --threads 1 -RTS) ms"
echo "rust pasta_curves        $(run ../bench/fieldmul/target/release/fieldmul) ms"
for b in ../../zcash/halo2/lib/t/mulbench ./t/mulbench32 ../bench/fieldmul/target/release/fieldmul; do "$b" | head -1; done
