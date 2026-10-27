#!/usr/bin/env python3
"""Lab check: each hook's output in-process (inproc.run_hook) == as a subprocess, on the same lists.
usage: inproc_check.py <hooks dir> <list file>...   (prints stdout equality and return codes)"""
import subprocess, sys, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import inproc

hooks = Path(sys.argv[1])
for lst in sys.argv[2:]:
    name = Path(lst).parent.name
    exe = hooks / name
    t = time.perf_counter()
    a = subprocess.run([str(exe), lst], capture_output=True, text=True)
    ta = time.perf_counter() - t
    t = time.perf_counter()
    b = inproc.run_hook(exe, lst, 600)
    tb = time.perf_counter() - t
    same = a.stdout == b.stdout and a.returncode == b.returncode
    print(f"{name}: {len(a.stdout.splitlines())} verdict lines; subprocess {ta * 1000:.0f} ms rc {a.returncode}, "
          f"in-process {tb * 1000:.0f} ms rc {b.returncode} (target {inproc.target(exe)}): {'IDENTICAL' if same else 'DIFFERENT'}")
    if not same:
        print("  sub:", a.stdout[-300:], a.stderr[-300:])
        print("  in :", b.stdout[-300:], b.stderr[-300:])
