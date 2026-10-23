#!/usr/bin/env python3
"""Generates the Pasta field modules fp.bend and fq.bend (and words.bend).

An element of GF(m) is 16 limbs of 16 bits in Montgomery form (R = 2^256), so
every 16x16-bit product fits a U32 (Bend has no U64). Both Pasta moduli are
1 mod 2^16, so the per-limb Montgomery factor -m^-1 mod 2^16 is 0xffff and the
reduction step is m_i = (2^16 - t_0) mod 2^16. Derived from gpu-scan/gen.py,
generalised over the modulus.

  python3 gen_field.py        # writes words.bend, fp.bend, fq.bend
"""

P = 0x40000000000000000000000000000000224698FC094CF91B992D30ED00000001
Q = 0x40000000000000000000000000000000224698FC0994A8DD8C46EB2100000001
R = 1 << 256
NL = 16
MASK = 0xFFFF


def limbs(x):
    return [(x >> (16 * i)) & MASK for i in range(NL)]


class Emit:
    def __init__(self):
        self.lines = []
        self.n = 0

    def let(self, expr):
        self.n += 1
        v = f"v{self.n}"
        self.lines.append(f"  +{v} = {expr}")
        return v


def u32(expr):
    return f"({expr} : U32)"


class Field:
    def __init__(self, name, m):
        self.T = name           # type and constructor name
        self.m = m
        self.ML = limbs(m)

    def lit(self, vals):
        return f"{self.T}{{" + ", ".join(str(v) for v in vals) + "}"

    def destructure(self, e, var, prefix):
        names = [f"{prefix}{i}" for i in range(NL)]
        e.lines.append(f"  {self.T}{{{', '.join('+' + n for n in names)}}} = {var}")
        return names

    def cond_sub(self, e, t, top):
        """t: limbs of a value < 2m (top: optional extra limb). Returns t mod m."""
        d, borrow = [], None
        for j in range(NL):
            s = e.let(u32(f"{t[j]} + 65536 - {self.ML[j]}" + (f" - {borrow}" if borrow else "")))
            d.append(e.let(u32(f"{s} .&. 65535")))
            borrow = e.let(u32(f"1 - ({s} >> 16n)"))
        if top is not None:
            borrow = e.let(u32(f"{borrow} .&. (1 - {top})"))
        mask = e.let(u32(f"0 - {borrow}"))
        nmask = e.let(u32(f"{mask} .^. 4294967295"))
        return [e.let(u32(f"({t[j]} .&. {mask}) .|. ({d[j]} .&. {nmask})")) for j in range(NL)]

    def gen_mul(self):
        e = Emit()
        a = self.destructure(e, "a", "a")
        b = self.destructure(e, "b", "b")
        t = [None] * (NL + 2)
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
            m = e.let(u32(f"(65536 - {t[0]}) .&. 65535"))
            s = e.let(u32(f"{t[0]} + {m}"))
            c = e.let(u32(f"{s} >> 16n"))
            nt = [None] * (NL + 2)
            for j in range(1, NL):
                parts = [t[j]] if t[j] else []
                if self.ML[j]:
                    parts.append(f"{m} * {self.ML[j]}")
                parts.append(c)
                s = e.let(u32(" + ".join(parts)))
                nt[j - 1] = e.let(u32(f"{s} .&. 65535"))
                c = e.let(u32(f"{s} >> 16n"))
            s = e.let(u32(f"{t[NL]} + {c}"))
            nt[NL - 1] = e.let(u32(f"{s} .&. 65535"))
            c = e.let(u32(f"{s} >> 16n"))
            nt[NL] = e.let(u32(f"{t[NL + 1]} + {c}"))
            t = nt
        r = self.cond_sub(e, t[:NL], t[NL])
        return (f"# Montgomery product a * b * R^-1 mod m.\ndef mul(a: {self.T}, b: {self.T}) -> {self.T}:\n"
                + "\n".join(e.lines) + f"\n  {self.lit(r)}\n")

    def gen_add(self):
        e = Emit()
        a = self.destructure(e, "a", "a")
        b = self.destructure(e, "b", "b")
        t, c = [], None
        for j in range(NL):
            s = e.let(u32(f"{a[j]} + {b[j]}" + (f" + {c}" if c else "")))
            t.append(e.let(u32(f"{s} .&. 65535")))
            c = e.let(u32(f"{s} >> 16n"))
        r = self.cond_sub(e, t, c)
        return f"def add(a: {self.T}, b: {self.T}) -> {self.T}:\n" + "\n".join(e.lines) + f"\n  {self.lit(r)}\n"

    def gen_sub(self):
        e = Emit()
        a = self.destructure(e, "a", "a")
        b = self.destructure(e, "b", "b")
        d, borrow = [], None
        for j in range(NL):
            s = e.let(u32(f"{a[j]} + 65536 - {b[j]}" + (f" - {borrow}" if borrow else "")))
            d.append(e.let(u32(f"{s} .&. 65535")))
            borrow = e.let(u32(f"1 - ({s} >> 16n)"))
        mask = e.let(u32(f"0 - {borrow}"))
        r, c = [], None
        for j in range(NL):
            s = e.let(u32(f"{d[j]} + ({self.ML[j]} .&. {mask})" + (f" + {c}" if c else "")))
            r.append(e.let(u32(f"{s} .&. 65535")))
            c = e.let(u32(f"{s} >> 16n"))
        return f"def sub(a: {self.T}, b: {self.T}) -> {self.T}:\n" + "\n".join(e.lines) + f"\n  {self.lit(r)}\n"

    def gen_eq(self):
        e = Emit()
        a = self.destructure(e, "a", "a")
        b = self.destructure(e, "b", "b")
        x = e.let(u32(" .|. ".join(f"({a[j]} .^. {b[j]})" for j in range(NL))))
        y = e.let(u32(f"({x} .|. (0 - {x})) >> 31n"))
        return (f"# 1 if a == b else 0 (branch-free).\ndef eq(a: {self.T}, b: {self.T}) -> U32:\n"
                + "\n".join(e.lines) + f"\n  (1 - {y} : U32)\n")

    def gen_sel(self):
        e = Emit()
        a = self.destructure(e, "a", "a")
        b = self.destructure(e, "b", "b")
        e.lines.append("  +mk = (0 - c : U32)")
        e.lines.append("  +nm = (mk .^. 4294967295 : U32)")
        r = [e.let(u32(f"({a[j]} .&. mk) .|. ({b[j]} .&. nm)")) for j in range(NL)]
        return (f"# c == 1 selects a, c == 0 selects b (branch-free).\ndef sel(+c: U32, a: {self.T}, b: {self.T}) -> {self.T}:\n"
                + "\n".join(e.lines) + f"\n  {self.lit(r)}\n")

    def const(self, name, value, mont=True, doc=""):
        v = (value * R) % self.m if mont else value
        return (f"# {doc}\n" if doc else "") + f"def {name}() -> {self.T}:\n  {self.lit(limbs(v))}\n"

    def pow_chain(self, name, exp, doc):
        """x^exp for a fixed exponent: runs of squarings each followed by one multiply."""
        bits = bin(exp)[2:]
        lines = ["  +x0 = x", "  acc0 = x0"]
        acc, k, i = "acc0", 0, 1
        while i < len(bits):
            run = 0
            while i < len(bits) and bits[i] == "0":
                run += 1
                i += 1
            k += 1
            if i < len(bits):
                run += 1
                lines.append(f"  acc{k} = mul(sqr_n({run}n, {acc}), x0)")
                i += 1
            else:
                lines.append(f"  acc{k} = sqr_n({run}n, {acc})")
            acc = f"acc{k}"
        return f"# {doc}\ndef {name}(x: {self.T}) -> {self.T}:\n" + "\n".join(lines) + f"\n  {acc}\n"

    def module(self):
        T = self.T
        t_odd = (self.m - 1) >> 32
        c3 = (t_odd - 1) // 2
        c5 = pow(5, t_odd, self.m)
        mname = {P: "p (pallas::Base = vesta::Scalar)", Q: "q (vesta::Base = pallas::Scalar)"}[self.m]
        header = f'''# GENERATED by gen_field.py. Do not edit.
# GF({mname}) = {hex(self.m)}
# Montgomery form (R = 2^256), 16 limbs x 16 bits so every product fits a U32.
# Canonical I/O goes through Wd.W: 8 little-endian U32 words.
import Base
import ./words.bend as Wd

type {T} is Data:
  {T}{{''' + ", ".join(f"l{i}: U32" for i in range(NL)) + "}\n\n"
        mod_words = ", ".join(str((self.m >> (32 * i)) & 0xFFFFFFFF) for i in range(8))
        extra = f'''
def zero() -> {T}:
  {self.lit([0] * NL)}

# 2^256 mod m in Montgomery form (used to fold the high half of a 512-bit value).
def R256() -> {T}:
  {self.lit(limbs(((R % self.m) * R) % self.m))}

def neg(a: {T}) -> {T}:
  sub(zero(), a)

def double(+a: {T}) -> {T}:
  add(a, a)

def sqr(+a: {T}) -> {T}:
  mul(a, a)

def sqr_n(n: Nat, x: {T}) -> {T}:
  match n:
    case 0n:
      x
    case 1n+k:
      sqr_n(k, sqr(x))

def is_eq(a: {T}, b: {T}) -> Bool:
  U32.is_eq(eq(a, b), 1)

def is_zero(a: {T}) -> Bool:
  U32.is_eq(eq(a, zero()), 1)

# Raw limbs of a 256-bit integer (any value < 2^256, not necessarily reduced).
def raw(w: Wd.W) -> {T}:
  Wd.W{{+a, +b, +c, +d, +e, +f, +g, +h}} = w
  {T}{{(a .&. 65535 : U32), (a >> 16n : U32), (b .&. 65535 : U32), (b >> 16n : U32),
    (c .&. 65535 : U32), (c >> 16n : U32), (d .&. 65535 : U32), (d >> 16n : U32),
    (e .&. 65535 : U32), (e >> 16n : U32), (f .&. 65535 : U32), (f >> 16n : U32),
    (g .&. 65535 : U32), (g >> 16n : U32), (h .&. 65535 : U32), (h >> 16n : U32)}}

def unraw(a: {T}) -> Wd.W:
  {T}{{a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15}} = a
  Wd.W{{(a0 .|. (a1 << 16n) : U32), (a2 .|. (a3 << 16n) : U32), (a4 .|. (a5 << 16n) : U32),
    (a6 .|. (a7 << 16n) : U32), (a8 .|. (a9 << 16n) : U32), (a10 .|. (a11 << 16n) : U32),
    (a12 .|. (a13 << 16n) : U32), (a14 .|. (a15 << 16n) : U32)}}

# Canonical (or any < 2^256) little-endian words -> element (reduced mod m).
# Montgomery REDC of raw(w) * R2 is valid for any input < 2^256 = R.
def from_words(w: Wd.W) -> {T}:
  mul(raw(w), R2())

# Element -> canonical little-endian words.
def to_words(a: {T}) -> Wd.W:
  unraw(mul(a, {self.lit([1] + [0] * (NL - 1))}))

# A 512-bit little-endian integer lo + 2^256 * hi, reduced mod m
# (ff's from_uniform_bytes, used by halo2's Challenge255 and hash-to-field).
def from_wide(lo: Wd.W, hi: Wd.W) -> {T}:
  add(from_words(lo), mul(from_words(hi), R256()))

def from_u32(x: U32) -> {T}:
  from_words(Wd.W{{x, 0, 0, 0, 0, 0, 0, 0}})

# The modulus as words.
def modulus() -> Wd.W:
  Wd.W{{{mod_words}}}

def mul_if(b: Bool, acc: {T}, +x: {T}) -> {T}:
  match b:
    case True{{}}:
      mul(acc, x)
    case False{{}}:
      acc

# acc^(2^32) * x^w, scanning the 32 bits of w from the top.
def pow_w(n: Nat, w: U32, acc: {T}, +x: {T}) -> {T}:
  match n:
    case 0n:
      acc
    case 1n+k:
      +w2 = w
      pow_w(k, (w2 << 1n : U32), mul_if(U32.is_eq((w2 >> 31n : U32), 1), sqr(acc), x), x)

# x^e for a variable 256-bit exponent e (little-endian words).
def pow(+x: {T}, e: Wd.W) -> {T}:
  Wd.W{{e0, e1, e2, e3, e4, e5, e6, e7}} = e
  a7 = pow_w(32n, e7, one(), x)
  a6 = pow_w(32n, e6, a7, x)
  a5 = pow_w(32n, e5, a6, x)
  a4 = pow_w(32n, e4, a5, x)
  a3 = pow_w(32n, e3, a4, x)
  a2 = pow_w(32n, e2, a3, x)
  a1 = pow_w(32n, e1, a2, x)
  pow_w(32n, e0, a1, x)

def inv(x: {T}) -> {T}:
  pow_m2(x)

# Lowest bit of the canonical value (the "sign" used by point compression).
def low_bit(a: {T}) -> U32:
  Wd.low_bit(to_words(a))

type S3 is Data:
  S3{{z: {T}, t: {T}, c: {T}}}

# One Tonelli-Shanks round (RFC 9380 App. I.4) after n squarings.
def ts_step(n: Nat, +z: {T}, +t: {T}, c: {T}) -> S3:
  +e = eq(sqr_n(n, t), one())
  +cc = c
  z2 = sel(e, z, mul(z, cc))
  +c2 = sqr(cc)
  t2 = sel(e, t, mul(t, c2))
  S3{{z2, t2, c2}}

def ts_z(s: S3) -> {T}:
  S3{{z, _, _}} = s
  z

def ts_loop(+n: Nat, s: S3) -> {T}:
  match n s:
    case 0n S3{{z, t, c}}:
      ts_z(ts_step(0n, z, t, c))
    case 1n+k S3{{z, t, c}}:
      ts_loop(k, ts_step(1n+k, z, t, c))

# A square root of x when x is a square (constant time; check sqr(r) == x).
# m - 1 = 2^32 * t with t odd; 5 is a non-residue.
def sqrt_cand(+x: {T}) -> {T}:
  +z0 = pow_c3(x)
  t0 = mul(sqr(z0), x)
  ts_loop(30n, S3{{mul(z0, x), t0, C5()}})

def maybe_if(b: Bool, r: {T}) -> Maybe<&2, {T}>:
  match b:
    case True{{}}:
      Some{{r}}
    case False{{}}:
      None{{}}

def sqrt(+x: {T}) -> Maybe<&2, {T}>:
  +r = sqrt_cand(x)
  maybe_if(is_eq(sqr(r), x), r)
'''
        return "\n".join([
            header,
            self.gen_mul(), self.gen_add(), self.gen_sub(), self.gen_eq(), self.gen_sel(),
            self.const("R2", R, mont=True, doc="R^2 mod m: raw -> Montgomery"),
            self.const("one", 1),
            self.const("C5", c5, doc="5^t: a 2^32-th root of unity used by Tonelli-Shanks"),
            extra.split("def is_eq(a:")[0],
            self.pow_chain("pow_m2", self.m - 2, "x^(m-2) = x^-1 (x != 0); 0 -> 0"),
            self.pow_chain("pow_c3", c3, "x^((t-1)/2), the Tonelli-Shanks starting power"),
            "def is_eq(a:" + extra.split("def is_eq(a:")[1],
        ])


WORDS = '''# 256-bit values as 8 little-endian U32 words: the canonical encoding shared by
# fp.bend, fq.bend, vesta.bend and the verifier (see ../CONTRACT.md).
import Base

type W is Data:
  W{w0: U32, w1: U32, w2: U32, w3: U32, w4: U32, w5: U32, w6: U32, w7: U32}

def zero() -> W:
  W{0, 0, 0, 0, 0, 0, 0, 0}

def is_eq(a: W, b: W) -> Bool:
  W{a0, a1, a2, a3, a4, a5, a6, a7} = a
  W{b0, b1, b2, b3, b4, b5, b6, b7} = b
  +x = ((a0 .^. b0) .|. (a1 .^. b1) .|. (a2 .^. b2) .|. (a3 .^. b3) .|. (a4 .^. b4) .|. (a5 .^. b5) .|. (a6 .^. b6) .|. (a7 .^. b7) : U32)
  U32.is_eq(x, 0)

# a_i < b_i, or a_i == b_i and the lower words already compared less.
def lt_step(+a: U32, +b: U32, lower: Bool) -> Bool:
  Bool.or(U32.is_lt(a, b), Bool.and(U32.is_eq(a, b), lower))

# Unsigned 256-bit a < b.
def is_lt(a: W, b: W) -> Bool:
  W{a0, a1, a2, a3, a4, a5, a6, a7} = a
  W{b0, b1, b2, b3, b4, b5, b6, b7} = b
  l0 = lt_step(a0, b0, False{})
  l1 = lt_step(a1, b1, l0)
  l2 = lt_step(a2, b2, l1)
  l3 = lt_step(a3, b3, l2)
  l4 = lt_step(a4, b4, l3)
  l5 = lt_step(a5, b5, l4)
  l6 = lt_step(a6, b6, l5)
  lt_step(a7, b7, l6)

def low_bit(w: W) -> U32:
  W{a, _, _, _, _, _, _, _} = w
  (a .&. 1 : U32)

def top_bit(w: W) -> U32:
  W{_, _, _, _, _, _, _, h} = w
  (h >> 31n : U32)

def clear_top_bit(w: W) -> W:
  W{a, b, c, d, e, f, g, h} = w
  W{a, b, c, d, e, f, g, (h .&. 2147483647 : U32)}

def set_top_bit(w: W, +b: U32) -> W:
  W{a0, a1, a2, a3, a4, a5, a6, a7} = w
  W{a0, a1, a2, a3, a4, a5, a6, (a7 .|. (b << 31n) : U32)}

# x in 0..15 -> '0'..'9', 'a'..'f' ((x + 6) >> 4 is 1 exactly when x >= 10).
def hex_digit(+x: U32) -> Char:
  Char.from_u32((x + 48 + 39 * ((x + 6) >> 4n) : U32))

def hex_byte(+b: U32) -> String:
  SCon{hex_digit((b >> 4n : U32)), SCon{hex_digit((b .&. 15 : U32)), SNil{}}}

def hex_u32(+x: U32) -> String:
  hex_byte((x .&. 255 : U32)) ++ hex_byte(((x >> 8n) .&. 255 : U32)) ++ hex_byte(((x >> 16n) .&. 255 : U32)) ++ hex_byte((x >> 24n : U32))

def hex_val(+c: Char) -> U32:
  +x = Char.to_u32(c)
  # '0'..'9' -> 0..9, 'a'..'f' / 'A'..'F' -> 10..15
  ((x .&. 15) + 9 * (x >> 6n) : U32)

type HexSt is Data:
  HexSt{+n: U32, +acc: U32, ws: +List<U32>}

# Nibble n of a word (n = 0..7) sits at bit 4 * (n xor 1): bytes are little-endian,
# and inside each byte the high nibble comes first.
def hex_shift(+n: U32) -> U32:
  (4 * (n .^. 1) : U32)

def hex_push(full: Bool, +acc: U32, +n: U32, ws: +List<U32>) -> HexSt:
  match full:
    case True{}:
      HexSt{0, 0, acc <> ws}
    case False{}:
      HexSt{(n + 1 : U32), acc, ws}

def hex_step(+c: Char, st: HexSt) -> HexSt:
  HexSt{+n, +acc, ws} = st
  hex_push(U32.is_eq(n, 7), (acc .|. (hex_val(c) << U32.to_nat(hex_shift(n))) : U32), n, ws)

def hex_go(s: String, st: HexSt) -> HexSt:
  match s:
    case SCon{c, t}:
      hex_go(t, hex_step(c, st))
    case SNil{}:
      st

def hex_ws(st: HexSt) -> +List<U32>:
  HexSt{_, _, ws} = st
  ws

def w_of(ws: +List<U32>) -> Maybe<&2, W>:
  match ws:
    case Con{h, Con{g, Con{f, Con{e, Con{d, Con{c, Con{b, Con{a, Nil{}}}}}}}}}:
      Some{W{a, b, c, d, e, f, g, h}}
    case _:
      None{}

# Inverse of `hex`: 64 hex digits (32 little-endian bytes) -> W; None on a wrong length.
def from_hex(s: String) -> Maybe<&2, W>:
  w_of(hex_ws(hex_go(s, HexSt{0, 0, Nil{}})))

# Lowercase hex of the 32 little-endian bytes (the vectors' text format).
def hex(w: W) -> String:
  W{a, b, c, d, e, f, g, h} = w
  hex_u32(a) ++ hex_u32(b) ++ hex_u32(c) ++ hex_u32(d) ++ hex_u32(e) ++ hex_u32(f) ++ hex_u32(g) ++ hex_u32(h)
'''


if __name__ == "__main__":
    open("words.bend", "w").write(WORDS)
    open("fp.bend", "w").write(Field("Fp", P).module())
    open("fq.bend", "w").write(Field("Fq", Q).module())
