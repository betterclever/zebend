#!/usr/bin/env python3
"""Exact-integer Python model of BLS12-381 as the `bls12_381` crate (0.9) computes it:
Fq / Fq2 / Fq6 / Fq12 tower, G1/G2 decoding, the Miller loop with the crate's projective
doubling/addition steps and line scaling (so Miller loop outputs agree bit for bit), and its
final exponentiation. Used (1) to check itself against the Rust oracle's dumps and
(2) as the source of the per-layer unit vectors the Bend code is diffed against, and of
the constants the generator bakes into Bend.

  python3 ref/bls.py selftest     # vs data/dump_*.txt and data/vectors.txt from the oracle
"""
import sys, os

P = 0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab
R = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001
X = 0xd201000000010000  # |x|; x is negative
B1 = 4

def inv(a): return pow(a, P - 2, P)

# ---- Fq2 = Fq[u]/(u^2+1), elements (c0, c1)
def f2(a, b=0): return (a % P, b % P)
F2Z, F2O = (0, 0), (1, 0)
def a2(x, y): return ((x[0] + y[0]) % P, (x[1] + y[1]) % P)
def s2(x, y): return ((x[0] - y[0]) % P, (x[1] - y[1]) % P)
def n2(x): return ((-x[0]) % P, (-x[1]) % P)
def m2(x, y):
    return ((x[0] * y[0] - x[1] * y[1]) % P, (x[0] * y[1] + x[1] * y[0]) % P)
def sq2(x): return m2(x, x)
def ms2(x, k): return (x[0] * k % P, x[1] * k % P)
def nr2(x):  # * (u + 1)
    return ((x[0] - x[1]) % P, (x[0] + x[1]) % P)
def conj2(x): return (x[0], (-x[1]) % P)
def inv2(x):
    t = inv((x[0] * x[0] + x[1] * x[1]) % P)
    return (x[0] * t % P, (-x[1]) * t % P)
def pow2(x, e):
    r = F2O
    for bit in bin(e)[2:]:
        r = sq2(r)
        if bit == '1':
            r = m2(r, x)
    return r

# ---- Fq6 = Fq2[v]/(v^3 - (u+1)), elements (c0, c1, c2)
F6Z = (F2Z, F2Z, F2Z)
F6O = (F2O, F2Z, F2Z)
def a6(x, y): return tuple(a2(p, q) for p, q in zip(x, y))
def s6(x, y): return tuple(s2(p, q) for p, q in zip(x, y))
def n6(x): return tuple(n2(p) for p in x)
def m6(x, y):
    a0, a1, a2_ = x
    b0, b1, b2 = y
    c0 = a2(m2(a0, b0), nr2(a2(m2(a1, b2), m2(a2_, b1))))
    c1 = a2(a2(m2(a0, b1), m2(a1, b0)), nr2(m2(a2_, b2)))
    c2 = a2(a2(m2(a0, b2), m2(a1, b1)), m2(a2_, b0))
    return (c0, c1, c2)
def nr6(x):  # * v
    return (nr2(x[2]), x[0], x[1])
def inv6(x):
    c0, c1, c2 = x
    t0 = s2(sq2(c0), nr2(m2(c1, c2)))
    t1 = s2(nr2(sq2(c2)), m2(c0, c1))
    t2 = s2(sq2(c1), m2(c0, c2))
    d = a2(m2(c0, t0), nr2(a2(m2(c2, t1), m2(c1, t2))))
    di = inv2(d)
    return (m2(t0, di), m2(t1, di), m2(t2, di))

# ---- Fq12 = Fq6[w]/(w^2 - v), elements (c0, c1)
F12O = (F6O, F6Z)
def m12(x, y):
    aa = m6(x[0], y[0])
    bb = m6(x[1], y[1])
    c1 = s6(s6(m6(a6(x[0], x[1]), a6(y[0], y[1])), aa), bb)
    c0 = a6(aa, nr6(bb))
    return (c0, c1)
def sq12(x): return m12(x, x)
def conj12(x): return (x[0], n6(x[1]))
def inv12(x):
    t = inv6(s6(m6(x[0], x[0]), nr6(m6(x[1], x[1]))))
    return (m6(x[0], t), n6(m6(x[1], t)))

# Frobenius: (a + b u)^p = a - b u; v^p = v * g1, v^2p = v^2 * g2, w^p = w * g12.
NR = (1, 1)  # u + 1
G6_1 = pow2(NR, (P - 1) // 3)
G6_2 = pow2(NR, 2 * (P - 1) // 3)
G12 = pow2(NR, (P - 1) // 6)
def frob6(x):
    return (conj2(x[0]), m2(conj2(x[1]), G6_1), m2(conj2(x[2]), G6_2))
def frob12(x):
    c0 = frob6(x[0])
    c1 = frob6(x[1])
    c1 = (m2(c1[0], G12), m2(c1[1], G12), m2(c1[2], G12))
    return (c0, c1)

def mul_by_014(f, c0, c1, c4):
    # sparse element: (c0 + c1 v) + (c4 v) w  [as Fq6 (c0, c1, 0), (0, c4, 0)]
    return m12(f, ((c0, c1, F2Z), (F2Z, c4, F2Z)))

# ---- final exponentiation (the crate's chain, ported literally)
def fp4_square(a, b):
    t0 = sq2(a); t1 = sq2(b)
    t2 = nr2(t1)
    c0 = a2(t2, t0)
    t2 = sq2(a2(a, b))
    t2 = s2(t2, t0)
    c1 = s2(t2, t1)
    return c0, c1

def cyclotomic_square(f):
    z0, z4, z3 = f[0]
    z2, z1, z5 = f[1]
    t0, t1 = fp4_square(z0, z1)
    z0 = s2(t0, z0); z0 = a2(a2(z0, z0), t0)
    z1 = a2(t1, z1); z1 = a2(a2(z1, z1), t1)
    t0, t1 = fp4_square(z2, z3)
    t2, t3 = fp4_square(z4, z5)
    z4 = s2(t0, z4); z4 = a2(a2(z4, z4), t0)
    z5 = a2(t1, z5); z5 = a2(a2(z5, z5), t1)
    t0 = nr2(t3)
    z2 = a2(t0, z2); z2 = a2(a2(z2, z2), t0)
    z3 = s2(t2, z3); z3 = a2(a2(z3, z3), t2)
    return ((z0, z4, z3), (z2, z1, z5))

def cyc_exp(f):
    tmp = F12O
    found = False
    for b in range(63, -1, -1):
        bit = (X >> b) & 1
        if found:
            tmp = cyclotomic_square(tmp)
        else:
            found = bit == 1
        if bit:
            tmp = m12(tmp, f)
    return conj12(tmp)

def final_exp(f):
    t0 = f
    for _ in range(6):
        t0 = frob12(t0)
    t1 = inv12(f)
    t2 = m12(t0, t1)
    t1 = t2
    t2 = frob12(frob12(t2))
    t2 = m12(t2, t1)
    f = t2
    t1 = conj12(cyclotomic_square(t2))
    t3 = cyc_exp(t2)
    t4 = m12(t1, t3)
    t1 = cyc_exp(t4)
    t4 = conj12(t4)
    f = m12(f, t4)
    t4 = cyclotomic_square(t3)
    t0 = cyc_exp(t1)
    t3 = m12(t3, t0)
    t3 = frob12(frob12(t3))
    f = m12(f, t3)
    t4 = m12(t4, cyc_exp(t0))
    f = m12(f, cyc_exp(t4))
    t4 = m12(t4, conj12(t2))
    t2 = m12(t2, t1)
    t2 = frob12(frob12(frob12(t2)))
    f = m12(f, t2)
    t4 = frob12(t4)
    f = m12(f, t4)
    return f

# ---- G2 Miller loop steps (Jacobian-like projective, as the crate)
def doubling_step(r):
    rx, ry, rz = r
    tmp0 = sq2(rx)
    tmp1 = sq2(ry)
    tmp2 = sq2(tmp1)
    tmp3 = s2(s2(sq2(a2(tmp1, rx)), tmp0), tmp2)
    tmp3 = a2(tmp3, tmp3)
    tmp4 = a2(a2(tmp0, tmp0), tmp0)
    tmp6 = a2(rx, tmp4)
    tmp5 = sq2(tmp4)
    zsq = sq2(rz)
    nx = s2(s2(tmp5, tmp3), tmp3)
    nz = s2(s2(sq2(a2(rz, ry)), tmp1), zsq)
    ny = m2(s2(tmp3, nx), tmp4)
    tmp2 = a2(tmp2, tmp2); tmp2 = a2(tmp2, tmp2); tmp2 = a2(tmp2, tmp2)
    ny = s2(ny, tmp2)
    tmp3 = m2(tmp4, zsq)
    tmp3 = a2(tmp3, tmp3)
    tmp3 = n2(tmp3)
    tmp6 = s2(s2(sq2(tmp6), tmp0), tmp5)
    tmp1 = a2(tmp1, tmp1); tmp1 = a2(tmp1, tmp1)
    tmp6 = s2(tmp6, tmp1)
    tmp0 = m2(nz, zsq)
    tmp0 = a2(tmp0, tmp0)
    return (nx, ny, nz), (tmp0, tmp3, tmp6)

def addition_step(r, q):
    rx, ry, rz = r
    qx, qy = q
    zsq = sq2(rz)
    ysq = sq2(qy)
    t0 = m2(zsq, qx)
    t1 = m2(s2(s2(sq2(a2(qy, rz)), ysq), zsq), zsq)
    t2 = s2(t0, rx)
    t3 = sq2(t2)
    t4 = a2(t3, t3); t4 = a2(t4, t4)
    t5 = m2(t4, t2)
    t6 = s2(s2(t1, ry), ry)
    t9 = m2(t6, qx)
    t7 = m2(t4, rx)
    nx = s2(s2(s2(sq2(t6), t5), t7), t7)
    nz = s2(s2(sq2(a2(rz, t2)), zsq), t3)
    t10 = a2(qy, nz)
    t8 = m2(s2(t7, nx), t6)
    t0 = m2(ry, t5)
    t0 = a2(t0, t0)
    ny = s2(t8, t0)
    t10 = s2(sq2(t10), ysq)
    ztsq = sq2(nz)
    t10 = s2(t10, ztsq)
    t9 = s2(a2(t9, t9), t10)
    t10 = a2(nz, nz)
    t6 = n2(t6)
    t1 = a2(t6, t6)
    return (nx, ny, nz), (t10, t1, t9)

def prepare(q):
    """68 line coefficient triples for G2 affine q (as G2Prepared)."""
    r = (q[0], q[1], F2O)
    coeffs = []
    found = False
    for b in range(63, -1, -1):
        bit = ((X >> 1) >> b) & 1
        if not found:
            found = bit == 1
            continue
        r, c = doubling_step(r); coeffs.append(c)
        if bit:
            r, c = addition_step(r, q); coeffs.append(c)
    r, c = doubling_step(r); coeffs.append(c)
    assert len(coeffs) == 68
    return coeffs

def ell(f, c, p):
    c0 = ms2(c[0], p[1])
    c1 = ms2(c[1], p[0])
    return mul_by_014(f, c[2], c1, c0)

def multi_miller_loop(terms):
    """terms: list of (G1 affine (x, y) or None for identity, coeffs)."""
    f = F12O
    idx = 0
    found = False
    def step(f, idx):
        for p, cs in terms:
            if p is not None:
                f = ell(f, cs[idx], p)
        return f
    for b in range(63, -1, -1):
        bit = ((X >> 1) >> b) & 1
        if not found:
            found = bit == 1
            continue
        f = step(f, idx); idx += 1
        if bit:
            f = step(f, idx); idx += 1
        f = sq12(f)
    f = step(f, idx); idx += 1
    return conj12(f)

# ---- G1 (affine (x, y) or None)
def g1_add(p, q):
    if p is None: return q
    if q is None: return p
    if p[0] == q[0]:
        if (p[1] + q[1]) % P == 0: return None
        l = 3 * p[0] * p[0] * inv(2 * p[1]) % P
    else:
        l = (q[1] - p[1]) * inv(q[0] - p[0]) % P
    x = (l * l - p[0] - q[0]) % P
    return (x, (l * (p[0] - x) - p[1]) % P)
def g1_neg(p): return None if p is None else (p[0], (-p[1]) % P)
def g1_mul(p, k):
    r = None
    for bit in bin(k)[2:]:
        r = g1_add(r, r)
        if bit == '1': r = g1_add(r, p)
    return r
def g1_on_curve(p): return (p[1] * p[1] - p[0] ** 3 - B1) % P == 0

# ---- G2
B2 = (4, 4)
def g2_add(p, q):
    if p is None: return q
    if q is None: return p
    if p[0] == q[0]:
        if a2(p[1], q[1]) == F2Z: return None
        l = m2(ms2(sq2(p[0]), 3), inv2(ms2(p[1], 2)))
    else:
        l = m2(s2(q[1], p[1]), inv2(s2(q[0], p[0])))
    x = s2(s2(sq2(l), p[0]), q[0])
    return (x, s2(m2(l, s2(p[0], x)), p[1]))
def g2_neg(p): return None if p is None else (p[0], n2(p[1]))
def g2_mul(p, k):
    r = None
    for bit in bin(k)[2:]:
        r = g2_add(r, r)
        if bit == '1': r = g2_add(r, p)
    return r

# ---- decoding (bls12_381 from_compressed: flags, canonical x, sqrt, sign, subgroup)
def sqrt1(a):
    r = pow(a, (P + 1) // 4, P)
    return r if r * r % P == a % P else None
def largest1(y): return y > (P - 1) // 2
def sqrt2(a):
    if a == F2Z: return F2Z
    a1 = pow2(a, (P - 3) // 4)
    alpha = m2(sq2(a1), a)
    x0 = m2(a1, a)
    if alpha == n2(F2O):
        s = ((-x0[1]) % P, x0[0])
    else:
        s = m2(pow2(a2(alpha, F2O), (P - 1) // 2), x0)
    return s if sq2(s) == a else None
def largest2(y): return largest1(y[1]) or (y[1] == 0 and largest1(y[0]))

def g1_decode(b):
    """None = invalid encoding; 'inf' = identity; else affine point (subgroup-checked)."""
    c, i, s = b[0] >> 7 & 1, b[0] >> 6 & 1, b[0] >> 5 & 1
    x = int.from_bytes(bytes([b[0] & 0x1f]) + bytes(b[1:48]), 'big')
    if x >= P: return None
    if i and c and not s and x == 0: return 'inf'
    y = sqrt1((x ** 3 + B1) % P)
    if y is None: return None
    if largest1(y) ^ s: y = (-y) % P
    if i or not c: return None
    p = (x, y)
    return p if g1_mul(p, R) is None else None
def g2_decode(b):
    c, i, s = b[0] >> 7 & 1, b[0] >> 6 & 1, b[0] >> 5 & 1
    x1 = int.from_bytes(bytes([b[0] & 0x1f]) + bytes(b[1:48]), 'big')
    x0 = int.from_bytes(bytes(b[48:96]), 'big')
    if x1 >= P or x0 >= P: return None
    x = (x0, x1)
    if i and c and not s and x == F2Z: return 'inf'
    y = sqrt2(a2(m2(sq2(x), x), B2))
    if y is None: return None
    if largest2(y) ^ s: y = n2(y)
    if i or not c: return None
    p = (x, y)
    return p if g2_mul(p, R) is None else None

# ---- Groth16
def load_vk(path):
    import struct
    b = open(path, 'rb').read()
    w = lambda o: int.from_bytes(b[o:o + 48], 'little')
    o = 0
    def g1():
        nonlocal o
        p = (w(o), w(o + 48)); o += 96; return p
    def g2():
        nonlocal o
        p = ((w(o), w(o + 48)), (w(o + 96), w(o + 144))); o += 192; return p
    alpha, beta, gamma, delta = g1(), g2(), g2(), g2()
    n = struct.unpack('<I', b[o:o + 4])[0]; o += 4
    ic = [g1() for _ in range(n)]
    return dict(alpha=alpha, beta=beta, gamma=gamma, delta=delta, ic=ic)

def read_set(path):
    import struct
    b = open(path, 'rb').read()
    i, out = 0, []
    while i < len(b):
        kind, tag = struct.unpack('<II', b[i:i + 8])
        proof = b[i + 8:i + 200]
        n = 7 if kind == 0 else 5
        ins = [int.from_bytes(b[i + 200 + 32 * k:i + 232 + 32 * k], 'little') for k in range(n)]
        out.append((kind, tag, proof, ins))
        i += 200 + 32 * n
    return out

def groth16_parts(vk, proof, ins):
    a = g1_decode(proof[0:48]); bb = g2_decode(proof[48:144]); c = g1_decode(proof[144:192])
    acc = vk['ic'][0]
    for x, p in zip(ins, vk['ic'][1:]):
        acc = g1_add(acc, g1_mul(p, x))
    return a, bb, c, acc

def verify(vk, proof, ins, ab=None):
    a, bb, c, acc = groth16_parts(vk, proof, ins)
    if a in (None, 'inf') or bb in (None, 'inf') or c in (None, 'inf'):
        return False
    ml = multi_miller_loop([(a, prepare(bb)), (acc, prepare(g2_neg(vk['gamma']))), (c, prepare(g2_neg(vk['delta'])))])
    if ab is None:
        ab = final_exp(multi_miller_loop([(vk['alpha'], prepare(vk['beta']))]))
    return final_exp(ml) == ab

# ---- printing in the oracle's format
def flat12(f): return [c for f6 in f for f2_ in f6 for c in f2_]
def hex12(f): return ' '.join('%096x' % c for c in flat12(f))

def selftest():
    here = os.path.dirname(os.path.abspath(__file__))
    data = os.path.join(here, '..', 'data')
    ok = bad = 0
    def chk(name, got, want):
        nonlocal ok, bad
        if got == want: ok += 1
        else:
            bad += 1; print('MISMATCH', name); print(' got ', got[:200]); print(' want', want[:200])
    # vectors: pairings and Miller loops of random points
    lines = open(os.path.join(data, 'vectors.txt')).read().split('\n')
    i = 0
    while i + 5 <= len(lines) and lines[i]:
        g1l, g2l, sml, pl, mll = [l.split() for l in lines[i:i + 5]]
        p = (int(g1l[1], 16), int(g1l[2], 16))
        q = ((int(g2l[1], 16), int(g2l[2], 16)), (int(g2l[3], 16), int(g2l[4], 16)))
        chk('g1 decode', g1_decode(bytes.fromhex(g1l[3])), p)
        chk('g2 decode', g2_decode(bytes.fromhex(g2l[5])), q)
        sm = g1_mul(p, int(sml[1], 16))
        chk('smul', '%096x %096x' % sm, sml[2] + ' ' + sml[3])
        ml = multi_miller_loop([(p, prepare(q))])
        chk('ml', hex12(ml), ' '.join(mll[1:]))
        chk('pair', hex12(final_exp(ml)), ' '.join(pl[1:]))
        i += 5
    # real proofs: the oracle's dumps
    for fn in sorted(os.listdir(data)):
        if not fn.startswith('dump_'): continue
        d = {l.split()[0]: l.split()[1:] for l in open(os.path.join(data, fn)) if l.strip()}
        recs = read_set(os.path.join(data, fn.split('_')[1].rstrip('0123456789.txt') + '.bin'))
        idx = int(''.join(ch for ch in fn.split('_')[1] if ch.isdigit()))
        kind, tag, proof, ins = recs[idx]
        vk = load_vk(os.path.join(data, 'vk_%s.bin' % ('spend' if kind == 0 else 'output')))
        a, bb, c, acc = groth16_parts(vk, proof, ins)
        chk(fn + ' acc', '%096x %096x' % acc, ' '.join(d['acc']))
        chk(fn + ' A', '%096x %096x' % a, ' '.join(d['A']))
        chk(fn + ' B', ' '.join('%096x' % v for v in (bb[0][0], bb[0][1], bb[1][0], bb[1][1])), ' '.join(d['B']))
        chk(fn + ' ml_ab', hex12(multi_miller_loop([(a, prepare(bb))])), ' '.join(d['ml_ab']))
        ml = multi_miller_loop([(a, prepare(bb)), (acc, prepare(g2_neg(vk['gamma']))), (c, prepare(g2_neg(vk['delta'])))])
        chk(fn + ' ml', hex12(ml), ' '.join(d['ml']))
        chk(fn + ' fe', hex12(final_exp(ml)), ' '.join(d['fe']))
    print(f'selftest: {ok} equal, {bad} mismatches')
    return bad == 0

if __name__ == '__main__':
    if sys.argv[1:2] == ['selftest']:
        sys.exit(0 if selftest() else 1)

# ---- fast subgroup checks (the crate's: G1 phi(P) == -[x^2]P, G2 psi(P) == [x]P, x < 0)
BETA = 0x5f19672fdf76ce51ba69c6076a0f77eaddb3a93be6f89688de17d813620a00022e01fffffffefffe
PSI_X = inv2(pow2(NR, (P - 1) // 3))
PSI_Y = inv2(pow2(NR, (P - 1) // 2))
def g1_in_subgroup(p): return g1_neg(g1_mul(g1_mul(p, X), X)) == ((BETA * p[0]) % P, p[1])
def g2_psi(p): return (m2(conj2(p[0]), PSI_X), m2(conj2(p[1]), PSI_Y))
def g2_in_subgroup(p): return g2_psi(p) == g2_neg(g2_mul(p, X))
