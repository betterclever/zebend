#!/bin/zsh
# bench.sh: every chunk with Bend, one process per chunk (see README, "in-process
# slowdown"): CPU 18 threads, CPU 1 thread, GPU preparation + CPU MSM, GPU preparation +
# GPU MSM; then Rust reddsa batch on 18 and 1 threads, back to back. Run under ../../tools/heavy.sh.
# Per-chunk logs in data/bench_*.txt.
cd ${0:a:h}; zmodload zsh/datetime
uptime
run() {  # name, command prefix...
  local name=$1; shift
  : > data/bench_$name.txt
  local s=$EPOCHREALTIME
  for f in data/chunk_*.bin; do
    "$@" $f | grep '^data/' >> data/bench_$name.txt
  done
  local w=$(( EPOCHREALTIME - s ))
  awk -v t=$name -v w=$w '{n += $3; ms += $5; p += $7; if (NF > 10) bad += NF - 10} END {printf "bend %-8s %d signatures, %d invalid, verify %.2fs (prep %.2fs) = %.0f sigs/s; wall incl. process start and file reading %.1fs\n", t, n, bad, ms/1000, p/1000, n*1000/ms, w}' data/bench_$name.txt
}
run cpu18 ./batch_main 11 +RTS --threads 18 -RTS --RTS
run cpu1 ./batch_main 11 +RTS --threads 1 -RTS --RTS
run gpu ./batch_gpu 11 1 0 +RTS --gpu on -RTS --RTS
run gpu_msm ./batch_gpu 8 1 4 +RTS --gpu on -RTS --RTS
./oracle/target/release/sigbatch-oracle rust 18
./oracle/target/release/sigbatch-oracle rust 1
uptime
