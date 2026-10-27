#!/bin/zsh
# run_tests.sh: rebuild everything and rerun every differential test (run on the Mac).
#   mac zsh -lc 'cd /Users/betterclever/projects/zecathon/bend-zcash/consensus/gaps/ed25519 && ./run_tests.sh'
set -e
cd ${0:A:h}
export BEND_NO_TELEMETRY=1
H=../../../heavy.sh
O=./oracle/target/release/ed25519-oracle
python3 gen_fields.py && python3 gen_ed.py
$H cargo build --release --offline --manifest-path oracle/Cargo.toml 2>&1 | tail -1
$H ./build.sh ed_main.bend ed_main
$H ./build.sh t/layer_main.bend t/layer_main
$H ./build.sh t/field_main.bend t/field_main
mkdir -p data
# 1. field arithmetic vs Python integers
python3 t/field_test.py gen data/pairs.bin 20000
$H ./t/field_main data/pairs.bin > data/pairs.bend.out
python3 t/field_test.py check data/pairs.bin data/pairs.bend.out
# 2. verdicts vs ed25519-zebra, two seeds; 3. decoding / SHA-512 / k / S<l layer dumps vs dalek + sha2
$O decset data/dec 7
for s in main:1:2000 s2:2:5000; do
  name=${s%%:*}; rest=${s#*:}; seed=${rest%%:*}; nv=${rest#*:}
  $O gen data/$name $seed $nv
  $H ./ed_main data/$name.bin > data/$name.bend.out
  python3 diff.py data/$name.meta data/$name.bend.out
done
for name in dec main s2; do
  $O layer data/$name.bin > data/$name.rust.layer
  $H ./t/layer_main data/$name.bin > data/$name.bend.layer
  python3 t/layer_diff.py data/$name.rust.layer data/$name.bend.layer
done
# 4. speed: 10,000 honest signatures (the 2,000 of `main`, x5), 1 thread, Bend then Rust
python3 t/subset.py data/main valid data/bench_valid.bin 5
$H ./ed_main data/bench_valid.bin +RTS --threads 1 | tail -1
$O verify data/bench_valid.bin | tail -1
