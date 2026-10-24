#!/bin/zsh
# Check a Bend proof file with the forked Bend (u64-rot primitives). A larger JS stack
# lets the checker unfold literals up to 2^16. Usage: chk.sh FILE [--verdict]
ulimit -s 65520
export BEND_NO_TELEMETRY=1 BUN_JSC_maxPerThreadStackUsage=60000000
FORK=${BEND_FORK:-/Users/betterclever/projects/zecathon/bend-fork}
cd "$(dirname "$1")"
if [ "$2" = "--verdict" ]; then
  exec timeout ${CHK_TIMEOUT:-600} bun "$FORK/bend2/main.ts" "$(basename "$1")" --verdict
fi
exec timeout ${CHK_TIMEOUT:-360} bun "$FORK/bend2/main.ts" "$(basename "$1")" --check-only
