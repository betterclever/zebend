#!/usr/bin/env python3
"""secp2 differential checks (Bend secp2/t/secp_t vs exact Python integers / libsecp256k1).

  python3 check2.py [N]

  mode 1: field mul sqr add sub neg inv sqrt-candidate (N random pairs + 19x19 edge pairs)
  mode 2: scalar inversion (new addition chain) and Montgomery product
  mode 5: GLV split (k1, k2 exact as libsecp256k1's split_lambda), Montgomery square, add mod n
  mode 4: u1 G + u2 Q (GLV + wNAF joint loop) vs Python affine arithmetic: edge scalars
          (0, 1, n-1, n-2, (n±1)/2, lambda, n-lambda, 2^128 ±1, values whose split halves are
          0 or hit the 128-bit bound), Q = G, -G, lambda G, 2G, and combinations that make
          the result or intermediate sums infinity (u1 G + u2 Q = 0 with Q = c G), plus random
  mode 3: ECDSA verdicts + decoded keys vs libsecp256k1 (data/t/ecdsa.bin, 32,000 cases from
          secp/rust secp-vectors; the expected file is libsecp256k1's output)
"""
import os, random, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import gen_secp2 as g2  # noqa: E402

DATA = os.path.join(HERE, "../../data/t")
P, N, GX, GY, LAM, BETA = g2.P, g2.N, g2.GX, g2.GY, g2.LAM, g2.BETA
BIN = os.path.join(HERE, "secp_t")
h = lambda x: format(x, "064x")
n = int(sys.argv[1]) if len(sys.argv) > 1 else 1000
random.seed(20261027)


def edges(m):
    e = [0, 1, 2, 3, m - 1, m - 2, (m - 1) // 2, (m + 1) // 2, 2**32 - 1, 2**32, 2**64 - 1, 2**64, 2**128,
         2**255, m - 2**32, 2**224, 977, 2**32 + 977, m - 977]
    return [x % m for x in e]


def vals(m, k):
    E = edges(m)
    out = [(a, b) for a in E for b in E]
    while len(out) < k:
        a = random.randrange(m) if random.random() < 0.8 else random.choice(E) ^ random.getrandbits(8)
        out.append((a % m, random.randrange(m)))
    return out


def run(mode, recs, tag):
    path = f"{DATA}/secp2_{tag}.bin"
    with open(path, "wb") as f:
        f.write(bytes([mode]))
        for r in recs:
            f.write(r)
    out = subprocess.run([BIN, path], capture_output=True, text=True).stdout.strip().split("\n")
    assert len(out) == len(recs), (tag, len(out), len(recs))
    return out


total_bad = 0


def report(name, cnt, bad):
    global total_bad
    total_bad += bad
    print(f"{name}: {cnt} cases, {bad} mismatches")


# ---- mode 1
fp = vals(P, n)
bad = 0
for (a, b), line in zip(fp, run(1, [a.to_bytes(32, "big") + b.to_bytes(32, "big") for a, b in fp], "f")):
    want = " ".join(h(v) for v in [a * b % P, a * a % P, (a + b) % P, (a - b) % P, (-a) % P, pow(a, P - 2, P), pow(a, (P + 1) // 4, P)])
    if line != want:
        bad += 1
        if bad < 5: print("FE MISMATCH", h(a), h(b), "\n got ", line, "\n want", want)
report("field (mul sqr add sub neg inv sqrt)", len(fp), bad)

# ---- mode 2
sp = vals(N, n)
bad = 0
for (a, b), line in zip(sp, run(2, [a.to_bytes(32, "big") + b.to_bytes(32, "big") for a, b in sp], "s")):
    want = h(pow(a, N - 2, N)) + " " + h(a * b % N)
    if line != want:
        bad += 1
        if bad < 5: print("SC MISMATCH", h(a), h(b), "\n got ", line, "\n want", want)
report("scalar (inv chain, mul)", len(sp), bad)

# ---- mode 5
ks = [0, 1, 2, N - 1, N - 2, (N - 1) // 2, (N + 1) // 2, LAM, N - LAM, 2**128, 2**128 - 1, 2**128 + 1,
      2**255, 2**256 % N, g2.MB1, N - g2.MB1, (LAM * 2**127) % N, (N - 1) * LAM % N]
# scalars whose split has a zero half: k = a (small) and k = b lambda
ks += [random.getrandbits(127) for _ in range(20)] + [random.getrandbits(127) * LAM % N for _ in range(20)]
s5 = [(k, b) for k in ks for b in (0, 1, N - 1, random.randrange(N))] + vals(N, n)
bad = 0
for (a, b), line in zip(s5, run(5, [a.to_bytes(32, "big") + b.to_bytes(32, "big") for a, b in s5], "s5")):
    k1, k2 = g2.split(a)
    want = " ".join(h(v) for v in [k1, k2, a * a % N, (a + b) % N])
    if line != want:
        bad += 1
        if bad < 5: print("S5 MISMATCH", h(a), h(b), "\n got ", line, "\n want", want)
report("scalar (GLV split, sqr, add)", len(s5), bad)

# ---- mode 4
G = (GX, GY)


def neg(p):
    return None if p is None else (p[0], (-p[1]) % P)


def mul(k, p):
    return g2.ec_mul(k % N, p)


Qs = [G, neg(G), (BETA * GX % P, GY), mul(2, G), mul(3, G), mul(LAM * 3 % N, G), mul(N - 1, G)]
rcs = [random.randrange(1, N) for _ in range(6)]
Qs += [mul(c, G) for c in rcs]
recs, want = [], []


def add_case(u1, u2, q, c=None):
    u1 %= N; u2 %= N
    recs.append(u1.to_bytes(32, "big") + u2.to_bytes(32, "big") + q[0].to_bytes(32, "big") + q[1].to_bytes(32, "big"))
    # q = c G when c known: result = (u1 + u2 c) G
    r = mul(u1 + u2 * c, G) if c is not None else g2.ec_add(mul(u1, G), mul(u2, q))
    want.append("inf" if r is None else h(r[0]) + " " + h(r[1]))


cs = [1, N - 1, LAM, 2, 3, LAM * 3 % N, N - 1]
special = [0, 1, 2, 3, N - 1, N - 2, N - 3, (N - 1) // 2, (N + 1) // 2, LAM, N - LAM, LAM - 1, LAM + 1,
           2**128 - 1, 2**128, 2**128 + 1, 2**127, 2**129, 2**255, g2.MB1, N - g2.MB1, 15, 16, 17, 127, 128, 129, 255, 256]
for qi, q in enumerate(Qs[:7]):
    c = cs[qi]
    for u1 in special:
        for u2 in special[:12]:
            add_case(u1, u2, q, c)
        # result infinity: u1 + u2 c = 0
        u2 = random.randrange(1, N)
        add_case((-u2 * c) % N, u2, q, c)
        add_case((-u1 * c) % N if u1 else 1, u1 if u1 else N - pow(c, -1, N), q, c)
    # intermediate sums: u1 G and u2 Q sharing digits, equal points mid-loop
    for _ in range(30):
        k = random.getrandbits(random.choice([8, 64, 128, 200, 256]))
        add_case(k, k, q, c)
        add_case(k, N - k, q, c)
        add_case(k * c % N, k, q, c)
for q, c in zip(Qs[7:], rcs):
    for _ in range(max(10, min(n // 10, 2000) // 6)):
        add_case(random.randrange(N), random.randrange(N), q, c)
    add_case(0, 0, q, c); add_case(0, 1, q, c); add_case(1, 0, q, c); add_case(N - 1, N - 1, q, c)
bad = 0
for i, line in enumerate(run(4, recs, "m4")):
    if line != want[i]:
        bad += 1
        if bad < 5: print("ECMULT MISMATCH", recs[i].hex(), "\n got ", line, "\n want", want[i])
report("u1 G + u2 Q (GLV/wNAF incl. edge scalars, infinity)", len(recs), bad)

# ---- mode 3: libsecp256k1 vectors
ec = os.path.join(DATA, "ecdsa.bin")
if os.path.exists(ec):
    out = subprocess.run([BIN, ec], capture_output=True, text=True).stdout.strip().split("\n")
    exp = open(ec + ".expect").read().strip().split("\n")
    bad = sum(1 for a, b in zip(out, exp) if a != b) + abs(len(out) - len(exp))
    report("ECDSA verify + key decoding vs libsecp256k1 (data/t/ecdsa.bin)", len(exp), bad)
print("TOTAL MISMATCHES", total_bad)
sys.exit(1 if total_bad else 0)
