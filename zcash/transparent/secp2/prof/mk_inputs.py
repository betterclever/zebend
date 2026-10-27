#!/usr/bin/env python3
"""Profiling inputs: big.ztv (every 4th file of data/real: 7,928 records, 28,679 inputs),
preow.ztv (all pre-Overwinter files), ecdsa_valid.bin (the 10,000 valid cases of
data/t/ecdsa.bin, x3, mode-3 records for secp_t)."""
import glob, os, struct
H = os.path.dirname(os.path.abspath(__file__)); T = os.path.join(H, "../..")
def cat(fs, out):
    recs, n = b"", 0
    for f in fs:
        b = open(f, "rb").read(); n += struct.unpack("<I", b[4:8])[0]; recs += b[8:]
    open(os.path.join(H, out), "wb").write(b"ZTV1" + struct.pack("<I", n) + recs)
cat(sorted(glob.glob(f"{T}/data/real/*.ztv"))[::4], "big.ztv")
cat(sorted(glob.glob(f"{T}/data/real/preoverwinter_*.ztv")), "preow.ztv")
d = open(f"{T}/data/t/ecdsa.bin", "rb").read(); exp = open(f"{T}/data/t/ecdsa.bin.expect").read().split("\n")
i, k, recs = 1, 0, []
while i < len(d):
    n = d[i]; r = d[i:i + 1 + n + 96]; i += 1 + n + 96
    if exp[k].startswith("v 1"): recs.append(r)
    k += 1
open(os.path.join(H, "ecdsa_valid.bin"), "wb").write(bytes([3]) + b"".join(recs * 3))
