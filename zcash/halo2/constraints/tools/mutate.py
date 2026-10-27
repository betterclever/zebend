"""Mutation testing of the anchoring checker.

usage: mutate.py DUMP OUTDIR [--workers N] [--limit K] [--relaxed]

--relaxed runs the checker in anchor.py's RELAXED mode (finite-domain equations dropped),
for baseline and mutants alike.

Mutants (each removes ONE thing from the extracted constraint system):
  copy:<i>       copy constraint i deleted                     (every copy)
  enable:<s>@<r> selector s's enable on row r deleted           (every enable)
  lookup:<l>     lookup argument l deleted                      (every lookup)

For each mutant the checker is re-run and the mutant counts as FLAGGED if, compared with
the unmutated dump, any of these appear:
  R  a new free-used cell in the per-region pass (regions touched by the mutation)
  D  a larger kernel dimension in the per-region pass for a touched region (catches extra
     freedom of cells that were already free, e.g. a witnessed point losing its on-curve gate)
  G  a new free cell used in some equation in the declared-anchored global pass
  F  a larger kernel, or a new free cell used in some equation, in the full pass
  I  a new unbound instance row
Writes OUTDIR/mutants_<tag>.jsonl (one line per mutant) and OUTDIR/mutation_<tag>.txt
(recall, and every surviving mutant described by its cells' region and name).
"""
import json, multiprocessing as mp, os, sys, time
from collections import defaultdict
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import anchor

CTX = None
BASE = None
CLASS_REGIONS = None


def region_free_used(res):
    out = {}
    for r in res["regions"]:
        s = set()
        for fl in r["flags"]:
            if fl["kind"] == "free-used":
                s |= {(c["col"], c["row"]) for c in fl["cells"]}
        out[r["idx"]] = s
    return out


RELAXED = False


def setup(path):
    global CTX, BASE, CLASS_REGIONS
    CTX = anchor.prepare(json.load(open(path)))
    res = anchor.analyze(CTX, relaxed=RELAXED)
    BASE = {"region": region_free_used(res),
            "dim": {r["idx"]: r["unknowns"] - r["rank"] for r in res["regions"]},
            "declared": set(res["declared"]["free_used_cells"]),
            "full_dim": res["full"]["kernel_dim"], "full": set(res["full"]["free_used_cells"]),
            "unbound": set(res["unbound_instance_rows"])}
    # regions owning a member of each copy's class (the regions whose inputs it can change)
    n, A = CTX["n"], CTX["A"]
    parent = {}

    def find(x):
        while parent.get(x, x) != x:
            x = parent[x]
        return x
    for l, r in CTX["copies"]:
        a, b = find(l), find(r)
        if a != b:
            parent[a] = b
    regs = defaultdict(set)
    for l, r in CTX["copies"]:
        for k in (l, r):
            if k[0] == "a":
                reg = A.get(k[1] * n + k[2], (None,))[0]
                if reg is not None:
                    regs[find(k)].add(reg)
    CLASS_REGIONS = [regs[find(l)] for l, r in CTX["copies"]]


def run(m):
    kind, arg = m
    kw, regions = {}, None
    if kind == "copy":
        kw["drop_copies"] = frozenset([arg])
        regions = set(CLASS_REGIONS[arg])
    elif kind == "enable":
        kw["drop_enables"] = frozenset([arg])
        reg = CTX["sel_on"].get(arg)
        regions = {reg} if reg is not None else set()
    else:
        kw["drop_lookups"] = frozenset([arg])
    res = anchor.analyze(CTX, only_regions=regions, relaxed=RELAXED, **kw)
    why = []
    new_r = []
    fu = region_free_used(res)
    for R, s in fu.items():
        extra = s - BASE["region"].get(R, set())
        if extra:
            new_r.append((R, sorted(extra)[:3], len(extra)))
    if new_r:
        why.append("R")
    if any(r["unknowns"] - r["rank"] > BASE["dim"].get(r["idx"], 0) for r in res["regions"]):
        why.append("D")
    if set(res["declared"]["free_used_cells"]) - BASE["declared"]:
        why.append("G")
    if res["full"]["kernel_dim"] > BASE["full_dim"] or set(res["full"]["free_used_cells"]) - BASE["full"]:
        why.append("F")
    if set(res["unbound_instance_rows"]) - BASE["unbound"]:
        why.append("I")
    return {"mutant": f"{kind}:{arg}", "flagged": bool(why), "why": why,
            "new_region_flags": [(CTX["regions"][R], cells, k) for R, cells, k in new_r][:5],
            "full_dim": res["full"]["kernel_dim"]}


def describe(m):
    n, A, regions = CTX["n"], CTX["A"], CTX["regions"]

    def cell(k):
        if k[0] != "a":
            return f"{k[0]}{k[1]}@{k[2]}"
        reg, name, v, w = A.get(k[1] * n + k[2], (None, "<unassigned>", 0, 0))
        return f"a{k[1]}@{k[2]} [{regions[reg] if reg is not None else '-'}] {name}"
    kind, arg = m
    if kind == "copy":
        l, r = CTX["copies"][arg]
        return f"copy {cell(l)}  <->  {cell(r)}"
    if kind == "enable":
        s, row = arg
        reg = CTX["sel_on"].get(arg)
        gates = sorted({e[1].split(" / ")[0] for e in CTX["EQ"] if (s, row) in e[3]})
        return f"enable selector {s} row {row} [{regions[reg] if reg is not None else '-'}] gates {gates}"
    return f"lookup {arg}"


def main(path, outdir, workers=8, limit=None):
    t0 = time.time()
    setup(path)
    tag = CTX["version"] + ("_relaxed" if RELAXED else "")
    muts = [("copy", i) for i in range(len(CTX["copies"]))]
    muts += [("enable", k) for k in sorted(CTX["sel_on"])]
    muts += [("lookup", i) for i in range(len(CTX["d"]["cs"]["lookups"]))]
    if limit:
        muts = muts[:limit]
    os.makedirs(outdir, exist_ok=True)
    mp.set_start_method("fork", force=True)
    with mp.Pool(workers) as pool:
        results = pool.map(run, muts, chunksize=8)
    with open(os.path.join(outdir, f"mutants_{tag}.jsonl"), "w") as f:
        for r in results:
            f.write(json.dumps(r) + "\n")
    by = defaultdict(lambda: [0, 0])
    for m, r in zip(muts, results):
        by[m[0]][0] += 1
        by[m[0]][1] += r["flagged"]
    lines = [f"{tag}: {len(muts)} mutants in {time.time() - t0:.0f} s; baseline full-pass kernel dim {BASE['full_dim']}"]
    tot = sum(v[0] for v in by.values()); fl = sum(v[1] for v in by.values())
    lines.append(f"  recall overall: {fl}/{tot} flagged ({100 * fl / tot:.1f}%)")
    for k, (a, b) in by.items():
        lines.append(f"  {k}: {b}/{a} flagged")
    crit = defaultdict(int)
    for r in results:
        for w in r["why"]:
            crit[w] += 1
    lines.append(f"  flagged by criterion (a mutant can hit several): {dict(crit)}")
    lines.append("  SURVIVORS (not flagged):")
    for m, r in zip(muts, results):
        if not r["flagged"]:
            lines.append("    " + describe(m))
    txt = "\n".join(lines) + "\n"
    with open(os.path.join(outdir, f"mutation_{tag}.txt"), "w") as f:
        f.write(txt)
    print("\n".join(lines[:6]))


if __name__ == "__main__":
    args = sys.argv[1:]
    w = 8; lim = None
    if "--relaxed" in args:
        args.remove("--relaxed"); RELAXED = True
    if "--workers" in args:
        i = args.index("--workers"); w = int(args[i + 1]); del args[i:i + 2]
    if "--limit" in args:
        i = args.index("--limit"); lim = int(args[i + 1]); del args[i:i + 2]
    main(args[0], args[1], w, lim)
