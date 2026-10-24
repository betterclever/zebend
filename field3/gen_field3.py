#!/usr/bin/env python3
"""Generates fp32.bend / fq32.bend: the Pasta fields on 8 limbs of 32 bits.

Same API and Montgomery representation (R = 2^256) as ../halo2/lib/fp.bend, but each
limb product is split with intrinsics.mulhi (high half) and U32.mul (low half) instead
of using 16-bit limbs. intrinsify.py turns mulhi into one hardware multiply, so a
field multiplication costs 64 limb products instead of 256.

Carries, borrows and multiply-accumulate high halves go through the addc / subb / mach
intrinsics (pure Bend definitions that intrinsify.py lowers to one 64-bit expression each). Both Pasta moduli are 1 mod 2^32, so the
CIOS reduction factor is m_i = -t_0 mod 2^32.

  python3 gen_field32.py      # writes fp32.bend, fq32.bend
"""
import importlib.util
import pathlib
import re
import sys

lib = pathlib.Path(__file__).resolve().parent.parent / "halo2" / "lib" / "gen_field.py"
spec = importlib.util.spec_from_file_location("gen_field16", lib)
g16 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g16)

P, Q, R = g16.P, g16.Q, g16.R
NL = 8
ONES = 4294967295


def limbs(x):
    return [(x >> (32 * i)) & ONES for i in range(NL)]


def u32(expr):
    return f"({expr} : U32)"


class Field32:
    def __init__(self, name, m, prims=True, sqr=True):
        self.T = name
        self.m = m
        self.ML = limbs(m)
        # prims: carries and multiply-accumulate highs via the U32.add_hi / U32.mac_hi
        # Bend primitives (one instruction each) instead of compare-based helpers.
        self.prims = prims
        self.dedicated_sqr = sqr

    def lit(self, vals):
        return f"{self.T}{{" + ", ".join(str(v) for v in vals) + "}"

    def destructure(self, e, var, prefix):
        names = [f"{prefix}{i}" for i in range(NL)]
        e.lines.append(f"  {self.T}{{{', '.join('+' + n for n in names)}}} = {var}")
        return names

    # s = x + y (+ cin) mod 2^32, carry via the addc intrinsic
    def adc(self, e, x, y, cin=None):
        if self.prims and cin is None:
            s = e.let(u32(f"{x} + {y}"))
            c = e.let(f"U32.add_hi({x}, {y})")
            return s, c
        z = cin or "0"
        s = e.let(u32(f"{x} + {y} + {z}"))
        c = e.let(f"I.addc({x}, {y}, {z})")
        return s, c

    # d = x - y (- bin) mod 2^32, borrow via the subb intrinsic
    def sbb(self, e, x, y, bin_=None):
        z = bin_ or "0"
        d = e.let(u32(f"{x} - {y} - {z}"))
        b = e.let(f"I.subb({x}, {y}, {z})")
        return d, b

    # lo, hi of a * b + c + d via the mach intrinsic
    def mac(self, e, a, b, c, d):
        lo = e.let(u32(f"{a} * {b} + {c} + {d}"))
        hi = e.let(f"U32.mac_hi({a}, {b}, {c}, {d})" if self.prims else f"I.mach({a}, {b}, {c}, {d})")
        return lo, hi

    def cond_sub(self, e, t, top):
        """t (+ top * 2^256) < 2m  ->  value mod m."""
        d, borrow = [], None
        for j in range(NL):
            dj, borrow = self.sbb(e, t[j], str(self.ML[j]), borrow)
            d.append(dj)
        if top is not None:
            borrow = e.let(u32(f"{borrow} .&. (1 - {top})"))
        mask = e.let(u32(f"0 - {borrow}"))
        nmask = e.let(u32(f"{mask} .^. {ONES}"))
        return [e.let(u32(f"({t[j]} .&. {mask}) .|. ({d[j]} .&. {nmask})")) for j in range(NL)]

    def gen_mul(self):
        e = g16.Emit()
        a = self.destructure(e, "a", "a")
        b = self.destructure(e, "b", "b")
        t = ["0"] * (NL + 2)
        for i in range(NL):
            C = "0"
            for j in range(NL):
                t[j], C = self.mac(e, a[j], b[i], t[j], C)
            t[NL], t[NL + 1] = self.adc(e, t[NL], C)
            m = e.let(u32(f"0 - {t[0]}"))
            # t0 + m * M0 with M0 = 1 is 0 mod 2^32; only its carry survives.
            C = e.let(f"U32.add_hi({t[0]}, {m})" if self.prims else f"I.addc({t[0]}, {m}, 0)")
            nt = ["0"] * (NL + 2)
            for j in range(1, NL):
                if self.ML[j]:
                    nt[j - 1], C = self.mac(e, m, str(self.ML[j]), t[j], C)
                else:
                    nt[j - 1], C = self.adc(e, t[j], C)
            nt[NL - 1], c = self.adc(e, t[NL], C)
            nt[NL] = e.let(u32(f"{t[NL + 1]} + {c}"))
            t = nt
        r = self.cond_sub(e, t[:NL], t[NL])
        return (f"# Montgomery product a * b * R^-1 mod m (CIOS, 32-bit limbs).\n"
                f"def mul(a: {self.T}, b: {self.T}) -> {self.T}:\n" + "\n".join(e.lines) + f"\n  {self.lit(r)}\n")

    def redc_wide(self, e, T):
        """Montgomery reduction (SOS) of a 16-limb T < m * R: T * R^-1 mod m, using the
        sparse modulus (limb 0 is 1, limbs 4..6 are 0)."""
        T = list(T)
        ex = None
        for i in range(NL):
            m = e.let(u32(f"0 - {T[i]}"))
            C = e.let(f"U32.add_hi({T[i]}, {m})" if self.prims else f"I.addc({T[i]}, {m}, 0)")
            for j in range(1, NL):
                if self.ML[j]:
                    T[i + j], C = self.mac(e, m, str(self.ML[j]), T[i + j], C)
                else:
                    T[i + j], C = self.adc(e, T[i + j], C)
            T[i + NL], ex = self.adc(e, T[i + NL], C, ex)
        return T[NL:], ex

    def gen_sqr(self):
        e = g16.Emit()
        a = self.destructure(e, "a", "a")
        # Off-diagonal products a_i * a_j (i < j), accumulated once.
        T = ["0"] * (2 * NL)
        for i in range(NL - 1):
            C = "0"
            for j in range(i + 1, NL):
                T[i + j], C = self.mac(e, a[i], a[j], T[i + j], C)
            T[i + NL] = C
        # Double them: shift the 512-bit value left by one bit (the top bit is 0).
        D = []
        for k in range(2 * NL):
            lo = e.let(u32(f"{T[k]} << 1n")) if T[k] != "0" else "0"
            if k > 0 and T[k - 1] != "0":
                D.append(e.let(u32(f"{lo} .|. ({T[k - 1]} >> 31n)")))
            else:
                D.append(lo)
        # Add the diagonal squares a_i^2 at limbs 2i, 2i+1.
        c = None
        for i in range(NL):
            lo = e.let(u32(f"{a[i]} * {a[i]}"))
            hi = e.let(f"U32.mul_hi({a[i]}, {a[i]})")
            D[2 * i], c = self.adc(e, D[2 * i], lo, c)
            D[2 * i + 1], c = self.adc(e, D[2 * i + 1], hi, c)
        r, top = self.redc_wide(e, D)
        r = self.cond_sub(e, r, top)
        return (f"# Montgomery square a^2 * R^-1 mod m: 28 cross products doubled + 8 squares,\n"
                f"# then a sparse SOS reduction.\n"
                f"def sqr_d(a: {self.T}) -> {self.T}:\n" + "\n".join(e.lines) + f"\n  {self.lit(r)}\n")

    def gen_add_nr(self):
        e = g16.Emit()
        a = self.destructure(e, "a", "a")
        b = self.destructure(e, "b", "b")
        t, c = [], None
        for j in range(NL):
            s_, c = self.adc(e, a[j], b[j], c)
            t.append(s_)
        return ("# Lazy add: a + b WITHOUT the final reduction, for a, b in [0, m): the result is\n"
                "# in [0, 2m), which fits 256 bits since m < 2^255. SAFE ONLY as one operand of\n"
                "# `mul` whose other operand is fully reduced (< m): then a*b < 2m^2 and the\n"
                "# Montgomery output stays < 2m, which mul's single conditional subtraction maps\n"
                "# into [0, m). NOT safe for both mul operands (4m > 2^256 for Pasta), nor for\n"
                "# to_words / eq / transcript, which need canonical inputs.\n"
                f"def add_nr(a: {self.T}, b: {self.T}) -> {self.T}:\n" + "\n".join(e.lines) + f"\n  {self.lit(t)}\n")

    def gen_add(self):
        e = g16.Emit()
        a = self.destructure(e, "a", "a")
        b = self.destructure(e, "b", "b")
        t, c = [], None
        for j in range(NL):
            s, c = self.adc(e, a[j], b[j], c)
            t.append(s)
        r = self.cond_sub(e, t, c)
        return f"def add(a: {self.T}, b: {self.T}) -> {self.T}:\n" + "\n".join(e.lines) + f"\n  {self.lit(r)}\n"

    def gen_sub(self):
        e = g16.Emit()
        a = self.destructure(e, "a", "a")
        b = self.destructure(e, "b", "b")
        d, borrow = [], None
        for j in range(NL):
            dj, borrow = self.sbb(e, a[j], b[j], borrow)
            d.append(dj)
        mask = e.let(u32(f"0 - {borrow}"))
        r, c = [], None
        for j in range(NL):
            mj = e.let(u32(f"{self.ML[j]} .&. {mask}"))
            s, c = self.adc(e, d[j], mj, c)
            r.append(s)
        return f"def sub(a: {self.T}, b: {self.T}) -> {self.T}:\n" + "\n".join(e.lines) + f"\n  {self.lit(r)}\n"

    def gen_eq(self):
        e = g16.Emit()
        a = self.destructure(e, "a", "a")
        b = self.destructure(e, "b", "b")
        x = e.let(u32(" .|. ".join(f"({a[j]} .^. {b[j]})" for j in range(NL))))
        y = e.let(u32(f"({x} .|. (0 - {x})) >> 31n"))
        return (f"# 1 if a == b else 0 (branch-free).\ndef eq(a: {self.T}, b: {self.T}) -> U32:\n"
                + "\n".join(e.lines) + f"\n  (1 - {y} : U32)\n")

    def gen_sel(self):
        e = g16.Emit()
        a = self.destructure(e, "a", "a")
        b = self.destructure(e, "b", "b")
        e.lines.append("  +mk = (0 - c : U32)")
        e.lines.append(f"  +nm = (mk .^. {ONES} : U32)")
        r = [e.let(u32(f"({a[j]} .&. mk) .|. ({b[j]} .&. nm)")) for j in range(NL)]
        return (f"# c == 1 selects a, c == 0 selects b (branch-free).\ndef sel(+c: U32, a: {self.T}, b: {self.T}) -> {self.T}:\n"
                + "\n".join(e.lines) + f"\n  {self.lit(r)}\n")

    def const(self, name, value, mont=True, doc=""):
        v = (value * R) % self.m if mont else value
        return (f"# {doc}\n" if doc else "") + f"def {name}() -> {self.T}:\n  {self.lit(limbs(v))}\n"

    pow_chain = g16.Field.pow_chain

    def window_chain(self, name, exp, doc, w=5):
        """x^exp with a sliding window of w bits: precompute x^1, x^3, ..., x^(2^w - 1),
        then square through the exponent and multiply once per window."""
        T = self.T
        lines = ["  +x1 = x", "  +xx = sqr(x1)"]
        for k in range(3, 1 << w, 2):
            lines.append(f"  +x{k} = mul(x{k - 2}, xx)")
        bits = bin(exp)[2:]
        i, acc, n, pend = 0, None, 0, 0
        def emit(e):
            nonlocal n
            n += 1
            lines.append(f"  +a{n} = {e}")
            return f"a{n}"
        while i < len(bits):
            if bits[i] == "0":
                pend += 1
                i += 1
                continue
            j = min(i + w, len(bits))
            while bits[j - 1] == "0":
                j -= 1
            val = int(bits[i:j], 2)
            if acc is None:
                acc = f"x{val}"
            else:
                acc = emit(f"mul(sqr_n({pend + (j - i)}n, {acc}), x{val})")
            pend = 0
            i = j
        if pend:
            acc = emit(f"sqr_n({pend}n, {acc})")
        used = {f"x{k}" for k in range(1, 1 << w, 2)} | {"xx"}
        return (f"# {doc}\n# Sliding window of {w} bits: {(1 << (w - 1)) - 1} multiplies of precomputation,\n"
                f"# then one multiply per window.\n"
                f"def {name}(x: {T}) -> {T}:\n" + "\n".join(lines) + f"\n  {acc}\n")

    def extras(self):
        T = self.T
        return f'''
# Variable-time Tonelli-Shanks (for PUBLIC inputs such as proof points: its running
# time depends on x). i is the least exponent with t^(2^i) = 1, found by repeated
# squaring; each round shrinks it, so at most 32 rounds. A non-square never reaches
# t^(2^i) = 1 below 2^32 and stops after one search (sqrt then answers None). About
# half the squarings of the constant-time loop (sqrt_ct, kept for secret inputs).
def ts_find(fuel: Nat, done: Bool, +i: Nat, +u: {T}) -> Nat:
  match fuel done:
    case 0n _:
      i
    case 1n+k True{{}}:
      i
    case 1n+k False{{}}:
      +v = sqr(u)
      ts_find(k, is_eq(v, one()), 1n+i, v)

def ts_vt(fuel: Nat, ok: Bool, +i: Nat, +m: Nat, +z: {T}, +t: {T}, +c: {T}) -> {T}:
  match fuel ok i:
    case 0n _ _:
      z
    case 1n+k False{{}} _:
      z
    case 1n+k True{{}} 0n:
      z
    case 1n+k True{{}} 1n+j:
      +b = sqr_n(Nat.sub(m, 2n+j), c)
      +c2 = sqr(b)
      +t2 = mul(t, c2)
      +i2 = ts_find(1n+j, is_eq(t2, one()), 0n, t2)
      ts_vt(k, Nat.is_lt(i2, 1n+j), i2, 1n+j, mul(z, b), t2, c2)

def sqrt_cand_vt(+x: {T}) -> {T}:
  +z0 = pow_c3(x)
  +t0 = mul(sqr(z0), x)
  +i0 = ts_find(32n, is_eq(t0, one()), 0n, t0)
  ts_vt(33n, Nat.is_lt(i0, 32n), i0, 32n, mul(z0, x), t0, C5())

# Batch inversion (Montgomery's trick): n inverses for one `inv` and 3(n-1) multiplies.
# Every input must be nonzero (a zero makes every output wrong).
def bi_pre(xs: +List<{T}>, +acc: {T}) -> +List<{T}>:
  match xs:
    case Nil{{}}:
      Nil{{}}
    case Con{{+h, +t}}:
      +a = mul(acc, h)
      a <> bi_pre(t, a)

def bi_back(rx: +List<{T}>, rp: +List<{T}>, +inv: {T}, out: +List<{T}>) -> +List<{T}>:
  match rx rp:
    case Con{{+h, +t}} Con{{+q, +r}}:
      bi_back(t, r, mul(inv, h), mul(inv, q) <> out)
    case Con{{_, _}} Nil{{}}:
      inv <> out
    case Nil{{}} _:
      out

def bi_go(+xs: +List<{T}>, rps: +List<{T}>) -> +List<{T}>:
  match rps:
    case Con{{+top, +rest}}:
      bi_back(List.reverse(&2, {T}, xs), rest, inv(top), Nil{{}})
    case Nil{{}}:
      Nil{{}}

def batch_inv(+xs: +List<{T}>) -> +List<{T}>:
  bi_go(xs, List.reverse(&2, {T}, bi_pre(xs, one())))
'''

    def module(self):
        # Reuse the 16-bit module's shared tail (pow, sqrt, conversions), swapping the
        # limb-specific pieces.
        f16 = g16.Field(self.T, self.m)
        full = f16.module()
        tail = full.split("\ndef zero() -> ", 1)[1]
        tail = "def zero() -> " + tail
        # raw / unraw become direct word copies with 32-bit limbs.
        start = tail.index("# Raw limbs of a 256-bit integer")
        end = tail.index("# Canonical (or any < 2^256)")
        T = self.T
        raw = f'''# Raw limbs of a 256-bit integer (any value < 2^256, not necessarily reduced).
def raw(w: Wd.W) -> {T}:
  Wd.W{{a, b, c, d, e, f, g, h}} = w
  {T}{{a, b, c, d, e, f, g, h}}

def unraw(a: {T}) -> Wd.W:
  {T}{{a0, a1, a2, a3, a4, a5, a6, a7}} = a
  Wd.W{{a0, a1, a2, a3, a4, a5, a6, a7}}

'''
        tail = tail[:start] + raw + tail[end:]
        # Constants in the shared tail were written with 16 limbs: regenerate them.
        tail = tail.replace(f16.lit([0] * 16), self.lit([0] * NL))
        tail = tail.replace(f16.lit(g16.limbs(((R % self.m) * R) % self.m)), self.lit(limbs(((R % self.m) * R) % self.m)))
        tail = tail.replace(f16.lit([1] + [0] * 15), self.lit([1] + [0] * (NL - 1)))
        t_odd = (self.m - 1) >> 32
        c3 = (t_odd - 1) // 2
        c5 = pow(5, t_odd, self.m)
        mname = {P: "p (pallas::Base = vesta::Scalar)", Q: "q (vesta::Base = pallas::Scalar)"}[self.m]
        header = f'''# GENERATED by gen_field32.py. Do not edit.
# GF({mname}) = {hex(self.m)}
# Montgomery form (R = 2^256), 8 limbs x 32 bits; limb products via U32.mul_hi (a Bend primitive).
import Base
import ../halo2/lib/words.bend as Wd
import ./intrinsics.bend as I

type {T} is Data:
  {T}{{''' + ", ".join(f"l{i}: U32" for i in range(NL)) + "}\n\n"
        # Drop the 16-bit module's own R2/one/C5/pow chains from the tail (we emit ours).
        extra = [self.gen_sqr()] if self.dedicated_sqr else []
        parts = [header, self.gen_mul()] + extra + [self.gen_add(), self.gen_add_nr(), self.gen_sub(), self.gen_eq(), self.gen_sel(),
                 self.const("R2", R, mont=True, doc="R^2 mod m: raw -> Montgomery"),
                 self.const("one", 1),
                 self.const("C5", c5, doc="5^t: a 2^32-th root of unity used by Tonelli-Shanks")]
        pre, post = tail.split("def is_eq(a:", 1)
        for name in ("pow_m2", "pow_c3"):
            i = pre.find(f"\ndef {name}(")
            if i >= 0:
                j = pre.rfind("\n#", 0, i)
                k = pre.find("\n\n", i)
                pre = pre[:j] + pre[k:]
        parts += [pre,
                  self.window_chain("pow_m2", self.m - 2, "x^(m-2) = x^-1 (x != 0); 0 -> 0"),
                  self.window_chain("pow_c3", c3, "x^((t-1)/2), the Tonelli-Shanks starting power"),
                  "def is_eq(a:" + post, self.extras()]
        out = "\n".join(parts)
        # sqrt -> variable-time Tonelli-Shanks; the constant-time loop stays as sqrt_ct.
        old = f"def sqrt(+x: {self.T}) -> Maybe<&2, {self.T}>:\n  +r = sqrt_cand(x)\n"
        assert old in out, "sqrt pattern changed"
        ct = old.replace("def sqrt(", "def sqrt_ct(")
        tail_ct = out.split(old, 1)[1]
        out = out.replace(old, f"# Constant-time square root (for secret inputs).\n{ct}")
        out += (f"\n# Square root for public inputs (variable time); None if x is not a square.\n"
                f"def sqrt(+x: {self.T}) -> Maybe<&2, {self.T}>:\n  +r = sqrt_cand_vt(x)\n" + tail_ct.split("\n\n")[0] + "\n")
        if self.dedicated_sqr:
            # Route the module's own sqr (used by sqr_n, pow, sqrt) to the dedicated squaring.
            out, n = re.subn(r"def sqr\(\+a: (\w+)\) -> \1:\n  mul\(a, a\)\n", r"def sqr(+a: \1) -> \1:\n  sqr_d(a)\n", out)
            assert n == 1, "sqr pattern changed"
        return out


if __name__ == "__main__":
    here = pathlib.Path(__file__).resolve().parent
    prims = "--no-prims" not in sys.argv
    sqr = "--no-sqr" not in sys.argv
    suffix = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--suffix=")), "")
    (here / f"fp3{suffix}.bend").write_text(Field32("Fp", P, prims, sqr).module())
    (here / f"fq3{suffix}.bend").write_text(Field32("Fq", Q, prims, sqr).module())
    print(f"wrote fp3{suffix}.bend fq3{suffix}.bend (prims={prims}, sqr={sqr})")
