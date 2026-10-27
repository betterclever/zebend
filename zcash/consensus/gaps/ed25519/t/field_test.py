#!/usr/bin/env python3
"""field_test.py gen FILE N | check FILE OUT: Fp / Fl arithmetic of fp.bend / fl.bend vs Python
integers on edge values (all pairs) plus N random pairs of raw 256-bit inputs (not reduced)."""
import random, struct, sys

P = 2**255 - 19
L = 2**252 + 27742317777372353535851937790883648493
R = 2**256
EDGES = [0, 1, 2, 3, 19, P - 1, P - 2, P, P + 1, P + 18, 2 * P - 1, 2**255 - 1, 2**255, 2**256 - 1,
         L - 1, L, L + 1, 2**252, 2**253 - 1, R % P, R * R % P, (P - 1) // 2, (P + 1) // 2,
         2**64 - 1, 2**64, 2**128, 2**192 - 1, 2**63 - 1, (2**63 - 1) << 192, 15 * L + 7]


def pairs(n):
    rnd = random.Random(12345)
    ps = [(a, b) for a in EDGES for b in EDGES]
    for _ in range(n):
        kind = rnd.randrange(4)
        a = rnd.getrandbits(256) if kind else rnd.randrange(P)
        b = rnd.getrandbits(256) if kind != 1 else rnd.randrange(P)
        ps.append((a, b))
    return ps


def le(x):
    return x.to_bytes(32, "little").hex()


def expect(a, b):
    am, bm = a % P, b % P
    inv = pow(am, P - 2, P)
    return " ".join([le(am), le(am * bm % P), le(am * am % P), le((am + bm) % P), le((am - bm) % P),
                     le(inv), le(pow(am, (P - 5) // 8, P)), str(am & 1), str(int(a < P)),
                     le(a % L), le(a * b % L), le((a + b) % L), str(int(a < L))])


if sys.argv[1] == "gen":
    ps = pairs(int(sys.argv[3]))
    with open(sys.argv[2], "wb") as f:
        f.write(struct.pack("<I", len(ps)))
        for a, b in ps:
            f.write(a.to_bytes(32, "little") + b.to_bytes(32, "little"))
    print(f"{len(ps)} pairs")
else:
    data = open(sys.argv[2], "rb").read()
    n = struct.unpack("<I", data[:4])[0]
    ps = [(int.from_bytes(data[4 + 64 * i:36 + 64 * i], "little"), int.from_bytes(data[36 + 64 * i:68 + 64 * i], "little")) for i in range(n)]
    got = [l.strip() for l in open(sys.argv[3]) if l.strip()]
    assert len(got) == n, (len(got), n)
    bad = 0
    for i, ((a, b), g) in enumerate(zip(ps, got)):
        e = expect(a, b)
        if e != g:
            bad += 1
            if bad <= 5:
                names = "fp fp_mul fp_sqr fp_add fp_sub fp_inv fp_p58 lowbit lt_p fl fl_mul fl_add lt_l".split()
                diffs = [nm for nm, x, y in zip(names, e.split(), g.split()) if x != y]
                print(f"pair {i}: a={hex(a)} b={hex(b)} differ in {diffs}")
    print(f"{n} pairs x 13 results: {n - bad} lines identical, {bad} mismatching")
    sys.exit(1 if bad else 0)
