#!/usr/bin/env python3
"""Generates the speed-round-2 secp256k1 modules for Zebend (transparent/secp2/).

  python3 gen_secp2.py     # writes fe.bend, sc.bend, gtab.bend, scinv.bend

* fe.bend: as secp/fe.bend (gen_secp.py), plus `sub` (a - b mod p in one pass) and `beta`.
* sc.bend: as secp/sc.bend, plus `sqr` (Montgomery), `add` (a + b mod n), `mul_shift_384`
  (round(a * b / 2^384), plain), `top_word` and the GLV constants.
* gtab.bend: odd multiples (2i+1)·G, i = 0 .. 2^(WG-2) - 1, affine, as dense U32 `match`es
  (the compiler turns each into a constant array).
* scinv.bend: x^(n-2) in Montgomery form by a fixed addition chain (no lists, no lookups).

GLV for secp256k1 (as libsecp256k1's secp256k1_scalar_split_lambda): k = k1 + k2·λ (mod n),
c1 = round(k·g1 / 2^384), c2 = round(k·g2 / 2^384), k2 = c1·(-b1) + c2·(-b2), k1 = k - k2·λ.
The self-test at the bottom checks the split on 200,000 random scalars and the edges.
"""
import pathlib, random, re, sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import gen_secp as g  # noqa: E402  (the round-1 generator, unchanged copy)

P, N, GX, GY = g.P, g.N, g.GX, g.GY
LAM = 0x5363AD4CC05C30E0A5261C028812645A122E22EA20816678DF02967C1B23BD72
BETA = 0x7AE96A2B657C07106E64479EAC3434E99CF0497512F58995C1396C28719501EE
G1 = 0x3086D221A7D46BCDE86C90E49284EB153DAA8A1471E8CA7FE893209A45DBB031
G2 = 0xE4437ED6010E88286F547FA90ABFE4C4221208AC9DF506C61571B4AE8AC47F71
MB1 = 0xE4437ED6010E88286F547FA90ABFE4C3
MB2 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE8A280AC50774346DD765CDA83DB1562C
WG = 8          # wNAF width for G and λG: table of 2^(WG-2) = 64 odd multiples
R = 2**256


# ------------------------------------------------------------------ Python model

def ec_add(p1, p2):
    return g.ec_add(p1, p2)


def ec_mul(k, pt):
    r = None
    for b in bin(k)[2:]:
        r = ec_add(r, r)
        if b == "1":
            r = ec_add(r, pt)
    return r


def msr(k, gg):
    t = k * gg
    return (t >> 384) + ((t >> 383) & 1)


def split(k):
    c1, c2 = msr(k, G1), msr(k, G2)
    k2 = (c1 * MB1 + c2 * MB2) % N
    k1 = (k - k2 * LAM) % N
    return k1, k2


def wnaf(k, w):
    """Digits LSB first, exactly as ec.bend's wn_go computes them."""
    out, i, carry = {}, 0, 0
    end = 32 * top_words(k)
    while i < end or carry:
        win = (k >> i) & ((1 << w) - 1)
        v = win + carry
        if v & 1 == 0:
            carry = ((win & 1) + carry) >> 1
            i += 1
        else:
            if v >= 1 << (w - 1):
                out[i] = v - (1 << w)
                carry = 1
            else:
                out[i] = v
                carry = 0
            i += w
    return out


def top_words(k):
    return (k.bit_length() + 31) // 32


def selftest():
    assert pow(LAM, 3, N) == 1 and pow(BETA, 3, P) == 1
    G = (GX, GY)
    assert ec_mul(LAM, G) == (BETA * GX % P, GY)
    random.seed(11)
    ks = [0, 1, 2, 3, N - 1, N - 2, (N - 1) // 2, (N + 1) // 2, LAM, N - LAM, 2**128, 2**128 - 1,
          2**255, R % N, MB1, N - MB1] + [random.randrange(N) for _ in range(200000)]
    mx = 0
    for k in ks:
        k1, k2 = split(k)
        assert (k1 + k2 * LAM) % N == k % N
        for x in (k1, k2):
            a = x if x <= (N - 1) // 2 else N - x
            mx = max(mx, a.bit_length())
            if k in ks[:16] or random.random() < 0.01:
                for w in (5, WG):
                    d = wnaf(a, w)
                    assert sum(v << i for i, v in d.items()) == a
                    assert all(v & 1 and -(1 << (w - 1)) < v < (1 << (w - 1)) for v in d.values())
    assert mx <= 128, mx
    # wNAF on full-width values too (the Bend code does not assume 128 bits)
    for _ in range(2000):
        a = random.getrandbits(random.choice([1, 2, 31, 32, 33, 64, 127, 128, 129, 200, 255, 256]))
        for w in (5, WG):
            d = wnaf(a, w)
            assert sum(v << i for i, v in d.items()) == a
    print(f"selftest ok: split max {mx} bits")


# ------------------------------------------------------------------ Bend generators

def gen_fe_sub():
    """a - b mod p for a, b < p: a + (2^256 - b) - 2^256 ... done as a - b with borrow, + p if borrow."""
    e = g.Emit()
    a = g.destructure(e, "Fe", "a", "a")
    b = g.destructure(e, "Fe", "b", "b")
    # d = a + ~b + 1 (= a - b + 2^256); carry out = 1 iff a >= b
    C = g.ONE
    d = []
    for j in range(4):
        nb = (f"U32.not({b[j][0]})", f"U32.not({b[j][1]})")
        dj, C = g.add(e, a[j], nb, C)
        d.append(dj)
    # borrow (no carry): add p = 2^256 - c, i.e. subtract c = 2^32 + 977 (mod 2^256)
    # x - c = x + (2^256 - c) mod 2^256
    pl = [g.halves((P >> (64 * j)) & g.M64) for j in range(4)]
    C2 = g.Z
    dp = []
    for j in range(4):
        dj, C2 = g.add(e, d[j], pl[j], C2)
        dp.append(dj)
    flag = e.let(f"(1 - {C[0]} : U32)")
    out = g.select(e, flag, dp, d)
    return "# a - b mod p; a, b < p.\ndef sub(a: Fe, b: Fe) -> Fe:\n" + "\n".join(e.lines) + f"\n  {g.lit('Fe', out)}\n"


def gen_sc_add():
    e = g.Emit()
    a = g.destructure(e, "Sc", "a", "a")
    b = g.destructure(e, "Sc", "b", "b")
    C = g.Z
    s = []
    for j in range(4):
        sj, C = g.add(e, a[j], b[j], C)
        s.append(sj)
    delta = R - N
    out = g.cond_sub(e, s, C[0], [(delta >> (64 * j)) & g.M64 for j in range(4)])
    return "# a + b mod n; a + b < 2n.\ndef add(a: Sc, b: Sc) -> Sc:\n" + "\n".join(e.lines) + f"\n  {g.lit('Sc', out)}\n"


def gen_sc_sqr():
    """Montgomery square: 512-bit square (6 cross products doubled + 4 squares), then a
    word-by-word Montgomery reduction (4 rounds), final conditional subtraction."""
    e = g.Emit()
    a = g.destructure(e, "Sc", "a", "a")
    Z = g.Z
    t = [Z] * 8
    for i in range(4):
        C = Z
        for j in range(i + 1, 4):
            t[i + j], C = g.mac(e, a[j], a[i], t[i + j], C)
        t[i + 4] = C
    C = Z
    for j in range(8):
        t[j], C = g.add(e, t[j], t[j], C)
    C = Z
    for i in range(4):
        t[2 * i], C = g.mac(e, a[i], a[i], t[2 * i], C)
        t[2 * i + 1], C = g.add(e, t[2 * i + 1], C)
    # Montgomery reduction of the 512-bit t (t < n^2 < n R): 4 rounds of m = t_i * inv,
    # t += m n 2^(64 i); the carry ripples into an extra top word t8.
    inv = g.halves((-pow(N, -1, 2**64)) % 2**64)
    Nl = [g.halves((N >> (64 * j)) & g.M64) for j in range(4)]
    top = "0"   # extra bit above t[7]
    for i in range(4):
        m = g.mac_lo(e, t[i], inv, Z, Z)
        C = Z
        for j in range(4):
            t[i + j], C = g.mac(e, m, Nl[j], t[i + j], C)
        # propagate C into t[i+4 ..]
        for j in range(i + 4, 8):
            t[j], C = g.add(e, t[j], C)
        top = e.let(f"({top} + {C[0]} : U32)")
    u = t[4:8]
    delta = R - N
    out = g.cond_sub(e, u, top, [(delta >> (64 * j)) & g.M64 for j in range(4)])
    return ("# Montgomery square a * a / 2^256 mod n.\n"
            "def sqr(a: Sc) -> Sc:\n" + "\n".join(e.lines) + f"\n  {g.lit('Sc', out)}\n")


def gen_mul_shift_384():
    """round(a * b / 2^384) for plain 256-bit a, b (result < 2^129)."""
    e = g.Emit()
    a = g.destructure(e, "Sc", "a", "a")
    b = g.destructure(e, "Sc", "b", "b")
    Z = g.Z
    t = [Z] * 8
    for i in range(4):
        C = Z
        for j in range(4):
            t[i + j], C = g.mac(e, a[j], b[i], t[i + j], C)
        t[i + 4] = C
    rb = e.let(f"({t[5][1]} >> 31n : U32)")
    lo, C = g.add(e, t[6], (rb, "0"))
    hi, C = g.add(e, t[7], C)
    out = [lo[0], lo[1], hi[0], hi[1], C[0], "0", "0", "0"]
    return ("# round(a * b / 2^384), plain integers (GLV split).\n"
            "def mul_shift_384(a: Sc, b: Sc) -> Sc:\n" + "\n".join(e.lines) + f"\n  {g.lit('Sc', out)}\n")


def sc_extra():
    out = [gen_sc_add(), gen_sc_sqr(), gen_mul_shift_384()]
    out.append(g.const("Sc", "glv_g1", G1, "GLV g1"))
    out.append(g.const("Sc", "glv_g2", G2, "GLV g2"))
    out.append(g.const("Sc", "glv_mb1_mont", MB1 * R % N, "-b1 in Montgomery form"))
    out.append(g.const("Sc", "glv_mb2_mont", MB2 * R % N, "-b2 in Montgomery form"))
    out.append(g.const("Sc", "lambda_mont", LAM * R % N, "lambda in Montgomery form"))
    out.append('''# Number of 32-bit words up to the highest non-zero one (0 for 0).
def top_words(a: Sc) -> U32:
  Sc{a0, a1, a2, a3, a4, a5, a6, a7} = a
  Bool.pick(U32, U32.is_ne(a7, 0), 8, Bool.pick(U32, U32.is_ne(a6, 0), 7, Bool.pick(U32, U32.is_ne(a5, 0), 6,
    Bool.pick(U32, U32.is_ne(a4, 0), 5, Bool.pick(U32, U32.is_ne(a3, 0), 4, Bool.pick(U32, U32.is_ne(a2, 0), 3,
    Bool.pick(U32, U32.is_ne(a1, 0), 2, Bool.pick(U32, U32.is_ne(a0, 0), 1, 0))))))))

# Word j (0 for j >= 8).
def word(a: Sc, j: U32) -> U32:
  Sc{a0, a1, a2, a3, a4, a5, a6, a7} = a
  match j:
    case 0: a0
    case 1: a1
    case 2: a2
    case 3: a3
    case 4: a4
    case 5: a5
    case 6: a6
    case 7: a7
    case _: 0

# 2^(32 - s) as (lo, hi) words, s in 0..31: the multiplier that brings bit s to bit 32.
def pw_lo(s: U32) -> U32:
  match s:
''' + "".join(f"    case {s}: {(2**(32 - s)) & g.M32}\n" for s in range(32)) + '''    case _: 0

# 32 bits of a starting at bit i (bits past 255 read as 0): word 1 of (w_j + w_(j+1) 2^32) 2^(32-s).
def bits32(+a: Sc, +i: U32) -> U32:
  +j = (i >> 5n : U32)
  +s = (i .&. 31 : U32)
  U32.mac64(1, word(a, j), word(a, (j + 1 : U32)), pw_lo(s), Bool.pick(U32, U32.is_zero(s), 1, 0), 0, 0, 0, 0)
''')
    return "\n".join(out)


def gen_gtab():
    nt = 1 << (WG - 2)
    pts, acc, G = [], None, (GX, GY)
    two = ec_add(G, G)
    acc = G
    for i in range(nt):
        pts.append(acc)
        acc = ec_add(acc, two)
    for i, p in enumerate(pts):
        assert p == ec_mul(2 * i + 1, G)
    out = ["# GENERATED by gen_secp2.py. Do not edit.",
           f"# (2i+1)·G for i = 0..{nt - 1} (affine), the wNAF-{WG} table for G and λG, as dense `match`es",
           "# on the index (one per 32-bit word; the compiler emits them as constant arrays).",
           "import Base", "import ./fe.bend as F", "", "type Af is Data:", "  Af{x: F.Fe, y: F.Fe}", ""]
    for c, name in ((0, "x"), (1, "y")):
        for w in range(8):
            out.append(f"def g{name}{w}(i: U32) -> U32:")
            out.append("  match i:")
            for i, p in enumerate(pts):
                out.append(f"    case {i}: {(p[c] >> (32 * w)) & g.M32}")
            out.append("    case _: 0")
            out.append("")
    out.append("def g_odd(+i: U32) -> Af:")
    out.append("  Af{F.Fe{" + ", ".join(f"gx{w}(i)" for w in range(8)) + "}, F.Fe{" + ", ".join(f"gy{w}(i)" for w in range(8)) + "}}")
    out.append("")
    out.append(f"def wg() -> U32:\n  {WG}\n")
    return "\n".join(out)


def chain_plan(e):
    """An addition chain for x^e: precompute x^(2^k - 1) for a few k and odd powers 1..2^w-1;
    MSB-first: long runs of ones use the x^(2^k-1) values, the rest a sliding window."""
    bits = bin(e)[2:]
    return bits


def gen_scinv():
    """x^(n-2) (Montgomery form in and out) by a fixed sequence: sliding window w=5 over
    the exponent, with runs of >= 8 ones taken from x^(2^k-1) values."""
    E = N - 2
    bits = bin(E)[2:]
    W = 5
    ones = [1, 2, 3, 4, 6, 8, 14, 28, 56, 112, 126]   # xk = x^(2^k - 1)
    ops = []   # ("sqr", k) or ("mul", var)
    i = 0
    L = len(bits)
    while i < L:
        if bits[i] == "0":
            ops.append(("sqr", 1)); i += 1; continue
        run = 0
        while i + run < L and bits[i + run] == "1":
            run += 1
        if run >= 8:
            k = max(x for x in ones if x <= run)
            ops.append(("sqr", k)); ops.append(("mul", f"x{k}")); i += k; continue
        # sliding window: longest window <= W starting at i ending in a 1
        j = min(i + W, L)
        while bits[j - 1] == "0":
            j -= 1
        v = int(bits[i:j], 2)
        ops.append(("sqr", j - i)); ops.append(("mul", f"u{v}")); i = j
    # the first op squares the initial accumulator (1): replace with direct init
    # simulate to verify and to drop leading squarings of 1
    # model: acc starts at 1 ("one"); emit with acc = None until the first mul
    lines = []
    var = 0

    def nv():
        nonlocal var
        var += 1
        return f"t{var}"
    pre = ["  +u1 = x", "  +x2_ = S.sqr(x)", "  +u3 = S.mul(x2_, x)"]
    for v in range(5, 1 << W, 2):
        pre.append(f"  +u{v} = S.mul(u{v - 2}, x2_)")
    # xk = x^(2^k-1)
    pre += ["  +x1 = x", "  +x2 = S.mul(x2_, x)", "  +x3 = u7_d", ]
    # build x^(2^k-1): x3 = x2^2 * x ; x4 = x3^2*x; x6 = x3^(2^3) * x3; x8 = x6^(2^2)*x2;
    # x14 = x8^(2^6)*x6; x28 = x14^(2^14)*x14; x56 = x28^(2^28)*x28; x112 = x56^(2^56)*x56; x126 = x112^(2^14)*x14
    pre = pre[:-1]
    pre += ["  +x3 = S.mul(S.sqr(x2), x)", "  +x4 = S.mul(S.sqr(x3), x)", "  +x6 = S.mul(sqr_n(3n, x3), x3)",
            "  +x8 = S.mul(sqr_n(2n, x6), x2)", "  +x14 = S.mul(sqr_n(6n, x8), x6)", "  +x28 = S.mul(sqr_n(14n, x14), x14)",
            "  +x56 = S.mul(sqr_n(28n, x28), x28)", "  +x112 = S.mul(sqr_n(56n, x56), x56)", "  +x126 = S.mul(sqr_n(14n, x112), x14)"]
    used = {v for op, v in ops if op == "mul"}
    # model check in Python
    def pw(name):
        if name.startswith("u"):
            return int(name[1:])
        return 2**int(name[1:]) - 1
    acc = None
    body = []
    cur = None
    for op, v in ops:
        if op == "sqr":
            if acc is None:
                continue
            acc = acc * 2**v
            t = nv(); body.append(f"  +{t} = sqr_n({v}n, {cur})" if v > 1 else f"  +{t} = S.sqr({cur})"); cur = t
        else:
            if acc is None:
                acc = pw(v); cur = v; continue
            acc += pw(v)
            t = nv(); body.append(f"  +{t} = S.mul({cur}, {v})"); cur = t
    assert acc == E, (hex(acc), hex(E))
    nsq = sum(v for op, v in ops if op == "sqr")
    nmul = sum(1 for op, v in ops if op == "mul")
    text = "\n".join(pre + body)
    nmul_all = text.count("S.mul(")
    nsq_all = text.count("S.sqr(") + sum(int(k) for k in re.findall(r"sqr_n\((\d+)n", text))
    src = ["# GENERATED by gen_secp2.py. Do not edit.",
           f"# Scalar inversion x^(n-2) in Montgomery form: a fixed addition chain ({nsq_all} squarings,",
           f"# {nmul_all} multiplications), no lists, no table lookups.",
           "import Base", "import ./sc.bend as S", "",
           "def sqr_n(n: Nat, +x: S.Sc) -> S.Sc:", "  match n:", "    case 0n:", "      x", "    case 1n+p:",
           "      sqr_n(p, S.sqr(x))", "",
           "def inv_mont(+x: S.Sc) -> S.Sc:"]
    # keep only the definitions something uses (Bend rejects nothing, but keep it tidy)
    allpre, text = [], "\n".join(body)
    for l in reversed(pre):
        name = l.split("=")[0].strip().lstrip("+")
        if re.search(rf"\b{name}\b", text + "\n" + "\n".join(allpre)) or name == cur:
            allpre.insert(0, l)
    src += allpre + body + [f"  {cur}", ""]
    return "\n".join(src)


def fe_file():
    s = g.fe_file()
    s += "\n" + gen_fe_sub() + "\n" + g.const("Fe", "beta", BETA, "beta: (beta x, y) = lambda (x, y)")
    return s


def sc_file():
    return g.sc_file() + "\n" + sc_extra()


if __name__ == "__main__":
    selftest()
    (HERE / "fe.bend").write_text(fe_file())
    (HERE / "sc.bend").write_text(sc_file())
    (HERE / "gtab.bend").write_text(gen_gtab())
    (HERE / "scinv.bend").write_text(gen_scinv())
    print("wrote fe.bend sc.bend gtab.bend scinv.bend")
