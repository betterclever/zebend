#!/usr/bin/env python3
"""Differential test of fq.bend (t/fq_test) against exact Python integers.
Inputs: edge values (0, 1, 2, p-1, p, p+1, (p-1)/2, (p+1)/2, R mod p, 2^381-1, 2^384-1, ...)
in all pairs, plus N random pairs (raw 384-bit values, so non-canonical ones too)."""
import os, random, subprocess, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'ref'))
from bls import P
HERE = os.path.dirname(os.path.abspath(__file__))
N = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
rnd = random.Random(1)
M = 1 << 383  # from_raw's domain: raw values < 2^383 (inputs are always < 2^381 after flag masking)
edges = [0, 1, 2, 3, P - 1, P - 2, P, P + 1, (P - 1) // 2, (P + 1) // 2, (1 << 384) % P, (1 << 381) - 1,
         (1 << 383) - 1, (1 << 64) - 1, 1 << 64, 1 << 320, 2 * P - 1, 2 * P, 3 * P]
pairs = [(a, b) for a in edges for b in edges]
for _ in range(N):
    k = rnd.random()
    a = rnd.randrange(P) if k < 0.8 else rnd.randrange(M)
    pairs.append((a, rnd.randrange(P) if rnd.random() < 0.9 else rnd.randrange(M)))
data = b''.join(a.to_bytes(48, 'little') + b.to_bytes(48, 'little') for a, b in pairs)
path = os.path.join(HERE, '..', 'data', 'fq_pairs.bin')
open(path, 'wb').write(data)
out = subprocess.run([os.path.join(HERE, 'fq_test'), path], capture_output=True, text=True).stdout.split('\n')
bad = checked = 0
for (a, b), line in zip(pairs, out):
    f = line.split()
    am, bm = a % P, b % P
    want = [str(int(a < P)), str(int(a <= (P - 1) // 2)), am * bm % P, am * am % P, (am + bm) % P, (am - bm) % P, (-am) % P,
            pow(am, P - 2, P)]
    got = f[:2] + [int(x, 16) for x in f[2:8]]
    ok = got == want
    s = f[8]
    is_sq = pow(am, (P - 1) // 2, P) in (0, 1)
    ok = ok and ((s == 'none') == (not is_sq)) and (s == 'none' or int(s, 16) ** 2 % P == am)
    checked += 1
    if not ok:
        bad += 1
        if bad < 5: print('MISMATCH', hex(a), hex(b), line[:200])
print(f'fq: {checked} pairs x 9 ops, {bad} mismatches' + ('' if checked == len(pairs) else f' (only {checked} of {len(pairs)} lines)'))
sys.exit(1 if bad or checked != len(pairs) else 0)
