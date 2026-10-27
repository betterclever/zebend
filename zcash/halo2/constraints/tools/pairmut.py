"""Double mutants: delete BOTH parallel copies (hi and lo half) that anchor x_p, or y_p, or
all four, in a fixed (NU6.2+) dump, and report whether the checker flags it.
usage: pairmut.py DUMP"""
import json, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import anchor
d = json.load(open(sys.argv[1]))
ctx = anchor.prepare(d)
n = ctx["n"]; A = ctx["A"]
anch = {"x": [], "y": []}
for i, (l, r) in enumerate(ctx["copies"]):
    for k in (l, r):
        if k[0] == "a" and A.get(k[1] * n + k[2], (0, ""))[1].endswith("anchor x_p to base"): anch["x"].append(i)
        if k[0] == "a" and A.get(k[1] * n + k[2], (0, ""))[1].endswith("anchor y_p to base"): anch["y"].append(i)
base = anchor.analyze(ctx)
R = [i for i, r in enumerate(ctx["regions"]) if r == "variable-base scalar mul"][0]
def fu(res):
    return {(c["col"], c["row"]) for r in res["regions"] if r["idx"] == R for f in r["flags"] if f["kind"] == "free-used" for c in f["cells"]}
b = fu(base)
for label, drop in (("x_p anchors (hi+lo)", anch["x"]), ("y_p anchors (hi+lo)", anch["y"]), ("all four anchors", anch["x"] + anch["y"])):
    res = anchor.analyze(ctx, drop_copies=frozenset(drop))
    reg = [r for r in res["regions"] if r["idx"] == R][0]
    new = fu(res) - b
    print(f"{d['version']}: drop {label} {sorted(drop)}: mul region kernel dim {reg['unknowns'] - reg['rank']}, new free-used cells {len(new)}"
          f" (x_p/y_p among them: {sum(1 for c, r in new if c in (0, 1))}) -> {'FLAGGED' if new else 'not flagged'}")
