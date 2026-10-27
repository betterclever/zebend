#!/usr/bin/env python3
import os
"""(field3 copy of zcash/headers/gen.py: BLAKE2b 64-bit adds use U32.add_hi.)
Generates hashes.bend: straight-line BLAKE2b and SHA-256 compression functions.

Bend 2 has only U32, so BLAKE2b's 64-bit words are (lo, hi) U32 pairs. Each round
is its own def: one straight-line def for a whole compression overflows the Bend
compiler (lesson from research/gpu-scan/gen.py, whose BLAKE2b this generalizes to a full
16-word message block, a byte counter and the final flag).
"""

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
SHA_K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]
SHA_IV = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]


class Emit:
    def __init__(self):
        self.lines, self.n = [], 0

    def let(self, expr):
        self.n += 1
        v = f"t{self.n}"
        self.lines.append(f"  +{v} = ({expr} : U32)")
        return v


def gen_blake():
    out = []
    vn = [f"v{i}{h}" for i in range(16) for h in "lh"]
    mn = [f"m{i}{h}" for i in range(16) for h in "lh"]
    out.append("# BLAKE2b working state: 16 64-bit words as (lo, hi) U32 pairs.\n"
               "type B16 is Data:\n  B16{" + ", ".join(f"{n}: U32" for n in vn) + "}\n")
    out.append("# A 128-byte message block: 16 64-bit little-endian words as (lo, hi).\n"
               "type BM is Data:\n  BM{" + ", ".join(f"{n}: U32" for n in mn) + "}\n")
    out.append("# A BLAKE2b chaining value: 8 64-bit words as (lo, hi).\n"
               "type BH is Data:\n  BH{" + ", ".join(f"h{i}{h}: U32" for i in range(8) for h in "lh") + "}\n")
    for r in range(12):
        e = Emit()
        e.lines.append("  B16{" + ", ".join("+" + n for n in vn) + "} = st")
        e.lines.append("  BM{" + ", ".join("+" + n for n in mn) + "} = m")
        v = [[f"v{i}l", f"v{i}h"] for i in range(16)]
        m = [[f"m{i}l", f"m{i}h"] for i in range(16)]

        def add(a, b):
            lo = e.let(f"{a[0]} + {b[0]}")
            # The carry of the low halves is one instruction with the U32.add_hi primitive
            # (Bend fork, branch u32-prims) instead of a five-op bitwise formula.
            if os.environ.get("ADD64") == "mac64":
                # Whole 64-bit add as words 0/1 of a * 1 + b (one 64-bit add once inlined).
                hi = e.let(f"U32.mac64(1, {a[0]}, {a[1]}, 1, 0, {b[0]}, {b[1]}, 0, 0)")
                return [lo, hi]
            carry = e.let(f"U32.add_hi({a[0]}, {b[0]})")
            hi = e.let(f"{a[1]} + {b[1]} + {carry}")
            return [lo, hi]

        def xor(a, b):
            return [e.let(f"{a[0]} .^. {b[0]}"), e.let(f"{a[1]} .^. {b[1]}")]

        def rotr(a, n):
            if n == 32:
                return [a[1], a[0]]
            if n < 32:
                return [e.let(f"({a[0]} >> {n}n) .|. ({a[1]} << {32 - n}n)"),
                        e.let(f"({a[1]} >> {n}n) .|. ({a[0]} << {32 - n}n)")]
            # n == 63: rotate left by one
            return [e.let(f"({a[0]} << 1n) .|. ({a[1]} >> 31n)"),
                    e.let(f"({a[1]} << 1n) .|. ({a[0]} >> 31n)")]

        def G(a, b, c, d, x, y):
            v[a] = add(add(v[a], v[b]), x)
            v[d] = rotr(xor(v[d], v[a]), 32)
            v[c] = add(v[c], v[d])
            v[b] = rotr(xor(v[b], v[c]), 24)
            v[a] = add(add(v[a], v[b]), y)
            v[d] = rotr(xor(v[d], v[a]), 16)
            v[c] = add(v[c], v[d])
            v[b] = rotr(xor(v[b], v[c]), 63)

        s = SIGMA[r % 10]
        G(0, 4, 8, 12, m[s[0]], m[s[1]]); G(1, 5, 9, 13, m[s[2]], m[s[3]])
        G(2, 6, 10, 14, m[s[4]], m[s[5]]); G(3, 7, 11, 15, m[s[6]], m[s[7]])
        G(0, 5, 10, 15, m[s[8]], m[s[9]]); G(1, 6, 11, 12, m[s[10]], m[s[11]])
        G(2, 7, 8, 13, m[s[12]], m[s[13]]); G(3, 4, 9, 14, m[s[14]], m[s[15]])
        outs = [x for w in v for x in w]
        out.append(f"def b2_round{r}(st: B16, +m: BM) -> B16:\n" + "\n".join(e.lines)
                   + "\n  B16{" + ", ".join(outs) + "}\n")
    # compress(h, m, t, last): t = bytes hashed so far (fits in U32 here)
    hn = [f"h{i}{x}" for i in range(8) for x in "lh"]
    iv = [x for w in B2_IV for x in (w & 0xFFFFFFFF, w >> 32)]
    init = hn + [str(x) for x in iv[:8]] + [f"({iv[8]} .^. t : U32)", str(iv[9]), str(iv[10]), str(iv[11]),
                                             f"({iv[12]} .^. last : U32)", f"({iv[13]} .^. last : U32)", str(iv[14]), str(iv[15])]
    chain = "B16{" + ", ".join(init) + "}"
    for r in range(12):
        chain = f"b2_round{r}({chain}, m)"
    fin = ", ".join(f"(h{i}{x} .^. v{i}{x} .^. v{i + 8}{x} : U32)" for i in range(8) for x in "lh")
    out.append(
        "# BLAKE2b compression F(h, m, t, f): t = byte counter (< 2^32 here), last = 0xFFFFFFFF on the final block.\n"
        "def b2_compress(h: BH, +m: BM, +t: U32, +last: U32) -> BH:\n"
        "  BH{" + ", ".join("+" + n for n in hn) + "} = h\n"
        f"  b2_fin(h, b2_mix({chain.replace('B16{' + ', '.join(hn), 'B16{' + ', '.join(hn))}))\n")
    # simpler: two helpers so `h` can be reused
    out[-1] = (
        "def b2_mix(+h: BH, +m: BM, +t: U32, +last: U32) -> B16:\n"
        "  BH{" + ", ".join("+" + n for n in hn) + "} = h\n"
        f"  {chain}\n\n"
        "def b2_fin(h: BH, st: B16) -> BH:\n"
        "  BH{" + ", ".join(hn) + "} = h\n"
        "  B16{" + ", ".join(vn) + "} = st\n"
        f"  BH{{{fin}}}\n\n"
        "# BLAKE2b compression F(h, m, t, f): t = byte counter (< 2^32 here), last = 0xFFFFFFFF on the final block.\n"
        "def b2_compress(+h: BH, +m: BM, +t: U32, +last: U32) -> BH:\n"
        "  b2_fin(h, b2_mix(h, m, t, last))\n")
    # Equihash(200, 9) initial chaining value: digest length 50, personalization "ZcashPoW" || LE32(200) || LE32(9)
    pers = b"ZcashPoW" + (200).to_bytes(4, "little") + (9).to_bytes(4, "little")
    h = list(B2_IV)
    h[0] ^= 0x01010000 ^ 50
    h[6] ^= int.from_bytes(pers[:8], "little")
    h[7] ^= int.from_bytes(pers[8:], "little")
    out.append("# h0 for BLAKE2b-400 personalized \"ZcashPoW\" || LE32(200) || LE32(9) (Equihash n=200, k=9).\n"
               "def eh_h0() -> BH:\n  BH{" + ", ".join(f"{x & 0xFFFFFFFF}, {x >> 32}" for x in h) + "}\n")
    return "\n".join(out)


def gen_sha():
    out = []
    sn = [f"s{i}" for i in range(8)]
    wn = [f"w{i}" for i in range(16)]
    out.append("# SHA-256 chaining value.\ntype SH is Data:\n  SH{" + ", ".join(f"{n}: U32" for n in sn) + "}\n")
    out.append("# A 64-byte block as 16 big-endian U32 words.\ntype SW is Data:\n  SW{" + ", ".join(f"{n}: U32" for n in wn) + "}\n")
    out.append("# Round state: working variables a..h plus the 16-word message window.\n"
               "type SR is Data:\n  SR{" + ", ".join(f"{n}: U32" for n in sn + wn) + "}\n")

    def rotr(e, x, n):
        return e.let(f"({x} >> {n}n) .|. ({x} << {32 - n}n)")

    for blk in range(4):
        e = Emit()
        e.lines.append("  SR{" + ", ".join("+" + n for n in sn + wn) + "} = st")
        a = sn[:]
        w = wn[:]
        for j in range(16):
            i = blk * 16 + j
            if i >= 16:
                # w[i] = s1(w[i-2]) + w[i-7] + s0(w[i-15]) + w[i-16]; window holds w[i-16..i-1]
                x2, x7, x15, x16 = w[14], w[9], w[1], w[0]
                s0 = e.let(f"{rotr(e, x15, 7)} .^. {rotr(e, x15, 18)} .^. ({x15} >> 3n)")
                s1 = e.let(f"{rotr(e, x2, 17)} .^. {rotr(e, x2, 19)} .^. ({x2} >> 10n)")
                wi = e.let(f"{s1} + {x7} + {s0} + {x16}")
                w = w[1:] + [wi]
                cur = wi
            else:
                cur = w[j]
            A, B, C, D, E, F, G, H = a
            S1 = e.let(f"{rotr(e, E, 6)} .^. {rotr(e, E, 11)} .^. {rotr(e, E, 25)}")
            ch = e.let(f"({E} .&. {F}) .^. (({E} .^. 4294967295) .&. {G})")
            t1 = e.let(f"{H} + {S1} + {ch} + {SHA_K[i]} + {cur}")
            S0 = e.let(f"{rotr(e, A, 2)} .^. {rotr(e, A, 13)} .^. {rotr(e, A, 22)}")
            maj = e.let(f"({A} .&. {B}) .^. ({A} .&. {C}) .^. ({B} .&. {C})")
            t2 = e.let(f"{S0} + {maj}")
            a = [e.let(f"{t1} + {t2}"), A, B, C, e.let(f"{D} + {t1}"), E, F, G]
        if blk == 0:
            # rounds 0..15 consume the block in place; the window stays the block
            w = wn[:]
        out.append(f"def sha_rounds{blk}(st: SR) -> SR:\n" + "\n".join(e.lines)
                   + "\n  SR{" + ", ".join(a + w) + "}\n")
    out.append(
        "def sha_fin(h: SH, st: SR) -> SH:\n"
        "  SH{" + ", ".join(sn) + "} = h\n"
        "  SR{" + ", ".join(f"r{i}" for i in range(8)) + ", " + ", ".join("_" for _ in range(16)) + "} = st\n"
        "  SH{" + ", ".join(f"({sn[i]} + r{i} : U32)" for i in range(8)) + "}\n\n"
        "def sha_start(+h: SH, m: SW) -> SR:\n"
        "  SH{" + ", ".join("+" + n for n in sn) + "} = h\n"
        "  SW{" + ", ".join(wn) + "} = m\n"
        "  SR{" + ", ".join(sn + wn) + "}\n\n"
        "# SHA-256 compression of one block.\n"
        "def sha_compress(+h: SH, m: SW) -> SH:\n"
        "  sha_fin(h, sha_rounds3(sha_rounds2(sha_rounds1(sha_rounds0(sha_start(h, m))))))\n\n"
        "def sha_iv() -> SH:\n  SH{" + ", ".join(str(x) for x in SHA_IV) + "}\n")
    return "\n".join(out)


def gen_adapters():
    a = [f"a{i}" for i in range(32)]
    pat32 = "".join(f"Con{{{x}, " for x in a) + "_" + "}" * 32
    pat16 = "".join(f"Con{{{x}, " for x in a[:16]) + "rest" + "}" * 16
    return (
        "# First 32 little-endian U32 words of a list as a BLAKE2b message block.\n"
        "def bm_of(ws: +List<U32>) -> BM:\n  match ws:\n"
        f"    case {pat32}:\n      BM{{{', '.join(a)}}}\n"
        "    case _:\n      BM{" + ", ".join("0" for _ in a) + "}\n\n"
        "# SHA-256 over a list of big-endian U32 words, already padded to 16-word blocks.\n"
        "def sha_blocks(ws: +List<U32>, +h: SH) -> SH:\n  match ws:\n"
        f"    case {pat16}:\n      sha_blocks(rest, sha_compress(h, SW{{{', '.join(a[:16])}}}))\n"
        "    case _:\n      h\n")


if __name__ == "__main__":
    src = ("# GENERATED by gen.py: BLAKE2b (full blocks) and SHA-256 compression on U32.\n"
           "import Base\n\n" + gen_blake() + "\n" + gen_sha() + "\n" + gen_adapters())
    open("hashes.bend", "w").write(src)
    print(f"hashes.bend: {src.count(chr(10))} lines")
