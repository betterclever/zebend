"""Facts about the variable-base scalar mul region of a dump that tie proofs/orchard_mul's
theorem to the real circuit.

usage: mulfacts.py DUMP

For the hi and lo halves (gates 8 and 11, "q_mul_2 == 1 checks"): the rows where q_mul_2 is
enabled (the constancy constraints x_p(r) = x_p(r+1), y_p(r) = y_p(r+1) hold on them), the
loop rows they chain (first q_mul_2 row .. last + 1), and whether x_p / y_p on the FIRST
loop row are copy-constrained to the witnessed g_d_old cell (the anchor hypothesis).
"""
import json, sys
from collections import defaultdict
d = json.load(open(sys.argv[1]))
cs, lay = d["cs"], d["layout"]
regions = lay["regions"]
def sels(e, acc):
    if e[0] == "s": acc.add(e[1])
    elif e[0] in ("-", "k"): sels(e[1], acc)
    elif e[0] in ("+", "*"): sels(e[1], acc); sels(e[2], acc)
    return acc
names = {(c[0], c[1]): (regions[c[2]], c[3]) for c in lay["advice"]}
parent = {}
def find(x):
    while parent.get(x, x) != x: x = parent[x]
    return x
for c in lay["copies"]:
    a, b = find((c[0], c[1], c[2])), find((c[3], c[4], c[5]))
    if a != b: parent[a] = b
gd = {col: (col, row) for (col, row), (reg, nm) in names.items() if reg == "witness non-identity point" and nm.startswith("gd_old ::") and col in (0, 1)}
print(f"{d['version']}: g_d_old witnessed at x: a{gd[0][0]}@{gd[0][1]}, y: a{gd[1][0]}@{gd[1][1]}")
for gi, half in ((8, "hi"), (11, "lo")):
    g = cs["gates"][gi]
    assert g["name"] == "q_mul_2 == 1 checks" and g["constraints"][0]["name"] == "x_p_check" and g["constraints"][1]["name"] == "y_p_check"
    s = sels(g["constraints"][0]["poly"], set()).pop()
    rows = sorted(r for s2, r, reg in lay["selectors"] if s2 == s and regions[reg] == "variable-base scalar mul")
    assert rows == list(range(rows[0], rows[-1] + 1))
    first = rows[0]
    links = []
    for col, coord in ((0, "x"), (1, "y")):
        same = find(("a", col, first)) == find(("a", gd[col][0], gd[col][1]))
        links.append(f"{coord}_p(first loop row) ~ g_d_old.{coord}: {'COPY-CONSTRAINED' if same else 'NOT LINKED'}")
        # every loop row's x_p is assigned in the region
        for r in range(first, rows[-1] + 2):
            assert names[(col, r)][0] == "variable-base scalar mul", (col, r)
    print(f"  {half}: q_mul_2 (selector {s}) on rows {first}..{rows[-1]} ({len(rows)} rows), chaining x_p/y_p on loop rows {first}..{rows[-1] + 1}; " + "; ".join(links))
