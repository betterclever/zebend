#!/usr/bin/env python3
"""Generates fp.bend (edwards25519 base field, p = 2^255 - 19) and fl.bend (the scalar field,
l = 2^252 + 27742317777372353535851937790883648493) for the Bend Ed25519 verifier.

Adapted from sapling/groth16/gen_fq.py: Montgomery form, R = 2^256, 4 x 64-bit limbs held
as 8 little-endian U32 words, multiplied through the forked Bend's U32.mac64.

Multiplication is the merged ("no-carry") CIOS. gen_fq.py asserts p's top limb < 2^63 - 1;
p = 2^255 - 19 has top limb exactly 2^63 - 1, so that assertion is replaced by the property
the code needs: with a < p (the operand multiplied by each 64-bit word of b) and b < 2^256,
every iteration keeps t < 2p (t' = (t + a*b_i + m*p)/W < (2p + 2(W-1)p)/W = 2p), and 2p < 2^256,
so the final A + C word never overflows and one conditional subtraction gives t mod p.
Each single U32.mac64 computes a*b + c + d < 2^128 exactly. Checked against Python integers
on edge values and random inputs (t/field_test.py).

  python3 gen_fields.py    # writes fp.bend and fl.bend
"""
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
N = 4                      # 64-bit limbs
NW = 2 * N                 # U32 words
R = 1 << (64 * N)
M64 = (1 << 64) - 1
M32 = (1 << 32) - 1
P = PL = INV = None


def setup(p):
    global P, PL, INV
    P = p
    PL = [(P >> (64 * i)) & M64 for i in range(N)]
    INV = (-pow(P, -1, 1 << 64)) % (1 << 64)
    assert P % 2 == 1 and P < (1 << (64 * N - 1))  # p < R/2 (see module doc)


def words(x):
    return [(x >> (32 * i)) & M32 for i in range(NW)]


def halves(v):
    return (str(v & M32), str(v >> 32))


Z = ("0", "0")


class Emit:
    def __init__(self):
        self.lines = []
        self.n = 0

    def let(self, expr):
        self.n += 1
        v = f"v{self.n}"
        self.lines.append(f"  +{v} = {expr}")
        return v

    def mac64(self, a, b, c, d, need=(0, 1, 2, 3)):
        """(lo, hi) 64-bit pairs of a*b + c + d; only the words in `need` are computed."""
        args = ", ".join([*a, *b, *c, *d])
        w = [self.let(f"U32.mac64({k}, {args})") if k in need else "0" for k in range(4)]
        return (w[0], w[1]), (w[2], w[3])

    def u32(self, expr):
        return self.let(f"({expr} : U32)")


def destructure(e, var, prefix):
    names = [f"{prefix}{i}" for i in range(NW)]
    e.lines.append(f"  Fq{{{', '.join('+' + n for n in names)}}} = {var}")
    return [(names[2 * i], names[2 * i + 1]) for i in range(N)]


def lit(ws):
    return "Fq{" + ", ".join(str(w) for w in ws) + "}"


def lit_limbs(t):
    return "Fq{" + ", ".join(w for limb in t for w in limb) + "}"


def cond_sub(e, t):
    """t < 2p (fits 384 bits) -> t mod p, branch-free."""
    c = ("1", "0")
    d = []
    for j in range(N):
        nq = halves((~PL[j]) & M64)
        dj, cc = e.mac64(t[j], ("1", "0"), nq, c, need=(0, 1, 2))
        d.append(dj)
        c = (cc[0], "0")
    # c = 1: no borrow, t >= p -> take d
    mask = e.u32(f"0 - {c[0]}")
    nmask = e.u32(f"{mask} .^. {M32}")
    r = []
    for j in range(N):
        r.append(tuple(e.u32(f"({d[j][h]} .&. {mask}) .|. ({t[j][h]} .&. {nmask})") for h in range(2)))
    return r


def gen_mul(name="mul", square=False):
    e = Emit()
    a = destructure(e, "a", "a")
    b = a if square else destructure(e, "b", "b")
    q = [halves(v) for v in PL]
    inv = halves(INV)
    t = [Z] * N
    for i in range(N):
        A, t0 = None, None
        (t0, A) = e.mac64(a[0], b[i], t[0], Z)
        m, _ = e.mac64(t0, inv, Z, Z, need=(0, 1))
        _, C = e.mac64(m, q[0], t0, Z, need=(2, 3))
        nt = [Z] * N
        for j in range(1, N):
            (tj, A) = e.mac64(a[j], b[i], t[j], A)
            (nt[j - 1], C) = e.mac64(m, q[j], tj, C)
        nt[N - 1], _ = e.mac64(C, ("1", "0"), A, Z, need=(0, 1))
        t = nt
    r = cond_sub(e, t)
    doc = "Montgomery square" if square else "Montgomery product a * b * R^-1 mod p"
    sig = f"def {name}(a: Fq) -> Fq:" if square else f"def {name}(a: Fq, b: Fq) -> Fq:"
    return f"# {doc} (no-carry CIOS, 6 x 64-bit limbs via U32.mac64).\n{sig}\n" + "\n".join(e.lines) + f"\n  {lit_limbs(r)}\n"


def gen_add():
    e = Emit()
    a = destructure(e, "a", "a")
    b = destructure(e, "b", "b")
    s, c = [], Z
    for j in range(N):
        sj, cc = e.mac64(a[j], ("1", "0"), b[j], c, need=(0, 1, 2))
        s.append(sj)
        c = (cc[0], "0")
    r = cond_sub(e, s)
    return "def add(a: Fq, b: Fq) -> Fq:\n" + "\n".join(e.lines) + f"\n  {lit_limbs(r)}\n"


def gen_sub():
    e = Emit()
    a = destructure(e, "a", "a")
    b = destructure(e, "b", "b")
    d, c = [], ("1", "0")
    for j in range(N):
        nb = (e.u32(f"{b[j][0]} .^. {M32}"), e.u32(f"{b[j][1]} .^. {M32}"))
        dj, cc = e.mac64(a[j], ("1", "0"), nb, c, need=(0, 1, 2))
        d.append(dj)
        c = (cc[0], "0")
    # c = 0: borrow -> add p
    mask = e.u32(f"{c[0]} - 1")
    r, c = [], Z
    for j in range(N):
        q = halves(PL[j])
        mq = (e.u32(f"{q[0]} .&. {mask}"), e.u32(f"{q[1]} .&. {mask}"))
        rj, cc = e.mac64(d[j], ("1", "0"), mq, c, need=(0, 1, 2))
        r.append(rj)
        c = (cc[0], "0")
    return "def sub(a: Fq, b: Fq) -> Fq:\n" + "\n".join(e.lines) + f"\n  {lit_limbs(r)}\n"


def gen_lt_const(name, k, doc):
    """1 if raw a < k (a any 384-bit value), else 0."""
    e = Emit()
    a = destructure(e, "a", "a")
    c = ("1", "0")
    for j in range(N):
        nk = halves((~((k >> (64 * j)) & M64)) & M64)
        _, cc = e.mac64(a[j], ("1", "0"), nk, c, need=(2,))
        c = (cc[0], "0")
    # a - k without borrow <=> carry 1 <=> a >= k
    return f"# {doc}\ndef {name}(a: Fq) -> U32:\n" + "\n".join(e.lines) + f"\n  (1 - {c[0]} : U32)\n"


def gen_eq():
    e = Emit()
    a = destructure(e, "a", "a")
    b = destructure(e, "b", "b")
    aw = [w for l in a for w in l]
    bw = [w for l in b for w in l]
    x = e.u32(" .|. ".join(f"({p} .^. {q})" for p, q in zip(aw, bw)))
    y = e.u32(f"({x} .|. (0 - {x})) >> 31n")
    return "# 1 if a == b else 0 (branch-free).\ndef eq(a: Fq, b: Fq) -> U32:\n" + "\n".join(e.lines) + f"\n  (1 - {y} : U32)\n"


def gen_sel():
    e = Emit()
    a = destructure(e, "a", "a")
    b = destructure(e, "b", "b")
    e.lines.append("  +mk = (0 - c : U32)")
    e.lines.append(f"  +nm = (mk .^. {M32} : U32)")
    r = [(e.u32(f"({a[j][0]} .&. mk) .|. ({b[j][0]} .&. nm)"), e.u32(f"({a[j][1]} .&. mk) .|. ({b[j][1]} .&. nm)")) for j in range(N)]
    return "# c == 1 selects a, c == 0 selects b (branch-free).\ndef sel(+c: U32, a: Fq, b: Fq) -> Fq:\n" + "\n".join(e.lines) + f"\n  {lit_limbs(r)}\n"


def window_chain(name, exp, doc, T="Fq", mul="mul", sqr="sqr", sqr_n="sqr_n", w=5):
    """x^exp, sliding window of w bits; split into a precompute def and chunked defs so no
    def grows large (Bend compile memory grows with def size)."""
    bits = bin(exp)[2:]
    steps = []  # (squarings, odd window value)
    i, first, pend = 0, None, 0
    while i < len(bits):
        if bits[i] == "0":
            pend += 1
            i += 1
            continue
        j = min(i + w, len(bits))
        while bits[j - 1] == "0":
            j -= 1
        val = int(bits[i:j], 2)
        if first is None:
            first = val
        else:
            steps.append((pend + (j - i), val))
        pend = 0
        i = j
    tail = pend
    odd = list(range(1, 1 << w, 2))
    tw = f"{name}_T"
    out = [f"type {tw} is Data:\n  {tw}{{" + ", ".join(f"x{k}: {T}" for k in odd) + "}\n"]
    pre = ["  +x1 = x", f"  +xx = {sqr}(x1)"] + [f"  +x{k} = {mul}(x{k - 2}, xx)" for k in odd[1:]]
    out.append(f"def {name}_pre(+x: {T}) -> {tw}:\n" + "\n".join(pre) + f"\n  {tw}{{" + ", ".join(f"x{k}" for k in odd) + "}\n")
    getters = [f"def {name}_g{k}(t: {tw}) -> {T}:\n  {tw}{{" + ", ".join((f"+x{j}" if j == k else "_") for j in odd) + f"}} = t\n  x{k}\n" for k in odd]
    out += getters
    CH = 12
    chunks = [steps[k:k + CH] for k in range(0, len(steps), CH)]
    for ci, ch in enumerate(chunks):
        lines = ["  +a0 = acc"]
        for si, (sq, val) in enumerate(ch):
            lines.append(f"  +a{si + 1} = {mul}({sqr_n}({sq}n, a{si}), {name}_g{val}(t))")
        out.append(f"def {name}_c{ci}(+t: {tw}, acc: {T}) -> {T}:\n" + "\n".join(lines) + f"\n  a{len(ch)}\n")
    body = [f"  +t = {name}_pre(x)", f"  +r0 = {name}_g{first}(t)"]
    for ci in range(len(chunks)):
        body.append(f"  +r{ci + 1} = {name}_c{ci}(t, r{ci})")
    res = f"r{len(chunks)}"
    if tail:
        res = f"{sqr_n}({tail}n, {res})"
    out.append(f"# {doc}\ndef {name}(x: {T}) -> {T}:\n" + "\n".join(body) + f"\n  {res}\n")
    return "\n".join(out)


def common(name):
    return [
        "# GENERATED by gen_fields.py. Do not edit.\n"
        f"# {name}, modulus = {hex(P)}\n"
        "# Montgomery form (R = 2^256), 4 x 64-bit limbs as 8 little-endian U32 words.\n"
        "import Base\n\n"
        "type Fq is Data:\n  Fq{" + ", ".join(f"l{i}: U32" for i in range(NW)) + "}\n",
        gen_mul(),
        gen_mul("sqr", square=True),
        gen_add(),
        gen_sub(),
        gen_eq(),
        gen_sel(),
        gen_lt_const("lt_p", P, "1 if the raw 256-bit value a < modulus (canonical), else 0."),
        f"def zero() -> Fq:\n  {lit([0] * NW)}\n",
        f"def one() -> Fq:\n  {lit(words(R % P))}\n",
        f"# R^2 mod p: raw -> Montgomery\ndef R2() -> Fq:\n  {lit(words(R * R % P))}\n",
        f"# R^3 mod p: mul(R3(), x) = x * R^2 (for x * 2^256 in Montgomery form)\ndef R3() -> Fq:\n  {lit(words(R * R * R % P))}\n",
        f"def raw_one() -> Fq:\n  {lit(words(1))}\n",
        "def neg(a: Fq) -> Fq:\n  sub(zero(), a)\n",
        "def dbl(+a: Fq) -> Fq:\n  add(a, a)\n",
        "def is_eq(a: Fq, b: Fq) -> Bool:\n  U32.is_eq(eq(a, b), 1)\n",
        "def is_zero(a: Fq) -> Bool:\n  U32.is_eq(eq(a, zero()), 1)\n",
        "# raw words (ANY value < 2^256) -> Montgomery form, reduced mod p. R2 is the left operand\n"
        "# (the one that must be < p; see gen_fields.py).\ndef from_raw(a: Fq) -> Fq:\n  mul(R2(), a)\n",
        "# Montgomery -> canonical raw words\ndef to_raw(a: Fq) -> Fq:\n  mul(a, raw_one())\n",
        "# low bit of the canonical value (Ed25519's 'is_negative')\ndef low_bit_raw(a: Fq) -> U32:\n  Fq{+l0, _, _, _, _, _, _, _} = a\n  (l0 .&. 1 : U32)\n\ndef low_bit(a: Fq) -> U32:\n  low_bit_raw(to_raw(a))\n",
        "def sqr_n(n: Nat, x: Fq) -> Fq:\n  match n:\n    case 0n:\n      x\n    case 1n+k:\n      sqr_n(k, sqr(x))\n",
    ]


def module_fp():
    setup(2**255 - 19)
    parts = common("edwards25519 base field Fp") + [
        window_chain("inv", P - 2, "x^(p-2) = x^-1 (0 -> 0)"),
        window_chain("pow_p58", (P - 5) // 8, "x^((p-5)/8), for sqrt_ratio_i"),
    ]
    return "\n".join(parts).replace("Fq", "Fp")


def module_fl():
    setup(2**252 + 27742317777372353535851937790883648493)
    return "\n".join(common("edwards25519 scalar field Fl")).replace("Fq", "Fl")


if __name__ == "__main__":
    (HERE / "fp.bend").write_text(module_fp())
    (HERE / "fl.bend").write_text(module_fl())
    print("wrote fp.bend fl.bend")
