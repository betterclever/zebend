#!/bin/zsh
# Build the sources exactly as deploy.sh installs them (imports rewritten for node/),
# in a mirror tree, and check the binaries print the same as fast/bin on the bench data.
set -e
F=/Users/betterclever/projects/zecathon/zebend/node/fast
R=/Users/betterclever/projects/zecathon/zebend
M=$F/bench/mirror
rm -rf $M; mkdir -p $M/fullnode/bend $M/fullnode/wire $M/fullnode/rules $M/fullnode/bin
for d in node halo2 consensus; do ln -s $R/$d $M/$d; done
cp $R/node/bend/parse.bend $M/fullnode/bend/
for f in delta zip244 pts sha; do sed -e 's#\.\./\.\./\.\./#../../#g' $F/bend/$f.bend > $M/fullnode/bend/$f.bend; done
for f in blk txv; do sed -e 's#\.\./\.\./\.\./#../../#g' $F/wire/$f.bend > $M/fullnode/wire/$f.bend; done
sed -e 's#\.\./\.\./\.\./#../../#g' $F/rules/rules.bend > $M/fullnode/rules/rules.bend
export BEND_NO_TELEMETRY=1 PATH=/opt/homebrew/opt/llvm/bin:$PATH
cd $M/fullnode/bend && ~/.bend/bin/bend delta.bend -o ../bin/blockdelta
cd $M/fullnode/rules && ~/.bend/bin/bend rules.bend -o ../bin/rules
cd $F/bench
for d in spam cons; do
  for k in 0 7; do
    $M/fullnode/bin/blockdelta data/$d/bd_$k.bin | cmp - data/$d/bd_$k.out && echo "mirror blockdelta $d part $k: identical"
    $M/fullnode/bin/rules data/$d/rw_$k.bin data/$d/rc_$k.bin --gated | cmp - data/$d/rw_$k.out && echo "mirror rules --gated $d part $k: identical"
  done
done
