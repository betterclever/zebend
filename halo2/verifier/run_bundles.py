#!/usr/bin/env python3
"""Runs ./bundle_main on every file in data/bundles and compares each verdict with the
official halo2 verdict (data/bundles/halo2_verdicts.txt). Prints per-bundle wall time."""
import subprocess, sys, time

binary = sys.argv[1] if len(sys.argv) > 1 else "./bundle_main"
dirn = sys.argv[2] if len(sys.argv) > 2 else "data/bundles"
rows = [l.split() for l in open(f"{dirn}/halo2_verdicts.txt")]
agree = 0
acc = rej = 0
for name, ref, np_ in rows:
    t = time.perf_counter()
    out = subprocess.run([binary, "data/params_g.bin", f"{dirn}/{name}.bin"], capture_output=True, text=True).stdout
    dt = time.perf_counter() - t
    got = out.strip().split()[-1] if out.strip() else "?"
    same = got == ref
    agree += same
    acc += got == "1"
    rej += got == "0"
    print(f"{name:24} actions {np_:>2}  bend {got}  halo2 {ref}  {'agree' if same else 'DISAGREE'}  {dt*1000:7.0f} ms")
print(f"{len(rows)} bundles: bend accepts {acc}, rejects {rej}; agrees with halo2 on {agree}/{len(rows)}")
