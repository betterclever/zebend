#!/bin/zsh
# optlevel.sh prog.c: --gpu-build the emitted C with MTLCompileOptions.optimizationLevel
# = Size instead of Default, to see whether Apple's compiler survives fully inlined kernels.
src=$1; d=$(mktemp -d); CC=/opt/homebrew/opt/llvm/bin/clang
python3 - $src $d/v.c <<'PY'
import sys
s=open(sys.argv[1]).read()
old='  opts.mathMode = MTLMathModeSafe;\n'
assert old in s
s=s.replace(old, old+'  opts.optimizationLevel = MTLLibraryOptimizationLevelSize;\n',1)
open(sys.argv[2],'w').write(s)
PY
$CC -x objective-c -fobjc-arc -fmodules -DBEND_METAL=1 -std=c11 -O3 $d/v.c -lpthread -lm -o $d/v || exit 1
start=$(date +%s)
if $d/v +RTS --gpu-build 2>$d/err; then echo "$src size-opt: OK ($(( $(date +%s)-start ))s)"; cp $d/v ${src:r}_os; cp $d/v.gpu ${src:r}_os.gpu; else echo "$src size-opt: FAIL ($(( $(date +%s)-start ))s) $(head -c 150 $d/err)"; fi
rm -rf $d
