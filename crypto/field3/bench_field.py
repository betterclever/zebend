#!/usr/bin/env python3
"""Field mul/sqr benchmark: previous pure Bend (research/fast/pure) vs field3 variants vs Rust.
Medians of RUNS, all run interleaved so machine load hits every column alike."""
import os, re, statistics, subprocess, sys
H = os.path.dirname(os.path.abspath(__file__))
Z = os.path.dirname(os.path.dirname(H))
RUNS = int(os.environ.get("RUNS", "7"))
one = ["+RTS", "--threads", "1", "-RTS"]
cases = {
    "mul: research/fast/pure (round 2)": ([f"{Z}/research/fast/pure/t/mulbench32"] + one, r"Fq\.mul: (\d+) ms"),
    "mul: + U32.mac_hi/add_hi": ([f"{H}/t/mulbench3_v1"] + one, r"Fq\.mul: (\d+) ms"),
    "mul: field3 32-bit limbs": ([f"{H}/t/mulbench3"] + one, r"Fq\.mul: (\d+) ms"),
    "mul: field3 64-bit limbs (mac64)": ([f"{H}/t/mulbench64"] + one, r"Fq\.mul: (\d+) ms"),
    "sqr: research/fast/pure (round 2)": ([f"{H}/t/sqrbench_old"] + one, r"Fq\.sqr: (\d+) ms"),
    "sqr: + primitives (sqr = mul)": ([f"{H}/t/sqrbench3_v1"] + one, r"Fq\.sqr: (\d+) ms"),
    "sqr: + dedicated squaring": ([f"{H}/t/sqrbench3"] + one, r"Fq\.sqr: (\d+) ms"),
    "sqr: 64-bit limbs (mac64)": ([f"{H}/t/sqrbench64"] + one, r"Fq\.sqr: (\d+) ms"),
    "rust mul": ([f"{H}/rust/target/release/field3-rust", "bench"], r"1e6 Fq\.mul: ([0-9.]+) ms"),
    "rust sqr": ([f"{H}/rust/target/release/field3-rust", "bench"], r"1e6 Fq\.sqr: ([0-9.]+) ms"),
}
vals = {k: [] for k in cases}
outs = {}
print(f"load {os.getloadavg()[0]:.1f}")
for _ in range(RUNS):
    for k, (cmd, pat) in cases.items():
        o = subprocess.run(cmd, capture_output=True, text=True).stdout
        vals[k].append(float(re.search(pat, o).group(1)))
        outs.setdefault(k, o.splitlines()[0])
print(f"load {os.getloadavg()[0]:.1f}")
for k in cases:
    print(f"{k:34s} {statistics.median(vals[k]):8.1f} ms")
# Same chain result for every Bend mul variant and every Bend sqr variant.
print("mul results agree:", len({outs[k] for k in cases if k.startswith('mul')}) == 1)
print("sqr results agree:", len({outs[k] for k in cases if k.startswith('sqr')}) == 1)
