#!/bin/zsh
# aircalls.sh prog.bend [CUBE_LOG]: emit the Bend program's C (which is also its Metal
# source), compile it to AIR (LLVM IR) the way the runtime does, and list every call
# to a non-intrinsic function left in the device code (air.* / llvm.* are intrinsics).
set -e
src=$1; cl=${2:-7}; out=${src:r}
bun /Users/betterclever/projects/zecathon/bend-fork/bend2/main.ts $src -o $out.c
xcrun -sdk macosx metal -x metal -DCUBE_LOG=$cl -fno-fast-math -S -emit-llvm $out.c -o $out.ll 2>&1 | grep -v warning | head -5 || true
echo "defined functions: $(grep -c '^define ' $out.ll)"
grep '^define ' $out.ll | sed -E 's/.*@([A-Za-z0-9_.$]+)\(.*/  \1/' | head -20
echo "calls to non-intrinsics: $(grep -E '(call|invoke) ' $out.ll | grep -vE '@(llvm|air)\.' | wc -l)"
grep -E '(call|invoke) ' $out.ll | grep -vE '@(llvm|air)\.' | sed -E 's/.*@([A-Za-z0-9_.$]+)\(.*/  \1/' | sort | uniq -c | sort -rn | head -20
