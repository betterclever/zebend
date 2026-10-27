#!/usr/bin/env python3
"""Build a window file for blockdelta from data/<h>.bin: u32 height | verified header | u32 len | block.
usage: mkwin.py OUT H [H ...]   (header bytes from zcash/headers' verified files; genesis: the block's own)"""
import struct, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import headers
out = open(sys.argv[1], "wb")
for a in sys.argv[2:]:
    h = int(a)
    b = (HERE / f"data/{h}.bin").read_bytes()
    hd = headers.header(h) if h >= 1 else b[:1487]
    out.write(struct.pack("<I", h) + hd + struct.pack("<I", len(b)) + b)
