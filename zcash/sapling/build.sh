#!/usr/bin/env bash
# build.sh prog.bend out [clang flags...]: forked Bend (bend-fork, branch metal-spill: U32.mac64
# etc., every Metal device helper always_inline) -> C -> clang (Metal if the program has GPU
# calls). Run it under ../../tools/heavy.sh. Same pattern as research/perf3/build.sh.
set -euo pipefail
FORK=${BEND_FORK:-/Users/betterclever/projects/zecathon/bend-fork}
G=/Users/betterclever/projects/zecathon/zebend/research/perf3/t/guard.sh
src=$1; out=$2; shift 2
tmp=$(mktemp -d)
"$G" "${GUARD_S:-480}" "${GUARD_KB:-7000000}" env BEND_NO_TELEMETRY=1 bun "$FORK/bend2/main.ts" "$src" -o "$tmp/prog.c"
gpu=()
if grep -Eq '^#define BANGS +[1-9]' "$tmp/prog.c" && [ "$(uname)" = Darwin ]; then
  gpu=(-DBEND_METAL=1 -x objective-c -fobjc-arc -fmodules)
fi
[ -n "${KEEP_C:-}" ] && cp "$tmp/prog.c" "$KEEP_C"
"$G" "${GUARD_S:-480}" "${GUARD_KB:-7000000}" "${CC:-clang}" ${gpu[@]+"${gpu[@]}"} -std=c11 ${CFLAGS_OPT:--O3} "$@" "$tmp/prog.c" -lpthread -lm -o "$out"
rm -f "$out.gpu"
rm -rf "$tmp"
