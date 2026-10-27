"""Cross-check the extracted constraint systems.

1. The VK's (selector-compressed) gates of each dump against zcash/halo2/gen/orchard_cs.bend
   (the generated Orchard gates Zebend's verifier uses): every polynomial evaluated at
   random query values, in VK query order.
2. Gates / lookups / queries / permutation columns identical across the given dumps?
3. Copy-constraint differences between dumps (as sets of unordered cell pairs).

usage: crosscheck.py DUMP [DUMP ...]
"""
import os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cslib import P, load, ev
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "proofs", "orchard"))
import gates as G  # parses zcash/halo2/gen/orchard_cs.bend


def gen_eval(e, a, f, i):
    return G.evaluate(e, a, f, i)


def main(paths):
    dumps = [load(p) for p in paths]
    gen = G.parse()
    rnd = random.Random(1)
    for p, d in zip(paths, dumps):
        vcs = d["vk_cs"]
        na, nf, ni = len(vcs["advice_queries"]), len(vcs["fixed_queries"]), len(vcs["instance_queries"])
        ok = bad = 0
        missing = 0
        for trial in range(3):
            a = [rnd.randrange(P) for _ in range(na)]
            f = [rnd.randrange(P) for _ in range(nf)]
            i = [rnd.randrange(P) for _ in range(ni)]
            for gi, g in enumerate(vcs["gates"]):
                for pi, c in enumerate(g["constraints"]):
                    name = f"gate_{gi}_{pi}"
                    if name not in gen:
                        missing += 1
                        continue
                    x = ev(c["poly"], lambda s: 1 / 0, lambda col, r, q: f[q], lambda col, r, q: a[q], lambda col, r, q: i[q])
                    y = gen_eval(gen[name], a, f, i)
                    ok += x == y
                    bad += x != y
        npoly = sum(len(g["constraints"]) for g in vcs["gates"])
        print(f"{os.path.basename(p)}: mock_ok={d['mock_ok']} vk_match={d['vk_match']}; "
              f"{len(vcs['gates'])} gates / {npoly} polys in the VK; vs orchard_cs.bend at 3 random points: "
              f"{ok} equal, {bad} differ, {missing} absent (generated file has {len(gen)} polys)")
    base = dumps[0]
    for p, d in zip(paths[1:], dumps[1:]):
        for key in ("gates", "lookups", "advice_queries", "fixed_queries", "permutation_columns", "constants_columns"):
            same_u = base["cs"][key] == d["cs"][key]
            same_c = base["vk_cs"][key] == d["vk_cs"][key]
            print(f"  {os.path.basename(paths[0])} vs {os.path.basename(p)}: {key}: uncompressed {'same' if same_u else 'DIFFERENT'}, VK {'same' if same_c else 'DIFFERENT'}")

    def copyset(d):
        s = set()
        for c in d["layout"]["copies"]:
            l, r = (c[0], c[1], c[2]), (c[3], c[4], c[5])
            s.add(frozenset([l, r]))
        return s
    names = lambda d: {(c[0], c[1]): (d["layout"]["regions"][c[2]] if c[2] >= 0 else "-", c[3]) for c in d["layout"]["advice"]}
    for p, d in zip(paths[1:], dumps[1:]):
        a, b = copyset(base), copyset(d)
        print(f"  copies only in {os.path.basename(p)}: {len(b - a)}; only in {os.path.basename(paths[0])}: {len(a - b)}")
        nm = names(d)
        for pair in sorted(b - a, key=lambda s: sorted(s)):
            desc = []
            for (k, col, row) in sorted(pair):
                desc.append(f"{k}{col}@{row} " + (repr(nm.get((col, row))) if k == "a" else ""))
            print("     ", " <-> ".join(desc))


if __name__ == "__main__":
    main(sys.argv[1:])
