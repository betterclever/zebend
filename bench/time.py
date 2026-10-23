import subprocess, time, statistics, sys, os
runs = int(os.environ.get("RUNS", "5"))
cases = [
  ("Bend  1 thread",       ["./xs_bend", "+RTS", "--threads", "1", "-RTS"]),
  ("C     1 thread",       ["./xs_c", "1"]),
  ("Rust  1 thread",       ["./xs_rs", "1"]),
  ("Bend  18 threads",     ["./xs_bend"]),
  ("C     18 threads",     ["./xs_c", "18"]),
  ("Rust  18 threads",     ["./xs_rs", "18"]),
  ("Bend  Metal GPU",      ["./xs_bend_gpu"]),
]
print(f"load before: {os.getloadavg()[0]:.1f}")
for name, cmd in cases:
    ts = []
    for _ in range(runs):
        t = time.perf_counter(); out = subprocess.run(cmd, capture_output=True, text=True).stdout.strip(); ts.append(time.perf_counter() - t)
    print(f"{name:20s} median {statistics.median(ts)*1000:8.1f} ms  (min {min(ts)*1000:7.1f})  out={out}")
print(f"load after: {os.getloadavg()[0]:.1f}")
