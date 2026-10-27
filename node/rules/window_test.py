#!/usr/bin/env python3
"""rules.validate (mode full, hooks) on a contiguous window of real blocks above the last
checkpoint, spent outputs from the real chain (lightwalletd, TEST DATA)."""
import sys, time
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent)); sys.path.insert(0, str(HERE))
import rules
from test_rules import DATA, TestStore, delta

a, b = int(sys.argv[1]), int(sys.argv[2])
raw = {h: (DATA / f"{h}.bin").read_bytes() for h in range(a, b + 1)}
blocks = delta(raw)
st = TestStore()
st.fetch([p for bl in blocks for t in bl["txs"] for (p, _, _) in t["ins"]])
t = time.time()
extra = rules.validate(blocks, st, raw, print, mode="full")
el = time.time() - t
print(f"window {a}..{b}: {len(blocks)} blocks, {sum(len(x['txs']) for x in blocks)} txs: every rule PASS in {el:.2f} s "
      f"({el / len(blocks) * 1000:.0f} ms/block incl. ctx + hooks)")
print(extra)
