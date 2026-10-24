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

lib = pathlib.Path(__file__).resolve().parent.parent.parent / "halo2" / "lib" / "gen_field.py"
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
    def __init__(self, name, m):
        self.T = name
        self.m = m
        self.ML = limbs(m)

    def lit(self, vals):
        return f"{self.T}{{" + ", ".join(str(v) for v in vals) + "}"

    def destructure(self, e, var, prefix):
        names = [f"{prefix}{i}" for i in range(NL)]
        e.lines.append(f"  {self.T}{{{', '.join('+' + n for n in names)}}} = {var}")
        return names

    # s = x + y (+ cin) mod 2^32, carry via the addc intrinsic
    def adc(self, e, x, y, cin=None):
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
        hi = e.let(f"I.mach({a}, {b}, {c}, {d})")
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
            C = e.let(f"I.addc({t[0]}, {m}, 0)")
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
import ../../halo2/lib/words.bend as Wd
import ./intrinsics.bend as I

type {T} is Data:
  {T}{{''' + ", ".join(f"l{i}: U32" for i in range(NL)) + "}\n\n"
        # Drop the 16-bit module's own R2/one/C5/pow chains from the tail (we emit ours).
        parts = [header, self.gen_mul(), self.gen_add(), self.gen_sub(), self.gen_eq(), self.gen_sel(),
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
                  self.pow_chain("pow_m2", self.m - 2, "x^(m-2) = x^-1 (x != 0); 0 -> 0"),
                  self.pow_chain("pow_c3", c3, "x^((t-1)/2), the Tonelli-Shanks starting power"),
                  "def is_eq(a:" + post]
        out = "\n".join(parts)
        return out


if __name__ == "__main__":
    here = pathlib.Path(__file__).resolve().parent
    (here / "fp32.bend").write_text(Field32("Fp", P).module())
    (here / "fq32.bend").write_text(Field32("Fq", Q).module())
    print("wrote fp32.bend fq32.bend")
