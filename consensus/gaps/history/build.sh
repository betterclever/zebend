#!/bin/zsh
# build.sh prog.bend out: forked Bend -> C -> clang -O3 (as sapling/groth16/build.sh). Run under ../../../heavy.sh.
set -e
FORK=/Users/betterclever/projects/zecathon/bend-fork
src=$1; out=$2; shift 2
tmp=$(mktemp -d)
BEND_NO_TELEMETRY=1 bun $FORK/bend2/main.ts $src -o $tmp/prog.c
[ -n "${KEEP_C:-}" ] && cp $tmp/prog.c $KEEP_C
PATH=/opt/homebrew/opt/llvm/bin:$PATH clang -std=c11 ${CFLAGS_OPT:--O3} "$@" $tmp/prog.c -lpthread -lm -o $out
rm -rf $tmp
