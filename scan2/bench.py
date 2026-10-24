#!/usr/bin/env python3
"""Cumulative benchmark: old gpu-scan vs scan2 variants on 1 thread, 18 threads, Metal.
Every run's hit list must equal orchard's expected list; medians of RUNS warm scans."""
import os, re, statistics, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
V = os.path.join(here, "..", "gpu-scan", "vectors", "out")
RUNS = int(os.environ.get("RUNS", "3"))
BINS = [("old gpu-scan (16-bit limbs)", os.path.join(here, "..", "gpu-scan", "scan_main")),
        ("step 1: 64-bit fields", os.path.join(here, "scan_main_v1")),
        ("step 2: + prepared ivk, GLV", os.path.join(here, "scan_main_v2")),
        ("step 3: + batched inversion", os.path.join(here, "scan_main"))]
CASES = [("1 thread", 16384, 8, ["+RTS", "--gpu", "off", "--threads", "1", "-RTS"]),
         ("18 threads", 65536, 8, ["+RTS", "--gpu", "off", "-RTS"]),
         ("Metal", 262144, 14, [])]
only = sys.argv[1:]

def run(binp, n, d, rts):
    want = open(os.path.join(V, f"expected_{n}.txt")).read().split("\n")[1].strip()
    out = subprocess.run([binp, os.path.join(V, f"batch_{n}.bin"), str(d), str(n)] + rts,
                         capture_output=True, text=True).stdout
    lines = out.split("\n")
    ms = int(re.search(r"scan_ms (\d+)", lines[0]).group(1))
    assert lines[2].strip() == want, f"MISMATCH {binp} N={n}"
    return ms

print(f"load {os.getloadavg()[0]:.1f}; medians of {RUNS}; outputs/s (all hit lists MATCH)")
print(f"{'':32s}" + "".join(f"{c[0]:>14s}" for c in CASES))
for name, binp in BINS:
    if only and not any(o in name for o in only):
        continue
    row = []
    for _, n, d, rts in CASES:
        if "old" in name and rts and "--threads" in rts:
            n = 4096  # the old 1-thread path is slow; same per-output work
        ms = statistics.median(run(binp, n, d, rts) for _ in range(RUNS))
        row.append(f"{n * 1000 / ms:>14,.0f}")
    print(f"{name:32s}" + "".join(row), flush=True)
print(f"load {os.getloadavg()[0]:.1f}")
