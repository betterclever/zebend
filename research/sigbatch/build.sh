#!/usr/bin/env bash
# build.sh prog.bend out: forked Bend (u64-rot: U32.mac64 etc.) -> C -> clang (Metal if the
# program has GPU calls). Run it under ../../tools/heavy.sh.
set -euo pipefail
FORK=${BEND_FORK:-/Users/betterclever/projects/zecathon/bend-fork-sig}
src=$1; out=$2; shift 2
tmp=$(mktemp -d)
BEND_NO_TELEMETRY=1 bun "$FORK/bend2/main.ts" "$src" -o "$tmp/prog.c"
gpu=()
if grep -Eq '^#define BANGS +[1-9]' "$tmp/prog.c" && [ "$(uname)" = Darwin ]; then
  gpu=(-DBEND_METAL=1 -x objective-c -fobjc-arc -fmodules)
  # Apple's Metal compiler can corrupt a caller's word across a non-inlined helper call
  # (nondeterministic). The device program is this same file (#embed __FILE__), so make
  # every noinline helper (FAR, and DFAR = FAR on the device) always_inline under Metal.
  # Forcing INLINE/OUTLINE too (all helpers) makes the Metal compiler service crash
  # (XPC_ERROR_CONNECTION_INTERRUPTED after ~3.5 min), so those stay inline hints.
  # NO_METAL_INLINE=1 skips this (only for reproducing the corruption).
  [ -n "${NO_METAL_INLINE:-}" ] || perl -0pi -e 's/^#define FAR static __attribute__\(\(noinline\)\)$/#ifdef __METAL_VERSION__\n#define FAR static inline __attribute__((always_inline))\n#else\n#define FAR static __attribute__((noinline))\n#endif/m or die "FAR"' "$tmp/prog.c"
fi
[ -n "${KEEP_C:-}" ] && cp "$tmp/prog.c" "$KEEP_C"
"${CC:-clang}" ${gpu[@]+"${gpu[@]}"} -std=c11 -O3 "$@" "$tmp/prog.c" -lpthread -lm -o "$out"
rm -f "$out.gpu"
rm -rf "$tmp"
