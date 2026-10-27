#!/usr/bin/env bash
# build.sh prog.bend out: forked Bend (U32.mac64) -> C -> clang -O3, via ../../research/perf3/build.sh.
# Run it under ../../tools/heavy.sh. Env as research/perf3/build.sh (KEEP_C, CFLAGS_OPT, GUARD_S, GUARD_KB).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
export BEND_NO_TELEMETRY=1 PATH=/opt/homebrew/opt/llvm/bin:$PATH
exec "$here/../perf3/build.sh" "$@"
