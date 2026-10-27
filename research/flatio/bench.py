# bench.py RUNS CMD... : run CMD RUNS times, print median/min wall ms and max RSS MB
import subprocess, sys, time, resource, os, statistics
n = int(sys.argv[1]); cmd = sys.argv[2:]
ts = []; out = None
for i in range(n + 2):
    t = time.perf_counter()
    r = subprocess.run(cmd, capture_output=True, text=True)
    dt = (time.perf_counter() - t) * 1000
    if i >= 2: ts.append(dt)
    out = r.stdout.strip().splitlines()[-1:] if r.stdout.strip() else r.stderr.strip()[-200:]
rss = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss / (1 << 20)
print(f"median {statistics.median(ts):8.2f} ms  min {min(ts):8.2f} ms  maxrss {rss:6.1f} MB  out {out}  :: {' '.join(cmd)}")
