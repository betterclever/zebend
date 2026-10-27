#!/usr/bin/env python3
"""Generates fp64.bend / fq64.bend: the same Pasta fields and API as fp3/fq3 (Montgomery
form, R = 2^256, 8 U32 words), but multiplied with 4 x 64-bit limbs through the
U32.mac64 primitive (Bend fork, branch u32-prims): word k of the 128-bit a * b + c + d
for 64-bit operands given as U32 halves. clang folds the words of one product into a
single widening multiply, so a field multiplication costs ~32 64x64-bit products instead
of ~96 32x32-bit ones, the same shape as pasta_curves.

  python3 gen_field64.py      # writes fp64.bend, fq64.bend (everything but mul / sqr_d
                              # comes from gen_field3.Field32)
"""
import importlib.util
import pathlib
import re

here = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("gen_field3", here / "gen_field3.py")
g3 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g3)
P, Q, R, NL, u32 = g3.P, g3.Q, g3.R, g3.NL, g3.u32
M64 = (1 << 64) - 1


class Field64(g3.Field32):
    def __init__(self, name, m):
        super().__init__(name, m, prims=True, sqr=True)
        self.M64 = [(m >> (64 * i)) & M64 for i in range(4)]
        self.INV = (-pow(m, -1, 1 << 64)) % (1 << 64)

    @staticmethod
    def halves(v):
        return (str(v & 0xffffffff), str(v >> 32))

    def mac64(self, e, a, b, c, d):
        """(lo64, hi64) of a * b + c + d; each argument is a (lo, hi) pair of U32 exprs."""
        args = ", ".join([*a, *b, *c, *d])
        w = [e.let(f"U32.mac64({k}, {args})") for k in range(4)]
        return (w[0], w[1]), (w[2], w[3])

    def add64(self, e, x, y, cin=("0", "0")):
        """(sum64, carry) of x + y + cin (cin is 0 or 1)."""
        s, c = self.mac64(e, x, ("1", "0"), y, cin)
        return s, c

    def gen_mul(self):
        e = g3.g16.Emit()
        a32 = self.destructure(e, "a", "a")
        b32 = self.destructure(e, "b", "b")
        a = [(a32[2 * i], a32[2 * i + 1]) for i in range(4)]
        b = [(b32[2 * i], b32[2 * i + 1]) for i in range(4)]
        Z = ("0", "0")
        t = [Z] * 6
        Mh = [self.halves(v) for v in self.M64]
        inv = self.halves(self.INV)
        for i in range(4):
            C = Z
            for j in range(4):
                t[j], C = self.mac64(e, a[j], b[i], t[j], C)
            t[4], c = self.add64(e, t[4], C)
            t[5] = c
            mlo, _ = self.mac64(e, t[0], inv, Z, Z)
            m = mlo
            _, C = self.mac64(e, m, Mh[0], t[0], Z)
            nt = [Z] * 6
            for j in range(1, 4):
                if self.M64[j]:
                    nt[j - 1], C = self.mac64(e, m, Mh[j], t[j], C)
                else:
                    nt[j - 1], C = self.add64(e, t[j], C)
            nt[3], c = self.add64(e, t[4], C)
            nt[4] = (e.let(u32(f"{t[5][0]} + {c[0]}")), "0")
            t = nt
        r = self.cond_sub(e, [w for limb in t[:4] for w in limb], t[4][0])
        return (f"# Montgomery product a * b * R^-1 mod m (CIOS over 4 x 64-bit limbs via U32.mac64).\n"
                f"def mul(a: {self.T}, b: {self.T}) -> {self.T}:\n" + "\n".join(e.lines) + f"\n  {self.lit(r)}\n")

    def gen_sqr(self):
        e = g3.g16.Emit()
        a32 = self.destructure(e, "a", "a")
        a = [(a32[2 * i], a32[2 * i + 1]) for i in range(4)]
        Z = ("0", "0")
        T = [Z] * 8
        for i in range(3):
            C = Z
            for j in range(i + 1, 4):
                T[i + j], C = self.mac64(e, a[i], a[j], T[i + j], C)
            T[i + 4] = C
        # Double: shift the 512-bit value left by one (top bit is 0).
        W = [w for limb in T for w in limb]
        D = []
        for k in range(16):
            lo = e.let(u32(f"{W[k]} << 1n")) if W[k] != "0" else "0"
            D.append(e.let(u32(f"{lo} .|. ({W[k - 1]} >> 31n)")) if k > 0 and W[k - 1] != "0" else lo)
        T = [(D[2 * i], D[2 * i + 1]) for i in range(8)]
        # Add the diagonal squares a_i^2 at limbs 2i, 2i+1.
        c = Z
        for i in range(4):
            lo, hi = self.mac64(e, a[i], a[i], Z, Z)
            T[2 * i], c = self.add64(e, T[2 * i], lo, c)
            T[2 * i + 1], c = self.add64(e, T[2 * i + 1], hi, c)
        # SOS reduction, 4 rounds.
        Mh = [self.halves(v) for v in self.M64]
        inv = self.halves(self.INV)
        ex = Z
        for i in range(4):
            m, _ = self.mac64(e, T[i], inv, Z, Z)
            _, C = self.mac64(e, m, Mh[0], T[i], Z)
            for j in range(1, 4):
                if self.M64[j]:
                    T[i + j], C = self.mac64(e, m, Mh[j], T[i + j], C)
                else:
                    T[i + j], C = self.add64(e, T[i + j], C)
            T[i + 4], ex = self.add64(e, T[i + 4], C, ex)
        r = self.cond_sub(e, [w for limb in T[4:] for w in limb], ex[0])
        return (f"# Montgomery square via 4 x 64-bit limbs (U32.mac64): 6 cross products doubled\n"
                f"# + 4 squares, then a 4-round SOS reduction.\n"
                f"def sqr_d(a: {self.T}) -> {self.T}:\n" + "\n".join(e.lines) + f"\n  {self.lit(r)}\n")


if __name__ == "__main__":
    for name, m, f in (("Fp", P, "fp64.bend"), ("Fq", Q, "fq64.bend")):
        (here / f).write_text(Field64(name, m).module())
    print("wrote fp64.bend fq64.bend")
