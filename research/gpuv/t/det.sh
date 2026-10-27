#!/bin/zsh
# det.sh N CMD...: run CMD N times (each under heavy.sh) and compare stdout bit for bit,
# ignoring timing lines (batch_ms / ms). Prints the distinct outputs with their counts.
# Exit 0 only if all N runs printed the same thing.
n=$1; shift
H=/Users/betterclever/projects/zecathon/zebend/tools/heavy.sh
tmp=$(mktemp -d)
for i in $(seq 1 $n); do
  $H "$@" 2>&1 | grep -vE '^(batch_ms|ms|prep_ms|prep digest) ' > $tmp/$i
done
shasum $tmp/* | awk '{print $1}' | sort | uniq -c > $tmp/sums
echo "runs $n distinct $(wc -l < $tmp/sums | tr -d ' ')"
while read c h; do f=$(shasum $tmp/* | awk -v h=$h '$1==h{print $2; exit}'); echo "  x$c: $(tr '\n' '|' < $f | cut -c1-200)"; done < $tmp/sums
d=$(wc -l < $tmp/sums | tr -d ' '); rm -rf $tmp; [ $d = 1 ]
