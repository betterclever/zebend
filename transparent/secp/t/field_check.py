#!/usr/bin/env python3
"""Field / scalar arithmetic of fe.bend, sc.bend, ec.bend vs exact Python integers.
  python3 field_check.py N   (random + edge values; runs ./secp_t on modes 1 and 2)"""
import os, random, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "../../data/t")
P = 2**256 - 2**32 - 977
N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
n = int(sys.argv[1]) if len(sys.argv) > 1 else 1000
random.seed(7)

def edges(m):
    e = [0, 1, 2, 3, m - 1, m - 2, (m - 1) // 2, (m + 1) // 2, 2**32 - 1, 2**32, 2**64 - 1, 2**64, 2**128,
         2**255, m - 2**32, 2**224, 977, 2**32 + 977, m - 977]
    return [x % m for x in e]

def vals(m, k):
    out = []
    E = edges(m)
    for a in E:
        for b in E:
            out.append((a, b))
    while len(out) < k:
        kind = random.random()
        a = random.randrange(m) if kind < 0.8 else random.choice(E) ^ random.getrandbits(8)
        b = random.randrange(m)
        out.append((a % m, b % m))
    return out

def run(mode, pairs):
    path = f"{DATA}/field_{mode}.bin"
    with open(path, "wb") as f:
        f.write(bytes([mode]))
        for a, b in pairs:
            f.write(a.to_bytes(32, "big") + b.to_bytes(32, "big"))
    out = subprocess.run([f"{HERE}/secp_t", path], capture_output=True, text=True).stdout.strip().split("\n")
    assert len(out) == len(pairs), (len(out), len(pairs))
    return out

h = lambda x: format(x, "064x")
fp = vals(P, n)
bad = 0
for (a, b), line in zip(fp, run(1, fp)):
    r = pow(a, (P + 1) // 4, P)
    want = " ".join(h(v) for v in [a * b % P, a * a % P, (a + b) % P, (a - b) % P, (-a) % P, pow(a, P - 2, P), r])
    if line != want:
        bad += 1
        if bad < 5: print("FE MISMATCH", h(a), h(b), "\n got ", line, "\n want", want)
print(f"field: {len(fp)} pairs x 7 ops, {bad} mismatches")
sp = vals(N, n)
bad2 = 0
for (a, b), line in zip(sp, run(2, sp)):
    want = h(pow(a, N - 2, N)) + " " + h(a * b % N)
    if line != want:
        bad2 += 1
        if bad2 < 5: print("SC MISMATCH", h(a), h(b), "\n got ", line, "\n want", want)
print(f"scalar: {len(sp)} pairs x 2 ops, {bad2} mismatches")
