#!/usr/bin/env python3
"""diff.py SET.meta BEND_OUT: compare Bend verdicts (ed_main's "verdicts" line) with the
Rust oracle's (ed25519-zebra 4.2.0, second column of SET.meta), per category.
Exit status 1 on any disagreement."""
import sys
from collections import defaultdict

meta = [l.split() for l in open(sys.argv[1]) if l.strip()]
bend = None
for l in open(sys.argv[2]):
    if l.startswith("verdicts "):
        bend = l.split()[1] if len(l.split()) > 1 else ""
assert bend is not None, "no verdicts line"
if len(bend) != len(meta):
    print(f"LENGTH MISMATCH: {len(meta)} records, {len(bend)} Bend verdicts")
    sys.exit(1)

cats = defaultdict(lambda: [0, 0, 0, 0, 0])  # n, rust valid, bend valid, agree, cofactorless-fails among rust-valid
bad = []
for i, ((tag, v, cofl), b) in enumerate(zip(meta, bend)):
    c = cats[tag]
    c[0] += 1
    c[1] += v == "1"
    c[2] += b == "1"
    c[3] += v == b
    c[4] += v == "1" and cofl != "1"
    if v != b:
        bad.append((i, tag, v, b))

tot = [0, 0, 0, 0]
print(f"{'category':<12} {'records':>7} {'rust ok':>7} {'bend ok':>7} {'agree':>13}  cofactorless-fails among valid")
for tag in sorted(cats):
    n, rv, bv, ag, cf = cats[tag]
    print(f"{tag:<12} {n:>7} {rv:>7} {bv:>7} {ag:>6}/{n:<6}  {cf}")
    for j, x in enumerate((n, rv, bv, ag)):
        tot[j] += x
print(f"{'TOTAL':<12} {tot[0]:>7} {tot[1]:>7} {tot[2]:>7} {tot[3]:>6}/{tot[0]:<6}  disagreements {len(bad)}")
for x in bad[:20]:
    print("  disagree: record %d tag %s rust %s bend %s" % x)
sys.exit(1 if bad else 0)
