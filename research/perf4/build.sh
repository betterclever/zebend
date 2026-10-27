#!/usr/bin/env bash
# build.sh prog.bend out [extra clang flags...]
# Pure Bend -> C (forked compiler, integration worktree `zebend` by default) -> clang.
# Runs under tools/heavy.sh (Mac-wide lock, RSS/time guard).
# Env: BEND_FORK (default ../../../bend-fork-zebend), CFLAGS_OPT (default -O3), KEEP_C=path.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
Z=$(cd "$here/../.." && pwd)
FORK=${BEND_FORK:-/Users/betterclever/projects/zecathon/bend-fork-zebend}
src=$1; out=$2; shift 2
tmp=$(mktemp -d)
export BEND_NO_TELEMETRY=1
HEAVY_MAX_GB=${HEAVY_MAX_GB:-8} "$Z/tools/heavy.sh" bun "$FORK/bend2/main.ts" "$src" -o "$tmp/prog.c"
gpu=()
if grep -Eq '^#define BANGS +[1-9]' "$tmp/prog.c" && [ "$(uname)" = Darwin ]; then
  gpu=(-DBEND_METAL=1 -x objective-c -fobjc-arc -fmodules)
fi
[ -n "${KEEP_C:-}" ] && cp "$tmp/prog.c" "$KEEP_C"
"$Z/tools/heavy.sh" "${CC:-clang}" ${gpu[@]+"${gpu[@]}"} -std=c11 ${CFLAGS_OPT:--O3} "$@" "$tmp/prog.c" -lpthread -lm -o "$out"
rm -rf "$tmp"
