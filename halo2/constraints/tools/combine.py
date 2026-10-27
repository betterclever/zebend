"""Combine a normal and a relaxed mutation run: recall by category, with self-copies (no-op
constraints) separated, and the remaining survivors listed.
usage: combine.py DUMP NORMAL.jsonl RELAXED.jsonl"""
import json, sys
from collections import Counter
d = json.load(open(sys.argv[1])); lay = d["layout"]; R = lay["regions"]
owner = {(c[0], c[1]): (R[c[2]], c[3]) for c in lay["advice"]}
copies = lay["copies"]
def load(p):
    return {json.loads(l)["mutant"]: json.loads(l) for l in open(p)}
a, b = load(sys.argv[2]), load(sys.argv[3])
cat = Counter(); fl_n = Counter(); fl_r = Counter(); fl_u = Counter()
surv = []
for k in a:
    kind, arg = k.split(":", 1)
    if kind == "copy":
        c = copies[int(arg)]
        kind = "copy (self, no-op)" if (c[0], c[1], c[2]) == (c[3], c[4], c[5]) else "copy (real)"
    cat[kind] += 1
    fl_n[kind] += a[k]["flagged"]; fl_r[kind] += b[k]["flagged"]
    u = a[k]["flagged"] or b[k]["flagged"]
    fl_u[kind] += u
    if not u and kind != "copy (self, no-op)":
        surv.append(k)
print(f"{d['version']}: recall by category (normal / relaxed / either)")
for k in cat:
    print(f"  {k:20s} {fl_n[k]:5d} / {fl_r[k]:5d} / {fl_u[k]:5d}  of {cat[k]}")
print(f"  survivors of both modes, excluding self-copies: {len(surv)}")
def cell(k, col, row):
    if k != "a": return {"f": "FIXED", "i": "INSTANCE"}[k] + f"{col}@{row}"
    reg, nm = owner.get((col, row), ("-", "<unassigned>"))
    return f"a{col}@{row} [{reg}] {nm.split('::')[-1].strip()}"
for k in surv:
    kind, arg = k.split(":", 1)
    if kind == "copy":
        c = copies[int(arg)]
        print(f"    {k}: {cell(c[0], c[1], c[2])}  <->  {cell(c[3], c[4], c[5])}")
    else:
        print(f"    {k}")
