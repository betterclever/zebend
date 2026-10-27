#!/usr/bin/env python3
"""check_batch.py BIN [THREADS]: batch soundness/completeness on the 42-bundle set.
 - all 21 honest bundles in one batch: `result 1` and `verified 21`;
 - each of the 21 tampered bundles, inserted into the honest batch (position varies): `result 0`;
PARAMS: params file (default the verifier data one; perf4/data/params_g.bin has the .gtab table).
 - each honest bundle alone: `result 1`; each tampered bundle alone: `result 0`."""
import os, re, subprocess, sys
Z = "/Users/betterclever/projects/zecathon/zebend"
D = f"{Z}/zcash/halo2/verifier/data"
binp = sys.argv[1]; T = sys.argv[2] if len(sys.argv) > 2 else "18"
rows = [l.split() for l in open(f"{D}/bundles/halo2_verdicts.txt")]
honest = [f"bundles/{n}.bin" for n, v, _ in rows if v == "1"]
bad = [f"bundles/{n}.bin" for n, v, _ in rows if v == "0"]
def run(fs):
    out = subprocess.run([binp, os.environ.get("PARAMS", f"{D}/params_g.bin"), *fs, "+RTS", "--threads", T, "-RTS"], cwd=D, capture_output=True, text=True).stdout
    m = re.search(r"^batch K (\d+) result ([01])$", out, re.M); v = re.search(r"^verified (\d+)", out, re.M)
    if not m or int(m.group(1)) != len(fs) or not v or int(v.group(1)) != len(fs):
        return f"?({out.strip()[-200:]!r})"
    return m.group(2)
fails = 0
r = run(honest); print("honest x21:", r); fails += r != "1"
for i, b in enumerate(bad):
    fs = honest[:i] + [b] + honest[i:]
    r = run(fs); fails += r != "0"
    if r != "0": print("TAMPERED ACCEPTED/ERR", b, r)
print(f"tampered-in-batch: {len(bad)} runs")
for f in honest:
    r = run([f]); fails += r != "1"
    if r != "1": print("HONEST REJECTED", f, r)
for f in bad:
    r = run([f]); fails += r != "0"
    if r != "0": print("TAMPERED ACCEPTED", f, r)
print(f"singles: {len(honest)} honest + {len(bad)} tampered")
print("CHECK", "PASS" if fails == 0 else f"FAIL ({fails})")
