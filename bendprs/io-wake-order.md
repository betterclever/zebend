# io_loop opens its wake pipe before it sets O_NONBLOCK on it

Branch `pr/io-wake-order` (on origin/main), a one-character change in comp.ts.

**Problem.** `if (pipe(io_wake_fd) | fcntl(io_wake_fd[0], F_SETFL, O_NONBLOCK))` uses `|`, so
the order of the two calls is up to the compiler. If `fcntl` runs first, it sets O_NONBLOCK on
fd 0. That is the inherited stdin, which is often shared with the parent and its other children.
The wake pipe then stays blocking, and `io_take`'s read loop blocks once the pipe drains.

**Fix.** `||`: `pipe` runs first, and `fcntl` runs only if `pipe` succeeded.

**Test.** clang currently calls `pipe` first (checked with `otool -tV`), so no test can show a
difference today. The io tests that go through `io_wait` / `io_take` still pass on C, JS and
the interpreter: tests/io/chan_pipe, sleep_timer and spawn_sleep.

**Tokens.** comp.ts 65,994, unchanged.

The fix came out of the empty-output audit (empty-output.md). It is not the cause of the empty
outputs.
