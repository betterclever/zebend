#!/usr/bin/env python3
"""Compares the Bend verifier's log with halo2's instrumented trace, name by name.
Repeated names (u_j, msm_g, expr*) are compared in order. Usage: compare.py bend_out oracle_trace"""
import sys
from collections import defaultdict

def load(path):
    seq = defaultdict(list)
    for line in open(path):
        parts = line.split()
        if len(parts) == 2:
            name, val = parts
            if name.startswith("msm_g") and name != "msm_g":
                name = "msm_g"
            seq[name].append(val)
    return seq

bend, ref = load(sys.argv[1]), load(sys.argv[2])
ok = bad = 0
for name in bend:
    if name not in ref or name in ("result",):
        continue
    for i, (a, b) in enumerate(zip(bend[name], ref[name])):
        if a == b:
            ok += 1
        else:
            bad += 1
            if bad <= 10:
                print(f"MISMATCH {name}[{i}]: bend {a} halo2 {b}")
    if len(bend[name]) != len(ref[name]):
        print(f"COUNT {name}: bend {len(bend[name])} halo2 {len(ref[name])}")
names = sorted(n for n in bend if n in ref)
print(f"{ok} values equal, {bad} differ, across {len(names)} names: {' '.join(names)}")
