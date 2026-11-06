"""Bend lemmas over Nat-level (T.fadd, ...) statements, proven by ring/cert.bend's cert_ok2.

emit_lemma writes lem_<name>: for canonical variables and hypotheses stated the way model
code states them, the identity t1 == t2 holds in Z/p. The certificate itself comes from
certgen.emit (same name). Constants 0 and 1 are written as the literals 0n and 1n, and may
appear only as a whole side; any other constant n is n mod p.
"""

HEADER = '''import Base
import %(root)s/prims/natlib.bend as L
import %(root)s/opt_gates/term.bend as T
import %(root)s/ring/expr.bend as X
import %(root)s/ring/poly.bend as P
import %(root)s/ring/cert.bend as R

def one_c(+bp: Nat, +l1: L.Le(1n, bp)) -> {Nat.mod(1n, 1n+bp) == 1n : Nat}:
  L.mod_small(1n, bp, l1)
'''


def natexpr(t, names):
    k = t[0]
    if k == 'v':
        return names[t[1]]
    if k == 'c':
        return '%dn' % t[1] if t[1] in (0, 1) else 'Nat.mod(%dn, 1n+bp)' % t[1]
    if k == 'neg':
        return 'T.fneg(bp, %s)' % natexpr(t[1], names)
    op = {'+': 'T.fadd', '-': 'T.fsub', '*': 'T.fmul'}[k]
    return '%s(bp, %s, %s)' % (op, natexpr(t[1], names), natexpr(t[2], names))


def _const01(t):
    return t[0] == 'c' and t[1] in (0, 1)


def _inner_ok(t):
    if t[0] == 'c':
        return t[1] not in (0, 1)
    if t[0] == 'v':
        return True
    return all(_inner_ok(s) for s in t[1:])


def _to_mod(a_s, k, h):
    """{a == kn} to {a == k mod p}, for k = 0, 1."""
    fact = 'one_c(bp, l1)' if k == 1 else 'X.mod_zero(bp)'
    return 'Equal.trans(Nat, %s, %dn, Nat.mod(%dn, 1n+bp), %s, Equal.sym(Nat, Nat.mod(%dn, 1n+bp), %dn, %s))' % (a_s, k, k, h, k, k, fact)


def emit_lemma(name, names, t1, t2, rels):
    for t in [t1, t2] + [s for r in rels for s in r]:
        assert _const01(t) or _inner_ok(t), 'constant 0/1 inside ' + name
    assert not _const01(t1)
    args = ['+bp: Nat', '+l1: L.Le(1n, bp)'] + ['+%s: Nat' % v for v in names] + ['+l_%s: L.Le(%s, bp)' % (v, v) for v in names]
    for i, (a, b) in enumerate(rels):
        args.append('h%d: {%s == %s : Nat}' % (i, natexpr(a, names), natexpr(b, names)))
    lhs_s, rhs_s = natexpr(t1, names), natexpr(t2, names)
    lines = ['def lem_%s(%s) -> {%s == %s : Nat}:' % (name, ', '.join(args), lhs_s, rhs_s)]
    env = '[%s]' % ', '.join(names)
    canon = 'Unit{}'
    for v in reversed(names):
        canon = '(l_%s, %s)' % (v, canon)
    lines.append('  +hc = {%s : X.Canon(bp, %s)}' % (canon, env))
    holds = 'Unit{}'
    for i, (a, b) in reversed(list(enumerate(rels))):
        assert not _const01(a)
        h = 'h%d' % i
        if _const01(b):
            h = _to_mod(natexpr(a, names), b[1], h)
        holds = '(%s, %s)' % (h, holds)
    lines.append('  +hr = {%s : R.Holds(bp, %s, %s_rs())}' % (holds, env, name))
    c = 'R.cert_nv(bp, %s, hc, %s_t1(), %s_t2(), %s_cs(), %s_rs(), %s_k1(), %s_k2(), hr, %s_lt(), %s_rt(), %s_el(), %s_er(), %s_hn(bp, %s))' % ((env,) + (name,) * 11 + (env,))
    if _const01(t2):
        k = t2[1]
        fact = 'one_c(bp, l1)' if k == 1 else 'X.mod_zero(bp)'
        lines.append('  Equal.trans(Nat, %s, Nat.mod(%dn, 1n+bp), %dn, %s, %s)' % (lhs_s, k, k, c, fact))
    else:
        lines.append('  ' + c)
    return '\n'.join(lines) + '\n'
