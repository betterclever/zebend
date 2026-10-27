#!/usr/bin/env python3
"""lat.py N T REPS bin[:params] ...: process wall time (ms) and the binary's batch_ms for one
batch of the first N proofsets bundles, REPS interleaved runs, medians. `bin:params` picks the
params file (a sibling .gtab is then used by perf4 binaries)."""
import os, re, statistics, subprocess, sys, time
Z = "/Users/betterclever/projects/zecathon/zebend"
CH = f"{Z}/research/proofsets/data/chunks"
DP = f"{Z}/zcash/halo2/verifier/data/params_g.bin"
N, T, R = int(sys.argv[1]), sys.argv[2], int(sys.argv[3])
bins = sys.argv[4:]
files = []
for c in sorted(os.listdir(CH)):
    files += [f"{c}/{f}" for f in sorted(os.listdir(f"{CH}/{c}"))]
    if len(files) >= N: break
files = files[:N]
res = {b: ([], [], []) for b in bins}
for _ in range(R):
    for b in bins:
        exe, _, par = b.partition(":")
        t = time.perf_counter()
        out = subprocess.run([exe, par or DP, *files, "+RTS", "--threads", T, "-RTS"], cwd=CH, capture_output=True, text=True).stdout
        w = (time.perf_counter() - t) * 1000
        m = re.search(r"batch K (\d+) result (\d)", out); bm = re.search(r"batch_ms (\d+)", out)
        assert m and int(m.group(1)) == N and m.group(2) == "1", out
        res[b][0].append(w); res[b][1].append(int(bm.group(1)))
print(f"N={N} T={T} reps={R} load={os.getloadavg()[0]:.1f}")
for b in bins:
    w, bm, _ = res[b]
    print(f"  {os.path.basename(b):60s} wall med {statistics.median(w):8.1f} min {min(w):8.1f}  batch_ms med {statistics.median(bm):7.1f}  -> {N*1000/statistics.median(w):7.1f} bundles/s (wall)")
