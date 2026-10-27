#!/bin/zsh
# sig_check.sh: RedPallas batch integration checks and throughput for research/decomp/sig (table-sqrt
# decompression, constant bases) against sigbatch's sources built with the same compiler
# (sig/batch_main_base). Run under ../../tools/heavy.sh.
#   1. every tamper file in ../sigbatch/data: the invalid list must be exactly the index in
#      its name (tamper_FIELD_I.bin), for both binaries
#   2. all 157 real chunks (1,283,411 signatures), one process per chunk as sigbatch's
#      bench.sh: all accepted; sigs/s from the in-process verify times, 18 threads (x2) and
#      1 thread, base and new interleaved
cd ${0:a:h}
D=../sigbatch/data
uptime
for f in $D/tamper_*.bin; do
  want=${${f:t:r}##*_}
  for b in batch_main_base batch_main; do
    got=$(sig/$b 11 $f | grep '^\.\./' | sed 's/.* invalid//')
    [ "$got" = " $want" ] && r=ok || r=MISMATCH
    echo "${f:t} $b invalid:$got (want $want) $r"
  done
done
# preparation digests (leaf Merkle root, sum of R_i + vk_i, sum of c_i) must be identical
for c in 0000 0010 0100 0156; do
  a=$(sig/batch_main_base 11 $D/chunk_$c.bin | grep digest); b=$(sig/batch_main 11 $D/chunk_$c.bin | grep digest)
  [ "$a" = "$b" ] && echo "chunk_$c prep digest identical" || echo "chunk_$c prep digest DIFFERS"
done
run() {  # bin threads
  : > data/sig_$1_$2.txt
  for f in $D/chunk_*.bin; do sig/$1 11 $f +RTS --threads $2 -RTS | grep '^\.\./' >> data/sig_$1_$2.txt; done
  awk -v t="$1 threads $2" '{n += $3; ms += $5; p += $7; if (NF > 10) bad += NF - 10} END {printf "%-28s %d signatures, %d invalid, verify %.2fs (prep %.2fs) = %.0f sigs/s\n", t, n, bad, ms/1000, p/1000, n*1000/ms}' data/sig_$1_$2.txt
}
for rep in 1 2; do run batch_main_base 18; run batch_main 18; done
run batch_main_base 1; run batch_main 1
uptime
