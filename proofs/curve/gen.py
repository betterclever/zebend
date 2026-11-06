"""Writes certs.bend: every polynomial identity the curve laws need, with its certificate.

Run from this directory: python3 gen.py (needs sympy). The functions below mirror
model.bend operation by operation (same operands, same order), so that the Z/p value of
each expression is, by definition, the value of the Nat-level copy in model.bend; a
mismatch makes the conversion in PROOF.bend fail, not pass. Nothing here is trusted: every
certificate is re-checked by ring/cert.bend's cert_ok2.
"""
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'ring'))
from certgen import V, C, add, sub, mul, emit  # noqa: E402
from lemgen import HEADER, emit_lemma  # noqa: E402


def neg(a):
    return ('neg', a)


# --- model.bend, as expressions -------------------------------------------------------------

def b3(b):
    return add(add(b, b), b)


def add_t2(p, q):
    return mul(p[2], q[2])


def add_y3a(p, q):
    x1, _, z1 = p
    x2, _, z2 = q
    t0 = mul(x1, x2)
    t2 = mul(z1, z2)
    x3a = mul(add(x1, z1), add(x2, z2))
    return sub(x3a, add(t0, t2))


def addh(p, q, t2b, y3b):
    x1, y1, z1 = p
    x2, y2, z2 = q
    t0 = mul(x1, x2)
    t1 = mul(y1, y2)
    t2 = mul(z1, z2)
    t3a = mul(add(x1, y1), add(x2, y2))
    t3 = sub(t3a, add(t0, t1))
    t4a = mul(add(y1, z1), add(y2, z2))
    t4 = sub(t4a, add(t1, t2))
    t0b = add(add(t0, t0), t0)
    z3a = add(t1, t2b)
    t1b = sub(t1, t2b)
    x3 = sub(mul(t3, t1b), mul(t4, y3b))
    y3 = add(mul(t1b, z3a), mul(y3b, t0b))
    z3 = add(mul(z3a, t4), mul(t0b, t3))
    return (x3, y3, z3)


def addb(k, p, q):
    return addh(p, q, mul(k, add_t2(p, q)), mul(k, add_y3a(p, q)))


def aff_y3a(p, q):
    x1, _, z1 = p
    x2, _ = q
    return add(mul(x2, z1), x1)


def add_affh(p, q, t2, y3b):
    x1, y1, z1 = p
    x2, y2 = q
    t0a = mul(x1, x2)
    t1a = mul(y1, y2)
    t3a = mul(add(x2, y2), add(x1, y1))
    t3 = sub(t3a, add(t0a, t1a))
    t4 = add(mul(y2, z1), y1)
    x3a = add(t0a, t0a)
    t0 = add(x3a, t0a)
    z3a = add(t1a, t2)
    t1 = sub(t1a, t2)
    x3 = sub(mul(t3, t1), mul(t4, y3b))
    y3 = add(mul(t1, z3a), mul(y3b, t0))
    z3 = add(mul(z3a, t4), mul(t0, t3))
    return (x3, y3, z3)


def add_affb(k, p, q):
    return add_affh(p, q, mul(k, p[2]), mul(k, aff_y3a(p, q)))


def doubleh(p, t2):
    x, y, z = p
    t0 = mul(y, y)
    z3a = add(t0, t0)
    z3b = add(z3a, z3a)
    z3c = add(z3b, z3b)
    t1 = mul(y, z)
    x3a = mul(t2, z3c)
    y3a = add(t0, t2)
    z3 = mul(t1, z3c)
    t1b = add(t2, t2)
    t2b = add(t1b, t2)
    t0b = sub(t0, t2b)
    x3b = mul(t0b, mul(x, y))
    return (add(x3b, x3b), add(x3a, mul(t0b, y3a)), z3)


def doubleb(k, p):
    return doubleh(p, mul(k, mul(p[2], p[2])))


def m15(a):
    a2 = add(a, a)
    a4 = add(a2, a2)
    a8 = add(a4, a4)
    return sub(add(a8, a8), a)


def oncurve(b, x, y):
    return (mul(y, y), add(mul(x, mul(x, x)), b))


def oncurvep(b, p):
    x, y, z = p
    return (mul(mul(y, y), z), add(mul(x, mul(x, x)), mul(b, mul(z, mul(z, z)))))


def chord_l(y1, y2, di):
    return mul(sub(y2, y1), di)


def chord_x(x1, y1, x2, y2, di):
    l = chord_l(y1, y2, di)
    return sub(sub(mul(l, l), x1), x2)


def chord_y(x1, y1, x2, y2, di):
    return sub(mul(chord_l(y1, y2, di), sub(x1, chord_x(x1, y1, x2, y2, di))), y1)


def tan_l(x, ti):
    xx = mul(x, x)
    return mul(add(add(xx, xx), xx), ti)


def tan_x(x, ti):
    l = tan_l(x, ti)
    return sub(sub(mul(l, l), x), x)


def tan_y(x, y, ti):
    return sub(mul(tan_l(x, ti), sub(x, tan_x(x, ti))), y)


def scaled(z, x, y):
    return (mul(z, x), mul(z, y), z)


ONE = C(1)
ZERO = C(0)


def inv_rel(a, ai):
    return (mul(a, ai), ONE)


# --- the obligations ------------------------------------------------------------------------
# (name, number of variables, t1, t2, relations, variable order for the division)

def vs(names):
    return [V(i) for i in range(len(names))]


def obligations():
    """(name, variable names, t1, t2, relations, variable order for the division)"""
    ob = []
    # vesta.mul15 is multiplication by 3 * 5
    names = ['a']
    (a,) = vs(names)
    ob.append(('m15', names, m15(a), mul(b3(C(5)), a), [], [0]))
    # (-y)^2 == y^2
    names = ['y']
    (y,) = vs(names)
    ob.append(('negsq', names, mul(neg(y), neg(y)), mul(y, y), [], [0]))
    # X == Z (X zi) when Z zi == 1
    names = ['X', 'Z', 'zi']
    X, Z, zi = vs(names)
    ob.append(('unscale', names, X, mul(Z, mul(X, zi)), [inv_rel(Z, zi)], [0, 1, 2]))

    # chord (P != +-Q)
    names = ['b', 'x1', 'y1', 'x2', 'y2', 'Z1', 'Z2', 'di', 'zi1', 'zi2']
    b, x1, y1, x2, y2, Z1, Z2, di, zi1, zi2 = vs(names)
    P, Q = scaled(Z1, x1, y1), scaled(Z2, x2, y2)
    R = addb(b3(b), P, Q)
    cur = [oncurve(b, x1, y1), oncurve(b, x2, y2)]
    dd = (mul(sub(x2, x1), di), ONE)
    order = [2, 4, 3, 1, 7, 0, 5, 6, 8, 9]
    ob.append(('add_chord_x', names, R[0], mul(chord_x(x1, y1, x2, y2, di), R[2]), cur + [dd], order))
    ob.append(('add_chord_y', names, R[1], mul(chord_y(x1, y1, x2, y2, di), R[2]), cur + [dd], order))
    w = mul(mul(mul(zi1, zi1), mul(zi2, zi2)), mul(di, mul(di, di)))
    ob.append(('add_chord_z', names, mul(R[2], w), chord_y(x1, y1, x2, neg(y2), di), cur + [dd, inv_rel(Z1, zi1), inv_rel(Z2, zi2)], [2, 4, 3, 1, 5, 6, 8, 9, 7, 0]))
    Ra = add_affb(b3(b), P, (x2, y2))
    ob.append(('aff_chord_x', names, Ra[0], mul(chord_x(x1, y1, x2, y2, di), Ra[2]), cur + [dd], order))
    ob.append(('aff_chord_y', names, Ra[1], mul(chord_y(x1, y1, x2, y2, di), Ra[2]), cur + [dd], order))
    cx, cy = chord_x(x1, y1, x2, y2, di), chord_y(x1, y1, x2, y2, di)
    ob.append(('chord_on', names, mul(cy, cy), add(mul(cx, mul(cx, cx)), b), cur + [dd], order))

    # tangent (P == Q), and P + (-P)
    names = ['b', 'x', 'y', 'Z1', 'Z2', 'ti', 'zi1', 'zi2']
    b, x, y, Z1, Z2, ti, zi1, zi2 = vs(names)
    P, Q = scaled(Z1, x, y), scaled(Z2, x, y)
    R = addb(b3(b), P, Q)
    cur = [oncurve(b, x, y)]
    tt = (mul(add(y, y), ti), ONE)
    order = [2, 1, 5, 0, 3, 4, 6, 7]
    zis = [inv_rel(Z1, zi1), inv_rel(Z2, zi2)]
    w = mul(mul(mul(zi1, zi1), mul(zi2, zi2)), mul(ti, mul(ti, ti)))
    ob.append(('add_tan_x', names, R[0], mul(tan_x(x, ti), R[2]), cur + [tt], order))
    ob.append(('add_tan_y', names, R[1], mul(tan_y(x, y, ti), R[2]), cur + [tt], order))
    ob.append(('add_tan_z', names, mul(R[2], w), ONE, cur + [tt] + zis, order))
    Rn = addb(b3(b), P, scaled(Z2, x, neg(y)))
    ob.append(('add_neg_x', names, Rn[0], ZERO, cur, order))
    ob.append(('add_neg_z', names, Rn[2], ZERO, cur, order))
    ob.append(('add_neg_y', names, mul(Rn[1], w), tan_y(x, y, ti), cur + [tt] + zis, order))
    Rd = doubleb(b3(b), P)
    ob.append(('dbl_tan_x', names, Rd[0], mul(tan_x(x, ti), Rd[2]), cur + [tt], order))
    ob.append(('dbl_tan_y', names, Rd[1], mul(tan_y(x, y, ti), Rd[2]), cur + [tt], order))
    wd = mul(mul(mul(zi1, zi1), mul(zi1, zi1)), mul(ti, mul(ti, ti)))
    ob.append(('dbl_tan_z', names, mul(Rd[2], wd), ONE, cur + [tt, inv_rel(Z1, zi1)], order))
    tx, ty = tan_x(x, ti), tan_y(x, y, ti)
    ob.append(('tan_on', names, mul(ty, ty), add(mul(tx, mul(tx, tx)), b), cur + [tt], order))

    # the identity (0 : Y : 0); z0 is a variable equal to 0
    names = ['b', 'z0', 'Y1', 'X2', 'Y2', 'Z2']
    b, z0, Y1, X2, Y2, Z2 = vs(names)
    zr = [(z0, ZERO)]
    order = [1, 0, 2, 3, 4, 5]
    Q = (X2, Y2, Z2)
    Rl = addb(b3(b), (z0, Y1, z0), Q)
    c = mul(mul(Y1, Y1), Y2)
    for i, nm in enumerate('xyz'):
        ob.append(('add_idl_' + nm, names, Rl[i], mul(c, Q[i]), zr, order))
    Rr = addb(b3(b), Q, (z0, Y1, z0))
    c = mul(Y2, mul(Y1, Y1))
    for i, nm in enumerate('xyz'):
        ob.append(('add_idr_' + nm, names, Rr[i], mul(c, Q[i]), zr, order))
    Rdi = doubleb(b3(b), (z0, Y1, z0))
    ob.append(('dbl_id_x', names, Rdi[0], ZERO, zr, order))
    ob.append(('dbl_id_y', names, Rdi[1], mul(mul(Y1, Y1), mul(Y1, Y1)), zr, order))
    ob.append(('dbl_id_z', names, Rdi[2], ZERO, zr, order))

    # add_aff is add with Z2 = 1; one is a variable equal to 1
    names = ['b', 'X1', 'Y1', 'Z1', 'x2', 'y2', 'one']
    b, X1, Y1, Z1, x2, y2, one = vs(names)
    Ra = add_affb(b3(b), (X1, Y1, Z1), (x2, y2))
    Rb = addb(b3(b), (X1, Y1, Z1), (x2, y2, one))
    for i, nm in enumerate('xyz'):
        ob.append(('aff_eq_' + nm, names, Ra[i], Rb[i], [(one, ONE)], [6, 0, 1, 2, 3, 4, 5]))

    # projective inputs on the curve give an output on the curve
    names = ['b', 'X1', 'Y1', 'Z1', 'X2', 'Y2', 'Z2']
    b, X1, Y1, Z1, X2, Y2, Z2 = vs(names)
    P = (X1, Y1, Z1)
    # (add's projective on-curve identity has a 3,150-monomial certificate, beyond what the
    # checker's stack and the kernel's fuel take; README.md, "Not proven")
    oc = oncurvep(b, doubleb(b3(b), P))
    ob.append(('dbl_on', names, oc[0], oc[1], [oncurvep(b, P)], [2, 1, 3, 0, 4, 5, 6]))
    return ob


def main():
    """Writes one file per obligation, certs/<name>.bend: the certificate (emit) and the
    lemma lem_<name> it proves (emit_lemma). One file with all of them is too much for the
    checker's stack."""
    only = set(sys.argv[1:])
    here = os.path.dirname(os.path.abspath(__file__))
    os.makedirs(os.path.join(here, 'certs'), exist_ok=True)
    for name, names, t1, t2, rels, order in obligations():
        if only and name not in only:
            continue
        t = time.time()
        text, size, ncp = emit(name, len(names), t1, t2, rels, order)
        print('%-14s %5d monomials %4d checkpoints %6.1f s' % (name, size, ncp, time.time() - t), file=sys.stderr)
        with open(os.path.join(here, 'certs', name + '.bend'), 'w') as f:
            f.write(HEADER % {'root': '../..'})
            f.write('\n# GENERATED by ../gen.py. Do not edit. %s: %d monomials, %d checkpoints\n\n' % (name, size, ncp))
            f.write(text)
            f.write('\n')
            f.write(emit_lemma(name, names, t1, t2, rels))


if __name__ == '__main__':
    main()
