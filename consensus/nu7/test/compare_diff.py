#!/usr/bin/env python3
"""Differential test of the height-aware difficulty (headers/diff7.bend via bin/t_diff) against
Zebra 1e03ee75's AdjustedDifficulty (oracle `diffchain`, data/vectors/zebra_diffchain_*.jsonl):
synthetic Mainnet chains across NU7 (on schedule, hash rate unchanged = 75 s blocks, 8 s blocks),
Testnet chains with minimum-difficulty gaps (449/450/451/900/901 s) on both sides of NU7, and
Zakura's own chains D and D2. Every block whose context is full is compared.
usage: compare_diff.py [files...]"""
import json, struct, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
VEC = HERE / "data/vectors"


def run(net, recs):
    p = HERE / "data/tmp/diff_in.bin"
    p.write_bytes(b"".join(struct.pack("<III", *r) for r in recs))
    out = subprocess.run([str(HERE / "bin/t_diff"), net, str(p), str(p.stat().st_size)], capture_output=True, text=True).stdout
    return {int(a): int(b) for _, a, b in (l.split() for l in out.splitlines() if l.startswith("exp "))}


bad = 0
files = sys.argv[1:] or sorted(str(p) for p in VEC.glob("zebra_diffchain_*.jsonl"))
for f in files:
    f = Path(f)
    net = "test" if "testnet" in f.name else "main"
    ins = [l.split() for l in open(f.with_suffix(".in")) if l.strip()]
    z = {r["h"]: r for r in map(json.loads, open(f))}
    recs = []
    for h, t, b in ins:
        h = int(h)
        bits = int(b, 16) if b != "?" else int(z[h]["expected"], 16)
        recs.append((h, int(t), bits))
    got = run(net, recs)
    mism = [(h, hex(v), z[h]["expected"]) for h, v in got.items() if f"{v:08x}" != z[h]["expected"]]
    nmin = sum(1 for h in got if z[h].get("min_diff"))
    print(f"{f.name}: {len(got)} blocks compared ({nmin} min-difficulty), {len(mism)} mismatches {mism[:3]}")
    bad += len(mism) + (len(got) == 0)
sys.exit(1 if bad else 0)
