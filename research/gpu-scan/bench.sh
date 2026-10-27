#!/bin/zsh
# Usage: ./bench.sh N DEPTH  — runs every backend on batch_N and checks hits == expected.
set -e
N=$1; D=$2
B=vectors/out/batch_$N.bin
want=$(sed -n 2p vectors/out/expected_$N.txt)
run() {
  local label=$1; shift
  out=$("$@" $B $D $N)
  ms=$(echo "$out" | awk '/^scan_ms/ {print $2}')
  cold=$(echo "$out" | awk '/^scan_ms/ {print $4}')
  got=$(echo "$out" | sed -n 3p | sed 's/^ //')
  ok=$([ "$got" = "$want" ] && echo MATCH || echo MISMATCH)
  printf '%-24s N=%-6s warm %6s ms  %9.0f outputs/s  (cold %s ms)  %s\n' "$label" $N $ms $(( N * 1000.0 / ms )) $cold $ok
}
run "bend gpu (metal)"        ./scan_main
run "bend cpu all threads"    ./scan_main +RTS --gpu off -RTS
run "bend cpu 1 thread"       ./scan_main +RTS --gpu off --threads 1 -RTS
(cd vectors && ./target/release/gpu-scan-vectors bench $N)
