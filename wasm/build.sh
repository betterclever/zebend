#!/usr/bin/env bash
# bend file -> C -> patched C -> WASI module.  Usage: build.sh file.bend out.wasm
set -euo pipefail
WASI_SDK=${WASI_SDK:?set WASI_SDK to an extracted wasi-sdk}
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
BEND_NO_TELEMETRY=1 "${BEND:-bend}" "$1" -o "$tmp/out.c"
python3 "$here/bend2wasm.py" "$tmp/out.c" "$tmp/out.wasi.c" "${HEAP_LOG2:-30}"
# TARGET=wasm32-wasip1 (default): single-threaded, runs anywhere (wasmtime, node, browsers).
# TARGET=wasm32-wasip1-threads: shared memory + wasi-threads, for hosts that still support it.
target=${TARGET:-wasm32-wasip1}
extra=(-Wl,--max-memory=4294967296 -Wl,-z,stack-size=${STACK_BYTES:-8388608})
[ "$target" = wasm32-wasip1-threads ] && extra+=(-pthread -Wl,--import-memory,--export-memory)
"$WASI_SDK/bin/clang" --target=$target --sysroot="$WASI_SDK/share/wasi-sysroot" \
  -O2 -mtail-call -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_MMAN -D_WASI_EMULATED_PROCESS_CLOCKS "${extra[@]}" \
  "$tmp/out.wasi.c" -lwasi-emulated-signal -lwasi-emulated-mman -lwasi-emulated-process-clocks \
  -o "$2" 2> "$tmp/cc.log" || { grep -E 'error' "$tmp/cc.log"; exit 1; }
echo "built $2 ($(wc -c < "$2") bytes)"
