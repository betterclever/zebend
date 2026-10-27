#!/usr/bin/env python3
"""Halo 2 Orchard bundle verification: Bend 16-bit fields vs Bend 32-bit + intrinsics.
Whole-process wall time (reads params + bundle, decompresses points, verifies), median of 9."""
import os, statistics, subprocess, time
V = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "zcash", "halo2", "verifier")
os.chdir(V)
bins = {"bend 16-bit (Pippenger)": "./bundle_main_fast", "bend 32-bit + intrinsics": "../../../research/fast/v32/bundle_main_fast"}
print(f"load {os.getloadavg()[0]:.1f}")
for bundle, label in [("data/bundles/tx_17.ironwood.bin", "2 actions"), ("data/bundles/tx_15.orchard.bin", "16 actions")]:
    for name, b in bins.items():
        for threads in ("1", None):
            cmd = [b, "data/params_g.bin", bundle] + (["+RTS", "--threads", threads, "-RTS"] if threads else [])
            ts, out = [], ""
            for _ in range(9):
                t = time.perf_counter(); out = subprocess.run(cmd, capture_output=True, text=True).stdout.strip(); ts.append(time.perf_counter() - t)
            print(f"{label:10s} {name:26s} threads={threads or 'all':3s} median {statistics.median(ts)*1000:7.1f} ms  ({out})")
