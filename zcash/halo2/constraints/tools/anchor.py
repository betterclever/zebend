"""Anchoring analysis of an extracted Orchard constraint system.

usage: anchor.py DUMP OUTDIR [--region SUBSTRING]

All checks linearise the circuit's equations at the dump's honest witness (exact partial
derivatives over Fp). "Equations" are every gate polynomial instance on a row where one of
its selectors is enabled, and every lookup input on such a row (a lookup pins its input to
a finite table, so to first order the input is constant). Cells joined by copy constraints
are one variable.

1. PER-REGION (the gadget view). For each region R, in synthesis order:
     inputs(R)    advice cells whose copy class contains a fixed cell, an instance cell the
                  circuit READS (assign_advice_from_instance), or a cell assigned by an
                  EARLIER region. An instance cell that a computed value is only EXPOSED to
                  (constrain_instance) is not an anchor here: a public output must not
                  "explain" a gadget input whose link was lost (rk = [alpha] G + ak with the
                  ak link removed is otherwise invisible); and cells owned by earlier regions
                  that R's gates reach by rotation.
     equations(R) the equations whose selector R enabled.
     unknowns(R)  every other cell those equations touch, and every cell R assigned.
   A cell is FREE in R if it has a non-zero component in some vector of ker(J_R): it can
   move to first order while R's inputs stay fixed and every equation of R still holds.
     free-used    free and appearing in an equation of R: a continuous family of R-valid
                  assignments for fixed inputs. The signature of an unanchored gadget input
                  (pre-NU6.2: the incomplete-addition base x_p, y_p).
     free-unused  free and in no equation of R (stored only: a private input, a value a
                  later region checks, or a don't-care).

2. GLOBAL, DECLARED-ANCHORED. All equations at once; anchors: instance, fixed and the
   declared private witnesses of the Action statement (DECLARED_*). A per-region flag that
   is determined here was free in its region only because a later region constrains it.
   Cells still free here are reported with whether any equation uses them.

3. GLOBAL, FULL. All equations; anchors: instance and fixed only (declared witnesses are
   unknowns too). Its kernel dimension is the local dimension of the set of all valid
   witnesses for fixed public inputs. It has no absolute expected value, but it is the
   right yardstick when comparing two constraint systems (mutation testing, pre- vs
   post-fix): dropping a constraint that relates declared witnesses to each other (e.g.
   pk_d = [ivk] g_d) raises it even though no single gadget changes.

4. INSTANCE BINDING. Instance rows that no copy constraint links to the circuit.

RELAXED mode (relaxed=True, mutate.py --relaxed) additionally drops every finite-domain
equation: lookup inputs, and gate instances that are a non-linear polynomial in a single
linear form of the advice (detected numerically: parallel, unequal gradients at two random
points; e.g. booleanity, 3-bit window range checks, sign^2 = 1). Values that only such
equations pin (bits, words) then count as free, so a missing LINEAR link from them to an
anchor (a running sum's start or end, a copy into a message piece) becomes visible. It is
meant for comparisons (mutation testing), not as an absolute report: in a correct circuit
the bits themselves are free in relaxed mode.

Kernel support is computed exactly w.h.p.: random values for the free (non-pivot)
variables, back-substituted twice.

NOT SEEN (README): finite ambiguity (roots of a boolean or range check, the sign of a
square root, which table row a lookup hits) is an isolated solution, so it looks anchored;
a missing link that leaves only DISCRETE freedom (bits, windows) is invisible to the
Jacobian. Degenerate honest points can produce spurious kernel vectors, so every flag is
triaged by hand, and results are reproduced on several witnesses (seeds).
"""
import json, os, random, sys
from collections import defaultdict
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cslib import P

sys.setrecursionlimit(100000)

# The private witnesses of the Orchard Action statement (protocol spec 4.17.4) that the
# circuit loads as free cells: g_d_old, pk_d_old, v_old, rho_old, psi_old, cm_old, ak, nk,
# g_d_new, pk_d_new, v_new, psi_new, v_net's magnitude and sign, and the 32 Merkle siblings
# ("witness b" in each swap). The scalars alpha, rcv, rcm_old, rcm_new, rivk and the
# position are witnessed as bits / windows (finite domains), which this analysis does not
# treat as free (see NOT SEEN).
DECLARED_REGIONS = {"load private", "witness point", "witness non-identity point"}
DECLARED_SUFFIX = ":: witness b"


def sels_of(e, acc):
    if e[0] == "s":
        acc.add(e[1])
    elif e[0] in ("-", "k"):
        sels_of(e[1], acc)
    elif e[0] in ("+", "*"):
        sels_of(e[1], acc); sels_of(e[2], acc)
    return acc


def prepare(d):
    """Everything that does not depend on which copies / selector enables / lookups exist."""
    cs, lay = d["cs"], d["layout"]
    n = lay["n"]
    ctx = {"d": d, "n": n, "regions": lay["regions"], "version": d["version"]}
    A = {}
    for col, row, reg, name, val, known, order, writes in lay["advice"]:
        A[col * n + row] = (reg, name, int(val, 16), writes)
    F = defaultdict(int)
    for col, row, val, reg, name in lay["fixed"]:
        F[(col, row)] = int(val, 16)
    INST = [[int(v, 16) for v in c] for c in lay["instance"]]
    sel_on = {(s, row): reg for s, row, reg in lay["selectors"]}
    ctx.update(A=A, F=F, INST=INST, sel_on=sel_on)

    def grad(e, r, val=None):
        if val is None:
            val = lambda cell: A.get(cell, (None, None, 0))[2]
        return _grad(e, r, val)

    def _grad(e, r, val):
        grad = lambda e2, r2: _grad(e2, r2, val)
        t = e[0]
        if t == "c":
            return int(e[1], 16), {}
        if t == "s":
            return (1 if (e[1], r) in sel_on else 0), {}
        if t == "f":
            return F[(e[1], (r + e[2]) % n)], {}
        if t == "i":
            rr = (r + e[2]) % n
            col = INST[e[1]]
            return (col[rr] if rr < len(col) else 0), {}
        if t == "a":
            cell = e[1] * n + (r + e[2]) % n
            return val(cell), {cell: 1}
        if t == "-":
            v, g = grad(e[1], r)
            return (-v) % P, {k: (-x) % P for k, x in g.items()}
        if t == "k":
            v, g = grad(e[1], r)
            k = int(e[2], 16)
            return v * k % P, {c: x * k % P for c, x in g.items()}
        va, ga = grad(e[1], r)
        vb, gb = grad(e[2], r)
        if t == "+":
            g = dict(ga)
            for c, x in gb.items():
                g[c] = (g.get(c, 0) + x) % P
            return (va + vb) % P, g
        if t == "*":
            g = {}
            if vb:
                for c, x in ga.items():
                    g[c] = x * vb % P
            if va:
                for c, x in gb.items():
                    g[c] = (g.get(c, 0) + x * va) % P
            return va * vb % P, g
        raise ValueError(t)

    rows_of_sel = defaultdict(list)
    for (s, row) in sel_on:
        rows_of_sel[s].append(row)
    EQ = []   # (owner region, label, row, frozenset of (sel,row) enabling it, lookup idx|None, grad, finite)
    nonzero = 0
    rr = random.Random(5)
    R1, R2 = {}, {}
    def rv(tab):
        return lambda cell: tab.setdefault(cell, rr.randrange(P))

    def finite_domain(e, r):
        # univariate, non-linear in ONE linear form L of the advice: the gradient at two
        # random advice points is parallel (to L) but not equal. Its roots in L are then
        # isolated (booleanity, range checks, sign^2 = 1, ...).
        _, g1 = grad(e, r, rv(R1)); _, g2 = grad(e, r, rv(R2))
        g1 = {c: x for c, x in g1.items() if x}; g2 = {c: x for c, x in g2.items() if x}
        if not g1 or set(g1) != set(g2) or g1 == g2:
            return False
        c0 = next(iter(g1))
        return all(g1[c] * g2[c0] % P == g2[c] * g1[c0] % P for c in g1)

    def add(label, e, lookup):
        nonlocal nonzero
        ss = sels_of(e, set())
        rows = set()
        for s in ss:
            rows.update(rows_of_sel[s])
        if not ss:
            rows = set(range(lay["usable_rows"] if lookup is not None else n))
        for r in sorted(rows):
            v, g = grad(e, r)
            g = {c: x for c, x in g.items() if x}
            if v and lookup is None:
                nonzero += 1
            if not g:
                continue
            en = frozenset((s, r) for s in ss if (s, r) in sel_on)
            regs = [sel_on[k] for k in en if sel_on[k] is not None]
            fin = lookup is not None or finite_domain(e, r)
            EQ.append((min(regs) if regs else -1, label, r, en, lookup, g, fin))

    for gi, gate in enumerate(cs["gates"]):
        for ci, c in enumerate(gate["constraints"]):
            add(f"gate {gi} '{gate['name']}' / '{c['name']}'", c["poly"], None)
    for li, lk in enumerate(cs["lookups"]):
        for ii, inp in enumerate(lk["inputs"]):
            add(f"lookup {li} input {ii}", inp, li)
    ctx["EQ"] = EQ
    ctx["nonzero_gate_values"] = nonzero
    ctx["copies"] = [((c[0], c[1], c[2]), (c[3], c[4], c[5])) for c in lay["copies"]]
    # instance cells the circuit READS (assign_advice_from_instance: the copy is made inside
    # a region). Instance cells a value is EXPOSED to (constrain_instance: made outside any
    # region, after the region that computed the value) are not anchors in the per-region pass.
    ctx["inst_read"] = {k for c in lay["copies"] if c[6] >= 0
                        for k in ((c[0], c[1], c[2]), (c[3], c[4], c[5])) if k[0] == "i"}
    owned = defaultdict(list)
    for cell, (reg, name, v, w) in A.items():
        owned[reg].append(cell)
    ctx["owned"] = owned

    def declared(cell):
        reg, name, v, w = A[cell]
        return ctx["regions"][reg] in DECLARED_REGIONS or name.endswith(DECLARED_SUFFIX)
    ctx["declared"] = {c for c in A if declared(c)}
    ctx["n_instance_rows"] = len(INST[0]) if INST else 0
    return ctx


def kernel(rows, keys, keyf, rnd):
    """Echelon form of `rows` over variables `keys` (ordered by keyf); returns
    (rank, set of variables with a non-zero component in some kernel vector)."""
    order = {v: i for i, v in enumerate(sorted(keys, key=keyf))}
    piv = {}
    for row in rows:
        row = dict(row)
        while row:
            v = min(row, key=order.__getitem__)
            if v in piv:
                k = row[v]
                for u, x in piv[v].items():
                    row[u] = (row.get(u, 0) - k * x) % P
                    if not row[u]:
                        del row[u]
            else:
                inv = pow(row[v], P - 2, P)
                piv[v] = {u: x * inv % P for u, x in row.items()}
                break
    free = [v for v in keys if v not in piv]
    support = set()
    if free:
        for _ in range(2):
            val = {v: rnd.randrange(1, P) for v in free}
            for v in sorted(piv, key=order.__getitem__, reverse=True):
                s = 0
                for u, x in piv[v].items():
                    if u != v:
                        s += x * val[u]
                val[v] = (-s) % P
            support |= {v for v, x in val.items() if x}
    return len(piv), support


def analyze(ctx, drop_copies=frozenset(), drop_enables=frozenset(), drop_lookups=frozenset(),
            only_regions=None, passes=("region", "declared", "full"), relaxed=False):
    """Run the passes on the dump minus the given copies (indices), selector enables
    ((sel,row) pairs) and lookups (indices). An equation is removed when every selector
    enable that activates it is dropped."""
    n, A, regions = ctx["n"], ctx["A"], ctx["regions"]
    rnd = random.Random(7)
    parent = {}

    def find(x):
        while parent.get(x, x) != x:
            parent[x] = parent.get(parent[x], parent[x])
            x = parent[x]
        return x
    members = defaultdict(list)
    copies = [c for i, c in enumerate(ctx["copies"]) if i not in drop_copies]
    for l, r in copies:
        a, b = find(l), find(r)
        if a != b:
            parent[a] = b
    for l, r in copies:
        members[find(l)].append(l)
        members[find(r)].append(r)
    origin = {}
    for root, ms in members.items():
        o = None
        for (k, col, row) in set(ms):
            if k == "f" or (k == "i" and (k, col, row) in ctx["inst_read"]):
                o = -1
                break
            reg = A.get(col * n + row, (None,))[0]
            if reg is not None:
                o = reg if o is None else min(o, reg)
        origin[root] = o

    def cls(cell):
        col, row = divmod(cell, n)
        return find(("a", col, row))

    def var(cell):
        root = cls(cell)
        return root if root in members else ("solo", cell)

    EQ = [e for e in ctx["EQ"] if not (e[3] and e[3] <= drop_enables) and e[4] not in drop_lookups
          and not (relaxed and e[6])]
    out = {}

    def label(cell):
        col, row = divmod(cell, n)
        reg, name, v, w = A.get(cell, (None, "<UNASSIGNED>", 0, 0))
        return {"col": col, "row": row, "owner": regions[reg] if reg is not None else None,
                "owner_idx": reg, "name": name}

    def okey_of(rep):
        def k(v):
            c = min(rep[v])
            reg = A.get(c, (10 ** 9,))[0]
            col, row = divmod(c, n)
            return (reg if reg is not None else 10 ** 9, row, col)
        return k

    if "region" in passes:
        by_region = defaultdict(list)
        for e in EQ:
            by_region[e[0]].append(e)
        res = []
        for R in range(len(regions)):
            if only_regions is not None and R not in only_regions:
                continue

            def is_input(cell):
                reg = A.get(cell, (None,))[0]
                if reg is not None and reg < R:
                    return True
                root = cls(cell)
                o = origin.get(root) if root in members else None
                return o is not None and o < R
            rep, rows, used, unassigned = defaultdict(set), [], set(), set()
            for e in by_region.get(R, []):
                row = {}
                for cell, x in e[5].items():
                    if is_input(cell):
                        continue
                    if cell not in A:
                        unassigned.add(cell)
                    v = var(cell)
                    rep[v].add(cell)
                    used.add(v)
                    row[v] = (row.get(v, 0) + x) % P
                row = {k: x for k, x in row.items() if x}
                if row:
                    rows.append(row)
            for cell in ctx["owned"].get(R, []):
                if not is_input(cell):
                    rep[var(cell)].add(cell)
            rank, sup = kernel(rows, list(rep), okey_of(rep), rnd)
            flags = []
            for v in sorted(sup, key=okey_of(rep)):
                later = set()
                if v in members:
                    for (k, col, row) in members[v]:
                        reg = A.get(col * n + row, (None,))[0] if k == "a" else None
                        if reg is not None and reg > R:
                            later.add(regions[reg])
                flags.append({"kind": "free-used" if v in used else "free-unused",
                              "cells": [label(c) for c in sorted(rep[v])],
                              "copied_to_later_regions": sorted(later)})
            res.append({"idx": R, "name": regions[R], "equations": len(rows), "unknowns": len(rep),
                        "rank": rank, "free": len(sup),
                        "free_used": sum(1 for f in flags if f["kind"] == "free-used"),
                        "unassigned_cells_in_equations": [label(c) for c in sorted(unassigned)],
                        "flags": flags})
        out["regions"] = res

    for mode in ("declared", "full"):
        if mode not in passes:
            continue
        anchored = set()
        for root, ms in members.items():
            for (k, col, row) in ms:
                if k in ("f", "i") or (mode == "declared" and k == "a" and col * n + row in ctx["declared"]):
                    anchored.add(root)

        def param(cell):
            if mode == "declared" and cell in ctx["declared"]:
                return True
            return cls(cell) in anchored
        rep, rows, used = defaultdict(set), [], set()
        for e in EQ:
            row = {}
            for cell, x in e[5].items():
                if param(cell):
                    continue
                v = var(cell)
                rep[v].add(cell)
                used.add(v)
                row[v] = (row.get(v, 0) + x) % P
            row = {k: x for k, x in row.items() if x}
            if row:
                rows.append(row)
        for cell in A:
            if not param(cell):
                rep[var(cell)].add(cell)
        rank, sup = kernel(rows, list(rep), okey_of(rep), rnd)
        cells = set()
        for v in sup:
            cells |= {(c, v in used) for c in rep[v]}
        out[mode] = {"unknowns": len(rep), "rank": rank, "kernel_dim": len(rep) - rank,
                     "free_cells": sorted(cells), "free_used_cells": sorted(c for c, u in cells if u)}

    bound = set()
    for l, r in copies:
        for k in (l, r):
            if k[0] == "i":
                bound.add(k[2])
    out["unbound_instance_rows"] = [r for r in range(ctx["n_instance_rows"]) if r not in bound]
    out["_label"] = label
    return out


def main(path, outdir, only=None):
    d = json.load(open(path))
    ctx = prepare(d)
    regions = ctx["regions"]
    only_regions = {i for i, r in enumerate(regions) if only in r} if only else None
    res = analyze(ctx, only_regions=only_regions)
    label = res.pop("_label")
    n = ctx["n"]
    gfree = {c for c, u in res["declared"]["free_cells"]}
    for r in res["regions"]:
        for fl in r["flags"]:
            fl["globally_free"] = any(c["col"] * n + c["row"] in gfree for c in fl["cells"])
        r["free_used_globally_free"] = sum(1 for fl in r["flags"] if fl["kind"] == "free-used" and fl["globally_free"])
    report = {"dump": os.path.basename(path), "version": d["version"],
              "honest_witness_nonzero_gate_values": ctx["nonzero_gate_values"],
              "regions": res["regions"],
              "global": {"declared_witness_cells": len(ctx["declared"]),
                         "unknowns": res["declared"]["unknowns"], "rank": res["declared"]["rank"],
                         "kernel_dim": res["declared"]["kernel_dim"],
                         "free_cells": [dict(label(c), used=u) for c, u in res["declared"]["free_cells"]]},
              "full": {k: res["full"][k] for k in ("unknowns", "rank", "kernel_dim")},
              "unbound_instance_rows": res["unbound_instance_rows"]}
    os.makedirs(outdir, exist_ok=True)
    tag = d["version"]
    with open(os.path.join(outdir, f"anchor_{tag}.json"), "w") as f:
        json.dump(report, f, indent=1)
    tot_used = sum(r["free_used"] for r in report["regions"])
    tot_free = sum(r["free"] for r in report["regions"])
    G = report["global"]
    lines = [f"{tag}: {len(report['regions'])} regions; honest witness: {ctx['nonzero_gate_values']} non-zero gate values;"
             f" per-region free cells {tot_free} (free-used {tot_used});"
             f" declared-anchored global pass ({G['declared_witness_cells']} declared-witness cells):"
             f" unknowns {G['unknowns']} rank {G['rank']} kernel dim {G['kernel_dim']},"
             f" free cells {len(G['free_cells'])} (in some equation: {sum(1 for c in G['free_cells'] if c['used'])});"
             f" full pass: unknowns {report['full']['unknowns']} kernel dim {report['full']['kernel_dim']};"
             f" unbound instance rows {report['unbound_instance_rows']}"]
    for r in report["regions"]:
        if r["free_used"] or r["unassigned_cells_in_equations"]:
            lines.append(f"  [{r['idx']}] {r['name']}: eqs {r['equations']} unknowns {r['unknowns']} rank {r['rank']}"
                         f" kernel dim {r['unknowns'] - r['rank']} free-used {r['free_used']}"
                         f" unassigned-in-eqs {len(r['unassigned_cells_in_equations'])}")
            for fl in r["flags"]:
                if fl["kind"] == "free-used":
                    c = fl["cells"][0]
                    lines.append(f"      {c['name']}  (a{c['col']}@{c['row']}, {len(fl['cells'])} cell(s))"
                                 f"{'  GLOBALLY FREE' if fl['globally_free'] else ''}")
    with open(os.path.join(outdir, f"anchor_{tag}.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print(lines[0])
    return report


if __name__ == "__main__":
    only = None
    if "--region" in sys.argv:
        i = sys.argv.index("--region")
        only = sys.argv[i + 1]
        del sys.argv[i:i + 2]
    main(sys.argv[1], sys.argv[2], only)
