#!/bin/zsh
# h2_check.sh: Halo 2 integration checks and throughput for decomp/v64 (table-sqrt
# decompression) against the same sources built with the original decompression
# (v64/batch_main_base, built from ../perf3/v64). Run under ../heavy.sh.
#   1. halo2/verifier bundle sets with v64/bundle_ba*: 42 (post-NU6.3), nu62 10, prenu62 8
#      (the older circuits via gen_variants.py)
#   2. a tampered chunk (one proof byte flipped): batch rejects, single verifier names it
#   3. the first N chunks (157 x 64 = 10,048 bundles) of proofsets: all accepted,
#      bundles/s at 1 and 18 threads, base and new interleaved.
cd ${0:a:h}
zmodload zsh/datetime
R=..; G=$R/halo2/verifier/data/params_g.bin; C=$R/proofsets/data/chunks
N=${N:-157}
uptime
if [ -z "${SKIP_VERDICTS:-}" ]; then
  for s in bundles:bundle_ba bundles_nu62:bundle_ba_nu62 bundles_prenu62:bundle_ba_prenu62; do
    (cd $R/halo2/verifier && echo "${s%:*}: $(python3 run_bundles.py ../../decomp/v64/${s#*:} data/${s%:*} | tail -1)")
  done
fi
# tamper: chunk 0 with bundle 17's proof byte 300 flipped
T=data/tamper_h2; rm -rf $T; mkdir -p $T; cp $C/p00c00000/*.bin $T/
f=$(ls $T | sed -n 18p)
python3 -c "import sys; p=sys.argv[1]; b=bytearray(open(p,'rb').read()); b[12+300]^=1; open(p,'wb').write(b)" $T/$f
echo "tamper: flipped proof byte 300 of $f"
for b in batch_main_base batch_main; do
  echo "$b tampered chunk: $(v64/$b $G $T/*.bin | grep -o 'batch K [0-9]* result [0-9]')"
done
for x in $T/*.bin; do r=$(v64/bundle_ba $G $x | grep -o 'result [0-9]'); [ "$r" = "result 1" ] || echo "bundle_ba rejects ${x:t}: $r"; done
run() {  # bin threads
  local s=$EPOCHREALTIME n=0 ok=1
  for c in $(ls $C | head -$N); do
    out=$(v64/$1 $G $C/$c/*.bin +RTS --threads $2 -RTS)
    echo "$out" | grep -q "result 1" && echo "$out" | grep -q "unreadable_or_missing 0" || { ok=0; echo "REJECTED $c"; }
    n=$((n + $(ls $C/$c | wc -l)))
  done
  printf "%-16s threads %2d: %d bundles, all accepted %d, %.1f s = %.0f bundles/s\n" $1 $2 $n $ok $((EPOCHREALTIME - s)) $((n / (EPOCHREALTIME - s)))
}
for t in 18 1; do
  for rep in 1 2 3; do run batch_main_base $t; run batch_main $t; done
done
uptime
