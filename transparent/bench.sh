#!/bin/zsh
# bench.sh DIR: sequential, one process at a time: Bend tv vs the Rust oracle (tv-oracle check) on the same files.
cd /Users/betterclever/projects/zecathon/bend-zcash/transparent
fs=($1/*.ztv)
s=$(python3 -c "import time;print(time.time())")
for f in $fs; do ./tv $f > /dev/null; done
b=$(python3 -c "import time;print(time.time())")
for f in $fs; do RAYON_NUM_THREADS=1 /usr/bin/time oracle/target/release/tv-oracle check $f > /dev/null; done
e=$(python3 -c "import time;print(time.time())")
n=$(cat ${fs[@]/%.ztv/.expect} | awk "{n+=length(\$3)} END {print n}")
python3 -c "print(f\"{len(\"$fs\".split())} files, $n inputs: Bend {($b-$s):.2f} s ({1e6*($b-$s)/$n:.0f} us/input), Rust {($e-$b):.2f} s ({1e6*($e-$b)/$n:.0f} us/input)\")"
