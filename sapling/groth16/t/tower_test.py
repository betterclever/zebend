#!/usr/bin/env python3
"""Differential test of fq2/fq6/fq12.bend (t/tower_test) against ref/bls.py (exact integers,
itself checked against the bls12_381 crate by `ref/bls.py selftest`)."""
import os, random, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'ref'))
from bls import *
N = int(sys.argv[1]) if len(sys.argv) > 1 else 200
rnd = random.Random(2)
def r12():
    return [rnd.randrange(P) for _ in range(12)]
recs = []
for i in range(N):
    a, b = r12(), r12()
    if i % 4 == 1:   # make a.c0.c0 a square so sqrt has a root
        x = (rnd.randrange(P), rnd.randrange(P)); a[0], a[1] = sq2(x)
    if i == 2: a[0], a[1] = 0, 0
    if i == 3: a[0], a[1] = P - 1, 0      # -1: square in Fq2
    recs.append((a, b))
path = os.path.join(HERE, '..', 'data', 'tower_in.bin')
open(path, 'wb').write(b''.join(v.to_bytes(48, 'little') for a, b in recs for v in a + b))
out = subprocess.run([os.path.join(HERE, 'tower_test'), path], capture_output=True, text=True).stdout.split('\n')
def to12(v): return (((v[0], v[1]), (v[2], v[3]), (v[4], v[5])), ((v[6], v[7]), (v[8], v[9]), (v[10], v[11])))
def h(xs): return ' '.join('%096x' % c for c in xs)
def f2(x): return h(x)
def f6(x): return h([c for e in x for c in e])
def f12(x): return h(flat12(x))
bad = n = 0
for k, (a, b) in enumerate(recs):
    A, B = to12(a), to12(b)
    x, y = A[0][0], B[0][0]
    u, v = A[0], B[0]
    l2, l6, l12 = out[3 * k:3 * k + 3]
    s = sqrt2(x)
    got_s = l2.split()[7:]
    ok_s = (s is None and got_s == ['none']) or (s is not None and len(got_s) == 2 and sq2((int(got_s[0], 16), int(got_s[1], 16))) == x)
    want2 = 'fq2 ' + ' '.join([f2(m2(x, y)), f2(sq2(x)), f2(inv2(x) if x != F2Z else F2Z)])
    want6 = 'fq6 ' + ' '.join([f6(m6(u, v)), f6(m6(u, u)), f6(inv6(u)), f6(frob6(u))])
    want12 = 'fq12 ' + ' '.join([f12(m12(A, B)), f12(sq12(A)), f12(inv12(A)), f12(frob12(A)), f12(conj12(A)), f12(mul_by_014(A, B[0][0], B[0][1], B[1][1]))])
    for name, ok in (('fq2', ' '.join(l2.split()[:7]) == want2 and ok_s), ('fq6', l6 == want6), ('fq12', l12 == want12)):
        n += 1
        if not ok:
            bad += 1
            if bad < 4: print('MISMATCH', k, name)
print(f'tower: {N} records, {n} op groups (fq2: mul sqr inv sqrt; fq6: mul sqr inv frob; fq12: mul sqr inv frob conj mul_by_014), {bad} mismatches')
sys.exit(1 if bad else 0)
