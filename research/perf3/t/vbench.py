# vbench.py BIN... : per-verify time (ms) from wall clock over many in-process verifies.
import os, statistics, subprocess, sys, time
DATA = "/Users/betterclever/projects/zecathon/zebend/zcash/halo2/verifier/data"
bundle = os.environ.get("BUNDLE", "bundles/tx_17.ironwood.bin")
def per(binp, n, thr, reps=3):
    ts = []
    for _ in range(reps):
        t = time.perf_counter()
        out = subprocess.run([binp, "params_g.bin", bundle, str(n), "+RTS", "--threads", str(thr), "-RTS"], cwd=DATA, capture_output=True, text=True).stdout
        assert f"ok {n}" in out, out
        ts.append((time.perf_counter() - t) * 1000 / n)
    return statistics.median(ts)
print(f"load {os.getloadavg()[0]:.1f}  bundle {bundle}")
for b in sys.argv[1:]:
    p = os.path.abspath(b)
    print(f"{os.path.basename(b):24s} 1T {per(p, 40, 1):7.1f} ms   18T {per(p, 150, 18):6.1f} ms", flush=True)
