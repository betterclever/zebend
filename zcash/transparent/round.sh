#!/bin/zsh
# round.sh: one heavy.sh slot: rebuild what changed, regenerate fuzz data, run the diffs.
#   ../../tools/heavy.sh ./round.sh [build] [fuzz N SEED] [vectors] [diff DIR...]
cd /Users/betterclever/projects/zecathon/zebend/zcash/transparent
export BEND_NO_TELEMETRY=1 PATH=/opt/homebrew/opt/llvm/bin:$PATH
while [ $# -gt 0 ]; do
  case $1 in
    build) (cd fuzz && cargo build --release 2>&1 | grep -E "^error" -A8 | head -40)
           ./build.sh tv_main.bend tv && ./build.sh sh_main.bend sh; shift ;;
    tv) ./build.sh tv_main.bend tv; shift ;;
    fuzz) mkdir -p data/fuzz; fuzz/target/release/tv-fuzz data/fuzz/fz_$3 $2 $3; shift 3 ;;
    hard) mkdir -p data/fuzz; fuzz/target/release/tv-fuzz data/fuzz/hard_$3 $2 $3 hard; shift 3 ;;
    cargo) (cd fuzz && cargo build --release 2>&1 | grep -E "^error" -A8 | head -40); shift ;;
    vectors) mkdir -p data/fuzz; fuzz/target/release/tv-fuzz vectors data/fuzz/vec_0; shift ;;
    diff) shift; python3 run_diff.py "$@"; exit $? ;;
    *) echo "unknown $1"; exit 2 ;;
  esac
done
