"""Parse zcash/halo2/gen/orchard_cs.bend's gate defs into expression trees over Fp.

Every gate def is a straight-line program of `at(k, a|f|i)` (queried evaluations),
Montgomery constants `{Z.F{16 limbs} : Z.F}` (16-bit limbs, little-endian, Montgomery
form with R = 2^256), Z.FZERO(), Z.fadd, Z.fsub, Z.fmul. We decode constants to their
canonical values (c = mont * R^-1 mod p) and keep the tree otherwise verbatim.
"""
import re, sys, os, json
P = 0x40000000000000000000000000000000224698fc094cf91b992d30ed00000001
RINV = pow(2**256, -1, P)
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "..", "zcash", "halo2", "gen", "orchard_cs.bend")

def parse():
    text = open(SRC).read()
    gates = {}
    for m in re.finditer(r"^def (gate_\d+_\d+)\(.*?\) -> Z\.F:\n((?:  .*\n)+)", text, re.M):
        name, body = m.group(1), m.group(2)
        env = {}
        last = None
        for line in body.splitlines():
            line = line.strip()
            mm = re.match(r"\+?(v\d+) = (.*)$", line)
            if mm:
                env[mm.group(1)] = expr(mm.group(2), env)
            else:
                last = expr(line, env)
        gates[name] = last
    return gates

def expr(s, env):
    s = s.strip()
    m = re.match(r"at\((\d+)n, ([afi])\)$", s)
    if m:
        return ("q", m.group(2), int(m.group(1)))
    m = re.match(r"\{Z\.F\{([\d, ]+)\} : Z\.F\}$", s)
    if m:
        limbs = [int(x) for x in m.group(1).split(",")]
        mont = sum(l << (16 * i) for i, l in enumerate(limbs))
        return ("c", mont * RINV % P)
    if s == "Z.FZERO()":
        return ("c", 0)
    m = re.match(r"Z\.(fadd|fsub|fmul)\((v\d+|Z\.FZERO\(\)), (v\d+)\)$", s)
    if m:
        a = env[m.group(2)] if m.group(2).startswith("v") else ("c", 0)
        return (m.group(1), a, env[m.group(3)])
    if s in env:
        return env[s]
    raise ValueError(s)

def show(e):
    t = e[0]
    if t == "q":
        return f"{e[1]}{e[2]}"
    if t == "c":
        return str(e[1]) if e[1] < 2**20 else (f"-{P - e[1]}" if P - e[1] < 2**20 else f"0x{e[1]:x}")
    op = {"fadd": "+", "fsub": "-", "fmul": "*"}[t]
    return f"({show(e[1])} {op} {show(e[2])})"

if __name__ == "__main__" and len(sys.argv) == 1:
    g = parse()
    for name, e in g.items():
        # gate = selector * body (outer fmul)
        assert e[0] == "fmul", name
        print(name, " body:", show(e[2])[:220])

def evaluate(e, a, f, i):
    t = e[0]
    if t == "q":
        return {"a": a, "f": f, "i": i}[e[1]][e[2]]
    if t == "c":
        return e[1]
    x, y = evaluate(e[1], a, f, i), evaluate(e[2], a, f, i)
    return {"fadd": (x + y) % P, "fsub": (x - y) % P, "fmul": x * y % P}[t]

def oracle_check():
    """Evaluate every decoded gate tree on the real Orchard proof's evaluations
    (zcash/halo2/vectors/orchard_verify.txt) and compare with halo2's own gate values."""
    path = os.path.join(HERE, "..", "..", "zcash", "halo2", "vectors", "orchard_verify.txt")
    phase, evals = None, {}
    exprs = {}
    for line in open(path):
        k, v = line.split()[:2] if len(line.split()) >= 2 else (line.strip(), "")
        if k == "phase":
            phase = v
            continue
        if k == "tx.absorb_scalar" and phase in ("instance_evals", "advice_evals", "fixed_evals"):
            evals.setdefault(phase, []).append(int.from_bytes(bytes.fromhex(v), "little"))
        m = re.match(r"expr\[(\d+)\]\.gate\[(\d+)\]\.poly\[(\d+)\]$", k)
        if m:
            exprs[(int(m.group(1)), int(m.group(2)), int(m.group(3)))] = int.from_bytes(bytes.fromhex(v), "little")
    nadv = len(evals["advice_evals"]) // 2
    ninst = len(evals["instance_evals"]) // 2
    gates = parse()
    ok = bad = 0
    for proof in (0, 1):
        a = evals["advice_evals"][proof * nadv:(proof + 1) * nadv]
        i = evals["instance_evals"][proof * ninst:(proof + 1) * ninst]
        f = evals["fixed_evals"]
        for name, e in gates.items():
            g, pnum = map(int, name.split("_")[1:])
            want = exprs.get((proof, g, pnum))
            got = evaluate(e, a, f, i)
            if want == got:
                ok += 1
            else:
                bad += 1
    print(f"decoded gate trees vs halo2's gate values on the real proof: {ok} equal, {bad} differ")
    return bad == 0

if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1] == "--check":
    sys.exit(0 if oracle_check() else 1)

SELECTED = ["gate_0_0", "gate_0_1", "gate_0_2", "gate_0_3", "gate_13_0", "gate_13_1",
            "gate_19_0", "gate_19_1", "gate_26_0", "gate_26_1", "gate_26_2"]

def vars_of(e, acc):
    if e[0] == "q":
        acc.add((e[1], e[2]))
    elif e[0] in ("fadd", "fsub", "fmul"):
        vars_of(e[1], acc); vars_of(e[2], acc)
    return acc

def bend(e):
    t = e[0]
    if t == "q":
        return f"{e[1]}{e[2]}"
    if t == "c":
        assert e[1] < 2**14, f"constant {e[1]} too large to state as a literal"
        return f"{e[1]}n"
    return f"{t}(1n+pp, {bend(e[1])}, {bend(e[2])})"

def emit():
    gates = parse()
    out = ["import Base", "import ./fieldmodel.bend as F", "",
           "# GENERATED by gates.py from zcash/halo2/gen/orchard_cs.bend. Do not edit.",
           "# Each gate_<g>_<p> is the generated gate polynomial with its compressed selector",
           "# factor (identical for every polynomial of the gate; gates.py checks) replaced by `sel`,",
           "# constants decoded from Montgomery form, and Z.fadd/fsub/fmul as F.fadd/fsub/fmul over",
           "# p = 1 + pp. Variable a<k>/f<k>/i<k> is the k-th queried advice/fixed/instance evaluation.", ""]
    sels = {}
    for name in SELECTED:
        e = gates[name]
        assert e[0] == "fmul"
        g = name.split("_")[1]
        if g in sels:
            assert sels[g] == e[1], f"{name}: selector differs within gate {g}"
        sels[g] = e[1]
        body = e[2]
        vs = sorted(vars_of(body, set()), key=lambda v: ("afi".index(v[0]), v[1]))
        params = ", ".join(["+pp: Nat", "+sel: Nat"] + [f"+{k}{i}: Nat" for k, i in vs])
        expr = f"fmul(1n+pp, sel, {bend(body)})"
        expr = expr.replace("fadd(", "F.fadd(").replace("fsub(", "F.fsub(").replace("fmul(", "F.fmul(")
        out += [f"def {name}({params}) -> Nat:", f"  {expr}", ""]
    open(os.path.join(HERE, "gates_model.bend"), "w").write("\n".join(out))
    print(f"wrote gates_model.bend ({len(SELECTED)} gates)")

if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1] == "--emit":
    emit()
