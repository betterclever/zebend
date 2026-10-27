#!/usr/bin/env python3
"""Bend `sh` sighashes vs the oracle's FILE.sighash (the values zcash_primitives / the oracle
fed to zcash_script's callback). Each oracle line (r, in, ht, value) is compared with Bend's
line for the same record, input and hash type when ht is one of 01 02 03 81 82 83.
  python3 sighash_check.py DIR_OR_FILE... (run under ../../tools/heavy.sh; SH_BIN=path picks another sh binary)"""
import os, re, subprocess, sys, collections
from concurrent.futures import ThreadPoolExecutor
HERE = os.path.dirname(os.path.abspath(__file__))
fs = []
for p in sys.argv[1:]:
    for root, _, names in (os.walk(p) if os.path.isdir(p) else [(os.path.dirname(p), None, [os.path.basename(p)])]):
        fs += [os.path.join(root, n) for n in names if n.endswith(".ztv")]
def one(f):
    out = subprocess.run([os.environ.get("SH_BIN", os.path.join(HERE, "sh")), f], capture_output=True, text=True).stdout
    got = {(r, i, h): v for r, i, h, v in re.findall(r"^r (\d+) in (\d+) ht (\w\w) (\S+)$", out, re.M)}
    c = collections.Counter(); bad = []
    for r, i, h, v in re.findall(r"^r (\d+) in (\d+) ht (\w\w) (\S+)$", open(f[:-4] + ".sighash").read(), re.M):
        if h.lower() not in ("01", "02", "03", "81", "82", "83"):
            c["other_ht"] += 1; continue
        g = got.get((r, i, h.lower()))
        c["compared"] += 1
        if g != v.lower() and not (g == "NONE" and v == "NONE"):
            c["mismatch"] += 1; bad.append((f, r, i, h, v, g))
    return c, bad
tot = collections.Counter(); bads = []
with ThreadPoolExecutor(12) as ex:
    for c, b in ex.map(one, sorted(fs)):
        tot += c; bads += b
print(f"files {len(fs)}  sighashes compared {tot['compared']}  mismatches {tot['mismatch']}  (other hash types skipped: {tot['other_ht']})")
for b in bads[:10]: print("MISMATCH", *b)
