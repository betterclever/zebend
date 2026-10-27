#!/bin/zsh
# micro_bench.sh [REPS]: 1e4 square roots and 1e4 decompression attempts, one thread, Bend
# (field3 vs decomp, t/bench and t/dec) and Rust pasta_curves 0.5 (rust/ bench), interleaved.
# Run under ../../tools/heavy.sh.
cd ${0:a:h}
uptime
for i in {1..${1:-3}}; do
  t/bench +RTS --threads 1 -RTS
  t/dec +RTS --threads 1 -RTS | grep ms
  rust/target/release/decomp-rust bench 2>/dev/null | head -4
done
uptime
