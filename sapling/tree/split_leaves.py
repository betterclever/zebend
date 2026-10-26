#!/usr/bin/env python3
"""Split the oracle's leaf file (36-byte records: u32 height, cmu) into 32-byte-cmu part
files of 2^24 leaves (256 chunks of 2^16) each, so that Bend's File.read_at (U32 offsets)
can address them:  ../data/leaves32/part_NNN.bin   (part p holds chunks 256p .. 256p+255).
Existing parts of the right size are kept (the sync is append-only).

  python3 split_leaves.py [LEAVES]"""
import pathlib, sys

here = pathlib.Path(__file__).resolve().parent
src = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else here.parent / "data/sapling_leaves.bin"
out = here.parent / "data/leaves32"
out.mkdir(parents=True, exist_ok=True)
PER = 1 << 24
n = src.stat().st_size // 36
with open(src, "rb") as f:
    for p in range((n + PER - 1) // PER):
        k = min(PER, n - p * PER)
        dst = out / f"part_{p:03d}.bin"
        if dst.exists() and dst.stat().st_size == 32 * k:
            continue
        f.seek(36 * PER * p)
        buf = f.read(36 * k)
        dst.write_bytes(b"".join(buf[i + 4:i + 36] for i in range(0, 36 * k, 36)))
        print(f"part {p}: {k} leaves", flush=True)
print(n, "leaves")
