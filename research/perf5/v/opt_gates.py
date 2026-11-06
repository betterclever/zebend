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
    Fp.inv(0) = 0^(p-2) = 0). perf5-gate: dependency-aware; the pure definitions an inversion's
    argument needs are hoisted above the first use of any result of its group, so every
    inversion of a function joins one group (19 -> 3 inversions per proof: verify, verify_1,
    verify_2) unless an argument needs a transcript value read after that first use;
 8. (perf5-gate) single-use temporaries computed unboxed inside their consumer (inline):
    L.bmul(a, L.bsub(b, c)) becomes {L.BF0{Fp.mul(L.ub(a), Fp.sub(L.ub(b), L.ub(c)))} : L.BF},
    one box instead of two; L.bfat used once becomes L.fat. Trees are capped at --cap=N
    operations (default 6) and only applied in INLINE_FNS (verify / verify_2 make clang's
    AArch64 backend fail: "live register clobbered by inserted prologue instructions");
 9. (perf5-gate) in pp_qa (per action) the 21 QA_f(q) accessors become one destructuring, and
    L.bms_push(m, s, L.bpat(i, xs)) pushes L.pat(i, xs) without boxing the point;
10. (perf5-gate, batch build only) L.sub_head(L.compute_s(us, init), v) becomes
    BT.s_recipe(us, init, v): bt.bend builds the G scalars with the batch weight folded in.
Values are unchanged by every rewrite (same field operations on canonical values; the -v
trace of the --keep-logs build checks 2,516 intermediates per bundle).
Only straight-line `+name = L.b...(...)` definitions are touched; everything else is kept."""
import os, re, sys
KEEP_LOGS = "--keep-logs" in sys.argv
CAP = int(next((a.split("=")[1] for a in sys.argv if a.startswith("--cap=")), "6"))
UNPACK_FNS = os.environ.get("UNPACK_FNS", r"pp_qa$")
INLINE_FNS = os.environ.get("INLINE_FNS", r"pp_expr|pp_qa|verify_1$")
sys.argv = [a for a in sys.argv if a != "--keep-logs" and not a.startswith("--cap=")]
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

stats = dict(logs=0, fat=0, fold=0, negsub=0, cse=0, dce=0, inv_batched=0, inv_groups=0, unboxed=0, qa_unpacked=0, pat_unboxed=0)

def opt_body(lines, fname=""):
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
    out = inline(out, CAP if re.match(INLINE_FNS, fname) else 1)
    if re.match(UNPACK_FNS, fname): out = unpack_qa(out)
    return [f"  +{var} = {e}" if var is not None else e for var, e, _ in out]

def batch_inv(out):
    """Groups field inversions into L.binvs. A group's inversion goes just before the first use
    U of any of its results; the pure definitions its arguments need (their transitive pure
    closure) are hoisted above U in their original order. Non-pure definitions (transcript
    reads, squeezes, boxing of challenges) and earlier inversions are never moved: every one an
    argument needs must already sit above U. Repeats until no two inversions can be grouped."""
    while True:
        pos = {o[0]: i for i, o in enumerate(out) if o[0] is not None}
        words = [set(re.findall(r"\b\w+\b", o[1])) for o in out]
        def first_use(i):
            v = out[i][0]
            for j in range(i + 1, len(out)):
                if v in words[j]: return j
            return len(out)
        def is_inv(i):
            return out[i][2] and (out[i][1].startswith("L.binv(") or out[i][1].startswith("L.binvs("))
        def closure(i):
            # pure lines the argument of inversion line i needs, and the fixed lines it needs
            arg = call(out[i][1])[1][0]
            seen, fixed, stack = set(), set(), [arg]
            while stack:
                v = stack.pop()
                if v not in pos: continue
                j = pos[v]
                if j in seen or j in fixed: continue
                if out[j][2] and not is_inv(j):
                    seen.add(j); stack.extend(w for w in words[j] if w in pos and w != v)
                else:
                    fixed.add(j)
            return seen, fixed
        cands = [i for i, o in enumerate(out) if o[2] and o[1].startswith("L.binv(")]
        info = {i: (first_use(i),) + closure(i) for i in cands}
        def fits(g):
            U = min(info[i][0] for i in g)
            gs = set(g)
            for i in g:
                _, cl, fx = info[i]
                if any(f >= U or f in gs for f in fx): return None
            return U
        group = None
        for k, c in enumerate(cands):
            g = [c]
            for d in cands[k + 1:]:
                if fits(g + [d]) is not None: g.append(d)
            if len(g) >= 2: group = g; break
        if group is None: return out
        U = fits(group); gs = set(group)
        hoist = sorted(set().union(*[info[i][1] for i in group]))
        hoist = [j for j in hoist if j >= U]
        hs = set(hoist)
        gv = f"invs_{out[group[0]][0]}"
        ins = [[gv, "L.binvs([" + ", ".join(f"L.ub({call(out[i][1])[1][0]})" for i in group) + "])", True]]
        ins += [[out[i][0], f"L.bfat({k}n, {gv})", True] for k, i in enumerate(group)]
        new = [o for i, o in enumerate(out[:U]) if i not in gs]
        new += [out[j] for j in hoist] + ins
        new += [o for i, o in enumerate(out) if i >= U and i not in gs and i not in hs]
        stats["inv_batched"] += len(group); stats["inv_groups"] += 1
        out = new

def unpack_qa(out):
    """QA_f(q) accessors (each destructures all 21 fields of q, dropping the other 20) for the
    same q become one destructuring at the first of them; Bend's destructuring gives the same
    field values. BMS pushes of a list point use the unboxed point (L.pat is what L.bpat boxes)."""
    first = {}; fields = {}
    for i, (v, e, pure) in enumerate(out):
        m = re.match(r"^QA_(\w+)\((\w+)\)$", e) if v is not None else None
        if m:
            first.setdefault(m.group(2), i); fields.setdefault(m.group(2), {})[m.group(1)] = v
    res = []
    for i, (v, e, pure) in enumerate(out):
        m = re.match(r"^QA_(\w+)\((\w+)\)$", e) if v is not None else None
        if m:
            q = m.group(2)
            if first[q] != i: continue
            pat = ", ".join(f"+{fields[q][f]}" if f in fields[q] else "_" for f in QA_FIELDS)
            res.append([None, f"  QA{{{pat}}} = {q}", False]); stats["qa_unpacked"] += len(fields[q]); continue
        if v is not None:
            e2 = re.sub(r"^L\.bms_push\((\w+), (\w+), L\.bpat\((\d+n), (\w+)\)\)$", r"L.ms_push(\1, L.ub(\2), L.pat(\3, \4))", e)
            if e2 != e: stats["pat_unboxed"] += 1; e = e2
        res.append([v, e, pure])
    return res

UNBOX = {"L.bmul": "Fp.mul", "L.badd": "Fp.add", "L.bsub": "Fp.sub", "L.bneg": "Fp.neg"}

def inline(out, cap):
    """Single-use temporaries computed unboxed inside their consumer. A pure arithmetic or
    list-lookup definition used exactly once, as a direct argument of an arithmetic line, is
    not boxed: the consumer becomes L.BF0{Fp.op(...)} on the unboxed expression (L.bmul(a, b)
    is L.BF0{Fp.mul(L.ub(a), L.ub(b))}, L.bfat(i, xs) is L.BF0{L.fat(i, xs)}, so the values are
    the same). Expression trees are capped at `cap` operations (frame registers)."""
    pos = {o[0]: i for i, o in enumerate(out) if o[0] is not None}
    words = [re.findall(r"\b\w+\b", o[1]) for o in out]
    uses = {}
    for j, ws in enumerate(words):
        for w in ws:
            if w in pos and pos[w] < j: uses.setdefault(w, []).append(j)
    parsed = {}
    for i, (v, e, pure) in enumerate(out):
        if v is not None and pure:
            c = call(e)
            if c and (c[0] in UNBOX or (c[0] == "L.bfat" and len(c[1]) == 2 and re.match(r"^\w+$", c[1][1]))): parsed[i] = c
    inl = {}
    for i, c in parsed.items():
        v = out[i][0]; u = uses.get(v, [])
        if len(u) == 1 and u[0] in parsed and parsed[u[0]][0] in UNBOX and v in parsed[u[0]][1]:
            inl[v] = True
    size = {}
    for i in sorted(parsed):
        op, args = parsed[i]
        if op not in UNBOX: size[i] = 1; continue
        kids = [a for a in args if inl.get(a)]
        while 1 + sum(size[pos[a]] for a in kids) > cap and kids:
            big = max(kids, key=lambda a: size[pos[a]])
            inl[big] = False; kids.remove(big)
        size[i] = 1 + sum(size[pos[a]] for a in kids)
    def ux(i):
        op, args = parsed[i]
        if op == "L.bfat": return f"L.fat({args[0]}, {args[1]})"
        return f"{UNBOX[op]}(" + ", ".join(ux(pos[a]) if inl.get(a) else f"L.ub({a})" for a in args) + ")"
    res = []
    for i, (v, e, pure) in enumerate(out):
        if v is not None and inl.get(v): stats["unboxed"] += 1; continue
        if i in parsed and parsed[i][0] in UNBOX and any(inl.get(a) for a in parsed[i][1]):
            res.append([v, "{L.BF0{" + ux(i) + "} : L.BF}", pure])
        else:
            res.append([v, e, pure])
    return res

# batch build: the G scalars as a recipe that BT.leaf expands with the weight folded in
if not KEEP_LOGS:
    src, n = re.subn(r"L\.sub_head\(L\.compute_s\((\[[^\]]*\]), (L\.ub\(\w+\))\), (L\.ub\(\w+\))\)", r"BT.s_recipe(\1, \2, \3)", src)
    assert n == 1, n
QA_FIELDS = re.findall(r"(\w+): L\.\w+", re.search(r"type QA is Data:\n  QA\{(.*)\}", src).group(1))
assert len(QA_FIELDS) == 21, QA_FIELDS
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
        out += opt_body(body, TOUCH.match(l).group(1))
    else:
        out.append(l); i += 1
open(sys.argv[2], "w").write("\n".join(out))
print(stats)
