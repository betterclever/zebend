#!/usr/bin/env python3 -B
"""tn_blk.py A B OUT: testnet raw blocks [A, B] from consensus/nu7/data/testnet/raw.bin (raw.idx:
'height offset length') into OUT records u32 h | u32 len | raw."""
import struct, sys
from pathlib import Path
T = Path(__file__).resolve().parents[4] / "consensus/nu7/data/testnet"
a, b, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
idx = {}
for l in open(T / "raw.idx"):
    h, o, n = map(int, l.split()); idx[h] = (o, n)
raw = open(T / "raw.bin", "rb")
with open(out, "wb") as w:
    k = 0
    for h in range(a, b + 1):
        if h not in idx:
            sys.exit(f"missing testnet block {h}")
        o, n = idx[h]; raw.seek(o); w.write(struct.pack("<II", h, n) + raw.read(n)); k += 1
print(k, "blocks")
