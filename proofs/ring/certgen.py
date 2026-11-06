"""Certificates for ring/cert.bend's cert_ok, and Bend output of expressions.

Shared by the generators of the directories that use ring/ (curve/gen.py, ...). Needs sympy.

An expression is a tuple: ('v', i) | ('c', n) | ('+', a, b) | ('-', a, b) | ('*', a, b) |
('neg', a). cert(t1, t2, rels, nvars) finds integer polynomials c_j with
t1 - t2 = sum_j c_j (a_j - b_j) (sympy's division with a lex order; the relations are
chosen by the caller so that this succeeds), lifts them to Nat polynomials (x - y read as
x + bp*y, -1 as bp), and returns (cs, K1, K2) for cert_ok, as Nat polynomials in the
variables and bp. Nothing here is trusted: cert_ok re-checks the identity by normalising.
"""
import sympy as sp

PP = sp.Symbol('pp')


def V(i):
    return ('v', i)


def C(n):
    return ('c', n)


def add(a, b):
    return ('+', a, b)


def sub(a, b):
    return ('-', a, b)


def mul(a, b):
    return ('*', a, b)


def syms(n):
    return [sp.Symbol('x%d' % i) for i in range(n)]


def tosym(t, xs):
    k = t[0]
    if k == 'v':
        return xs[t[1]]
    if k == 'c':
        return sp.Integer(t[1])
    if k == 'neg':
        return -tosym(t[1], xs)
    a, b = tosym(t[1], xs), tosym(t[2], xs)
    return a + b if k == '+' else a - b if k == '-' else a * b


def nlift(t, xs):
    """expr.bend's nv: subtraction read as x + bp*y."""
    k = t[0]
    if k == 'v':
        return xs[t[1]]
    if k == 'c':
        return sp.Integer(t[1])
    if k == 'neg':
        return PP * nlift(t[1], xs)
    a, b = nlift(t[1], xs), nlift(t[2], xs)
    return a + b if k == '+' else a + PP * b if k == '-' else a * b


def split(f, gens):
    P = sp.Poly(sp.expand(f), *gens)
    pos = sp.Integer(0)
    neg = sp.Integer(0)
    for m, c in P.terms():
        mono = sp.prod([g ** e for g, e in zip(gens, m)])
        if c > 0:
            pos += c * mono
        else:
            neg += -c * mono
    return pos, neg


def _tracked(e, rs, gens):
    """Buchberger with cofactors: returns q with e == sum q_j rs_j (over Q), when e lies in
    the ideal. Used when plain division by rs leaves a remainder."""
    k = len(rs)
    P = lambda f: sp.Poly(f, *gens, domain='QQ')
    basis = [(P(g), [P(1 if i == j else 0) for j in range(k)]) for i, g in enumerate(rs)]

    def reduce(f, cof):
        f = P(f.as_expr())
        cof = list(cof)
        changed = True
        while changed and not f.is_zero:
            changed = False
            for m, c in f.terms(order='lex'):
                for g, gc in basis:
                    lm = g.monoms(order='lex')[0]
                    if all(a >= b for a, b in zip(m, lm)):
                        lc = g.coeffs(order='lex')[0]
                        t = P(sp.Rational(c) / lc * sp.prod([x ** (a - b) for x, a, b in zip(gens, m, lm)]))
                        f = f - t * g
                        cof = [a - t * b for a, b in zip(cof, gc)]
                        changed = True
                        break
                if changed:
                    break
        return f, cof

    pairs = [(i, j) for i in range(len(basis)) for j in range(i)]
    while pairs:
        i, j = pairs.pop()
        (f, fc), (g, gcf) = basis[i], basis[j]
        mf, mg = f.monoms(order='lex')[0], g.monoms(order='lex')[0]
        lcm = [max(a, b) for a, b in zip(mf, mg)]
        uf = P(sp.prod([x ** (a - b) for x, a, b in zip(gens, lcm, mf)]) / f.coeffs(order='lex')[0])
        ug = P(sp.prod([x ** (a - b) for x, a, b in zip(gens, lcm, mg)]) / g.coeffs(order='lex')[0])
        s = uf * f - ug * g
        sc = [uf * a - ug * b for a, b in zip(fc, gcf)]
        s, sc = reduce(s, sc)
        if not s.is_zero:
            basis.append((s, sc))
            n = len(basis) - 1
            pairs.extend((n, m) for m in range(n))
        if len(basis) > 40:
            raise ValueError('Groebner basis too large')
    neg = [P(0) for _ in range(k)]
    r, cof = reduce(P(e), neg)
    if not r.is_zero:
        raise ValueError('not in the ideal: remainder %s' % r.as_expr())
    return [sp.expand(-c.as_expr()) for c in cof]


def cert(t1, t2, rels, nvars, order):
    """order: variable indices, highest first, for the lex order of the division."""
    xs = syms(nvars)
    gens = [xs[i] for i in order]
    e = sp.expand(tosym(t1, xs) - tosym(t2, xs))
    rs = [sp.expand(tosym(a, xs) - tosym(b, xs)) for a, b in rels]
    if rs:
        q, r = sp.reduced(e, rs, *gens, order='lex')
        if r != 0:
            q = _tracked(e, rs, gens)
            r = sp.expand(e - sum((c * g for c, g in zip(q, rs)), sp.Integer(0)))
    else:
        q, r = [], e
    if r != 0:
        raise ValueError('not in the ideal: remainder %s' % r)
    for c in q:
        if any(not co.is_integer for co in sp.Poly(sp.expand(c), *gens).coeffs()):
            raise ValueError('certificate needs a non-integer coefficient')
    cs = []
    for c in q:
        pos, neg = split(c, gens)
        cs.append(sp.expand(pos + PP * neg))
    n1, n2 = nlift(t1, xs), nlift(t2, xs)
    na = [nlift(a, xs) for a, _ in rels]
    nb = [nlift(b, xs) for _, b in rels]
    rhs = sp.expand(n2 - n1 + sum((c * (a - b) for c, a, b in zip(cs, na, nb)), sp.Integer(0)))
    allg = [PP] + xs
    D, rem = sp.div(sp.Poly(rhs, *allg), sp.Poly(1 + PP, *allg))
    assert rem.is_zero
    K1, K2 = split(D.as_expr(), allg)
    L = sp.expand(n1 + sum((c * b for c, b in zip(cs, nb)), sp.Integer(0)) + K1 * (1 + PP))
    R = sp.expand(n2 + sum((c * a for c, a in zip(cs, na)), sp.Integer(0)) + K2 * (1 + PP))
    assert sp.expand(L - R) == 0
    size = len(sp.Poly(L, *allg).terms()) if L != 0 else 0
    return cs, K1, K2, size


# --- Bend output -------------------------------------------------------------------------

def bend_expr(t):
    k = t[0]
    if k == 'v':
        return 'X.V{%dn}' % t[1]
    if k == 'c':
        return 'X.C{%dn}' % t[1]
    if k == 'neg':
        return 'X.Ng{%s}' % bend_expr(t[1])
    tag = {'+': 'Ad', '-': 'Sb', '*': 'Ml'}[k]
    return 'X.%s{%s, %s}' % (tag, bend_expr(t[1]), bend_expr(t[2]))


def _balanced(items, op, empty):
    if not items:
        return empty
    while len(items) > 1:
        nxt = []
        for i in range(0, len(items) - 1, 2):
            nxt.append('X.%s{%s, %s}' % (op, items[i], items[i + 1]))
        if len(items) % 2:
            nxt.append(items[-1])
        items = nxt
    return items[0]


def bend_poly(f, nvars):
    """A Nat polynomial in pp and x0.. as an expression (a balanced sum of products)."""
    xs = syms(nvars)
    allg = [PP] + xs
    f = sp.expand(f)
    if f == 0:
        return 'X.C{0n}'
    terms = []
    for m, c in sp.Poly(f, *allg).terms():
        assert c > 0
        fac = []
        if c != 1:
            fac.append('X.C{%dn}' % c)
        for g, e in enumerate(m):
            atom = 'X.Pp{}' if g == 0 else 'X.V{%dn}' % (g - 1)
            fac.extend([atom] * e)
        if not fac:
            fac = ['X.C{1n}']
        terms.append(_balanced(fac, 'Ml', 'X.C{1n}'))
    return _balanced(terms, 'Ad', 'X.C{0n}')


def bend_list(items, ty='X.E'):
    if not items:
        return 'Nil{}'
    return '[' + ', '.join(items) + ']'


# --- ring/poly.bend's normal form, computed here -------------------------------------------
# A polynomial is a dict {monomial: coefficient}; a monomial is a tuple of exponents over
# [bp, x0, x1, ...] without trailing zeros (poly.bend's representation).

def _trim(m):
    m = list(m)
    while m and m[-1] == 0:
        m.pop()
    return tuple(m)


def _mm(a, b):
    n = max(len(a), len(b))
    return _trim(tuple((a[i] if i < len(a) else 0) + (b[i] if i < len(b) else 0) for i in range(n)))


def p_add(p, q):
    r = dict(p)
    for m, c in q.items():
        r[m] = r.get(m, 0) + c
    return r


def p_mul(p, q):
    r = {}
    for m1, c1 in p.items():
        for m2, c2 in q.items():
            m = _mm(m1, m2)
            r[m] = r.get(m, 0) + c1 * c2
    return r


PVAR0 = {(1,): 1}


def p_var(i):
    return {tuple([0] * i + [1]): 1}


def nf_py(t):
    """poly.bend's nf, as a dict."""
    k = t[0]
    if k == 'v':
        return p_var(1 + t[1])
    if k == 'c':
        return {(): t[1]} if t[1] else {}
    if k == 'pp':
        return dict(PVAR0)
    if k == 'neg':
        return p_mul(PVAR0, nf_py(t[1]))
    a, b = nf_py(t[1]), nf_py(t[2])
    if k == '+':
        return p_add(a, b)
    if k == '-':
        return p_add(a, p_mul(PVAR0, b))
    return p_mul(a, b)


def _key(m, n):
    return tuple(m) + (0,) * (n - len(m))


def bend_nf(p):
    """The normal form as poly.bend writes it: sorted by the lex order on monomials."""
    if not p:
        return 'Nil{}'
    n = max(len(m) for m in p)
    items = sorted(p.items(), key=lambda mc: _key(mc[0], n))
    return '[' + ', '.join('P.Tm{%dn, %s}' % (c, '[' + ', '.join('%dn' % e for e in m) + ']' if m else 'Nil{}') for m, c in items) + ']'


def poly_term(f, nvars):
    """A sympy Nat polynomial in pp and x0.. as an expression tuple (balanced sum of products)."""
    xs = syms(nvars)
    allg = [PP] + xs
    f = sp.expand(f)
    if f == 0:
        return ('c', 0)
    terms = []
    for m, c in sp.Poly(f, *allg).terms():
        assert c > 0
        fac = []
        if c != 1:
            fac.append(('c', int(c)))
        for g, e in enumerate(m):
            atom = ('pp',) if g == 0 else ('v', g - 1)
            fac.extend([atom] * e)
        if not fac:
            fac = [('c', 1)]
        terms.append(_bal(fac, '*'))
    return _bal(terms, '+')


def _bal(items, op):
    while len(items) > 1:
        nxt = [(op, items[i], items[i + 1]) for i in range(0, len(items) - 1, 2)]
        if len(items) % 2:
            nxt.append(items[-1])
        items = nxt
    return items[0]


def _sum(items):
    t = ('c', 0)
    for it in reversed(items):
        t = ('+', it, t)
    return t


def lhs_term(t1, cs, rels, k1):
    """cert.bend's lhs(t1, cs, rs, k1), unfolded."""
    return ('+', ('+', t1, _sum([('*', c, b) for c, (a, b) in zip(cs, rels)])), ('*', k1, ('+', ('c', 1), ('pp',))))


def rhs_term(t2, cs, rels, k2):
    return ('+', ('+', t2, _sum([('*', c, a) for c, (a, b) in zip(cs, rels)])), ('*', k2, ('+', ('c', 1), ('pp',))))


class Emitter:
    """Writes expressions as Bend defs, with a checkpoint lemma {P.nf(node) == literal} at
    every node whose normal form has at least `big` terms (or has a checkpointed child), so
    that no single conversion has to normalise more than one operation on literals."""

    def __init__(self, prefix, big=12):
        self.prefix = prefix
        self.big = big
        self.out = []
        self.memo = {}
        self.n = 0

    def node(self, t):
        """Returns (bend expression, nf dict, checkpoint name or None)."""
        if t in self.memo:
            return self.memo[t]
        k = t[0]
        if k == 'v':
            r = ('X.V{%dn}' % t[1], nf_py(t), None)
        elif k == 'c':
            r = ('X.C{%dn}' % t[1], nf_py(t), None)
        elif k == 'pp':
            r = ('X.Pp{}', dict(PVAR0), None)
        else:
            subs = [self.node(s) for s in t[1:]]
            tag = {'+': 'Ad', '-': 'Sb', '*': 'Ml', 'neg': 'Ng'}[k]
            expr = 'X.%s{%s}' % (tag, ', '.join(s[0] for s in subs))
            if k == 'neg':
                p = p_mul(PVAR0, subs[0][1])
            elif k == '+':
                p = p_add(subs[0][1], subs[1][1])
            elif k == '-':
                p = p_add(subs[0][1], p_mul(PVAR0, subs[1][1]))
            else:
                p = p_mul(subs[0][1], subs[1][1])
            ck = None
            if len(p) >= self.big or any(s[2] for s in subs):
                self.n += 1
                nm = '%s_%d' % (self.prefix, self.n)
                self.out.append('def %s() -> X.E:\n  %s\n' % (nm, expr))
                self.out.append('def %s_w() -> +List<P.Tm>:\n  %s\n' % (nm, bend_nf(p)))
                lines = ['def %s_ok() -> {P.nf(%s()) == %s_w() : +List<P.Tm>}:' % (nm, nm, nm)]
                ops = {'+': 'P.plus(%s, %s)', '*': 'P.pmul(%s, %s)', '-': 'P.plus(%s, P.pmul(P.pvar(0n), %s))', 'neg': 'P.pmul(P.pvar(0n), %s)'}[k]
                cur = ['P.nf(%s)' % s[0] for s in subs]
                for i, s in enumerate(subs):
                    if s[2]:
                        motive = list(cur)
                        motive[i] = '_'
                        lines.append('  %%Equal.sym(+List<P.Tm>, P.nf(%s()), %s_w(), %s_ok()) : {%s == %s_w() : +List<P.Tm>}' % (s[2], s[2], s[2], ops % tuple(motive), nm))
                        cur[i] = '%s_w()' % s[2]
                lines.append('  {==}\n')
                self.out.append('\n'.join(lines))
                expr = '%s()' % nm
                ck = nm
            r = (expr, p, ck)
        self.memo[t] = r
        return r


def emit(name, nvars, t1, t2, rels, order, big=40):
    """Bend defs for one obligation: ev(t1) == ev(t2) modulo rels (a list of (a, b) pairs).
    Use as R.cert_ok2(bp, env, hc, name_t1(), name_t2(), name_cs(), name_rs(), name_k1(),
    name_k2(), holds, name_lt(), name_rt(), name_el(), name_er(), name_h())."""
    cs, K1, K2, size = cert(t1, t2, rels, nvars, order)
    cst = [poly_term(c, nvars) for c in cs]
    k1t, k2t = poly_term(K1, nvars), poly_term(K2, nvars)
    em = Emitter(name + '_n', big=big)
    L = lhs_term(t1, cst, rels, k1t)
    R = rhs_term(t2, cst, rels, k2t)
    le, lp, lc = em.node(L)
    re_, rp, rc = em.node(R)
    if lp != rp:
        raise ValueError('normal forms differ for ' + name)
    ex = lambda t: em.node(t)[0]
    out = list(em.out)
    out.append('def %s_t1() -> X.E:\n  %s\n' % (name, ex(t1)))
    out.append('def %s_t2() -> X.E:\n  %s\n' % (name, ex(t2)))
    out.append('def %s_rs() -> +List<R.Rel>:\n  %s\n' % (name, bend_list(['R.Rel{%s, %s}' % (ex(a), ex(b)) for a, b in rels])))
    out.append('def %s_cs() -> +List<X.E>:\n  %s\n' % (name, bend_list([ex(c) for c in cst])))
    out.append('def %s_k1() -> X.E:\n  %s\n' % (name, ex(k1t)))
    out.append('def %s_k2() -> X.E:\n  %s\n' % (name, ex(k2t)))
    out.append('def %s_lt() -> X.E:\n  %s\n' % (name, le))
    out.append('def %s_rt() -> X.E:\n  %s\n' % (name, re_))
    out.append('def %s_el() -> {%s_lt() == R.lhs(%s_t1(), %s_cs(), %s_rs(), %s_k1()) : X.E}:\n  {==}\n' % ((name,) * 6))
    out.append('def %s_er() -> {%s_rt() == R.rhs(%s_t2(), %s_cs(), %s_rs(), %s_k2()) : X.E}:\n  {==}\n' % ((name,) * 6))
    if lc and rc:
        proof = 'Equal.trans(+List<P.Tm>, P.nf(%s_lt()), %s_w(), P.nf(%s_rt()), %s_ok(), Equal.sym(+List<P.Tm>, P.nf(%s_rt()), %s_w(), %s_ok()))' % (name, lc, name, lc, name, rc, rc)
    else:
        proof = '{==}'
    out.append('def %s_h() -> {P.nf(%s_lt()) == P.nf(%s_rt()) : +List<P.Tm>}:\n  %s\n' % (name, name, name, proof))
    return '\n'.join(out), size, em.n


HEADER = '''import Base
import %(ring)s/expr.bend as X
import %(ring)s/poly.bend as P
import %(ring)s/cert.bend as R
'''
