#!/usr/bin/env bash
# bend program -> C -> intrinsify -> native binary, with the flags `bend -o` uses
# (clang -std=c11 -O3 ... -lpthread -lm). Usage: build.sh prog.bend out_binary
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
BEND_NO_TELEMETRY=1 "${BEND:-$HOME/.bend/bin/bend}" "$1" -o "$tmp/prog.c"
python3 "$here/intrinsify.py" "$tmp/prog.c" "$tmp/prog.fast.c"
"${CC:-clang}" -std=c11 -O3 "$tmp/prog.fast.c" -lpthread -lm -o "$2"
rm -rf "$tmp"
