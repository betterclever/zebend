#!/bin/zsh
# airdiff.sh: AIR of flh.c with term_tag forced inline vs plain inline.
cd /Users/betterclever/projects/zecathon/bend-zcash/gpuv/t
python3 -c "
s=open('flh.c').read()
s=s.replace('INLINE u64 term_tag(','inline u64 term_tag(',1)
open('flh_plain.c','w').write(s)"
for f in flh flh_plain; do xcrun -sdk macosx metal -x metal -DCUBE_LOG=7 -fno-fast-math -S -emit-llvm $f.c -o $f.ll 2>/dev/null; echo "$f: $(wc -l < $f.ll) lines, calls $(grep -E '(call|invoke) ' $f.ll | grep -vcE '@(llvm|air)\.'), defs $(grep -c '^define ' $f.ll)"; done
diff <(grep -v '^;\|^source_filename\|^!' flh.ll) <(grep -v '^;\|^source_filename\|^!' flh_plain.ll) | head -20
