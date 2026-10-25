#!/bin/zsh
# metal_inline_build.sh [scan|eq|tree ...]: rebuild the three shipped GPU programs with the Bend
# fork's metal-spill branch (every Metal device helper always_inline + GPU lane spill restored;
# bend-fork/METAL_INLINE.md, METAL_SPILL.md) to *.inl binaries, and count non-intrinsic calls
# left in the emitted Metal (gpuv/t/aircalls.sh; must be 0). Log: bench/metal_inline_build.log.
# Gate the *.inl binaries (RUNS=20 BIN_SUFFIX=.inl bench/metal_inline_gate.sh) before moving them
# (and their .gpu caches) over the shipped names.
# Run from the Mac. Each step goes through heavy.sh.
R=/Users/betterclever/projects/zecathon/bend-zcash
FORK=${BEND_FORK:-/Users/betterclever/projects/zecathon/bend-fork}
export BEND_NO_TELEMETRY=1 PATH=/opt/homebrew/opt/llvm/bin:$PATH
log=$R/bench/metal_inline_build.log
say() { echo "$@" | tee -a $log; }
[ "$(git -C $FORK rev-parse --abbrev-ref HEAD)" = metal-spill ] || { echo "fork not on metal-spill" >&2; exit 1; }
say "== $(date)  fork $(git -C $FORK rev-parse --short HEAD) (metal-spill)"
one() {  # dir src out
  local d=$1 src=$2 out=$3
  cd $R/$d || return 1
  rm -f $out.inl $out.inl.gpu
  $R/heavy.sh bun $FORK/bend2/main.ts $src -o $out.inl 2>&1 | tail -5 | tee -a $log
  [ -x $out.inl ] && say "$d/$out.inl built" || { say "$d/$out.inl BUILD FAILED"; return 1; }
  # aircalls writes ${src:r}.c/.ll next to the source; keep them out of the tree afterwards
  $R/heavy.sh $R/gpuv/t/aircalls.sh $src 2>&1 | awk '/^defined functions/ {p=1} p' | sed "s|^|$d/$src: |" | tee -a $log
  rm -f ${src:r}.c ${src:r}.ll
}
for p in ${@:-scan eq tree}; do
  case $p in
    scan) one scan2 scan_main.bend scan_main ;;
    eq)   one blake3x/eqv4 main.bend verify ;;
    tree) one node/state tree_main.bend tree_main ;;
  esac
done
say "== done $(date)"
