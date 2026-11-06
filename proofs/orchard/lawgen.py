"""Generate per-gate soundness laws, their proofs and non-vacuity witnesses for Orchard gates.

Used by ../orchard_ecc/gen.py, ../orchard_canon/gen.py and ../orchard_hash/gen.py. Each
directory lists the gates it covers; for every gate this module emits

  gates_model.bend  the generated gate polynomials exactly as ./gates.py parses them from
                    zcash/halo2/gen/orchard_cs.bend: the compressed selector factor becomes
                    the variable `sel`, constants below 2^14 stay literals, larger constants
                    become parameters (`t250` = 2^250, `tP` = t_P, ...) whose values the
                    script asserts and lists,
  LAWS.bend         law gate_<g>: with the selector invertible, canonical cells, and every
                    polynomial of the gate vanishing on the row, the per-polynomial facts
                    below hold together; and law gate_<g>_satisfiable: every hypothesis of
                    gate_<g> holds at once, at p = 11, for a concrete row found here,
  PROOF.bend        both proofs.

Each polynomial body is read as one of these shapes (nothing else is accepted):
  X - Y                 (fadd(X, fsub(0, Y)))   =>  X == Y, or A == B + Y when X = A - B
  x * (1 - x)                                   =>  x == 0 or x == 1         (uses NZD once)
  x (1 - x)(2 - x)...(k - x)                    =>  x <= k as an integer      (uses NZD k times)
  b * body, b a cell, listed in IMPL           =>  b == 1 implies the fact of body
  X * Y, listed in EITHER                       =>  the fact of X or the fact of Y (NZD once)
  anything else                                 =>  body == 0 (kept as is)

A Bend closure is affine, so a law that splits k products takes k copies of the hypothesis
F.NZD(pp) (nzd0, nzd1, ...): all the same proposition, assumed once each.
"""
import os, sys, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gates as G

P = G.P
TP = P - 2**254
Q = 0x40000000000000000000000000000000224698fc0994a8dd8c46eb2100000001
TQ = Q - 2**254
SMALL = 2**14
PNV = 11          # the prime of the non-vacuity witnesses
PPNV = PNV - 1

SRC = open(os.path.join(HERE, "..", "..", "zcash", "halo2", "gen", "orchard_cs.bend")).read()
import re
def _tbl(name):
    return [int(x) for x in re.search(rf"def {name}\(\) -> \+List<U32>:\n  \[([\d, ]+)\]", SRC).group(1).split(",")]
ACOL, AROT = _tbl("ADVICE_QUERY_COLUMN"), _tbl("ADVICE_QUERY_ROTATION")
FCOL = _tbl("FIXED_QUERY_COLUMN")

def query_doc(kind, i):
    if kind == "a":
        r = AROT[i]
        r = r - 2**32 if r >= 2**31 else r
        return f"advice column {ACOL[i]}, rotation {r:+d}"
    if kind == "f":
        return f"fixed column {FCOL[i]}"
    return f"instance column 0"

def const_name(v):
    if v == TP:
        return "tP"
    if v == TQ:
        return "tQ"
    if v & (v - 1) == 0:
        return f"t{v.bit_length() - 1}"
    if v == (P + 1) // 2:
        return "inv2"
    return f"c{v:064x}"[:9]

# ---------------------------------------------------------------- expressions
def is_c(e, v=None):
    return e[0] == "c" and (v is None or e[1] == v)

def is_neg(e):            # fsub(0, Y)
    return e[0] == "fsub" and is_c(e[1], 0)

def is_q(e):
    return e[0] == "q"

def qname(e):
    return f"{e[1]}{e[2]}"

def walk_consts(e, acc):
    if e[0] == "c" and e[1] >= SMALL:
        acc[const_name(e[1])] = e[1]
    elif e[0] in ("fadd", "fsub", "fmul"):
        walk_consts(e[1], acc); walk_consts(e[2], acc)
    return acc

def vkey(v):
    return ("afi".index(v[0]), v[1])

class Ctx:
    """Per-law bookkeeping: the hypotheses a proof term needs."""
    def __init__(self):
        self.nzd = 0
        self.l1 = False
        self.lc = set()        # small constants c needing Le(c, pp)
        self.lk = set()        # big constants needing Le(K, pp)
        self.lv = set()        # cells needing Le(v, pp)
        self.helpers = []
        self.uid = 0
        self.lam = 0
    def new_nzd(self):
        n = f"nzd{self.nzd}"
        self.nzd += 1
        return n

def B(e, P_="1n+pp"):
    """Bend text of an expression."""
    t = e[0]
    if t == "q":
        return qname(e)
    if t == "c":
        return f"{e[1]}n" if e[1] < SMALL else const_name(e[1])
    op = {"fadd": "F.fadd", "fsub": "F.fsub", "fmul": "F.fmul"}[t]
    return f"{op}({P_}, {B(e[1], P_)}, {B(e[2], P_)})"

def LE(e, cx):
    """Proof that e is canonical, L.Le(e, pp)."""
    t = e[0]
    if t == "q":
        cx.lv.add((e[1], e[2]))
        return f"l{qname(e)}"
    if t == "c":
        if e[1] == 0:
            return "R.le_0(pp)"
        if e[1] == 1:
            cx.l1 = True
            return "l1"
        if e[1] < SMALL:
            cx.lc.add(e[1])
            return f"lc{e[1]}"
        cx.lk.add(e[1])
        return f"l{const_name(e[1])}"
    return f"E.le_{t}(pp, {B(e[1])}, {B(e[2])})"

def range_of(e):
    """x (1 - x)(2 - x)...(k - x)  ->  (x, k), else None."""
    fs = []
    while e[0] == "fmul" and e[2][0] == "fadd" and is_c(e[2][1]) and is_neg(e[2][2]):
        fs.append((e[2][1][1], e[2][2][2]))
        e = e[1]
    x = e
    fs.reverse()
    if len(fs) < 1 or any(xx != x for _, xx in fs) or [c for c, _ in fs] != list(range(1, len(fs) + 1)):
        return None
    return x, len(fs)

def fact(e, cx, impl=(), either=False):
    """(type text, proof builder z -> term) for the fact `e == 0`."""
    if e[0] == "fadd" and is_neg(e[2]):
        X, Y = e[1], e[2][2]
        if X[0] == "fadd" and is_neg(X[2]):
            A, Bb = X[1], X[2][2]
            T = f"{{{B(A)} == F.fadd(1n+pp, {B(Bb)}, {B(Y)}) : Nat}}"
            return T, lambda z: f"F.neg_eq(pp, {B(A)}, {B(Bb)}, {B(Y)}, {LE(A, cx)}, {LE(Bb, cx)}, F.neg_zero(pp, {B(X)}, {B(Y)}, {LE(X, cx)}, {LE(Y, cx)}, {z}))"
        T = f"{{{B(X)} == {B(Y)} : Nat}}"
        return T, lambda z: f"F.neg_zero(pp, {B(X)}, {B(Y)}, {LE(X, cx)}, {LE(Y, cx)}, {z})"
    r = range_of(e)
    if r and r[1] == 1:
        x = r[0]
        T = f"Either<&1, &1, {{{B(x)} == 0n : Nat}}, {{{B(x)} == 1n : Nat}}>"
        def mk(z, x=x):
            cx.l1 = True
            return f"E.boolean(pp, {B(x)}, {cx.new_nzd()}, l1, {LE(x, cx)}, {z})"
        return T, mk
    if r:
        x, k = r
        return f"L.Le({B(x)}, {k}n)", lambda z, x=x, k=k: range_proof(x, k, z, cx)
    if e[0] == "fmul" and is_q(e[1]) and qname(e[1]) in impl:
        b, X = e[1], e[2]
        Ti, mki = fact(X, cx, impl)
        cx.lam += 1
        zz = f"z{cx.lam}"
        T = f"({{{B(b)} == 1n : Nat}} -> {Ti})"
        return T, lambda z: f"{zz} => {mki(f'R.one_mul_zero(pp, {B(b)}, {B(X)}, {LE(X, cx)}, {zz}, {z})')}"
    if e[0] == "fmul" and either:
        X, Y = e[1], e[2]
        Tx, mkx = fact(X, cx)
        Ty, mky = fact(Y, cx)
        T = f"Either<&1, &1, {Tx}, {Ty}>"
        def mk(z):
            cx.uid += 1
            h = f"either_{cx.gate}_{cx.uid}"
            n = cx.new_nzd()
            split = f"{n}({B(X)}, {B(Y)}, {LE(X, cx)}, {LE(Y, cx)}, {z})"
            cx.helpers.append((h, Tx, Ty, mkx("z"), mky("z"), f"Either<&1, &1, {{{B(X)} == 0n : Nat}}, {{{B(Y)} == 0n : Nat}}>", T))
            return f"{h}(CTXARGS, {split})"
        return T, mk
    T = f"{{{B(e)} == 0n : Nat}}"
    return T, lambda z: z

def range_proof(x, k, z, cx):
    """x (1 - x) ... (k - x) == 0  ==>  L.Le(x, k): one helper per factor, each splitting
    with one NZD copy."""
    cx.lc.add(k) if k > 1 else None
    if k == 1:
        cx.l1 = True
    cx.uid += 1
    base = f"range_{cx.gate}_{cx.uid}"
    def prod(j):
        e = x
        for c in range(1, j + 1):
            e = ("fmul", e, ("fadd", ("c", c), ("fsub", ("c", 0), x)))
        return e
    lk = "l1" if k == 1 else f"lc{k}"
    nz = [cx.new_nzd() for _ in range(k)]
    # helper j receives Either<{prod(j-1) == 0}, {(j - x) == 0}> and nzd copies for levels < j
    for j in range(1, k + 1):
        fj = ("fadd", ("c", j), ("fsub", ("c", 0), x))
        lej = f"R.le_trans({j}n, {k}n, pp, ({k - j}n, {{==}}), {lk})"
        inr = f"R.le_eq({j}n, {B(x)}, {k}n, F.neg_zero(pp, {j}n, {B(x)}, {lej}, {LE(x, cx)}, z), ({k - j}n, {{==}}))"
        if j == 1:
            inl = f"R.le_eq(0n, {B(x)}, {k}n, Equal.sym(Nat, {B(x)}, 0n, z), ({k}n, {{==}}))"
        else:
            pj1, fj1 = prod(j - 2), ("fadd", ("c", j - 1), ("fsub", ("c", 0), x))
            inl = f"{base}_{j - 1}(CTXARGS, {', '.join(nz[:j - 2] + [''])}{nz[j - 2]}({B(pj1)}, {B(fj1)}, {LE(pj1, cx)}, {LE(fj1, cx)}, z))".replace(", , ", ", ")
        cx.helpers.append(("range", f"{base}_{j}", nz[:j - 1], f"Either<&1, &1, {{{B(prod(j - 1))} == 0n : Nat}}, {{{B(fj)} == 0n : Nat}}>", f"L.Le({B(x)}, {k}n)", inl, inr))
    pk1, fk = prod(k - 1), ("fadd", ("c", k), ("fsub", ("c", 0), x))
    args = ", ".join(nz[:k - 1])
    args = args + ", " if args else ""
    return f"{base}_{k}(CTXARGS, {args}{nz[k - 1]}({B(pk1)}, {B(fk)}, {LE(pk1, cx)}, {LE(fk, cx)}, {z}))"

# ---------------------------------------------------------------- evaluation mod 11
MAXRAW = [0]
def ev(e, env, p):
    t = e[0]
    if t == "q":
        return env[qname(e)]
    if t == "c":
        return e[1] % p if e[1] >= SMALL else e[1]
    x, y = ev(e[1], env, p), ev(e[2], env, p)
    MAXRAW[0] = max(MAXRAW[0], x * y if t == "fmul" else x + y)
    if t == "fadd":
        return (x + y) % p
    if t == "fsub":
        return (x + max(p - y, 0)) % p
    return (x * y) % p

def find_witness(polys, names, seed=1, tries=4000, fixed=None):
    """A row over F_11 on which every polynomial (with sel = 1) vanishes."""
    rnd = random.Random(seed)
    fixed = fixed or {}
    for _ in range(tries):
        env = {n: (fixed[n] if n in fixed else rnd.choice([0, 0, 1] + list(range(PNV)))) for n in names}
        for _ in range(60):
            MAXRAW[0] = 0
            bad = [b for b in polys if ev(b, env, PNV) != 0]
            if not bad and MAXRAW[0] <= 2000:
                return env
            if not bad:
                break
            b = rnd.choice(bad)
            vs = sorted({qname(v) for v in vars_in(b)} - set(fixed))
            if not vs:
                break
            v = rnd.choice(vs)
            best = None
            for val in range(PNV):
                env[v] = val
                cnt = sum(ev(bb, env, PNV) != 0 for bb in polys)
                if best is None or cnt < best[0] or (cnt == best[0] and rnd.random() < 0.3):
                    best = (cnt, val)
            env[v] = best[1]
    raise SystemExit(f"no witness found for {names}")

def vars_in(e, acc=None):
    acc = set() if acc is None else acc
    if e[0] == "q":
        acc.add(e)
    elif e[0] in ("fadd", "fsub", "fmul"):
        vars_in(e[1], acc); vars_in(e[2], acc)
    return acc

# ---------------------------------------------------------------- emission
class Gate:
    def __init__(self, g, title, polys, impl=(), either=(), split_sel=False, same_as=None, note=""):
        self.g, self.title, self.polys, self.impl, self.either = g, title, polys, set(impl), set(either)
        self.split_sel, self.same_as, self.note = split_sel, same_as or [], note

def emit(dirname, gates, header, model_only=(), extra_imports=()):
    trees = G.parse()
    model = ["import Base", "import ../orchard/fieldmodel.bend as F", "",
             f"# GENERATED by gen.py (with ../orchard/lawgen.py) from zcash/halo2/gen/orchard_cs.bend. Do not edit.",
             "# Each gate_<g>_<p> is the generated polynomial with its compressed selector factor (identical",
             "# for every polynomial of the gate; checked) replaced by `sel`, small constants as literals and",
             "# large ones as the parameters listed below, over p = 1 + pp.", ""]
    laws = ["import Base", "import ../prims/natlib.bend as L", "import ../orchard/fieldmodel.bend as F",
            "import ./gates_model.bend as G", ""] + header + [""]
    proof = ["import Base", "import ../prims/natlib.bend as L", "import ../orchard/fieldmodel.bend as F",
             "import ../orchard/evals.bend as E", "import ../orchard/rowlemmas.bend as R",
             "import ../orchard/nzd11.bend as Z", "import ./gates_model.bend as G", "import ./LAWS.bend as Laws"] \
            + [f"import {f} as {a}" for f, a in extra_imports] + ["",
             "# GENERATED by gen.py (with ../orchard/lawgen.py). Do not edit."] \
            + (["# The import" + ("s" if len(extra_imports) > 1 else "") + " above bring" + ("" if len(extra_imports) > 1 else "s") + " the hand-written laws into this check."] if extra_imports else []) + [""]
    consts_all = {}
    summary = []
    for gt in gates:
        g = gt.g
        names = [f"gate_{g}_{i}" for i in gt.polys]
        sel = None
        bodies, fulls = [], []
        for n in names:
            e = trees[n]
            assert e[0] == "fmul", n
            if gt.split_sel:
                s, x = e[1][1], e[1][2]
                assert e[1][0] == "fmul" and is_q(x), n
                body = ("fmul", x, e[2])
            else:
                s, body = e[1], e[2]
            assert sel is None or sel == s, f"{n}: selector differs within gate {g}"
            sel = s
            bodies.append(body)
        # identical gates elsewhere in the circuit (same polynomials, other selector)
        for other in gt.same_as:
            for i, n in zip(gt.polys, names):
                assert trees[f"gate_{other}_{i}"][2] == trees[n][2], (other, n)
            assert f"gate_{other}_{len(gt.polys)}" not in trees, other
        omitted = [k for k in range(64) if f"gate_{g}_{k}" in trees and k not in gt.polys]
        cx = Ctx()
        cx.gate = g
        allv = sorted(set().union(*[vars_in(b) for b in bodies]), key=lambda v: ("afi".index(v[1]), v[2]))
        vnames = [qname(v) for v in allv]
        consts = {}
        for b in bodies:
            walk_consts(b, consts)
        consts_all.update(consts)
        cparams = sorted(consts)
        # model
        for n, b, i in zip(names, bodies, gt.polys):
            vs = sorted(vars_in(b), key=lambda v: ("afi".index(v[1]), v[2]))
            cs = sorted(walk_consts(b, {}))
            params = ", ".join(["+pp: Nat", "+sel: Nat"] + [f"+{c}: Nat" for c in cs] + [f"+{qname(v)}: Nat" for v in vs])
            if gt.split_sel:
                x = B(b[1])
                expr = f"F.fmul(1n+pp, F.fmul(1n+pp, sel, {x}), {B(b[2])})"
            else:
                expr = f"F.fmul(1n+pp, sel, {B(b)})"
            model += [f"def {n}({params}) -> Nat:", f"  {expr}", ""]
        if g in model_only:
            summary.append((g, gt.title, len(names), 0, "model only (hand-written laws)"))
            continue
        def call(n, b, P_="pp", selv="sel", env=None):
            vs = sorted(vars_in(b), key=lambda v: ("afi".index(v[1]), v[2]))
            cs = sorted(walk_consts(b, {}))
            if env is None:
                args = [P_, selv] + cs + [qname(v) for v in vs]
            else:
                args = [P_, selv] + [f"{env[c]}n" for c in cs] + [f"{env[qname(v)]}n" for v in vs]
            return f"G.{n}({', '.join(args)})"
        # facts
        concl, terms = [], []
        for i, (n, b) in enumerate(zip(names, bodies)):
            T, mk = fact(b, cx, gt.impl, gt.polys[i] in gt.either)
            if gt.split_sel:
                z = f"R.strip_inv_l(pp, sel, {B(b[1])}, {B(b[2])}, si, inv, h{i})"
            else:
                z = f"E.strip_inv(pp, sel, {B(b)}, si, inv, {LE(b, cx)}, h{i})"
            concl.append(T)
            terms.append(mk(z))
        # hypotheses, in order
        hyps = [("+pp", "Nat")]
        hyps += [(f"nzd{k}", "F.NZD(pp)") for k in range(cx.nzd)]
        if cx.l1:
            hyps.append(("+l1", "L.Le(1n, pp)"))
        for c in sorted(cx.lc):
            assert c < PNV, f"Le({c}, pp) would fail at p = {PNV}"
            hyps.append((f"+lc{c}", f"L.Le({c}n, pp)"))
        hyps += [("+sel", "Nat"), ("+si", "Nat"), ("+inv", "{F.fmul(1n+pp, si, sel) == 1n : Nat}")]
        for c in cparams:
            hyps.append((f"+{c}", "Nat"))
            if consts[c] in cx.lk:
                hyps.append((f"+l{c}", f"L.Le({c}, pp)"))
        for v in vnames:
            hyps.append((f"+{v}", "Nat"))
        for v in allv:
            if (v[1], v[2]) in cx.lv:
                hyps.append((f"+l{qname(v)}", f"L.Le({qname(v)}, pp)"))
        for i, (n, b) in enumerate(zip(names, bodies)):
            hyps.append((f"h{i}", f"{{{call(n, b)} == 0n : Nat}}"))
        # law text
        laws.append(f"# Gate {g} \"{gt.title}\"" + (f" (also gate{'s' if len(gt.same_as) > 1 else ''} {', '.join(map(str, gt.same_as))}: the same polynomials, checked by gen.py)" if gt.same_as else "") + ".")
        if gt.note:
            laws += [f"# {l}" for l in gt.note.split("\n")]
        if omitted:
            laws.append(f"# Not covered by this law: polynomial{'s' if len(omitted) > 1 else ''} {', '.join(f'{g}_{k}' for k in omitted)}.")
        for v in allv:
            laws.append(f"#   {qname(v)}: {query_doc(v[1], v[2])}")
        laws.append(f"law gate_{g}:")
        laws += [f"  for {h}: {t}" for h, t in hyps]
        laws.append("  " + " & ".join(concl))
        laws.append("")
        # non-vacuity at p = 11
        env = find_witness(bodies, vnames, seed=g)
        env.update({c: consts[c] % PNV for c in cparams})
        nvparts, nvterms = [], []
        for h, t in hyps:
            hn = h.lstrip("+")
            if hn == "pp" or hn in ("sel", "si") or hn in cparams or hn in vnames:
                continue
            if hn.startswith("nzd"):
                nvparts.append("F.NZD(10n)"); nvterms.append("Z.nzd11")
            elif hn == "l1":
                nvparts.append("L.Le(1n, 10n)"); nvterms.append("(9n, {==})")
            elif hn.startswith("lc"):
                c = int(hn[2:])
                nvparts.append(f"L.Le({c}n, 10n)"); nvterms.append(f"({PPNV - c}n, {{==}})")
            elif hn == "inv":
                nvparts.append("{F.fmul(11n, 1n, 1n) == 1n : Nat}"); nvterms.append("{==}")
            elif hn.startswith("l"):
                v = hn[1:]
                val = env[v]
                nvparts.append(f"L.Le({val}n, 10n)"); nvterms.append(f"({PPNV - val}n, {{==}})")
            elif hn.startswith("h"):
                i = int(hn[1:])
                nvparts.append(f"{{{call(names[i], bodies[i], '10n', '1n', env)} == 0n : Nat}}"); nvterms.append("{==}")
            else:
                raise ValueError(hn)
        laws.append(f"# NON-VACUITY: every hypothesis of gate_{g} holds at once for p = 11 (pp = 10), sel = si = 1,")
        laws.append(f"# the large constants reduced mod 11, and the row " + ", ".join(f"{v} = {env[v]}" for v in vnames) + ".")
        laws.append(f"law gate_{g}_satisfiable:")
        laws.append("  " + " & ".join(nvparts))
        laws.append("")
        # proof text
        ctxp = ["+pp: Nat"] + (["+l1: L.Le(1n, pp)"] if cx.l1 else []) + [f"+lc{c}: L.Le({c}n, pp)" for c in sorted(cx.lc)] \
            + [f"+{c}: Nat" for c in cparams] + [f"+l{c}: L.Le({c}, pp)" for c in cparams if consts[c] in cx.lk] \
            + [f"+{v}: Nat" for v in vnames] + [f"+l{qname(v)}: L.Le({qname(v)}, pp)" for v in allv if (v[1], v[2]) in cx.lv]
        ctxa = ", ".join(p.split(":")[0].lstrip("+") for p in ctxp)
        for hp in cx.helpers:
            if hp[0] == "range":
                _, name, nzs, ety, rty, inl, inr = hp
                ps = ", ".join(ctxp + [f"{n}: F.NZD(pp)" for n in nzs] + [f"e: {ety}"])
                proof += [f"def {name}({ps}) -> {rty}:", "  match e:", "    case Inl{z}:", f"      {inl.replace('CTXARGS', ctxa)}",
                          "    case Inr{z}:", f"      {inr.replace('CTXARGS', ctxa)}", ""]
            else:
                name, Tx, Ty, px, py, ety, T = hp
                ps = ", ".join(ctxp + [f"e: {ety}"])
                proof += [f"def {name}({ps}) -> {T}:", "  match e:", "    case Inl{z}:", f"      Inl{{{px}}}",
                          "    case Inr{z}:", f"      Inr{{{py}}}", ""]
        proof.append(f"def Laws.gate_{g}({', '.join(h.lstrip('+') for h, _ in hyps)}):")
        body = ", ".join(t.replace("CTXARGS", ctxa) for t in terms)
        proof.append(f"  ({body})" if len(terms) > 1 else f"  {body}")
        proof.append("")
        proof.append(f"def Laws.gate_{g}_satisfiable():")
        proof.append(f"  ({', '.join(nvterms)})" if len(nvterms) > 1 else f"  {nvterms[0]}")
        proof.append("")
        summary.append((g, gt.title, len(names), cx.nzd, omitted))
    model[7:7] = ["# Large constants (asserted by gen.py):"] + [f"#   {k} = {v:#x}" + (f" = 2^{v.bit_length() - 1}" if v & (v - 1) == 0 else "") for k, v in sorted(consts_all.items())] + [""]
    out = os.path.join(HERE, "..", dirname)
    open(os.path.join(out, "gates_model.bend"), "w").write("\n".join(model))
    open(os.path.join(out, "LAWS.bend"), "w").write("\n".join(laws))
    open(os.path.join(out, "PROOF.bend"), "w").write("\n".join(proof))
    for g, t, n, k, om in summary:
        print(f"gate {g:>2} {t!r}: {n} polynomials, NZD x{k}" + (f", {om}" if isinstance(om, str) else f", NOT covered: polynomials {om}" if om else ""))
    print(f"wrote {dirname}/gates_model.bend, LAWS.bend, PROOF.bend ({2 * sum(1 for x in summary if not isinstance(x[4], str))} laws)")

# ---------------------------------------------------------------- NZD at p = 11
def emit_nzd11():
    out = ["import Base", "import ../prims/natlib.bend as L", "import ./fieldmodel.bend as F", "import ./rowlemmas.bend as R", "",
           "# GENERATED by lawgen.py --nzd11. Do not edit.",
           "# Z/11 has no zero divisors: F.NZD(10n), by cases on the canonical elements 0..10.",
           "# The non-vacuity laws use it to show that the NZD hypothesis can hold together with all others.", ""]
    for x in range(1, PNV):
        out.append(f"def nzd11_{x}(y: Nat, ly: L.Le(y, 10n), h: {{F.fmul(11n, {x}n, y) == 0n : Nat}}) -> Either<&1, &1, {{{x}n == 0n : Nat}}, {{y == 0n : Nat}}>:")
        ind = "  "
        var = "y"
        for d in range(PNV):
            out.append(f"{ind}match {var}:")
            out.append(f"{ind}  case 0n:")
            if d == 0:
                out.append(f"{ind}    Inr{{{{==}}}}")
            else:
                k = (x * d) % PNV
                assert k != 0
                out.append(f"{ind}    Empty.absurd(Either<&1, &1, {{{x}n == 0n : Nat}}, {{{d}n == 0n : Nat}}>, L.succ_ne_zero({k - 1}n, h))")
            out.append(f"{ind}  case 1n+y{d}:")
            ind += "    "
            var = f"y{d}"
        out.append(f"{ind}Empty.absurd(Either<&1, &1, {{{x}n == 0n : Nat}}, {{11n+{var} == 0n : Nat}}>, R.gt_absurd(10n, {var}, ly))".replace(f"{{11n+{var} == 0n", f"{{1n+Nat.add(10n, {var}) == 0n"))
        out.append("")
    out.append("def nzd11(x: Nat, y: Nat, lx: L.Le(x, 10n), ly: L.Le(y, 10n), h: {F.fmul(11n, x, y) == 0n : Nat}) -> Either<&1, &1, {x == 0n : Nat}, {y == 0n : Nat}>:")
    ind, var = "  ", "x"
    for d in range(PNV):
        out.append(f"{ind}match {var}:")
        out.append(f"{ind}  case 0n:")
        out.append(f"{ind}    Inl{{{{==}}}}" if d == 0 else f"{ind}    nzd11_{d}(y, ly, h)")
        out.append(f"{ind}  case 1n+{var}{d}:" if var == "x" else f"{ind}  case 1n+x{d}:")
        ind += "    "
        var = f"x{d}"
    out.append(f"{ind}Empty.absurd(Either<&1, &1, {{1n+Nat.add(10n, {var}) == 0n : Nat}}, {{y == 0n : Nat}}>, R.gt_absurd(10n, {var}, lx))")
    out.append("")
    open(os.path.join(HERE, "nzd11.bend"), "w").write("\n".join(out))
    print("wrote nzd11.bend")

if __name__ == "__main__" and "--nzd11" in sys.argv:
    emit_nzd11()
