#!/usr/bin/env python3
"""Tamper tests for blockdelta (prints one line per case and whether Bend caught it)."""
import struct, subprocess, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import headers
BIN = HERE.parent / "bin/blockdelta"

def rec(h, blk, hd=None):
    hd = hd if hd is not None else headers.header(h)
    return struct.pack("<I", h) + hd + struct.pack("<I", len(blk)) + blk

def run(win):
    p = Path("/tmp/tamper_win.bin"); p.write_bytes(win)
    return subprocess.run([str(BIN), str(p)], capture_output=True, text=True).stdout

ok = 0
cases = []
b = (HERE / "data/3460010.bin").read_bytes()
t = bytearray(b); t[len(b) // 2] ^= 1                       # a byte inside some tx
cases.append(("flip one byte inside a tx (3460010)", rec(3460010, bytes(t)), "merkle MISMATCH"))
b1 = (HERE / "data/396.bin").read_bytes()
t = bytearray(b1); t[-5] ^= 0x10                           # inside the v2 JoinSplit tx's tail
cases.append(("flip one byte in the JoinSplit tx (396)", rec(396, bytes(t)), "merkle MISMATCH"))
cases.append(("truncate block by 1 byte (3460010)", rec(3460010, b[:-1]), "INVALID wire"))
cases.append(("append 1 trailing byte (396)", rec(396, b1 + b"\0"), "INVALID wire"))
cases.append(("header from another height (396 vs verified 397)", rec(396, b1, headers.header(397)), "header MISMATCH"))
t = bytearray(b1); t[36] ^= 1                              # merkle root field in the header
cases.append(("flip header merkle root (396)", rec(396, bytes(t)), "header MISMATCH merkle MISMATCH"))
big = (HERE / "data/1750000.bin").read_bytes()
cases.append(("block over 2,000,000 bytes", rec(1750000, big + b"\0" * 50000), "INVALID wire"))
for name, win, want in cases:
    out = run(win).splitlines()[0]
    hit = want in out
    ok += hit
    print(f"{'CAUGHT' if hit else 'MISSED'}  {name}: {out[:40]}...{out[-40:]}")
# a window mixing a bad record between good ones: processing continues
win = rec(1, (HERE / "data/1.bin").read_bytes()) + rec(3460010, b[:-1]) + rec(2, (HERE / "data/2.bin").read_bytes())
out = run(win)
cont = "block 2 " in out and "merkle MATCH" in out.split("block 2 ")[1].splitlines()[0]
print(f"{'OK' if cont else 'FAIL'}  invalid record mid-window: following block still processed")
print(f"{ok}/{len(cases)} tampers caught")
