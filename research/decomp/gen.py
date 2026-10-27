#!/usr/bin/env python3
"""Generate the table-based square roots for field3's Pasta fields.

    python3 gen.py [N]   -> fp_sqrt.bend, fq_sqrt.bend (after an N-input Python self-test)

Sarkar's algorithm (eprint 2020/1407) as pasta_curves implements it under its `sqrt-table`
feature (src/arithmetic/fields.rs, SqrtTables::sqrt_alt), for p - 1 = t * 2^32, with
windows of W bits (n = 32 / W windows):

    v  = u^((t-1)/2)                 (pasta_curves' addition chain for each field)
    uv = u * v,  y = uv * v = u^t    (y lies in the 2^32-th roots of unity)
    x_{n-1} = y, x_{i-1} = x_i^(2^W): x_0 lies in the 2^W-th roots of unity
    e = dlog(x_0); for i = 1..n-1: e += dlog(x_i * prod_{j<i} G_{n-1-i+j}[digit_j(e)]) << W*i
    then y * w^e = 1 and the root is uv * w^ceil(e/2) = uv * prod_k G_k[digit_k(ceil(e/2))],
    where w = 5^t and G_k[d] = w^(d * 2^(W*k)).

pasta uses W = 8 (four 256-entry tables). This generator defaults to W = 4 (eight 16-entry
tables, 28 more multiplications per root): the forked Bend compiler needs ~0.6 MB per
`match` arm, so W = 8's ~8,200 limb arms would add ~4 GB to every build that uses it
(the Halo 2 batch build is already 2.5 GB); W = 4 adds ~1,100 arms.

Every table is a dense `match` on U32 literals returning one 32-bit limb, which the forked
Bend compiles to a constant-array lookup (TAB_AT): no branches, the same work for every
input. The discrete log in the 2^W-th roots of unity hashes the Montgomery-form low limb
(field3 keeps elements in Montgomery form; pasta reduces first) with a multiplicative hash
(l0 * M) >> (32 - HB) into 2^HB slots of 8-bit logs, four to a word.
"""
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

FIELDS = {
    "fp": dict(p=0x40000000000000000000000000000000224698fc094cf91b992d30ed00000001,
               ty="Fp", mod="../../crypto/field3/fp64.bend"),
    "fq": dict(p=0x40000000000000000000000000000000224698fc0994a8dd8c46eb2100000001,
               ty="Fq", mod="../../crypto/field3/fq64.bend"),
}
S = 32
R = 1 << 256
W = 4
NW = S // W
HB = 6 if W == 4 else 12

# pasta_curves 0.5.2 pow_by_t_minus1_over2: small powers, then a = x^(2^129) * x, then
# (squarings, multiplier) steps, then `tail` bare squarings.
CHAINS = {
    "fp": dict(pre={"r10": ("sqr", "x"), "r11": ("mul", "r10", "x"), "r110": ("sqr", "r11"),
                    "r111": ("mul", "r110", "x"), "r1001": ("mul", "r111", "r10"),
                    "r1101": ("mul", "r111", "r110")},
               steps=[(7, "r1001"), (7, "r1101"), (4, "r11"), (6, "r111"), (3, "r111"),
                      (10, "r1001"), (5, "r1001"), (4, "r1001"), (3, "r111"), (4, "r1001"),
                      (5, "r11"), (4, "r111"), (4, "r11"), (6, "r1001"), (5, "r1101"),
                      (4, "r11"), (7, "r111"), (3, "r11")], tail=1),
    "fq": dict(pre={"s10": ("sqr", "x"), "s11": ("mul", "s10", "x"), "s110": ("sqr", "s11"),
                    "s111": ("mul", "s110", "x"), "s1001": ("mul", "s111", "s10"),
                    "s1011": ("mul", "s1001", "s10"), "s1101": ("mul", "s1011", "s10")},
               steps=[(7, "s1001"), (7, "s1101"), (4, "s11"), (6, "s111"), (3, "s111"),
                      (10, "s1001"), (4, "s1001"), (5, "s1001"), (5, "s1001"), (3, "s1001"),
                      (4, "s1011"), (4, "s1011"), (5, "s11"), (4, "x"), (5, "s11"),
                      (4, "s111"), (5, "s1011"), (3, "x")], tail=4),
}


def chain_exp(c):
    """The exponent the chain computes, to check it equals (t-1)/2."""
    env = {"x": 1}
    for k, op in c["pre"].items():
        env[k] = 2 * env[op[1]] if op[0] == "sqr" else env[op[1]] + env[op[2]]
    e = (1 << 129) + 1
    for n, k in c["steps"]:
        e = (e << n) + env[k]
    return e << c["tail"]


def limbs(a):
    return [(a >> (32 * i)) & 0xFFFFFFFF for i in range(8)]


def digit(e, j):
    return (e >> (W * j)) & ((1 << W) - 1)


class F:
    def __init__(self, name):
        self.name = name
        d = FIELDS[name]
        self.p = p = d["p"]
        self.ty = d["ty"]
        self.mod = d["mod"]
        t = (p - 1) >> S
        assert t * (1 << S) == p - 1 and t % 2 == 1
        self.t = t
        assert chain_exp(CHAINS[name]) == (t - 1) // 2, name
        w = pow(5, t, p)
        assert pow(w, 1 << (S - 1), p) == p - 1
        self.w = w
        self.g = [[pow(w, i << (W * k), p) for i in range(1 << W)] for k in range(NW)]
        # Discrete log in the 2^W-th roots of unity: slot of x -> d with x * G_top[d] == 1.
        mu = self.g[NW - 1]
        keys = [self.mont(m) & 0xFFFFFFFF for m in mu]
        assert len(set(keys)) == len(mu)
        rng = random.Random(name)
        while True:
            m = rng.getrandbits(32) | 1
            hs = [((k * m) & 0xFFFFFFFF) >> (32 - HB) for k in keys]
            if len(set(hs)) == len(mu):
                break
        self.hmul = m
        slots = [0] * (1 << HB)
        for j, h in enumerate(hs):
            slots[h] = ((1 << W) - j) & ((1 << W) - 1)
        self.packed = [slots[4 * i] | slots[4 * i + 1] << 8 | slots[4 * i + 2] << 16 |
                       slots[4 * i + 3] << 24 for i in range(1 << (HB - 2))]

    def mont(self, a):
        return a * R % self.p

    def dlog(self, x):
        h = ((self.mont(x) & 0xFFFFFFFF) * self.hmul & 0xFFFFFFFF) >> (32 - HB)
        return (self.packed[h >> 2] >> (8 * (h & 3))) & 0xFF

    def sqrt_cand(self, u):
        p, g = self.p, self.g
        v = pow(u, (self.t - 1) // 2, p)
        uv = u * v % p
        x = [0] * NW
        x[NW - 1] = uv * v % p
        for i in range(NW - 1, 0, -1):
            x[i - 1] = pow(x[i], 1 << W, p)
        e = self.dlog(x[0])
        for i in range(1, NW):
            a = x[i]
            for j in range(i):
                a = a * g[NW - 1 - i + j][digit(e, j)] % p
            e += self.dlog(a) << (W * i)
        e &= 0xFFFFFFFF
        tt = (e >> 1) + (e & 1)
        r = uv
        for k in range(NW):
            r = r * g[k][digit(tt, k)] % p
        return r

    def selftest(self, n):
        p = self.p
        rng = random.Random(1)
        xs = [0, 1, p - 1, 5, self.w, self.w * self.w % p] + \
             [pow(self.w, 1 << k, p) for k in range(S)] + \
             [pow(self.w, rng.randrange(1 << 32), p) for _ in range(64)] + \
             [rng.randrange(p) for _ in range(n)]
        sq = 0
        for u in xs:
            r = self.sqrt_cand(u)
            is_sq = u == 0 or pow(u, (p - 1) // 2, p) == 1
            assert (r * r % p == u) == is_sq, (self.name, u)
            if not is_sq:
                assert r * r % p == self.w * u % p
            sq += is_sq
        return len(xs), sq


def table(name, vals):
    o = [f"def {name}(i: U32) -> U32:", "  match i:"]
    o += [f"    case {i}: {v}" for i, v in enumerate(vals)]
    return o + ["    case _: 0", ""]


def emit(f):
    T = f"B.{f.ty}"
    mask = (1 << W) - 1
    o = ["# GENERATED by research/decomp/gen.py. Do not edit.",
         f"# Table-based square root in GF({f.p:#x})",
         f"# (Sarkar 2020/1407 as in pasta_curves' sqrt-table, {W}-bit windows) on {f.mod}'s",
         f"# Montgomery {f.ty}. Fixed work per input: every table is a dense U32 `match`,",
         "# compiled to a constant-array lookup.",
         "import Base",
         f"import {f.mod} as B",
         ""]
    for k in range(NW):
        for l in range(8):
            o += table(f"g{k}_{l}", [limbs(f.mont(f.g[k][i]))[l] for i in range(1 << W)])
        o += [f"# w^(i * 2^{W * k})", f"def g{k}(+i: U32) -> {T}:",
              f"  B.{f.ty}{{{', '.join(f'g{k}_{l}(i)' for l in range(8))}}}", ""]
    o += table("dl_t", f.packed)
    o += ["def byte_of(b: U32, +w: U32) -> U32:", "  match b:",
          "    case 0:", "      (w .&. 255 : U32)",
          "    case 1:", "      ((w >> 8n) .&. 255 : U32)",
          "    case 2:", "      ((w >> 16n) .&. 255 : U32)",
          "    case _:", "      (w >> 24n : U32)", "",
          f"# d in [0, {1 << W}) with x * w^(d * 2^{S - W}) = 1, for x a 2^{W}-th root of unity.",
          f"def dlog(a: {T}) -> U32:",
          f"  B.{f.ty}{{+l0, _, _, _, _, _, _, _}} = a",
          f"  +h = ((l0 * {f.hmul} : U32) >> {32 - HB}n : U32)",
          "  byte_of((h .&. 3 : U32), dl_t((h >> 2n : U32)))", ""]
    c = CHAINS[f.name]
    o += ["# x^((t-1)/2): pasta_curves' addition chain (field3's dedicated squaring).",
          f"def pow_t(+x: {T}) -> {T}:"]
    for k, op in c["pre"].items():
        o.append(f"  +{k} = B.sqr({op[1]})" if op[0] == "sqr" else f"  +{k} = B.mul({op[1]}, {op[2]})")
    o.append("  +a0 = B.mul(B.sqr_n(129n, x), x)")
    for i, (n, k) in enumerate(c["steps"]):
        o.append(f"  +a{i + 1} = B.mul(B.sqr_n({n}n, a{i}), {k})")
    o += [f"  B.sqr_n({c['tail']}n, a{len(c['steps'])})", ""]

    def dg(var, j):
        if j == 0:
            return f"({var} .&. {mask} : U32)"
        if W * (j + 1) >= 32:
            return f"({var} >> {W * j}n : U32)"
        return f"(({var} >> {W * j}n) .&. {mask} : U32)"

    # The search: one def per step keeps each def small.
    o += ["# Window i of the discrete log of y = u^t: e_i = e_{i-1} + dlog(x_i * prod_j G[...]) << W*i."]
    for i in range(1, NW):
        o.append(f"def st{i}(+x: {T}, +e: U32) -> U32:")
        a = "x"
        for j in range(i):
            a = f"B.mul({a}, g{NW - 1 - i + j}({dg('e', j)}))"
        o += [f"  (e + (dlog({a}) << {W * i}n) : U32)", ""]
    o += [f"# The root step, given uv = u^((t+1)/2) and v = u^((t-1)/2): uv * w^ceil(e/2) with",
          "# u^t * w^e = 1. For a non-square u it is a square root of w * u.",
          f"def common(+uv: {T}, +v: {T}) -> {T}:",
          f"  +x{NW - 1} = B.mul(uv, v)"]
    for i in range(NW - 1, 0, -1):
        o.append(f"  +x{i - 1} = B.sqr_n({W}n, x{i})")
    o.append("  +e0 = dlog(x0)")
    for i in range(1, NW):
        o.append(f"  +e{i} = st{i}(x{i}, e{i - 1})")
    e = f"e{NW - 1}"
    o.append(f"  +tt = (({e} >> 1n) + ({e} .&. 1 : U32) : U32)")
    r = "uv"
    for k in range(NW):
        r = f"B.mul({r}, g{k}({dg('tt', k)}))"
    o += [f"  {r}", "",
          "# A square root of x when x is a square (of w * x otherwise). Fixed work.",
          f"def root(+x: {T}) -> {T}:",
          "  +v = pow_t(x)",
          "  common(B.mul(x, v), v)",
          "",
          "# 1 if r is a square root of x, else 0 (branch-free form for GPU callers).",
          f"def is_root(+r: {T}, +x: {T}) -> U32:",
          "  B.eq(B.sqr(r), x)",
          "",
          "# Drop-in for field3's sqrt: Some(r) with r^2 = x, None if x is not a square.",
          f"def sqrt(+x: {T}) -> Maybe<&2, {T}>:",
          "  +r = root(x)",
          "  B.maybe_if(B.is_eq(B.sqr(r), x), r)",
          ""]
    return "\n".join(o)


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
    for name in FIELDS:
        f = F(name)
        tot, sq = f.selftest(n)
        print(f"{name}: W = {W}, hash M = {f.hmul:#x}; python self-test {tot} inputs ({sq} squares) ok")
        (HERE / f"{name}_sqrt.bend").write_text(emit(f))
    src = (HERE / "pallas_dec.bend").read_text()
    src = src.replace("# vesta_dec.bend is generated from this file by gen.py (Fp <-> Fq, pallas <-> vesta).\n", "")
    for a, b in [("Pallas", "Vesta"), ("pallas", "vesta"), ("fp64", "fq64"), ("B.Fp", "B.Fq"),
                 ("fp_sqrt", "fq_sqrt")]:
        src = src.replace(a, b)
    (HERE / "vesta_dec.bend").write_text("# GENERATED by research/decomp/gen.py from pallas_dec.bend. Do not edit.\n" + src)


if __name__ == "__main__":
    main()
