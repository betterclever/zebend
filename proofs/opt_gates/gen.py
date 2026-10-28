#!/usr/bin/env python3
"""gen.py: translation validation of research/perf4/v/opt_gates.py.

For every function opt_gates.py rewrites (pp_expr*, verify*, pp_qa, ex_loop, qa_loop), in both
generated verifiers it is applied to

    bt: orchard_bt.pre_opt.bend -> orchard_bt.bend   (batch verifier, logs removed)
    ba: orchard_ba.pre_opt.bend -> orchard_ba.bend   (single verifier, --keep-logs)

this script reads the ORIGINAL and the OPTIMISED body and translates each into

  * terms (term.bend's T) for every value computed by straight-line field arithmetic
    (`+v = L.bmul/badd/bsub/bneg/binv/bfat(...)`), over atoms (parameters, list reads
    `L.bfat(n, xs)`, and results of every other call), and
  * the list of remaining statements (every line that is not field arithmetic: transcript,
    points, MSM pushes, tail calls, results, matches), each split into a SKELETON (its text
    with every variable replaced by `#`) and the terms of the variables it reads.

It then checks mechanically, and fails loudly otherwise, that
  (1) both bodies have the same number of statements, and
  (2) the statements' skeletons are identical, in order.
The values the statements read are emitted as two lists of terms, original and optimised,
and LAWS.bend states that the two lists evaluate equal in Z/p for every p >= 2 and every
values of the atoms and constants; PROOF.bend proves it with sound.bend's `equiv` (the
normal forms of the two lists coincide, which the checker computes).

Two steps are taken as part of the translation, not proven in Bend (README.md):
  * bt only: the log statements `+st' = L.blgf(st, ...)` / `L.log_list(..., st)` are erased
    from the original exactly as opt_gates.py erases them (st' read as st), because the batch
    verifier never reads the log;
  * `L.bfat(k, L.binvs([L.ub(x0), .., L.ub(xn)]))` (opt_gates.py rule 7) is read as
    `L.binv(xk)`, i.e. binvs returns the pointwise inverses (vlib.bend's comment; see README).

Usage: python3 gen.py            (writes gen_bt.bend, gen_ba.bend, LAWS.bend, PROOF.bend)
"""
import re, sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
V = os.environ.get("OPT_GATES_V") or os.path.normpath(os.path.join(HERE, "../../research/perf4/v"))
OUT = os.environ.get("OPT_GATES_OUT") or HERE
VARIANTS = [("bt", "orchard_bt.pre_opt.bend", "orchard_bt.bend", False),
            ("ba", "orchard_ba.pre_opt.bend", "orchard_ba.bend", True)]
TOUCH = re.compile(r"^def (pp_expr\w*|verify\w*|pp_qa|ex_loop|qa_loop)\(")
ASSIGN = re.compile(r"^  \+(\w+) = (.*)$")
PURE = ("L.bmul", "L.badd", "L.bsub", "L.bneg", "L.bfat", "L.binv")
BIN = {"L.badd": "Ad", "L.bsub": "Sb", "L.bmul": "Ml"}
UN = {"L.bneg": "Ng", "L.binv": "Iv"}
BUDGET = 4500

def untouched(path):
    """The file with the bodies of the touched functions removed (signatures kept)."""
    lines, out, i = open(path).read().split("\n"), [], 0
    while i < len(lines):
        out.append(lines[i])
        if TOUCH.match(lines[i]):
            i += 1
            while i < len(lines) and lines[i].startswith("  "): i += 1
        else:
            i += 1
    return out

def bodies(path):
    lines = open(path).read().split("\n")
    out, i = {}, 0
    while i < len(lines):
        m = TOUCH.match(lines[i])
        if m:
            name = lines[i].split("(")[0][4:]
            sig = lines[i]; i += 1; body = []
            while i < len(lines) and lines[i].startswith("  "):
                body.append(lines[i]); i += 1
            out[name] = (sig, body)
        else:
            i += 1
    return out

# --- expressions -------------------------------------------------------------------------
TOK = re.compile(r"\s*(L\.\w+|K\d+\(\)|\d+n|\w+|[(),\[\]])")
def parse_expr(s):
    toks = TOK.findall(s)
    if "".join(toks).replace(" ", "") != s.replace(" ", ""):
        raise ValueError("untokenisable: " + s)
    pos = [0]
    def peek(): return toks[pos[0]] if pos[0] < len(toks) else None
    def take(t=None):
        x = toks[pos[0]]; pos[0] += 1
        if t is not None and x != t: raise ValueError(f"expected {t} got {x} in {s}")
        return x
    def expr():
        t = take()
        if t == "[":
            xs = []
            while peek() != "]":
                xs.append(expr())
                if peek() == ",": take(",")
            take("]"); return ("list", xs)
        if re.match(r"^K\d+\(\)$", t): return ("K", int(t[1:-2]))
        if re.match(r"^\d+n$", t): return ("nat", int(t[:-1]))
        if peek() == "(":
            take("("); args = []
            while peek() != ")":
                args.append(expr())
                if peek() == ",": take(",")
            take(")"); return ("call", t, args)
        return ("var", t)
    e = expr()
    if pos[0] != len(toks): raise ValueError("trailing: " + s)
    return e

class Fn:
    """Translation of one function body."""
    def __init__(self, atoms):
        self.atoms = atoms      # shared atom numbering (name -> index)
        self.term = {}          # pure var -> term
        self.invs = {}          # binvs var -> list of terms
        self.stmts = []         # (skeleton, [terms])
    def atom(self, key):
        if key not in self.atoms: self.atoms[key] = len(self.atoms)
        return ("A", self.atoms[key])
    def var(self, name):
        return self.term[name] if name in self.term else self.atom("v:" + name)
    def tr(self, e):
        k = e[0]
        if k == "var": return self.var(e[1])
        if k == "K": return ("K", e[1])
        if k == "call":
            f, args = e[1], e[2]
            if f in BIN:
                assert len(args) == 2; return (BIN[f], self.tr(args[0]), self.tr(args[1]))
            if f in UN:
                assert len(args) == 1; return (UN[f], self.tr(args[0]))
            if f == "L.bfat":
                assert len(args) == 2 and args[0][0] == "nat" and args[1][0] == "var", e
                n, xs = args[0][1], args[1][1]
                if xs in self.invs:            # rule 7: bfat(k, binvs([ub x..])) read as binv(x_k)
                    return ("Iv", self.invs[xs][n])
                return self.atom(f"fat:{xs}:{n}")
        raise ValueError(f"not field arithmetic: {e}")
    def assign_pure(self, var, expr):
        e = parse_expr(expr)
        if e[0] == "call" and e[1] == "L.binvs":
            lst = e[2][0]; assert lst[0] == "list"
            xs = []
            for it in lst[1]:
                assert it[0] == "call" and it[1] == "L.ub" and len(it[2]) == 1, it
                xs.append(self.tr(it[2][0]))
            self.invs[var] = xs; return
        self.term[var] = self.tr(e)
    def statement(self, line):
        # skeleton: string literals kept verbatim; every bare variable becomes '#'
        parts = re.split(r'("(?:[^"\\]|\\.)*")', line)
        skel, terms = [], []
        for j, p in enumerate(parts):
            if j % 2 == 1: skel.append(p); continue
            def rep(m):
                w = m.group(1)
                if w in ("match", "case"): return w
                terms.append(self.var(w)); return "#"
            skel.append(re.sub(r"(?<![\w.])([a-z_]\w*)(?![\w({])", rep, p))
        self.stmts.append(("".join(skel), terms))

LOG = [re.compile(r'^L\.blgf\((\w+), "[^"]*", .*\)$'), re.compile(r"^L\.log_list\(.*, (\w+)\)$")]

def translate(body, atoms, erase_logs, is_opt):
    fn = Fn(atoms); alias = {}
    for line in body:
        if alias:
            line = re.sub(r"\b(\w+)\b", lambda m: alias.get(m.group(1), m.group(1)), line)
        m = ASSIGN.match(line)
        if m:
            var, expr = m.group(1), m.group(2)
            if erase_logs:
                lm = LOG[0].match(expr) or LOG[1].match(expr)
                if lm: alias[var] = lm.group(1); continue
            if expr.startswith("L.binvs(") and is_opt:
                fn.assign_pure(var, expr); continue
            head = re.match(r"^(L\.\w+)\(", expr)
            if head and head.group(1) in PURE:
                fn.assign_pure(var, expr); continue
        fn.statement(line)
    return fn

# --- Bend emission -------------------------------------------------------------------------
def emit_terms(name, terms):
    ids, lines = {}, []
    def go(t):
        if t in ids: return ids[t]
        if t[0] in ("A", "K"): s = f"T.{t[0]}{{{t[1]}n}}"
        elif len(t) == 3: s = f"T.{t[0]}{{{go(t[1])}, {go(t[2])}}}"
        else: s = f"T.{t[0]}{{{go(t[1])}}}"
        v = f"n{len(ids)}"; ids[t] = v; lines.append(f"  +{v} = {{{s} : T.T}}"); return v
    outs = [go(t) for t in terms]
    return f"def {name}() -> +List<T.T>:\n" + "\n".join(lines) + ("\n" if lines else "") + "  [" + ", ".join(outs) + "]\n"

def size(t, memo=None):
    if t[0] in ("A", "K"): return 1
    return 1 + sum(size(x) for x in t[1:])

def main():
    laws, proofs, report = [], [], []
    for tag, pre, opt, keep in VARIANTS:
        bo, bn = bodies(os.path.join(V, pre)), bodies(os.path.join(V, opt))
        assert list(bo) == list(bn), (tag, list(bo), list(bn))
        for path in (pre, opt):    # term.bend reads K0 as 1 and K1 as 0 (opt_gates.py asserts the same)
            src = open(os.path.join(V, path)).read()
            assert "def K0() -> L.BF:\n  L.BF0{Fp.Fp{4294967293, 880307512, 3826848941, 2569811211, 4294967295, 4294967295, 4294967295, 1073741823}}" in src, path
            assert "def K1() -> L.BF:\n  L.BF0{Fp.Fp{0, 0, 0, 0, 0, 0, 0, 0}}" in src, path
        if untouched(os.path.join(V, pre)) != untouched(os.path.join(V, opt)):
            sys.exit(f"{tag}: the files differ outside the bodies of the touched functions")
        out = [f"# GENERATED by gen.py from research/perf4/v/{pre} (o_*) and {opt} (n_*). Do not edit.",
               "import Base", "import ./term.bend as T", ""]
        for f in bo:
            atoms = {}
            fo = translate(bo[f][1], atoms, not keep, False)
            fn = translate(bn[f][1], atoms, not keep, True)
            if bo[f][0] != bn[f][0]: sys.exit(f"{tag} {f}: signature differs")
            if len(fo.stmts) != len(fn.stmts):
                sys.exit(f"{tag} {f}: {len(fo.stmts)} vs {len(fn.stmts)} statements")
            xs, ys, triv = [], [], 0
            for (so, to), (sn, tn) in zip(fo.stmts, fn.stmts):
                if so != sn: sys.exit(f"{tag} {f}: skeletons differ:\n  {so}\n  {sn}")
                assert len(to) == len(tn)
                for a, b in zip(to, tn):
                    if a == b and a[0] == "A": triv += 1; continue
                    xs.append(a); ys.append(b)
            n_pure_o = len(fo.term); n_pure_n = len(fn.term)
            report.append((tag, f, len(fo.stmts), len(xs), triv, n_pure_o, n_pure_n,
                           sum(size(t) for t in xs), len(atoms)))
            # split into chunks of at most BUDGET term nodes: BendTT's kernel (--verdict)
            # normalises each law within a fuel limit
            chunks, cur, cn = [], [], 0
            for a, b in zip(xs, ys):
                n = size(a) + size(b)
                if cur and cn + n > BUDGET: chunks.append(cur); cur, cn = [], 0
                cur.append((a, b)); cn += n
            chunks.append(cur)
            for k, ch in enumerate(chunks):
                sfx = f"{f}" if len(chunks) == 1 else f"{f}_part{k}"
                out.append(emit_terms(f"o_{sfx}", [a for a, _ in ch])); out.append(emit_terms(f"n_{sfx}", [b for _, b in ch]))
                law = f"{tag}_{sfx}"
                laws.append(f"law {law}:\n  for +q: Nat\n  for +env: +List<Nat>\n  for +cs: +List<Nat>\n"
                            f"  {{T.evs(1n+q, env, cs, {tag.upper()}.o_{sfx}()) == T.evs(1n+q, env, cs, {tag.upper()}.n_{sfx}()) : +List<Nat>}}\n")
                proofs.append(f"def Laws.{law}(q, env, cs):\n  S.equiv(1n+q, (q, {{==}}), env, cs, {tag.upper()}.o_{sfx}(), {tag.upper()}.n_{sfx}(), {{==}})\n")
        open(os.path.join(OUT, f"gen_{tag}.bend"), "w").write("\n".join(out))
    hdr = ["import Base", "import ./term.bend as T", "import ./gen_bt.bend as BT", "import ./gen_ba.bend as BA", ""]
    open(os.path.join(OUT, "LAWS.bend"), "w").write("\n".join(hdr) + LAWS_DOC + "\n".join(laws))
    open(os.path.join(OUT, "PROOF.bend"), "w").write("\n".join(
        ["import Base", "import ./term.bend as T", "import ./sound.bend as S", "import ./gen_bt.bend as BT",
         "import ./gen_ba.bend as BA", "import ./LAWS.bend as Laws", ""]) + "\n".join(proofs))
    print(f"{'var':3} {'function':12} {'stmts':>5} {'oblig':>5} {'triv':>5} {'pure o':>6} {'pure n':>6} {'nodes':>6} {'atoms':>5}")
    for r in report: print(f"{r[0]:3} {r[1]:12} {r[2]:5} {r[3]:5} {r[4]:5} {r[5]:6} {r[6]:6} {r[7]:6} {r[8]:5}")
    print(f"{len(laws)} laws; statements {sum(r[2] for r in report)}; obligations {sum(r[3] for r in report)}")

LAWS_DOC = """# The optimised generated verifier computes the same values as the original (opt_gates.py).
#
# One law per function opt_gates.py rewrites, for each of the two generated verifiers
# (bt = orchard_bt, the batch verifier; ba = orchard_ba, the single verifier). gen.py has
# checked that the original and the optimised body perform the same statements in the same
# order (every line that is not straight-line field arithmetic: calls into the transcript,
# points, MSM, the tail call and the result), differing only in which values they pass.
# o_<f>() lists, as terms, the values the ORIGINAL body passes to those statements; n_<f>()
# the values the OPTIMISED body passes, in the same positions (pairs that are the same
# atom on both sides are left out). The law: in Z/p, for every p = 2 + q, every values of
# the atoms (env: parameters, list reads, results of the other calls) and every values of
# the constants K2.. (cs; K0 = 1 and K1 = 0), the two lists are equal, value by value.

"""

if __name__ == "__main__":
    main()
