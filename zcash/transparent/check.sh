#!/bin/zsh
# check.sh prog.bend: type/termination check only (no C, no clang), capped at 1.5 GB / 120 s.
# Light enough to run outside ../../tools/heavy.sh; builds still go through heavy.sh + build.sh.
export BEND_NO_TELEMETRY=1
exec /usr/bin/time -l /Users/betterclever/projects/zecathon/zebend/research/perf3/t/guard.sh 120 1500000 bun /Users/betterclever/projects/zecathon/bend-fork/bend2/main.ts "$1" --check-only
