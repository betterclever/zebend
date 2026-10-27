# Silent empty output under parallel load: investigation (no PR)

Status: **not reproduced, root cause not found in the runtime.** No branch was made: there is
nothing to fix that a test can pin.

## The report

`node/follow/README.md`: "Under parallel load a Bend process occasionally exits 0 having printed
nothing (about 1 run in 700)". `node/follow/logs/run.log` has 39 `rerun: txx printed nothing` in
19,284 `txx` calls, all between 2026-10-25 10:19Z and about 10:51Z (catch-up with 14 jobs).
After that there are 0 in 14,366 calls, though those later windows are much less parallel.
`node/follow/zebend_follow.py` `run()` never records the return code, so "exits 0" was not logged
by the driver itself.

## Stress runs (all 0 empty, all rc 0)

Harness: `/Users/betterclever/projects/zecathon/bendwork/empty/`. Each script counts outputs
where `(stdout + stderr).strip()` is empty, as follow does.

| harness | binary / inputs | parallel | runs | empty |
|---|---|---|---|---|
| `stress.py` | small fork program `tbin` | 64 | 20,000 | 0 |
| `stress.py` | `tbin --threads 1 --gpu off` | 64 | 10,000 | 0 |
| `stress2.py` | `node/follow/bin/txx`, 400 Sapling-era tx/ctx pairs | 48 | 20,000 | 0 |
| `stress2.py` | same | 14 | 3,000 | 0 |
| `stress2.py` | same | 14 | 60,000 | 0 |
| `stress2.py` | same, `--threads 1 --gpu off` | 14 | 30,000 | 0 |
| `stress2.py` | `node/follow/work/oldbin/txx` (the older build) | 14 | 30,000 | 0 |
| `mix.py` (10 min) | txx on 1,500 Orchard tx (14 + 6 at `--threads 1`), a Metal `!` program (3), `tbin` (6), all at once | 29 | 177,934 | 0 |
| `mix2.py` (7 min) | follow-like driver: 1.5 GB resident Python, 6 busy socket/file threads, `ThreadPoolExecutor(14)`, `text=True` | 14 | 51,400 | 0 |
| Linux VM, `stress2.py` | txx C built on Linux (clang -O2) | 32 | 10,000 | 0 |

That is about 422,000 runs and 0 empties. The Mac ran with swap 9.4 of 10 GB used and load
averages of 28 to 126 during some runs.

Sanitizers (Linux VM, same `txx.c`):
- MemorySanitizer (`-fno-sanitize-memory-param-retval`; the default param check only flags
  the register bank passed uninitialised through musttail calls, which is by design) is clean
  on 60 Orchard inputs, default threads and `--threads 1`.
- ThreadSanitizer is clean on 30 Orchard inputs.

## Code audit: every way the C runtime can end

- `main` returns 0 only after `io_loop` returns and `io_sync` (fflush, checked) succeeds.
  `io_loop` returns only when the last IO fibre reaches `Emit`. `exit` flushes again.
- `Halt` / `Exit` call `io_sync` before `exit(code)`. `Halt` writes its message to stderr.
- `err_fail` and `err_trap` always write `bend: ...` to stderr, so they are never silent, and
  their exit status is non-zero.
- Short writes or EPIPE on stdout go to `io_lost`, which raises SIGPIPE or calls `err_fail`
  (non-zero, stderr).
- IO helper threads (`io_help`) hand results back through `io_wake_fd`, and `io_busy` is
  touched only on the main thread. No path was found that loses a request.
- `txx` itself always prints: a missing file gives `IO.die` (stderr, rc 2), and empty or bad
  bytes give `INVALID ...`.

So an empty stdout with an empty stderr means either the program never ran its print (only a
wrong evaluation could do that; it is deterministic with `--threads 1`, and MSan is clean) or
the process was killed by a signal it cannot report, SIGKILL. A SIGKILL leaves no crash report
and gives rc -9, which `run()` does not look at. No `txx*.ips` or JetsamEvent reports exist in
`~/Library/Logs/DiagnosticReports` or `/Library/Logs/DiagnosticReports`. The unified log for
that window is no longer available.

## Suggested next steps

1. Make the drivers log `r.returncode` and the wall time of every empty run (one line in
   `run()`). The next occurrence will say whether it was rc 0 or a signal.
2. Keep the rerun. It is still right whatever the cause.
3. One small, unrelated latent issue found in the audit: `io_loop` does
   `pipe(io_wake_fd) | fcntl(io_wake_fd[0], ...)`. The two operands of `|` are unsequenced, so
   a compiler may call `fcntl` on the still-zero `io_wake_fd[0]` (stdin) first. clang
   currently calls `pipe` first (checked with `otool`), so it does no harm today. Using `||`
   fixes it at no token cost.
