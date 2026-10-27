"""Group the surviving mutants of mutate.py by (mutation kind, region names involved, gate).
usage: survivors.py DUMP MUTANTS.jsonl"""
import json, sys, re
from collections import Counter
sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
d = json.load(open(sys.argv[1]))
lay = d["layout"]; R = lay["regions"]; n = lay["n"]
owner = {(c[0], c[1]): R[c[2]] for c in lay["advice"]}
copies = lay["copies"]
selreg = {(s, r): R[g] if g >= 0 else "-" for s, r, g in lay["selectors"]}
def selgates(s):
    out = []
    def walk(e):
        if e[0] == "s": return e[1] == s
        if e[0] in ("-", "k"): return walk(e[1])
        if e[0] in ("+", "*"): return walk(e[1]) or walk(e[2])
        return False
    for g in d["cs"]["gates"]:
        if any(walk(c["poly"]) for c in g["constraints"]): out.append(g["name"])
    for i, l in enumerate(d["cs"]["lookups"]):
        if any(walk(e) for e in l["inputs"]): out.append(f"lookup {i}")
    return out
sg = {}
tot = Counter(); surv = Counter()
for line in open(sys.argv[2]):
    m = json.loads(line)
    kind, arg = m["mutant"].split(":", 1)
    if kind == "copy":
        c = copies[int(arg)]
        def nm(k, col, row):
            return owner.get((col, row), "-") if k == "a" else {"f": "FIXED/constant", "i": "INSTANCE"}[k]
        key = ("copy", " <-> ".join(sorted([nm(c[0], c[1], c[2]), nm(c[3], c[4], c[5])])))
    elif kind == "enable":
        s, r = map(int, re.findall(r"\d+", arg))
        if s not in sg: sg[s] = selgates(s)
        key = ("enable", f"{selreg.get((s, r), '-')} :: {', '.join(sg[s])}")
    else:
        key = ("lookup", arg)
    tot[key] += 1
    if not m["flagged"]: surv[key] += 1
print(f"{sum(surv.values())} survivors of {sum(tot.values())}")
for k, v in sorted(tot.items(), key=lambda kv: -surv[kv[0]]):
    if surv[k]: print(f"  {surv[k]:5d}/{v:<5d} {k[0]:6s} {k[1][:150]}")

# ---- classification of surviving copy mutants
# self-copy: both endpoints are the same cell (a no-op constraint; deleting it changes nothing)
# parallel: the same two cells are joined by another copy too, or both already lie in one class
#           without this copy (redundant)
import collections
parent = {}
def find(x):
    while parent.get(x, x) != x: x = parent[x]
    return x
def classes_without(skip):
    parent.clear()
    for i, c in enumerate(copies):
        if i == skip: continue
        a, b = find((c[0], c[1], c[2])), find((c[3], c[4], c[5]))
        if a != b: parent[a] = b
kinds = Counter()
surv_ids = []
for line in open(sys.argv[2]):
    m = json.loads(line)
    k, a = m["mutant"].split(":", 1)
    if k == "copy" and not m["flagged"]:
        surv_ids.append(int(a))
# redundancy test: is the pair still in one class without this copy? (one union-find per copy is
# slow for thousands; group by class instead)
parent.clear()
edges = collections.defaultdict(list)
for i, c in enumerate(copies):
    l, r = (c[0], c[1], c[2]), (c[3], c[4], c[5])
    edges[l].append((r, i)); edges[r].append((l, i))
def connected_without(l, r, skip):
    seen = {l}; st = [l]
    while st:
        x = st.pop()
        if x == r: return True
        for y, i in edges[x]:
            if i != skip and y not in seen:
                seen.add(y); st.append(y)
    return False
for i in surv_ids:
    c = copies[i]
    l, r = (c[0], c[1], c[2]), (c[3], c[4], c[5])
    if l == r: kinds["self-copy (no-op)"] += 1
    elif connected_without(l, r, i): kinds["redundant (cells still in one copy class)"] += 1
    else: kinds["non-redundant (a real link the checker does not see)"] += 1
print("surviving copy mutants:", dict(kinds))
