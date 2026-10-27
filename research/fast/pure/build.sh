#!/usr/bin/env bash
# Pure Bend: no C post-processing. Builds with the forked compiler that has the
# U32.mul_hi primitive (bend-fork, branch u32-mulhi).  Usage: build.sh prog.bend out
set -euo pipefail
FORK=${BEND_FORK:-/Users/betterclever/projects/zecathon/bend-fork}
BEND_NO_TELEMETRY=1 bun "$FORK/bend2/main.ts" "$1" -o "$2"
