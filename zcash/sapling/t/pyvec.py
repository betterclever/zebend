#!/usr/bin/env python3
"""Quick self-check of the Bend Jubjub layer against the pure-Python reference (jj.py).
NOT the oracle: the Rust vectors (vectors.py) are what "tested" means. This only catches
bugs early.   python3 pyvec.py OUTDIR   (then run vec_main on the files; see vectors.py)"""
import random, sys, pathlib, subprocess
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "jubjub"))
import jj

Q, RJ = jj.Q, jj.R_J
rnd = random.Random(7)
b32 = lambda x: x.to_bytes(32, "little")
h = lambda x: b32(x).hex()


def run(op, recs, expect):
    d = pathlib.Path(__file__).resolve().parent
    f = d / f"py_{op}.bin"
    f.write_bytes(b"".join(recs))
    out = subprocess.run([str(d / "vec_main"), op, str(f), str(len(expect))], capture_output=True, text=True).stdout.split("\n")
    bad = sum(1 for a, b in zip(out, expect) if a.strip() != b)
    print(f"{op}: {len(expect) - bad}/{len(expect)} match")
    for a, b in list((a, b) for a, b in zip(out, expect) if a.strip() != b)[:3]:
        print("  bend:", a, "\n  want:", b)


def fr():
    recs, exp = [], []
    vals = [0, 1, 2, Q - 1, Q - 2, 5] + [rnd.randrange(Q) for _ in range(300)]
    for a in vals:
        b = rnd.randrange(Q)
        s = jj.sqrt(a)
        sq = "none" if s is None else None
        if s is not None:
            s2 = Q - s
            sq = (s, s2)
        recs.append(b32(a) + b32(b))
        inv = pow(a, -1, Q) if a else 0
        exp.append((a, b, sq, inv))
    return recs, exp


def main():
    # fr: sqrt sign is implementation-defined; accept either root.
    recs, exp = fr()
    d = pathlib.Path(__file__).resolve().parent
    f = d / "py_fr.bin"; f.write_bytes(b"".join(recs))
    out = subprocess.run([str(d / "vec_main"), "fr", str(f), str(len(exp))], capture_output=True, text=True).stdout.split("\n")
    ok = 0
    for line, (a, b, sq, inv) in zip(out, exp):
        p = line.split()
        want = [h((a + b) % Q), h((a - b) % Q), h(a * b % Q), h(a * a % Q), h(inv)]
        good = p[:5] == want and ((sq == "none" and p[5] == "none") or (sq != "none" and p[5] in (h(sq[0]), h(sq[1]))))
        ok += good
        if not good and ok < 3:
            print("fr mismatch", line, want, sq)
    print(f"fr: {ok}/{len(exp)} match")
    # fs: from_wide
    recs, expect = [], []
    for _ in range(300):
        x = rnd.getrandbits(512)
        recs.append(x.to_bytes(64, "little")); expect.append(h(x % RJ))
    run("fs", recs, expect)
    # points
    g = jj.gens()
    pts = [g[k] for k in g] + [jj.mul(rnd.randrange(1, RJ), g["G_SPENDAUTH"]) for _ in range(50)]
    # dec: encodings of points, random strings, non-canonical
    recs, expect = [], []
    for p in pts:
        recs.append(jj.encode(p)); expect.append(jj.encode(p).hex())
    for _ in range(200):
        x = rnd.getrandbits(256)
        p = jj.decode(b32(x))
        recs.append(b32(x)); expect.append("none" if p is None else jj.encode(p).hex())
    for x in [Q | (1 << 255), Q + 5, 1 | (1 << 255), 1, Q - 1, (Q - 1) | (1 << 255)]:  # v=1,u=0 sign 1: ZIP 216 reject
        p = jj.decode(b32(x))
        recs.append(b32(x)); expect.append("none" if p is None else jj.encode(p).hex())
    run("dec", recs, expect)
    # add / double / cofactor; include small-order points (0,-1) and (0,1)
    recs, expect = [], []
    small = [(0, 1), (0, Q - 1)]
    for p in pts[:40] + small:
        q = pts[rnd.randrange(len(pts))]
        p8 = jj.mul(8, p)
        recs.append(jj.encode(p) + jj.encode(q))
        expect.append(" ".join([jj.encode(jj.add(p, q)).hex(), jj.encode(jj.add(p, p)).hex(), jj.encode(p8).hex(), "1" if p8 == jj.ID else "0"]))
    run("add", recs, expect)
    recs, expect = [], []
    for p in pts[:40]:
        k = rnd.getrandbits(256)
        recs.append(jj.encode(p) + b32(k)); expect.append(jj.encode(jj.mul(k, p)).hex())
    run("mul", recs, expect)
    # merkle hash
    recs, expect = [], []
    e = jj.empties()
    for l in range(32):
        recs.append(b32(l) + b32(e[l]) + b32(e[l])); expect.append(h(e[l + 1]))
    for _ in range(40):
        l, a, b = rnd.randrange(32), rnd.randrange(Q), rnd.randrange(Q)
        recs.append(b32(l) + b32(a) + b32(b)); expect.append(h(jj.merkle_hash(l, a, b)))
    run("mh", recs, expect)


main()
