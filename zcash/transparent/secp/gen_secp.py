#!/usr/bin/env python3
"""Generates fe.bend (secp256k1 base field) and sc.bend (scalar field) for Zebend.

Both use 8 little-endian U32 words (4 x 64-bit limbs as (lo, hi) halves) and the forked
Bend's U32.mac64(k, al, ah, bl, bh, cl, ch, dl, dh) = word k of the 128-bit a*b + c + d.

* fe.bend: p = 2^256 - c, c = 2^32 + 977. Values are kept fully reduced in [0, p), in
  plain (non-Montgomery) form. A product is the 512-bit schoolbook product (16 mac64)
  folded twice with 2^256 = c (mod p) (5 mac64 + 3 carries), then one conditional
  subtraction done as "x + c overflows 2^256 iff x >= p".
* sc.bend: n = the group order. Montgomery form (R = 2^256), CIOS over 4 x 64-bit
  limbs, final subtraction by the same overflow trick with 2^256 - n.

  python3 gen_secp.py     # writes fe.bend, sc.bend, gtab.bend
"""
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
P = 2**256 - 2**32 - 977
N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
GX = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
GY = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8
M32 = 2**32 - 1
M64 = 2**64 - 1


def words(x):
    return [(x >> (32 * i)) & M32 for i in range(8)]


class Emit:
    def __init__(self):
        self.lines, self.n = [], 0

    def let(self, expr):
        self.n += 1
        v = f"v{self.n}"
        self.lines.append(f"  +{v} = {expr}")
        return v


Z = ("0", "0")
ONE = ("1", "0")


def mac(e, a, b, c, d):
    """((lo64), (hi64)) of a*b + c + d; each operand a (lo, hi) pair of U32 expressions."""
    args = ", ".join([*a, *b, *c, *d])
    w = [e.let(f"U32.mac64({k}, {args})") for k in range(4)]
    return (w[0], w[1]), (w[2], w[3])


def mac_lo(e, a, b, c, d):
    args = ", ".join([*a, *b, *c, *d])
    return (e.let(f"U32.mac64(0, {args})"), e.let(f"U32.mac64(1, {args})"))


def add(e, x, y, cin=Z):
    return mac(e, x, ONE, y, cin)


def halves(v):
    return (str(v & M32), str(v >> 32))


def destructure(e, T, var, prefix):
    names = [f"{prefix}{i}" for i in range(8)]
    e.lines.append(f"  {T}{{{', '.join('+' + n for n in names)}}} = {var}")
    return [(names[2 * i], names[2 * i + 1]) for i in range(4)]


def select(e, flag, d, u):
    """flag (0/1 U32 expr): d if 1 else u, word by word."""
    m = e.let(f"(0 - {flag} : U32)")
    out = []
    for (dl, dh), (ul, uh) in zip(d, u):
        out.append(e.let(f"(({dl} .&. {m}) .|. ({ul} .&. U32.not({m})) : U32)"))
        out.append(e.let(f"(({dh} .&. {m}) .|. ({uh} .&. U32.not({m})) : U32)"))
    return out


def cond_sub(e, u, k, delta):
    """u: 4 limbs (value U = u + k*2^256, U < 2m); delta = 2^256 - m (limbs). Returns U mod m words."""
    C = Z
    d = []
    for j in range(4):
        dj, C = add(e, u[j], halves(delta[j]), C)
        d.append(dj)
    flag = e.let(f"({k} .|. {C[0]} : U32)")
    return select(e, flag, d, u)


def lit(T, ws):
    return f"{T}{{" + ", ".join(ws) + "}"


def gen_fe_mul(sqr=False):
    e = Emit()
    a = destructure(e, "Fe", "a", "a")
    b = a if sqr else destructure(e, "Fe", "b", "b")
    c = halves(2**32 + 977)
    t = [Z] * 8
    if not sqr:
        for i in range(4):
            C = Z
            for j in range(4):
                t[i + j], C = mac(e, a[j], b[i], t[i + j], C)
            t[i + 4] = C
    else:
        # cross products a_i a_j (i < j), doubled, plus the squares on the diagonal
        for i in range(4):
            C = Z
            for j in range(i + 1, 4):
                t[i + j], C = mac(e, a[j], a[i], t[i + j], C)
            t[i + 4] = C
        # double t (shift left by one bit over 8 limbs): t*2 via add(t, t)
        C = Z
        for j in range(8):
            t[j], C = add(e, t[j], t[j], C)
        # add diagonal squares
        C = Z
        for i in range(4):
            t[2 * i], C = mac(e, a[i], a[i], t[2 * i], C)
            t[2 * i + 1], C = add(e, t[2 * i + 1], C)
    # first fold: r = t_lo + t_hi * c
    C = Z
    r = []
    for j in range(4):
        rj, C = mac(e, t[4 + j], c, t[j], C)
        r.append(rj)
    r4 = C
    # second fold: s = r + r4 * c
    s0, C = mac(e, r4, c, r[0], Z)
    s = [s0]
    for j in range(1, 4):
        sj, C = add(e, r[j], C)
        s.append(sj)
    k = (C[0], "0")
    # third fold: u = s + k * c (cannot overflow)
    u0, C = mac(e, k, c, s[0], Z)
    u = [u0]
    for j in range(1, 4):
        uj, C = add(e, s[j], C)
        u.append(uj)
    out = cond_sub(e, u, "0", [2**32 + 977, 0, 0, 0])
    name = "sqr" if sqr else "mul"
    args = "a: Fe" if sqr else "a: Fe, b: Fe"
    return f"def {name}({args}) -> Fe:\n" + "\n".join(e.lines) + f"\n  {lit('Fe', out)}\n"


def gen_fe_add():
    e = Emit()
    a = destructure(e, "Fe", "a", "a")
    b = destructure(e, "Fe", "b", "b")
    C = Z
    s = []
    for j in range(4):
        sj, C = add(e, a[j], b[j], C)
        s.append(sj)
    out = cond_sub(e, s, C[0], [2**32 + 977, 0, 0, 0])
    return "# a + b mod p; a < p, b <= p.\ndef add(a: Fe, b: Fe) -> Fe:\n" + "\n".join(e.lines) + f"\n  {lit('Fe', out)}\n"


def gen_pminus(T, m, name):
    """m - b for b <= m (no reduction): m + ~b + 1."""
    e = Emit()
    b = destructure(e, T, "b", "b")
    C = ONE
    out = []
    for j in range(4):
        nb = (f"U32.not({b[j][0]})", f"U32.not({b[j][1]})")
        dj, C = add(e, nb, halves((m >> (64 * j)) & M64), C)
        out += list(dj)
    return f"def {name}(b: {T}) -> {T}:\n" + "\n".join(e.lines) + f"\n  {lit(T, out)}\n"


def gen_sc_mul():
    e = Emit()
    a = destructure(e, "Sc", "a", "a")
    b = destructure(e, "Sc", "b", "b")
    Nl = [halves((N >> (64 * j)) & M64) for j in range(4)]
    inv = halves((-pow(N, -1, 2**64)) % 2**64)
    t = [Z] * 4
    t4 = Z
    for i in range(4):
        C = Z
        for j in range(4):
            t[j], C = mac(e, a[j], b[i], t[j], C)
        t4, c1 = add(e, t4, C)
        t5 = c1[0]
        m = mac_lo(e, t[0], inv, Z, Z)
        _, C = mac(e, m, Nl[0], t[0], Z)
        nt = []
        for j in range(1, 4):
            ntj, C = mac(e, m, Nl[j], t[j], C)
            nt.append(ntj)
        t3, c2 = add(e, t4, C)
        nt.append(t3)
        t = nt
        t4 = (e.let(f"({t5} + {c2[0]} : U32)"), "0")
    delta = 2**256 - N
    out = cond_sub(e, t, t4[0], [(delta >> (64 * j)) & M64 for j in range(4)])
    return ("# Montgomery product a * b / 2^256 mod n (CIOS, 4 x 64-bit limbs).\n"
            "def mul(a: Sc, b: Sc) -> Sc:\n" + "\n".join(e.lines) + f"\n  {lit('Sc', out)}\n")


def gen_reduce_once(T, m, name):
    """x mod m for x < 2^256 < 2m: x + (2^256 - m) overflows iff x >= m."""
    e = Emit()
    x = destructure(e, T, "x", "x")
    delta = 2**256 - m
    out = cond_sub(e, x, "0", [(delta >> (64 * j)) & M64 for j in range(4)])
    return f"def {name}(x: {T}) -> {T}:\n" + "\n".join(e.lines) + f"\n  {lit(T, out)}\n"


def gen_is_lt(T, m, name):
    """x < m  <=>  x + (2^256 - m) does not overflow."""
    e = Emit()
    x = destructure(e, T, "x", "x")
    delta = 2**256 - m
    C = Z
    for j in range(4):
        _, C = add(e, x[j], halves((delta >> (64 * j)) & M64), C)
    return f"def {name}(x: {T}) -> Bool:\n" + "\n".join(e.lines) + f"\n  U32.is_zero({C[0]})\n"


def const(T, name, v, comment):
    return f"# {comment}\ndef {name}() -> {T}:\n  {lit(T, [str(w) for w in words(v)])}\n"


COMMON = '''
def eq(a: {T}, b: {T}) -> Bool:
  {T}{{a0, a1, a2, a3, a4, a5, a6, a7}} = a
  {T}{{b0, b1, b2, b3, b4, b5, b6, b7}} = b
  U32.is_eq(a0, b0) && U32.is_eq(a1, b1) && U32.is_eq(a2, b2) && U32.is_eq(a3, b3) && U32.is_eq(a4, b4) && U32.is_eq(a5, b5) && U32.is_eq(a6, b6) && U32.is_eq(a7, b7)

def is_zero(a: {T}) -> Bool:
  {T}{{a0, a1, a2, a3, a4, a5, a6, a7}} = a
  U32.is_zero((a0 .|. a1 .|. a2 .|. a3 .|. a4 .|. a5 .|. a6 .|. a7 : U32))

def zero() -> {T}:
  {T}{{0, 0, 0, 0, 0, 0, 0, 0}}

def be_word(+xs: +List<U32>, +i: Nat) -> U32:
  match xs:
    case Con{{a, Con{{b, Con{{c, Con{{d, _}}}}}}}}:
      ((a << 24n) .|. (b << 16n) .|. (c << 8n) .|. d : U32)
    case _:
      0

def drop(xs: +List<U32>, n: Nat) -> +List<U32>:
  match xs n:
    case Nil{{}} _:
      Nil{{}}
    case Con{{h, t}} 0n:
      h <> t
    case Con{{_, t}} 1n+p:
      drop(t, p)

# 32 big-endian bytes (missing bytes read as 0) as a value (no reduction).
def from_be(+xs: +List<U32>) -> {T}:
  {T}{{be_word(drop(xs, 28n), 0n), be_word(drop(xs, 24n), 0n), be_word(drop(xs, 20n), 0n), be_word(drop(xs, 16n), 0n),
      be_word(drop(xs, 12n), 0n), be_word(drop(xs, 8n), 0n), be_word(drop(xs, 4n), 0n), be_word(xs, 0n)}}

def be4(+w: U32, acc: +List<U32>) -> +List<U32>:
  (w >> 24n : U32) <> ((w >> 16n) .&. 255 : U32) <> ((w >> 8n) .&. 255 : U32) <> (w .&. 255 : U32) <> acc

def to_be(a: {T}) -> +List<U32>:
  {T}{{a0, a1, a2, a3, a4, a5, a6, a7}} = a
  be4(a7, be4(a6, be4(a5, be4(a4, be4(a3, be4(a2, be4(a1, be4(a0, Nil{{}}))))))))

def low_word(a: {T}) -> U32:
  {T}{{a0, _, _, _, _, _, _, _}} = a
  a0

'''


def fe_file():
    out = ["# GENERATED by gen_secp.py. Do not edit.",
           "# secp256k1 base field GF(p), p = 2^256 - 2^32 - 977: 8 little-endian U32 words, fully",
           "# reduced, plain form. Products: 4 x 64-bit limbs via U32.mac64, folded with 2^256 = 2^32 + 977.",
           "import Base", "", "type Fe is Data:", "  Fe{l0: U32, l1: U32, l2: U32, l3: U32, l4: U32, l5: U32, l6: U32, l7: U32}", ""]
    out.append(gen_fe_mul(False))
    out.append("# Dedicated squaring: 6 cross products doubled + 4 squares.")
    out.append(gen_fe_mul(True))
    out.append(gen_fe_add())
    out.append("# p - b for b <= p.")
    out.append(gen_pminus("Fe", P, "p_minus"))
    out.append("# x mod p for any 256-bit x.")
    out.append(gen_reduce_once("Fe", P, "reduce"))
    out.append(gen_is_lt("Fe", P, "is_canonical"))
    out.append(const("Fe", "one", 1, "1"))
    out.append(const("Fe", "seven", 7, "the curve constant b"))
    out.append(COMMON.replace("{T}", "Fe").replace("{{", "{").replace("}}", "}"))
    return "\n".join(out)


def sc_file():
    R = 2**256
    out = ["# GENERATED by gen_secp.py. Do not edit.",
           "# secp256k1 scalar field GF(n): 8 little-endian U32 words. `mul` is a Montgomery product",
           "# (R = 2^256); the other helpers work on plain values.",
           "import Base", "", "type Sc is Data:", "  Sc{l0: U32, l1: U32, l2: U32, l3: U32, l4: U32, l5: U32, l6: U32, l7: U32}", ""]
    out.append(gen_sc_mul())
    out.append("# x mod n for any 256-bit x.")
    out.append(gen_reduce_once("Sc", N, "reduce"))
    out.append(gen_is_lt("Sc", N, "is_lt_n"))
    out.append(gen_is_lt("Sc", (N - 1) // 2 + 1, "is_low"))
    out.append(gen_pminus("Sc", N, "n_minus"))
    out.append(gen_is_lt("Sc", P - N, "is_lt_p_minus_n"))
    out.append(const("Sc", "n_value", N, "n itself, as a plain value"))
    out.append(const("Sc", "r2", R * R % N, "R^2 mod n (to Montgomery form: mul(x, r2))"))
    out.append(const("Sc", "mont_one", R % N, "R mod n (1 in Montgomery form)"))
    out.append(const("Sc", "n_minus_2", N - 2, "n - 2 (Fermat inversion exponent)"))
    out.append(COMMON.replace("{T}", "Sc").replace("{{", "{").replace("}}", "}"))
    return "\n".join(out)


def ec_add(p1, p2):
    if p1 is None:
        return p2
    if p2 is None:
        return p1
    (x1, y1), (x2, y2) = p1, p2
    if x1 == x2 and (y1 + y2) % P == 0:
        return None
    if p1 == p2:
        l = 3 * x1 * x1 * pow(2 * y1, -1, P) % P
    else:
        l = (y2 - y1) * pow(x2 - x1, -1, P) % P
    x3 = (l * l - x1 - x2) % P
    return (x3, (l * (x1 - x3) - y1) % P)


def gtab_file():
    out = ["# GENERATED by gen_secp.py. Do not edit.",
           "# k * G for k = 1..15 (affine), the fixed-base window table of ECDSA verification.",
           "import Base", "import ./fe.bend as F", "", "type Af is Data:", "  Af{x: F.Fe, y: F.Fe}", ""]
    pts, acc = [], None
    for k in range(1, 16):
        acc = ec_add(acc, (GX, GY))
        pts.append(acc)
    fe = lambda v: "F.Fe{" + ", ".join(str(w) for w in words(v)) + "}"
    out.append("def g_table() -> List<&2, Af>:")
    out.append("  [" + ",\n   ".join(f"Af{{{fe(x)}, {fe(y)}}}" for x, y in pts) + "]")
    out.append("")
    return "\n".join(out)


if __name__ == "__main__":
    (HERE / "fe.bend").write_text(fe_file())
    (HERE / "sc.bend").write_text(sc_file())
    (HERE / "gtab.bend").write_text(gtab_file())
    print("wrote fe.bend sc.bend gtab.bend")
