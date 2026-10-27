#!/bin/zsh
# run_chain.sh STATE0 FROM TO STEP OUTDIR BLK... : run `history` over [FROM, TO] in windows of STEP
# blocks, each window starting from the previous window's state.out (as the node would).
# Side roots from data/nu63e.bin (histdata). Prints the concatenated hist lines to stdout.
set -e
cd ${0:a:h}/..
st=$1; from=$2; to=$3; step=$4; out=$5; shift 5
mkdir -p $out
cat "$@" > $out/all.blk
a=$from
while [ $a -le $to ]; do
  b=$(( a + step - 1 )); [ $b -gt $to ] && b=$to
  python3 -B tools/mkwin.py main $out/all.blk data/nu63e.bin $out/w.bin $out/s.bin $a $b > /dev/null
  ./bin/history $st $out/w.bin $out/s.bin $out/st_$b.st
  st=$out/st_$b.st
  a=$(( b + 1 ))
done
rm -f $out/all.blk $out/w.bin $out/s.bin
