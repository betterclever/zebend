#!/usr/bin/env python3
"""subset.py SET TAG OUT [REPEAT]: the records of SET.bin whose SET.meta tag is TAG, written to
OUT (record format unchanged), optionally repeated REPEAT times (for timing)."""
import struct, sys
base, tag, out = sys.argv[1], sys.argv[2], sys.argv[3]
rep = int(sys.argv[4]) if len(sys.argv) > 4 else 1
data = open(base + ".bin", "rb").read()
tags = [l.split()[0] for l in open(base + ".meta") if l.strip()]
n = struct.unpack("<I", data[:4])[0]
p, recs = 4, []
for i in range(n):
    ml = struct.unpack("<I", data[p + 96:p + 100])[0]
    if tags[i] == tag:
        recs.append(data[p:p + 100 + ml])
    p += 100 + ml
recs = recs * rep
open(out, "wb").write(struct.pack("<I", len(recs)) + b"".join(recs))
print(f"{len(recs)} records")
