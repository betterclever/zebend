# bend2wasm

Bend 2 (2.0.38) targets C, Metal, CUDA and JavaScript, but not WebAssembly. Its C
output is a self-contained runtime, though, so a few guarded patches are enough to
compile it with [wasi-sdk](https://github.com/WebAssembly/wasi-sdk) and run it in any
WASI host (wasmtime, Node.js `node:wasi`, browsers with a WASI shim).

```sh
WASI_SDK=/path/to/wasi-sdk-34 BEND=~/.bend/bin/bend ./build.sh program.bend program.wasm
wasmtime run program.wasm
```

## What gets patched (`bend2wasm.py`)

Every change sits behind `#ifdef __wasi__`, so the patched file still builds natively.

| Native assumption | WASI replacement |
|---|---|
| 8 GB heap + 2 GB stack reserved lazily with `mmap(MAP_NORESERVE)` | `calloc`: 1 GB heap (`HEAP_LOG2`, default 30), 16 MB stack |
| `sigaltstack` / `SIGSEGV` handler for stack-overflow reporting | dropped |
| fixed-address mmap hints above 4 GB | ignored (wasm32) |
| blocking effects on helper threads, woken through a `pipe()` | run inline, completed through an in-memory queue |
| one worker thread per CPU | one thread by default (`+RTS --threads N` still overrides) |

Two build flags matter:

- `-mtail-call`: the runtime's worker functions chain through `musttail` calls.
  Without WASM tail calls each becomes a real call and the engine's stack runs out.
- `-Wl,-z,stack-size=8388608`: wasm-ld's default 64 KB shadow stack overflows and
  wraps to address 2³², which shows up as a "memory fault at 0x100000000".

## Verified

`smoke.bend` (`pow2!(20n)`, a parallel recursion) prints `1048576` under wasmtime 50
and Node 24 (`node:wasi`). The same patched C also compiles natively with clang and
prints the same result.

## Limits

- Single-threaded. `wasm32-wasip1-threads` builds (`TARGET=wasm32-wasip1-threads`),
  but wasmtime 50 dropped `wasi-threads`. `!` (GPU) calls run on the CPU.
- No sockets or processes on wasip1. Pure code, files, stdout, time and sleep are fine.
- The patches match Bend 2.0.38's emitted C exactly and fail loudly if it changes.
