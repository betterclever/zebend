#!/bin/zsh
# Repeat stock-Bend (2.0.38) Metal workloads on identical inputs and compare outputs bit for bit.
R=/Users/betterclever/projects/zecathon/bend-zcash
out=$R/bench/metal_determinism.log; : > $out
say() { echo "$@" | tee -a $out; }
say "== $(date)  $(sysctl -n machdep.cpu.brand_string)  macOS $(sw_vers -productVersion)"

# 1. gpu-scan (stock 2.0.38 build): hit list for 262,144 outputs, 30 runs
cd $R/gpu-scan
want=$(sed -n 2p vectors/out/expected_262144.txt)
ok=0; bad=0; : > /tmp/zb_scan_variants
for i in $(seq 1 30); do
  got=$(./scan_main vectors/out/batch_262144.bin 14 262144 | sed -n 3p | sed 's/^ //')
  echo "$got" | shasum | cut -c1-12 >> /tmp/zb_scan_variants
  [ "$got" = "$want" ] && ok=$((ok+1)) || bad=$((bad+1))
done
say "gpu-scan 262144 outputs x30: match $ok, mismatch $bad, distinct outputs $(sort -u /tmp/zb_scan_variants | wc -l | tr -d ' ')"

# 2. Equihash on GPU (eqv4, stock 2.0.38): 16384 mainnet headers, 20 runs
cd $R/blake3x/eqv4
: > /tmp/zb_eq
for i in $(seq 1 20); do
  ./verify $R/node/headers/data/mainnet.bin 16384 4096 12 2>&1 | grep -E 'valid|target|links|difficulty' | shasum | cut -c1-12 >> /tmp/zb_eq
done
say "equihash GPU 16384 headers x20: distinct outputs $(sort -u /tmp/zb_eq | wc -l | tr -d ' ')"
./verify $R/node/headers/data/mainnet.bin 16384 4096 12 2>&1 | grep -E 'valid|target|links' | tee -a $out

# 3. Ironwood tree on GPU (node/state tree_main, stock build): 6 roots, 10 runs
cd $R/node/state
: > /tmp/zb_tree
for i in $(seq 1 10); do
  ./tree_main out/cmx.bin gpu 2>&1 | grep -E '^height' | awk '{print $6, $7}' | shasum | cut -c1-12 >> /tmp/zb_tree
done
say "ironwood tree GPU x10: distinct outputs $(sort -u /tmp/zb_tree | wc -l | tr -d ' ')"
./tree_main out/cmx.bin gpu 2>&1 | grep -c MATCH | xargs -I{} echo "roots MATCH in last run: {}/6" | tee -a $out
say "== done $(date)"
