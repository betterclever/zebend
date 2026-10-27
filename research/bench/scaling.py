# Thread scaling: Bend (32-bit + intrinsics) vs Rust, same machine, medians.
import os, re, statistics, subprocess, sys, time
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
THREADS = [1, 2, 4, 8, 18]

def wall(cmd, cwd, runs=5):
    ts = []
    out = ""
    for _ in range(runs):
        t = time.perf_counter()
        out = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True).stdout
        ts.append((time.perf_counter() - t) * 1000)
    return statistics.median(ts), out

def row(name, vals):
    print(f"{name:44s}" + "".join(f"{v:>10}" for v in vals), flush=True)

print(f"load {os.getloadavg()[0]:.1f}", flush=True)
row("threads", THREADS)

v = os.path.join(ROOT, "zcash", "halo2", "verifier")
for bundle, label in [("data/bundles/tx_17.ironwood.bin", "2 actions"), ("data/bundles/tx_15.orchard.bin", "16 actions")]:
    vals = []
    for t in THREADS:
        ms, out = wall([os.path.join(ROOT, "research", "fast", "v32", "bundle_main_fast"), "data/params_g.bin", bundle, "+RTS", "--threads", str(t), "-RTS"], v)
        assert "result 1" in out, out
        vals.append(f"{ms:.1f}")
    row(f"Bend Halo 2 verify, {label} (ms, wall)", vals)

lib = os.path.join(ROOT, "zcash", "halo2", "lib")
vals = []
for t in THREADS:
    ms_list = []
    for _ in range(5):
        out = subprocess.run([os.path.join(ROOT, "research", "fast", "lib32", "msm_fast_main"), "vectors/out/msm_2048.bin", "8", "0", "2048", "+RTS", "--gpu", "off", "--threads", str(t), "-RTS"], cwd=lib, capture_output=True, text=True).stdout
        m = re.search(r"warm_ms (\d+)", out.splitlines()[0])
        ms_list.append(float(m.group(1)))
    vals.append(f"{statistics.median(ms_list):.1f}")
row("Bend MSM n=2048 Pippenger (ms, timed in-program)", vals)

perf = os.path.join(ROOT, "zcash", "halo2", "lib", "perf")
vals, vvals = [], []
for t in THREADS:
    env = dict(os.environ, RAYON_NUM_THREADS=str(t))
    out = subprocess.run(["./target/release/bend-halo2-perf", "bench-msm", "2048"], cwd=perf, capture_output=True, text=True, env=env).stdout
    m = re.findall(r"threads=(\d+): median ([0-9.]+) ms", out)
    vals.append(m[-1][1])
    out = subprocess.run(["./target/release/bend-halo2-perf", "bench-verify", "1"], cwd=perf, capture_output=True, text=True, env=env).stdout
    m = re.search(r"single proof verify[^:]*: median ([0-9.]+) ms", out)
    vvals.append(m.group(1) if m else "?")
row("Rust best_multiexp n=2048 (ms)", vals)
row("Rust orchard verify, 2-action bundle (ms)", vvals)
