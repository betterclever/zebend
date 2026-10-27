#!/bin/zsh
# Run under ../../heavy.sh: every differential test of transparent/ against tv.new / the secp2
# binaries. Logs to secp2/logs/.
cd /Users/betterclever/projects/zecathon/bend-zcash/transparent
mkdir -p secp2/logs
J=${JOBS:-12}
python3 script2/t/hash_check.py 2>&1 | tee secp2/logs/hash.log | tail -3
python3 secp2/t/check2.py ${N:-20000} 2>&1 | tee secp2/logs/check2.log | tail -8
python3 run_diff.py --bin ./tv.new --jobs $J data/real 2>&1 | tee secp2/logs/real.log | head -3
python3 run_diff.py --bin ./tv.new --jobs $J data/tampered 2>&1 | tee secp2/logs/tampered.log | head -3
python3 run_diff.py --bin ./tv.new --jobs $J data/fuzz 2>&1 | tee secp2/logs/fuzz.log | head -3
SH_BIN=secp2/t/sh2 python3 sighash_check.py data/real 2>&1 | tee secp2/logs/sighash.log | head -3
