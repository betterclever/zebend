#!/usr/bin/env python3
"""Patch the single C file emitted by `bend x.bend -o x.c` so it compiles for WASI.

Bend 2 has no WebAssembly target, but its C output is a self-contained runtime.
Only a few native-only pieces stand in the way: huge lazily-committed mmap
reservations (an 8 GB heap, a 2 GB stack) that wasm32's 4 GB address space and
WASI's malloc-backed mmap emulation cannot provide, and a SIGSEGV alt-stack
handler. Everything is wrapped in `#ifdef __wasi__`, so the patched file still
builds natively.  Usage: bend2wasm.py in.c out.c [heap_log2=28]
"""
import sys

src, dst = sys.argv[1], sys.argv[2]
heap_log2 = int(sys.argv[3]) if len(sys.argv) > 3 else 30
stack_log2 = int(sys.argv[4]) if len(sys.argv) > 4 else 24
s = open(src).read()

def sub(old, new):
    global s
    if s.count(old) != 1:
        sys.exit(f"bend2wasm: expected exactly one occurrence of:\n{old}")
    s = s.replace(old, new)

# Stack: 2 GB reservation -> 16 MB, no guard page or signal alt-stack on WASI.
sub("  u64   len = 1ull << 31;\n",
    "#ifdef __wasi__\n  u64   len = 1ull << __WASI_STACK_LOG2;\n#else\n  u64   len = 1ull << 31;\n#endif\n")
sub("""  if (mprotect(p + len, 16384, PROT_NONE)) {
    err_fail("stack guard failed");
  }
  stack_t ss = { .ss_sp = p + len + 16384, .ss_size = alt };
  sigaltstack(&ss, NULL);
  struct sigaction sa = { .sa_handler = err_trap,
    .sa_flags = SA_ONSTACK | SA_NODEFER };
  sigaction(SIGSEGV, &sa, NULL);
  sigaction(SIGBUS, &sa, NULL);
""", """#ifndef __wasi__
  if (mprotect(p + len, 16384, PROT_NONE)) {
    err_fail("stack guard failed");
  }
  stack_t ss = { .ss_sp = p + len + 16384, .ss_size = alt };
  sigaltstack(&ss, NULL);
  struct sigaction sa = { .sa_handler = err_trap,
    .sa_flags = SA_ONSTACK | SA_NODEFER };
  sigaction(SIGSEGV, &sa, NULL);
  sigaction(SIGBUS, &sa, NULL);
#endif
""")
sub("  u64   alt = 4 * SIGSTKSZ;\n",
    "#ifdef __wasi__\n  u64   alt = 0;\n#else\n  u64   alt = 4 * SIGSTKSZ;\n#endif\n")
# Heap: 8 GB CPU reservation -> 2^heap_log2 bytes.
sub("(!gpu ? 1ull << 33 :",
    f"(!gpu ? (__WASI_HEAP_BYTES) :")
s = f"#define __WASI_STACK_LOG2 {stack_log2}\n#ifdef __wasi__\n#define __WASI_HEAP_BYTES (1ull << {heap_log2})\n#else\n#define __WASI_HEAP_BYTES (1ull << 33)\n#endif\n" + s
# Fixed-address hints above 4 GB are meaningless on wasm32.
sub("""static void* corpus_map(u64 size) {
""", """static void* corpus_map(u64 size) {
#ifdef __wasi__
  return pool_mmap(size);
#endif
""")
# WASI's mmap emulation rejects MAP_NORESERVE. Big reservations (the heap) grow
# linear memory directly: fresh pages are zeroed and contiguous at the top, so the
# runtime's "double the heap in place" (an mmap at H + size) keeps working while the
# heap is the topmost allocation. Small ones (the term stack) come from calloc.
sub("""static void* pool_try(void* at, u64 bytes) {
""", """static void* pool_try(void* at, u64 bytes) {
#ifdef __wasi__
  if (bytes >= (1ull << 26)) {
    size_t top = __builtin_wasm_memory_size(0) * 65536;
    if (at != NULL && (size_t)at != top) {
      return MAP_FAILED;
    }
    if (__builtin_wasm_memory_grow(0, (size_t)((bytes + 65535) / 65536)) == (size_t)-1) {
      return MAP_FAILED;
    }
    return (void*)top;
  }
  (void)at;
  void* z = calloc(1, (size_t)bytes);
  return z ? z : MAP_FAILED;
#endif
""")
# No pipe() and no threads on wasip1: blocking effects run inline and their
# completions go through an in-memory queue instead of helper thread + wake pipe.
sub("""static int             io_wake_fd[2];
""", """static int             io_wake_fd[2];
#ifdef __wasi__
static IoWork*         io_done_q;
#endif
""")
sub("""static void io_take(Env e) {
  IoWork* acts[64];
  ssize_t n;
""", """static void io_take(Env e) {
#ifdef __wasi__
  while (io_done_q != NULL) {
    IoWork* a = io_pop(&io_done_q);
    a->item   = a->pack(e, a);
    io_push(&io_runs, a);
    io_busy -= 1;
  }
  return;
#endif
  IoWork* acts[64];
  ssize_t n;
""")
sub("""  w->call  = call;
  w->pack  = pack;
  io_busy += 1;
""", """  w->call  = call;
  w->pack  = pack;
  io_busy += 1;
#ifdef __wasi__
  call(w);
  io_push(&io_done_q, w);
  return IO_PARK;
#endif
""")
sub("""static void io_wait(Env e, bool block) {
  int top  = io_wake_fd[0];
""", """static void io_wait(Env e, bool block) {
#ifdef __wasi__
  if (io_done_q != NULL) {
    block = false;
  }
#endif
  int top  = io_wake_fd[0];
""")
sub("""  io_bit(set, io_wake_fd[0], true);
  io_parked(a) {""", """#ifndef __wasi__
  io_bit(set, io_wake_fd[0], true);
#endif
  io_parked(a) {""")
sub("""  if (io_bit(set, io_wake_fd[0], false)) {
    io_take(e);
  }""", """#ifdef __wasi__
  io_take(e);
#else
  if (io_bit(set, io_wake_fd[0], false)) {
    io_take(e);
  }
#endif""")
sub("""  if (pipe(io_wake_fd) | fcntl(io_wake_fd[0], F_SETFL, O_NONBLOCK)) {""", """#ifdef __wasi__
  io_wake_fd[0] = io_wake_fd[1] = -1;
  if (0) {
#else
  if (pipe(io_wake_fd) | fcntl(io_wake_fd[0], F_SETFL, O_NONBLOCK)) {
#endif""")
sub("  signal(SIGPIPE, SIG_IGN);\n", "#ifndef __wasi__\n  signal(SIGPIPE, SIG_IGN);\n#endif\n")
# Single-threaded by default on wasip1 (`+RTS --threads N` still overrides).
sub("""static long cpu_count(void) {
""", """static long cpu_count(void) {
#ifdef __wasi__
  return 1;
#endif
""")
# Without the wake pipe the highest fd may be -1; size the fd sets from 0.
sub("""  u64 len = (u64)top / 64 * 8 + 8;
""", """#ifdef __wasi__
  if (top < 0) {
    top = 0;
  }
#endif
  u64 len = (u64)top / 64 * 8 + 8;
""")
open(dst, "w").write(s)
