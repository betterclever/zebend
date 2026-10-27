#!/usr/bin/env python3
"""opt_gates.py IN OUT [--keep-logs]: source-level optimisation of the generated batch verifier (orchard_bt):
 1. (unless --keep-logs, used for the single verifier's -v trace) transcript logging removed (L.blgf / L.log_list only feed the -v trace, never the verdict:
    the batch verifier never prints the log), the St chain is re-linked;
 2. L.bfat(i, list) (an O(i) list walk) computed once per function, at its first use;
 3. constant folding with K0 = 1 and K1 = 0 (Montgomery one / zero; every value is a reduced
    field element, so x*1 = x, x*0 = 0, x+0 = x, x-0 = x, -0 = 0 hold bit for bit);
 4. a + (-b) -> a - b (Fp.add(a, Fp.neg(b)) and Fp.sub(a, b) both return (a - b) mod p, reduced);
 5. common subexpressions (bmul / badd commutative) computed once;
 6. dead pure definitions dropped;
 7. field inversions batched (L.binvs: Montgomery's trick, zero-safe: 0 maps to 0 as
    Fp.inv(0) = 0^(p-2) = 0): every group of L.binv whose arguments are all defined before
    the first use of any of their results becomes one inversion.
Only straight-line `+name = L.b...(...)` definitions are touched; everything else is kept."""
import re, sys
KEEP_LOGS = "--keep-logs" in sys.argv
sys.argv = [a for a in sys.argv if a != "--keep-logs"]
src = open(sys.argv[1]).read()
K_ONE, K_ZERO = "K0()", "K1()"
assert "def K0() -> L.BF:\n  L.BF0{Fp.Fp{4294967293, 880307512, 3826848941, 2569811211, 4294967295, 4294967295, 4294967295, 1073741823}}" in src
assert "def K1() -> L.BF:\n  L.BF0{Fp.Fp{0, 0, 0, 0, 0, 0, 0, 0}}" in src
PURE = ("L.bmul", "L.badd", "L.bsub", "L.bneg", "L.bfat", "L.binv")
ASSIGN = re.compile(r"^  \+(\w+) = (.*)$")

def split_args(s):
    out, d, cur = [], 0, ""
    for ch in s:
        if ch in "([{": d += 1
        if ch in ")]}": d -= 1
        if ch == "," and d == 0: out.append(cur.strip()); cur = ""
        else: cur += ch
    if cur.strip(): out.append(cur.strip())
    return out

def call(expr):
    m = re.match(r"^(L\.\w+)\((.*)\)$", expr)
    if not m: return None
    # make sure the outer parens match
    d = 0
    for i, ch in enumerate(expr):
        if ch == "(": d += 1
        elif ch == ")":
            d -= 1
            if d == 0 and i != len(expr) - 1: return None
    return m.group(1), split_args(m.group(2))

stats = dict(logs=0, fat=0, fold=0, negsub=0, cse=0, dce=0, inv_batched=0, inv_groups=0)

def opt_body(lines):
    alias = {}
    def sub_alias(s):
        if not alias: return s
        return re.sub(r"\b(\w+)\b", lambda m: alias.get(m.group(1), m.group(1)), s)
    out = []  # list of [var or None, expr or raw line]
    defs = {}   # var -> (op, args)
    cse = {}    # key -> var
    fatvar = {}
    nfat = [0]
    def emit(var, expr):
        out.append([var, expr, True])
    def intern_fat(expr):
        # replace nested L.bfat(n, xs) by a variable (defined before the current line)
        def rep(m):
            key = m.group(0)
            if key in fatvar: return fatvar[key]
            v = f"fat_{m.group(2)}_{m.group(1)}"
            fatvar[key] = v; emit(v, key); defs[v] = ("L.bfat", [m.group(1) + "n", m.group(2)]); stats["fat"] += 1
            return v
        return re.sub(r"L\.bfat\((\d+)n, (\w+)\)", rep, expr)
    for line in lines:
        m = ASSIGN.match(line)
        if not m:
            out.append([None, sub_alias(line), False]); continue
        var, expr = m.group(1), sub_alias(m.group(2))
        lm = re.match(r'^L\.blgf\((\w+), "[^"]*", .*\)$', expr) or re.match(r"^L\.log_list\(.*, (\w+)\)$", expr)
        if lm and not KEEP_LOGS:
            alias[var] = lm.group(1); stats["logs"] += 1; continue
        c = call(expr)
        if not c or c[0] not in PURE:
            out.append([var, expr, False]); continue
        op, args = c
        if op == "L.bfat" and re.match(r"^\d+n$", args[0]) and re.match(r"^\w+$", args[1]):
            key = f"L.bfat({args[0]}, {args[1]})"
            if key in fatvar: alias[var] = fatvar[key]; continue
            fatvar[key] = var; defs[var] = (op, args); emit(var, key); continue
        args = [intern_fat(a) for a in args]
        # a + (-b) -> a - b
        if op == "L.badd":
            a, b = args
            if b in defs and defs[b][0] == "L.bneg": op, args = "L.bsub", [a, defs[b][1][0]]; stats["negsub"] += 1
            elif a in defs and defs[a][0] == "L.bneg": op, args = "L.bsub", [b, defs[a][1][0]]; stats["negsub"] += 1
        # folding
        res = None
        if op == "L.bmul":
            a, b = args
            if K_ZERO in (a, b): res = K_ZERO
            elif a == K_ONE: res = b
            elif b == K_ONE: res = a
        elif op == "L.badd":
            a, b = args
            if a == K_ZERO: res = b
            elif b == K_ZERO: res = a
        elif op == "L.bsub":
            a, b = args
            if b == K_ZERO: res = a
        elif op == "L.bneg":
            if args[0] == K_ZERO: res = K_ZERO
        if res is not None:
            alias[var] = res; stats["fold"] += 1; continue
        key_args = sorted(args) if op in ("L.bmul", "L.badd") else args
        key = op + "(" + ", ".join(key_args) + ")"
        if key in cse:
            alias[var] = cse[key]; stats["cse"] += 1; continue
        cse[key] = var; defs[var] = (op, args)
        emit(var, f"{op}({', '.join(args)})")
    # dead code: pure definitions never used later
    used = set()
    keep = [True] * len(out)
    for i in range(len(out) - 1, -1, -1):
        var, e, pure = out[i]
        if pure and var not in used:
            keep[i] = False; stats["dce"] += 1; continue
        text = e
        for w in re.findall(r"\b\w+\b", text): used.add(w)
    out = [o for k, o in zip(keep, out) if k]
    out = batch_inv(out)
    return [f"  +{var} = {e}" if var is not None else e for var, e, _ in out]

def batch_inv(out):
    words = [set(re.findall(r"\b\w+\b", e)) for _, e, _ in out]
    pos = {var: i for i, (var, _, _) in enumerate(out) if var is not None}
    invs = [i for i, (var, e, pure) in enumerate(out) if pure and e.startswith("L.binv(")]
    def first_use(i):
        v = out[i][0]
        for j in range(i + 1, len(out)):
            if v in words[j]: return j
        return len(out)
    info = []
    for i in invs:
        arg = call(out[i][1])[1][0]
        d = pos.get(arg, -1)
        info.append((i, arg, d, first_use(i)))
    groups, cur = [], []
    for it in info:
        if cur:
            md = max(max(x[2] for x in cur), it[2]); mu = min(min(x[3] for x in cur), it[3])
            if md < mu: cur.append(it); continue
            groups.append(cur); cur = []
        cur = [it]
    if cur: groups.append(cur)
    ins = {}; drop = set()
    for gi, g in enumerate(groups):
        if len(g) < 2: continue
        p = max(x[2] for x in g) + 1
        gv = f"invs_{out[g[0][0]][0]}"
        lines = [(gv, "L.binvs([" + ", ".join(f"L.ub({x[1]})" for x in g) + "])", True)]
        for k, x in enumerate(g):
            lines.append((out[x[0]][0], f"L.bfat({k}n, {gv})", True)); drop.add(x[0])
        ins.setdefault(p, []).extend(lines)
        stats["inv_batched"] += len(g); stats["inv_groups"] += 1
    res = []
    for i, o in enumerate(out):
        res += ins.get(i, [])
        if i not in drop: res.append(o)
    res += ins.get(len(out), [])
    return res

lines = src.split("\n")
out = []; i = 0
TOUCH = re.compile(r"^def (pp_expr\w*|verify\w*|pp_qa|ex_loop|qa_loop)\(")
while i < len(lines):
    l = lines[i]
    if TOUCH.match(l):
        out.append(l); i += 1
        body = []
        while i < len(lines) and lines[i].startswith("  "):
            body.append(lines[i]); i += 1
        out += opt_body(body)
    else:
        out.append(l); i += 1
open(sys.argv[2], "w").write("\n".join(out))
print(stats)
