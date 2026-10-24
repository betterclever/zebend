#!/usr/bin/env bash
# bend program -> C -> intrinsify -> native binary, with the flags `bend -o` uses:
#   CPU-only programs:  clang -std=c11 -O3 prog.c -lpthread -lm
#   programs with `!`:  add -DBEND_METAL=1 -x objective-c -fobjc-arc -fmodules (macOS)
# The binary embeds its own (patched) C file and compiles it as the Metal program on
# first run, so the GPU executes the same intrinsics as the CPU.
# Usage: build.sh prog.bend out_binary   (CC=... to pick a compiler)
set -euo pipefail
here=$(cd "$(dirname "$0")/../fast" && pwd)
tmp=$(mktemp -d)
BEND_NO_TELEMETRY=1 "${BEND:-$HOME/.bend/bin/bend}" "$1" -o "$tmp/prog.c"
python3 "$here/intrinsify.py" "$tmp/prog.c" "$tmp/prog.fast.c"
gpu=()
if grep -Eq '^#define BANGS +[1-9]' "$tmp/prog.fast.c" && [ "$(uname)" = Darwin ]; then
  gpu=(-DBEND_METAL=1 -x objective-c -fobjc-arc -fmodules)
fi
"${CC:-clang}" ${gpu[@]+"${gpu[@]}"} -std=c11 -O3 "$tmp/prog.fast.c" -lpthread -lm -o "$2"
rm -f "$2.gpu"
rm -rf "$tmp"
