#!/bin/zsh
# timeall.sh: upstream crates vs Zakura Common, same session, interleaved (ABAB, order flipped each
# round) so background load lands on both sides. Also the deployed Bend Halo 2 batch verifier on the
# perf4 10,048-bundle sample. Usage: ROUNDS=3 ./timeall.sh > timing/run-$(date +%Y%m%d-%H%M).log
R=/Users/betterclever/projects/zecathon/zebend
Z=$R/research/bench/zakura-common
P4=$R/research/perf4
H16K=$R/research/blake3x/scratch/h16k.bin
REAL=$R/zcash/sapling/groth16/data/real.bin

typeset -A UP ZK
UP[halo2_batch]="cd $R/research/proofsets/oracle && ./target/release/proofsets-oracle rust-batch 18 10048"
ZK[halo2_batch]="cd $Z/halo2_batch && ./target/release/zc-halo2-batch rust-batch 18 10048 && ./target/release/zc-halo2-batch actions-batch 18 10048 && ./target/release/zc-halo2-batch zakura-batch 18 10048"
UP[halo2_one_1t]="cd $R/zcash/halo2/lib/perf && RAYON_NUM_THREADS=1 ./target/release/bend-halo2-perf bench-verify 1"
ZK[halo2_one_1t]="cd $Z/halo2_perf && RAYON_NUM_THREADS=1 ./target/release/zc-halo2-perf bench-verify 1"
UP[halo2_one_18t]="cd $R/zcash/halo2/lib/perf && RAYON_NUM_THREADS=18 ./target/release/bend-halo2-perf bench-verify 1"
ZK[halo2_one_18t]="cd $Z/halo2_perf && RAYON_NUM_THREADS=18 ./target/release/zc-halo2-perf bench-verify 1"
UP[redpallas_18t]="cd $R/research/sigbatch/oracle && ./target/release/sigbatch-oracle rust 18"
ZK[redpallas_18t]="cd $Z/redpallas && ./target/release/zc-redpallas rust 18"
UP[groth16_1t]="cd $R && zcash/sapling/groth16/oracle/target/release/groth16-oracle bench $REAL 1 3"
ZK[groth16_1t]="cd $R && $Z/groth16/target/release/groth16-zakura bench $REAL 1 3"
UP[redjubjub_1t]="cd $R/zcash/sapling/oracle && ./target/release/sapling-oracle rust 1"
ZK[redjubjub_1t]="cd $R && $Z/redjubjub/target/release/redjubjub-zakura rust 1"
UP[equihash]="cd $R/zcash/headers/oracle && ./target/release/headers-oracle check $H16K 0"
ZK[equihash]="cd $R && $Z/equihash/target/release/equihash-zakura check $H16K"
UP[scan]="cd $R/research/scan2/rust && ./target/release/scan2-vectors bench-orchard 262144"
ZK[scan]="cd $Z/scan && ./target/release/scan2-vectors-zakura bench-orchard 262144"

run() { echo "--- $1 $2  $(uptime | sed 's/.*load/load/')"; local t0=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
  (eval "$3") 2>&1 | tail -12
  echo "    wall $(perl -MTime::HiRes=time -e "printf '%.2f', time-$t0") s"; }

for i in $(seq ${ROUNDS:-3}); do
  echo "===== round $i  $(date)"
  for w in halo2_batch halo2_one_1t halo2_one_18t redpallas_18t groth16_1t redjubjub_1t equihash scan; do
    if (( i % 2 )); then run $w upstream "$UP[$w]"; run $w zakura "$ZK[$w]"
    else run $w zakura "$ZK[$w]"; run $w upstream "$UP[$w]"; fi
  done
  run halo2_batch bend "cd $P4 && CHUNKS=157 python3 t/full.py $R/node/follow/bin/halo2_batch 60 | tail -1"
done
echo "===== transparent (bench.sh runs both sides itself)"
$Z/transparent/bench.sh 12 2>&1 | tail -30
echo "===== done $(date)"
