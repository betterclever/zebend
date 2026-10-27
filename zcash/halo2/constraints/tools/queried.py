"""For the globally free cells of an anchor_*.json report: is the cell queried (symbolically,
whatever its coefficient at this witness) by any gate or lookup on a row where one of the
expression's selectors is enabled? usage: queried.py DUMP ANCHOR_JSON"""
import json, sys
from collections import defaultdict
d = json.load(open(sys.argv[1])); r = json.load(open(sys.argv[2]))
cs, lay = d["cs"], d["layout"]; n = lay["n"]
on = defaultdict(list)
for s, row, reg in lay["selectors"]:
    on[s].append(row)
def walk(e, sels, advs):
    t = e[0]
    if t == "s": sels.add(e[1])
    elif t == "a": advs.add((e[1], e[2]))
    elif t in ("-", "k"): walk(e[1], sels, advs)
    elif t in ("+", "*"): walk(e[1], sels, advs); walk(e[2], sels, advs)
exprs = [(f"gate {g['name']}/{c['name']}", c["poly"]) for g in cs["gates"] for c in g["constraints"]]
exprs += [(f"lookup {i}", e) for i, l in enumerate(cs["lookups"]) for e in l["inputs"]]
queried = defaultdict(set)
for lab, e in exprs:
    sels, advs = set(), set()
    walk(e, sels, advs)
    rows = set()
    for s in sels: rows.update(on[s])
    if not sels: rows = set(range(n))
    for row in rows:
        for col, rot in advs:
            queried[(col, (row + rot) % n)].add(lab)
cells = [(c["col"], c["row"], c["name"]) for c in r["global"]["free_cells"]]
hit = [(c, sorted(queried[(c[0], c[1])])) for c in cells if queried.get((c[0], c[1]))]
print(f"{r['version']}: {len(cells)} globally free cells; queried by an active gate/lookup: {len(hit)}")
for c, labs in hit:
    print("  ", c, labs[:4])

# ---- is each hit's coefficient zero for EVERY witness, or only for the honest one?
# Re-evaluate d(expr)/d(cell) with every advice cell set to a random value (cells in one
# copy class share a value; fixed, selectors, instance as in the dump). A coefficient that
# is zero at random advice values is (w.h.p.) zero as a polynomial in the advice after the
# fixed/selector/copy structure is substituted: the cell cannot influence that equation.
import random, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cslib import P
rnd = random.Random(11)
parent = {}
def find(x):
    while parent.get(x, x) != x:
        x = parent[x]
    return x
for c in lay["copies"]:
    a, b = find((c[0], c[1], c[2])), find((c[3], c[4], c[5]))
    if a != b: parent[a] = b
F = defaultdict(int)
for col, row, val, reg, name in lay["fixed"]:
    F[(col, row)] = int(val, 16)
selset = {(s, row) for s, row, reg in lay["selectors"]}
INST = [[int(v, 16) for v in c] for c in lay["instance"]]
fixed_class = {}
for c in lay["copies"]:
    for k in ((c[0], c[1], c[2]), (c[3], c[4], c[5])):
        if k[0] == "f": fixed_class[find(k)] = F[(k[1], k[2])]
        if k[0] == "i": fixed_class[find(k)] = INST[k[1]][k[2]] if k[2] < len(INST[k[1]]) else 0
rv = {}
def aval(col, row):
    root = find(("a", col, row))
    if root in fixed_class: return fixed_class[root]
    if root not in rv: rv[root] = rnd.randrange(P)
    return rv[root]
def dval(e, r, target):
    t = e[0]
    if t == "c": return int(e[1], 16), 0
    if t == "s": return (1 if (e[1], r) in selset else 0), 0
    if t == "f": return F[(e[1], (r + e[2]) % n)], 0
    if t == "i":
        rr = (r + e[2]) % n; col = INST[e[1]]
        return (col[rr] if rr < len(col) else 0), 0
    if t == "a":
        cell = (e[1], (r + e[2]) % n)
        return aval(*cell), (1 if find(("a",) + cell) == target else 0)
    if t == "-":
        v, g = dval(e[1], r, target); return (-v) % P, (-g) % P
    if t == "k":
        v, g = dval(e[1], r, target); k = int(e[2], 16); return v * k % P, g * k % P
    va, ga = dval(e[1], r, target); vb, gb = dval(e[2], r, target)
    if t == "+": return (va + vb) % P, (ga + gb) % P
    return va * vb % P, (ga * vb + gb * va) % P
struct = wit = 0
for c, labs in hit:
    col, row = c[0], c[1]
    target = find(("a", col, row))
    nz = []
    for lab, e in exprs:
        if lab not in labs: continue
        sels, advs = set(), set(); walk(e, sels, advs)
        rows = set()
        for s in sels: rows.update(on[s])
        for rr in rows:
            if any((cc, (rr + rot) % n) == (col, row) for cc, rot in advs):
                for _ in range(2):
                    rv.clear()
                    if dval(e, rr, target)[1]:
                        nz.append((lab, rr)); break
    if nz:
        wit += 1
        print("   WITNESS-DEPENDENT zero coefficient:", c, nz[:3])
    else:
        struct += 1
print(f"  coefficient zero for random advice values too (structural don't-care): {struct}; zero only at the honest witness: {wit}")
