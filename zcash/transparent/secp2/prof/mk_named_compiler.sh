#!/bin/zsh
# Profiling only: a private copy of the fork compiler (bend-fork/bend2, unchanged on disk) whose
# emitted C names each specialized helper spin_<n>_<bend def> instead of spin_<n>, so macOS
# `sample` output can be read. Creates secp2/prof/fk/bend2; build with
#   BEND_FORK=$PWD/secp2/prof/fk ./build.sh prog.bend out     (from zcash/transparent/, under ../heavy.sh)
here=$(cd "$(dirname "$0")" && pwd)
rm -rf $here/bend2p $here/fk; cp -r /Users/betterclever/projects/zecathon/bend-fork/bend2 $here/bend2p
python3 - $here/bend2p/comp.ts <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = 'const name = `spin_${FL.spun.size}`;'
assert old in s
s = s.replace(old, 'const name = `spin_${FL.spun.size}_${String(k).replace(/[^A-Za-z0-9]/g,"_").slice(-60)}`;')
open(p, "w").write(s)
PY
mkdir -p $here/fk && ln -sfn ../bend2p $here/fk/bend2
