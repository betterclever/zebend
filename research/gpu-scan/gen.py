#!/usr/bin/env python3
"""Generates zcrypto.bend: straight-line Bend for Ironwood trial decryption.

Field elements of GF(p), p the Pallas base prime, are 16 limbs of 16 bits in
Montgomery form (R = 2^256), so every 16x16-bit product fits a U32 (Bend has no
U64). Point arithmetic uses the complete Renes-Costello-Batina formulas for
a = 0 (y^2 = x^3 + 5). BLAKE2b emulates 64-bit words as (lo, hi) U32 pairs.
"""

P = 0x40000000000000000000000000000000224698FC094CF91B992D30ED00000001
R = 1 << 256
NL = 16
MASK = 0xFFFF


def limbs(x):
    return [(x >> (16 * i)) & MASK for i in range(NL)]


PL = limbs(P)


class Emit:
    def __init__(self):
        self.lines = []
        self.n = 0

    def fresh(self, base="v"):
        self.n += 1
        return f"{base}{self.n}"

    def let(self, expr, base="v"):
        v = self.fresh(base)
        self.lines.append(f"  +{v} = {expr}")
        return v


def u32(expr):
    return f"({expr} : U32)"


def fe_lit(vals):
    return "F{" + ", ".join(str(v) for v in vals) + "}"


def fe_destructure(e, name, prefix):
    names = [f"{prefix}{i}" for i in range(NL)]
    e.lines.append(f"  F{{{', '.join('+' + n for n in names)}}} = {name}")
    return names


def cond_sub_p(e, t, top):
    """t: 16 limb vars (value < 2p), top: extra limb var or None. Returns limbs of t mod p."""
    d = []
    borrow = None
    for j in range(NL):
        expr = f"{t[j]} + 65536 - {PL[j]}" + (f" - {borrow}" if borrow else "")
        s = e.let(u32(expr))
        d.append(e.let(u32(f"{s} .&. 65535")))
        borrow = e.let(u32(f"1 - ({s} >> 16n)"))
    if top is not None:
        # value = top*2^256 + t; t - p underflows iff borrow and top == 0
        borrow = e.let(u32(f"{borrow} .&. (1 - {top})"))
    mask = e.let(u32(f"0 - {borrow}"))  # all ones when t < p: keep t
    nmask = e.let(u32(f"{mask} .^. 4294967295"))
    return [e.let(u32(f"({t[j]} .&. {mask}) .|. ({d[j]} .&. {nmask})")) for j in range(NL)]


def gen_fmul():
    e = Emit()
    a = fe_destructure(e, "a", "a")
    b = fe_destructure(e, "b", "b")
    t = [None] * (NL + 2)  # None = 0
    for i in range(NL):
        c = None
        for j in range(NL):
            parts = [x for x in (t[j], f"{a[j]} * {b[i]}", c) if x]
            s = e.let(u32(" + ".join(parts)))
            t[j] = e.let(u32(f"{s} .&. 65535"))
            c = e.let(u32(f"{s} >> 16n"))
        parts = [x for x in (t[NL], c) if x]
        s = e.let(u32(" + ".join(parts)))
        t[NL] = e.let(u32(f"{s} .&. 65535"))
        t[NL + 1] = e.let(u32(f"{s} >> 16n"))
        # m = t0 * (-p^-1) mod 2^16; p = 1 mod 2^16 so -p^-1 = 0xffff
        m = e.let(u32(f"(65536 - {t[0]}) .&. 65535"))
        # t += m*p, then shift one limb right. t0 + m*1 is 0 mod 2^16.
        s = e.let(u32(f"{t[0]} + {m}"))
        c = e.let(u32(f"{s} >> 16n"))
        nt = [None] * (NL + 2)
        for j in range(1, NL):
            parts = [t[j]] if t[j] else []
            if PL[j]:
                parts.append(f"{m} * {PL[j]}")
            parts.append(c)
            s = e.let(u32(" + ".join(parts)))
            nt[j - 1] = e.let(u32(f"{s} .&. 65535"))
            c = e.let(u32(f"{s} >> 16n"))
        s = e.let(u32(f"{t[NL]} + {c}"))
        nt[NL - 1] = e.let(u32(f"{s} .&. 65535"))
        c = e.let(u32(f"{s} >> 16n"))
        nt[NL] = e.let(u32(f"{t[NL + 1]} + {c}"))
        t = nt
    r = cond_sub_p(e, t[:NL], t[NL])
    body = "\n".join(e.lines)
    return f"def fmul(a: F, b: F) -> F:\n{body}\n  {fe_lit(r)}\n"


def gen_fadd():
    e = Emit()
    a = fe_destructure(e, "a", "a")
    b = fe_destructure(e, "b", "b")
    t = []
    c = None
    for j in range(NL):
        s = e.let(u32(f"{a[j]} + {b[j]}" + (f" + {c}" if c else "")))
        t.append(e.let(u32(f"{s} .&. 65535")))
        c = e.let(u32(f"{s} >> 16n"))
    r = cond_sub_p(e, t, c)
    return f"def fadd(a: F, b: F) -> F:\n" + "\n".join(e.lines) + f"\n  {fe_lit(r)}\n"


def gen_fsub():
    e = Emit()
    a = fe_destructure(e, "a", "a")
    b = fe_destructure(e, "b", "b")
    d = []
    borrow = None
    for j in range(NL):
        s = e.let(u32(f"{a[j]} + 65536 - {b[j]}" + (f" - {borrow}" if borrow else "")))
        d.append(e.let(u32(f"{s} .&. 65535")))
        borrow = e.let(u32(f"1 - ({s} >> 16n)"))
    mask = e.let(u32(f"0 - {borrow}"))  # add p back when a < b
    r = []
    c = None
    for j in range(NL):
        s = e.let(u32(f"{d[j]} + ({PL[j]} .&. {mask})" + (f" + {c}" if c else "")))
        r.append(e.let(u32(f"{s} .&. 65535")))
        c = e.let(u32(f"{s} >> 16n"))
    return f"def fsub(a: F, b: F) -> F:\n" + "\n".join(e.lines) + f"\n  {fe_lit(r)}\n"


def gen_is_eq():
    e = Emit()
    a = fe_destructure(e, "a", "a")
    b = fe_destructure(e, "b", "b")
    acc = " .|. ".join(f"({a[j]} .^. {b[j]})" for j in range(NL))
    x = e.let(u32(acc))
    # 1 if x == 0 else 0
    y = e.let(u32(f"({x} .|. (0 - {x})) >> 31n"))
    return "def fis_eq(a: F, b: F) -> U32:\n" + "\n".join(e.lines) + f"\n  (1 - {y} : U32)\n"


def const_def(name, value, mont=True):
    v = (value * R) % P if mont else value
    return f"def {name}() -> F:\n  {fe_lit(limbs(v))}\n"


def pow_def(name, exp):
    """x^exp as runs of squarings then a multiply (left-to-right binary)."""
    bits = bin(exp)[2:]
    lines = ["  +x0 = x", "  acc0 = x0"]
    acc = "acc0"
    k = 0
    i = 1
    while i < len(bits):
        run = 0
        while i < len(bits) and bits[i] == "0":
            run += 1
            i += 1
        if i < len(bits):  # bits[i] == '1'
            run += 1
            k += 1
            lines.append(f"  acc{k} = fmul(sqr_n({run}n, {acc}), x0)")
            acc = f"acc{k}"
            i += 1
        else:
            k += 1
            lines.append(f"  acc{k} = sqr_n({run}n, {acc})")
            acc = f"acc{k}"
    return f"def {name}(x: F) -> F:\n" + "\n".join(lines) + f"\n  {acc}\n"


HEADER = '''# GENERATED by gen.py. Do not edit.
# Pallas base field GF(p) in Montgomery form, 16 limbs x 16 bits.
import Base

type F is Data:
  F{''' + ", ".join(f"l{i}: U32" for i in range(NL)) + '''}

'''

FIELD_EXTRA = '''
def fsqr(+a: F) -> F:
  fmul(a, a)

def sqr_n(n: Nat, x: F) -> F:
  match n:
    case 0n:
      x
    case 1n+k:
      sqr_n(k, fsqr(x))

# canonical -> Montgomery and back
def to_mont(x: F) -> F:
  fmul(x, R2())

def from_mont(x: F) -> F:
  fmul(x, F{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0})
'''


def field_module():
    out = [HEADER, gen_fmul(), gen_fadd(), gen_fsub(), gen_is_eq()]
    out.append(const_def("R2", R, mont=True))  # R2 = R^2 mod p = mont(R)
    out.append(const_def("FONE", 1))
    out.append(const_def("FZERO", 0, mont=False))
    out.append(FIELD_EXTRA)
    out.append(pow_def("pow_pm2", P - 2))
    out.append("def finv(x: F) -> F:\n  pow_pm2(x)\n")
    return "\n".join(out)


if __name__ == "__main__":
    import sys
    open(sys.argv[1] if len(sys.argv) > 1 else "zcrypto.bend", "w").write(field_module())


# ---------------------------------------------------------------------------
# Selection, curve arithmetic, decompression
# ---------------------------------------------------------------------------

def gen_fsel():
    e = Emit()
    a = fe_destructure(e, "a", "a")
    b = fe_destructure(e, "b", "b")
    e.lines.append("  +m = (0 - c : U32)")
    e.lines.append("  +nm = (m .^. 4294967295 : U32)")
    r = [e.let(u32(f"({a[j]} .&. m) .|. ({b[j]} .&. nm)")) for j in range(NL)]
    return "# c == 1 selects a, c == 0 selects b\ndef fsel(+c: U32, a: F, b: F) -> F:\n" + "\n".join(e.lines) + f"\n  {fe_lit(r)}\n"


T_ODD = (P - 1) >> 32
C3 = (T_ODD - 1) // 2
C5 = pow(5, T_ODD, P)

CURVE = '''
type Pt is Data:
  Pt{x: F, y: F, z: F}

type Aff is Data:
  Aff{x: F, y: F}

# 15 * a (b3 = 3 * 5 for y^2 = x^3 + 5)
def mul15(+a: F) -> F:
  +a2 = fadd(a, a)
  +a4 = fadd(a2, a2)
  +a8 = fadd(a4, a4)
  fsub(fadd(a8, a8), a)

# Renes-Costello-Batina 2016, Algorithm 9 (doubling, a = 0); complete.
def pdbl(p: Pt) -> Pt:
  Pt{+x, +y, +z} = p
  +t0 = fsqr(y)
  +z3a = fadd(t0, t0)
  +z3b = fadd(z3a, z3a)
  +z3c = fadd(z3b, z3b)
  t1 = fmul(y, z)
  +t2 = mul15(fsqr(z))
  x3a = fmul(t2, z3c)
  y3a = fadd(t0, t2)
  z3 = fmul(t1, z3c)
  +t1b = fadd(t2, t2)
  t2b = fadd(t1b, t2)
  +t0b = fsub(t0, t2b)
  +x3b = fmul(t0b, fmul(x, y))
  Pt{fadd(x3b, x3b), fadd(x3a, fmul(t0b, y3a)), z3}

# RCB Algorithm 8 (mixed addition P + Q, Q affine and not the identity, a = 0).
def padd(p: Pt, q: Aff) -> Pt:
  Pt{+x1, +y1, +z1} = p
  Aff{+x2, +y2} = q
  +t0a = fmul(x1, x2)
  +t1a = fmul(y1, y2)
  t3a = fmul(fadd(x2, y2), fadd(x1, y1))
  +t3 = fsub(t3a, fadd(t0a, t1a))
  +t4 = fadd(fmul(y2, z1), y1)
  y3a = fadd(fmul(x2, z1), x1)
  +x3a = fadd(t0a, t0a)
  +t0 = fadd(x3a, t0a)
  +t2 = mul15(z1)
  +z3a = fadd(t1a, t2)
  +t1 = fsub(t1a, t2)
  +y3b = mul15(y3a)
  x3 = fsub(fmul(t3, t1), fmul(t4, y3b))
  y3 = fadd(fmul(t1, z3a), fmul(y3b, t0))
  z3 = fadd(fmul(z3a, t4), fmul(t0, t3))
  Pt{x3, y3, z3}

def add_if(b: Bool, p: Pt, +q: Aff) -> Pt:
  match b:
    case True{}:
      padd(p, q)
    case False{}:
      p

# Left-to-right double-and-add over the 32 bits of w, most significant first.
# The scalar is the wallet's ivk: the same for every lane, so the branch is uniform.
def smul_w(n: Nat, w: U32, p: Pt, +q: Aff) -> Pt:
  match n:
    case 0n:
      p
    case 1n+k:
      d = pdbl(p)
      +w2 = w
      smul_w(k, (w2 << 1n : U32), add_if(U32.is_eq((w2 >> 31n : U32), 1), d, q), q)

type Sc is Data:
  Sc{w0: U32, w1: U32, w2: U32, w3: U32, w4: U32, w5: U32, w6: U32, w7: U32}

def PID() -> Pt:
  Pt{FZERO(), FONE(), FZERO()}

def smul(s: Sc, +q: Aff) -> Pt:
  Sc{w0, w1, w2, w3, w4, w5, w6, w7} = s
  p7 = smul_w(32n, w7, PID(), q)
  p6 = smul_w(32n, w6, p7, q)
  p5 = smul_w(32n, w5, p6, q)
  p4 = smul_w(32n, w4, p5, q)
  p3 = smul_w(32n, w3, p4, q)
  p2 = smul_w(32n, w2, p3, q)
  p1 = smul_w(32n, w1, p2, q)
  smul_w(32n, w0, p1, q)

type S3 is Data:
  S3{z: F, t: F, c: F}

# One Tonelli-Shanks round (RFC 9380 App. I.4) after n squarings.
def ts_step(n: Nat, +z: F, +t: F, c: F) -> S3:
  +e = fis_eq(sqr_n(n, t), FONE())
  +cc = c
  z2 = fsel(e, z, fmul(z, cc))
  +c2 = fsqr(cc)
  t2 = fsel(e, t, fmul(t, c2))
  S3{z2, t2, c2}

def ts_z(s: S3) -> F:
  S3{z, _, _} = s
  z

def ts_loop(+n: Nat, s: S3) -> F:
  match n s:
    case 0n S3{z, t, c}:
      ts_z(ts_step(0n, z, t, c))
    case 1n+k S3{z, t, c}:
      ts_loop(k, ts_step(1n+k, z, t, c))

# Constant-time square root for p - 1 = 2^32 * t (no early exits: uniform lanes).
def fsqrt(+x: F) -> F:
  +z0 = pow_c3(x)
  t0 = fmul(fsqr(z0), x)
  ts_loop(30n, S3{fmul(z0, x), t0, C5()})

type U8w is Data:
  U8w{w0: U32, w1: U32, w2: U32, w3: U32, w4: U32, w5: U32, w6: U32, w7: U32}

def words_to_f(+a: U32, +b: U32, +c: U32, +d: U32, +e: U32, +f: U32, +g: U32, +h: U32) -> F:
  F{(a .&. 65535 : U32), (a >> 16n : U32), (b .&. 65535 : U32), (b >> 16n : U32),
    (c .&. 65535 : U32), (c >> 16n : U32), (d .&. 65535 : U32), (d >> 16n : U32),
    (e .&. 65535 : U32), (e >> 16n : U32), (f .&. 65535 : U32), (f >> 16n : U32),
    (g .&. 65535 : U32), (g >> 16n : U32), (h .&. 65535 : U32), (h >> 16n : U32)}

def f_to_words(a: F) -> U8w:
  F{a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15} = a
  U8w{(a0 .|. (a1 << 16n) : U32), (a2 .|. (a3 << 16n) : U32), (a4 .|. (a5 << 16n) : U32),
    (a6 .|. (a7 << 16n) : U32), (a8 .|. (a9 << 16n) : U32), (a10 .|. (a11 << 16n) : U32),
    (a12 .|. (a13 << 16n) : U32), (a14 .|. (a15 << 16n) : U32)}

def f_low_bit(+a: F) -> U32:
  F{a0, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} = a
  (a0 .&. 1 : U32)

type Dec is Data:
  Dec{ok: U32, q: Aff}

# Decompresses an encoded Pallas point (x LE, bit 255 = sign of y). ok = 1 on success.
def decompress(e: U8w) -> Dec:
  U8w{w0, w1, w2, w3, w4, w5, w6, +w7} = e
  +xm = to_mont(words_to_f(w0, w1, w2, w3, w4, w5, w6, (w7 .&. 2147483647 : U32)))
  +rhs = fadd(fmul(fsqr(xm), xm), FIVE())
  +y = fsqrt(rhs)
  ok = fis_eq(fsqr(y), rhs)
  flip = ((f_low_bit(from_mont(y)) .^. (w7 >> 31n)) : U32)
  Dec{ok, Aff{xm, fsel(flip, fsub(FZERO(), y), y)}}

def enc_fin(xa: U8w, ybit: U32) -> U8w:
  U8w{a0, a1, a2, a3, a4, a5, a6, a7} = xa
  U8w{a0, a1, a2, a3, a4, a5, a6, (a7 .|. (ybit << 31n) : U32)}

# repr_P of a projective point: affine x LE with the sign of y in bit 255.
def encode(p: Pt) -> U8w:
  Pt{x, y, z} = p
  +zi = finv(z)
  enc_fin(f_to_words(from_mont(fmul(x, zi))), f_low_bit(from_mont(fmul(y, zi))))
'''


# ---------------------------------------------------------------------------
# BLAKE2b-256 (one 128-byte block, 64-byte message) with 64-bit words as U32 pairs
# ---------------------------------------------------------------------------

B2_IV = [0x6A09E667F3BCC908, 0xBB67AE8584CAA73B, 0x3C6EF372FE94F82B, 0xA54FF53A5F1D36F1,
         0x510E527FADE682D1, 0x9B05688C2B3E6C1F, 0x1F83D9ABFB41BD6B, 0x5BE0CD19137E2179]
SIGMA = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
    [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
    [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
    [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
    [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
    [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
    [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
    [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
    [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
]


class W64:
    """A 64-bit word: each half is a var name or an int constant."""
    def __init__(self, lo, hi):
        self.lo, self.hi = lo, hi


def c64(x):
    return W64(x & 0xFFFFFFFF, x >> 32)


def isc(x):
    return isinstance(x, int)


def gen_blake():
    """One def per round (a single straight-line def overflows the Bend compiler)."""
    defs = []
    vnames = [f"v{i}{h}" for i in range(16) for h in ("l", "h")]
    mparams = [f"m{i}{h}" for i in range(8) for h in ("l", "h")]
    v16 = "type V16 is Data:\n  V16{" + ", ".join(f"{n}: U32" for n in vnames) + "}\n"
    defs.append(v16)
    for r in range(12):
        e = Emit()
        e.lines.append("  V16{" + ", ".join("+" + n for n in vnames) + "} = st")

        def op(a, sym, b):
            if isc(a) and isc(b):
                return {"^": a ^ b, "+": (a + b) & 0xFFFFFFFF}[sym]
            if sym == "^" and (a == 0 or b == 0):
                return b if a == 0 else a
            if sym == "+" and (a == 0 or b == 0):
                return b if a == 0 else a
            o = {"^": ".^.", "+": "+"}[sym]
            return e.let(u32(f"{a} {o} {b}"))

        def add(a, b):
            if isc(b.lo) and isc(b.hi) and b.lo == 0 and b.hi == 0:
                return a
            lo = e.let(u32(f"{a.lo} + {b.lo}"))
            nlo = e.let(u32(f"{lo} .^. 4294967295"))
            carry = e.let(u32(f"(({a.lo} .&. {b.lo}) .|. (({a.lo} .|. {b.lo}) .&. {nlo})) >> 31n"))
            hi = e.let(u32(f"{a.hi} + {b.hi} + {carry}"))
            return W64(lo, hi)

        def xor(a, b):
            return W64(op(a.lo, "^", b.lo), op(a.hi, "^", b.hi))

        def rotr(a, n):
            if n == 32:
                return W64(a.hi, a.lo)
            if n < 32:
                lo = e.let(u32(f"({a.lo} >> {n}n) .|. ({a.hi} << {32 - n}n)"))
                hi = e.let(u32(f"({a.hi} >> {n}n) .|. ({a.lo} << {32 - n}n)"))
                return W64(lo, hi)
            lo = e.let(u32(f"({a.lo} << 1n) .|. ({a.hi} >> 31n)"))
            hi = e.let(u32(f"({a.hi} << 1n) .|. ({a.lo} >> 31n)"))
            return W64(lo, hi)

        v = [W64(f"v{i}l", f"v{i}h") for i in range(16)]
        m = [W64(f"m{i}l", f"m{i}h") for i in range(8)] + [c64(0)] * 8

        def G(a, b, c, d, x, y):
            v[a] = add(add(v[a], v[b]), x)
            v[d] = rotr(xor(v[d], v[a]), 32)
            v[c] = add(v[c], v[d])
            v[b] = rotr(xor(v[b], v[c]), 24)
            v[a] = add(add(v[a], v[b]), y)
            v[d] = rotr(xor(v[d], v[a]), 16)
            v[c] = add(v[c], v[d])
            v[b] = rotr(xor(v[b], v[c]), 63)

        sg = SIGMA[r % 10]
        G(0, 4, 8, 12, m[sg[0]], m[sg[1]]); G(1, 5, 9, 13, m[sg[2]], m[sg[3]])
        G(2, 6, 10, 14, m[sg[4]], m[sg[5]]); G(3, 7, 11, 15, m[sg[6]], m[sg[7]])
        G(0, 5, 10, 15, m[sg[8]], m[sg[9]]); G(1, 6, 11, 12, m[sg[10]], m[sg[11]])
        G(2, 7, 8, 13, m[sg[12]], m[sg[13]]); G(3, 4, 9, 14, m[sg[14]], m[sg[15]])
        outs = []
        for w in v:
            outs += [str(w.lo) if isc(w.lo) else w.lo, str(w.hi) if isc(w.hi) else w.hi]
        sig = ", ".join(f"+{q}: U32" for q in mparams)
        defs.append(f"def b2_round{r}(st: V16, {sig}) -> V16:\n" + "\n".join(e.lines) + "\n  V16{" + ", ".join(outs) + "}\n")
    pers = b"Zcash_OrchardKDF"
    h = list(B2_IV)
    h[0] ^= 0x01010020
    h[6] ^= int.from_bytes(pers[:8], "little")
    h[7] ^= int.from_bytes(pers[8:], "little")
    init = h + list(B2_IV)
    init[12] = B2_IV[4] ^ 64
    init[14] = B2_IV[6] ^ 0xFFFFFFFFFFFFFFFF
    lit = "V16{" + ", ".join(f"{x & 0xFFFFFFFF}, {x >> 32}" for x in init) + "}"
    margs = ", ".join(mparams)
    chain = lit
    for r in range(12):
        chain = f"b2_round{r}({chain}, {margs})"
    fin = "def b2_out(st: V16) -> U8w:\n  V16{" + ", ".join(vnames) + "} = st\n"
    outs = []
    for i in range(4):
        for half, sh in (("l", 0), ("h", 32)):
            outs.append(f"({(h[i] >> sh) & 0xFFFFFFFF} .^. v{i}{half} .^. v{i + 8}{half} : U32)")
    fin += "  U8w{" + ", ".join(outs) + "}\n"
    defs.append(fin)
    sig = ", ".join(f"+{q}: U32" for q in mparams)
    defs.append(f"# K = BLAKE2b-256(personal \"Zcash_OrchardKDF\", m), m = 64 bytes as 8 LE u64 (lo, hi)\n"
                f"def kdf({sig}) -> U8w:\n  b2_out({chain})\n")
    return "\n".join(defs)


def gen_chacha():
    """ChaCha20 (RFC 8439) block with counter 1, nonce 0: returns keystream word 0."""
    e = Emit()
    k = [f"k{i}" for i in range(8)]
    init = [0x61707865, 0x3320646E, 0x79622D32, 0x6B206574] + k + [1, 0, 0, 0]
    x = list(init)

    def add(a, b):
        if isc(a) and isc(b):
            return (a + b) & 0xFFFFFFFF
        return e.let(u32(f"{a} + {b}"))

    def xr(a, b):
        if isc(a) and isc(b):
            return a ^ b
        if isc(a) and a == 0:
            return b
        if isc(b) and b == 0:
            return a
        return e.let(u32(f"{a} .^. {b}"))

    def rotl(a, n):
        if isc(a):
            return ((a << n) | (a >> (32 - n))) & 0xFFFFFFFF
        return e.let(u32(f"({a} << {n}n) .|. ({a} >> {32 - n}n)"))

    def qr(a, b, c, d):
        x[a] = add(x[a], x[b]); x[d] = rotl(xr(x[d], x[a]), 16)
        x[c] = add(x[c], x[d]); x[b] = rotl(xr(x[b], x[c]), 12)
        x[a] = add(x[a], x[b]); x[d] = rotl(xr(x[d], x[a]), 8)
        x[c] = add(x[c], x[d]); x[b] = rotl(xr(x[b], x[c]), 7)

    for _ in range(10):
        qr(0, 4, 8, 12); qr(1, 5, 9, 13); qr(2, 6, 10, 14); qr(3, 7, 11, 15)
        qr(0, 5, 10, 15); qr(1, 6, 11, 12); qr(2, 7, 8, 13); qr(3, 4, 9, 14)
    w0 = add(x[0], init[0])
    sig = ", ".join(f"+{p}: U32" for p in k)
    return f"def chacha_w0({sig}) -> U32:\n" + "\n".join(e.lines) + f"\n  {w0}\n"


PIPELINE = '''
type Rec is Data:
  Rec{e: U8w, c: U32}

def u8w_kdf(+s: U8w, +p: U8w) -> U8w:
  U8w{s0, s1, s2, s3, s4, s5, s6, s7} = s
  U8w{p0, p1, p2, p3, p4, p5, p6, p7} = p
  kdf(s0, s1, s2, s3, s4, s5, s6, s7, p0, p1, p2, p3, p4, p5, p6, p7)

def ks_w0(k: U8w) -> U32:
  U8w{k0, k1, k2, k3, k4, k5, k6, k7} = k
  chacha_w0(k0, k1, k2, k3, k4, k5, k6, k7)

def check_dec(+ivk: Sc, +e: U8w, c: U32, d: Dec) -> U32:
  Dec{ok, q} = d
  lead = (((c .^. ks_w0(u8w_kdf(encode(smul(ivk, q)), e))) .&. 255) : U32)
  (ok .&. Bool.to_u32(U32.is_eq(lead, 3)) : U32)

# The GPU filter for one compact output: ECDH, KDF, ChaCha20, lead byte == 0x03.
def check(+ivk: Sc, r: Rec) -> U32:
  Rec{+e, c} = r
  check_dec(ivk, e, c, decompress(e))

type Recs is Data:
  RNil{}
  RCons{+r: Rec, next: Recs}

type Flags is Data:
  FNil{}
  FCons{+f: U32, next: Flags}

def scan_list(rs: Recs, +ivk: Sc, acc: Flags) -> Flags:
  match rs:
    case RNil{}:
      acc
    case RCons{r, next}:
      scan_list(next, ivk, FCons{check(ivk, r), acc})

type Tree is Data:
  Leaf{rs: Recs}
  Node{l: Tree, r: Tree}

type RTree is Data:
  RLeaf{fs: Flags}
  RNode{l: RTree, r: RTree}

def scan(+k: Nat, t: Tree, +ivk: Sc) -> RTree:
  match k t:
    case _ Leaf{rs}:
      RLeaf{scan_list(rs, ivk, FNil{})}
    case 1n+j Node{l, r}:
      a b = scan(j, l, ivk) scan(j, r, ivk)
      RNode{a, b}
    case _ _:
      RLeaf{FNil{}}
'''


def full_module():
    parts = [field_module(), gen_fsel()]
    parts.append(const_def("FIVE", 5))
    parts.append(const_def("C5", C5))
    parts.append(pow_def("pow_c3", C3))
    parts.append(CURVE)
    parts.append(gen_blake())
    parts.append(gen_chacha())
    parts.append(PIPELINE)
    return "\n".join(parts)


if __name__ == "__main__":
    import sys
    open(sys.argv[1] if len(sys.argv) > 1 else "zcrypto.bend", "w").write(full_module())
