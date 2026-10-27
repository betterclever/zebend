"""Summarise anchor_*.json: per region name, number of regions, kernel dimension
(unknowns - rank), free-used cells, unassigned cells in equations; and the free-cell names
of regions matching --region."""
import json, sys
from collections import Counter, defaultdict
r = json.load(open(sys.argv[1]))
only = sys.argv[2] if len(sys.argv) > 2 else None
agg = defaultdict(lambda: [0, 0, 0, 0])
for g in r["regions"]:
    a = agg[g["name"]]
    a[0] += 1; a[1] += g["unknowns"] - g["rank"]; a[2] += g["free_used"]; a[3] += len(g["unassigned_cells_in_equations"])
print(f"{r['version']}: regions={len(r['regions'])} total kernel dim={sum(v[1] for v in agg.values())} free-used cells={sum(v[2] for v in agg.values())} unassigned-in-eqs={sum(v[3] for v in agg.values())}")
print("  [regions, kernel dim, free-used cells, unassigned cells in eqs] region name")
for k, v in agg.items():
    if v[1] or v[2] or v[3]:
        print("  ", v, k)
if only:
    for g in r["regions"]:
        if only in g["name"]:
            c = Counter(f["cells"][0]["name"].split("::")[-1].strip() for f in g["flags"] if f["kind"] == "free-used")
            print(f"  [{g['idx']}] {g['name']}: eqs {g['equations']} unknowns {g['unknowns']} rank {g['rank']} kernel dim {g['unknowns']-g['rank']} free-used by name: {dict(c)}")
