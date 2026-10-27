#!/usr/bin/env bash
# Pure Bend (forked compiler with U32.mul_hi) -> C -> clang with selectable flags.
#   build.sh prog.bend out [extra clang flags...]
# Env: CFLAGS_OPT (default "-O3"), KEEP_C=path to keep the emitted C, GUARD_S/GUARD_KB limits.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
FORK=${BEND_FORK:-/Users/betterclever/projects/zecathon/bend-fork}
src=$1; out=$2; shift 2
tmp=$(mktemp -d)
"$here/t/guard.sh" "${GUARD_S:-360}" "${GUARD_KB:-5000000}" env BEND_NO_TELEMETRY=1 bun "$FORK/bend2/main.ts" "$src" -o "$tmp/prog.c"
gpu=()
if grep -Eq '^#define BANGS +[1-9]' "$tmp/prog.c" && [ "$(uname)" = Darwin ]; then
  gpu=(-DBEND_METAL=1 -x objective-c -fobjc-arc -fmodules)
fi
[ -n "${KEEP_C:-}" ] && cp "$tmp/prog.c" "$KEEP_C"
"$here/t/guard.sh" "${GUARD_S:-360}" "${GUARD_KB:-5000000}" "${CC:-clang}" ${gpu[@]+"${gpu[@]}"} -std=c11 ${CFLAGS_OPT:--O3} "$@" "$tmp/prog.c" -lpthread -lm -o "$out"
rm -f "$out.gpu"
rm -rf "$tmp"
