#!/usr/bin/env python3
"""Small pure-Python Jubjub reference (affine, exact integers), written from the protocol
spec (sections 5.4.9.3 Jubjub, 5.4.9.5 GroupHash, 5.4.1.7 Pedersen hash, 5.4.1.3 MerkleCRH).

Used ONLY to generate constants (generators, d) for the Bend code and for quick
self-checks while the Rust oracle's vectors are not available. The authority for every
"tested" claim is the Rust oracle (sapling-crypto / jubjub), never this file.
"""
import hashlib

Q = 0x73EDA753299D7D483339D80809A1D80553BDA402FFFE5BFEFFFFFFFF00000001  # base field (BLS12-381 r)
R_J = 0x0E7DB4EA6533AFA906673B0101343B00A6682093CCC81082D0970E5ED6F72CB7  # subgroup order
A = Q - 1
D = (-10240 * pow(10241, -1, Q)) % Q
URS = b"096b36a5804bfacef1691e173c366a47ff5ba84a44f26ddd7e8d9f79d5b42df0"

ID = (0, 1)


def add(p, q):
    (u1, v1), (u2, v2) = p, q
    t = D * u1 * u2 * v1 * v2 % Q
    u3 = (u1 * v2 + v1 * u2) * pow(1 + t, -1, Q) % Q
    v3 = (v1 * v2 - A * u1 * u2) * pow(1 - t, -1, Q) % Q
    return (u3, v3)


def neg(p):
    return ((-p[0]) % Q, p[1])


def mul(k, p):
    r = ID
    for bit in bin(k)[2:] if k > 0 else "":
        r = add(r, r)
        if bit == "1":
            r = add(r, p)
    return r


def sqrt(x):
    x %= Q
    if x == 0:
        return 0
    if pow(x, (Q - 1) // 2, Q) != 1:
        return None
    # Tonelli-Shanks
    s, t = 0, Q - 1
    while t % 2 == 0:
        s, t = s + 1, t // 2
    z = 5
    m, c, tt, r = s, pow(z, t, Q), pow(x, t, Q), pow(x, (t + 1) // 2, Q)
    while tt != 1:
        i, t2 = 0, tt
        while t2 != 1:
            t2, i = t2 * t2 % Q, i + 1
        b = pow(c, 1 << (m - i - 1), Q)
        m, c, tt, r = i, b * b % Q, tt * b * b % Q, r * b % Q
    return r


def encode(p):
    u, v = p
    return (v | ((u & 1) << 255)).to_bytes(32, "little")


def decode(b, zip216=True):
    """abst_J. Returns None if not a point (or non-canonical)."""
    y = int.from_bytes(b, "little")
    sign, v = y >> 255, y & ((1 << 255) - 1)
    if v >= Q:
        return None
    u2 = (v * v - 1) * pow(D * v * v - A, -1, Q) % Q
    u = sqrt(u2)
    if u is None:
        return None
    if u == 0 and sign == 1:
        return None if zip216 else (0, v)
    if u & 1 != sign:
        u = Q - u
    return (u, v)


def group_hash(tag, pers):
    h = hashlib.blake2s(URS + tag, digest_size=32, person=pers).digest()
    p = decode(h, zip216=False)
    if p is None:
        return None
    p = mul(8, p)
    return None if p == ID else p


def find_group_hash(m, pers):
    i = 0
    while True:
        p = group_hash(m + bytes([i]), pers)
        if p is not None:
            return p
        i += 1


def gens():
    g = {
        "G_SPENDAUTH": find_group_hash(b"", b"Zcash_G_"),
        "V_CV": find_group_hash(b"v", b"Zcash_cv"),
        "R_CV": find_group_hash(b"r", b"Zcash_cv"),
    }
    for i in range(6):
        g[f"PH{i}"] = find_group_hash(i.to_bytes(4, "little"), b"Zcash_PH")
    return g


_PH = None


def pedersen_hash(bits):
    """bits: list of 0/1 (personalization already prepended). Returns the point."""
    global _PH
    if _PH is None:
        g = gens()
        _PH = [g[f"PH{i}"] for i in range(6)]
    bits = list(bits)
    while len(bits) % 3:
        bits.append(0)
    acc = ID
    chunks = [bits[i:i + 3] for i in range(0, len(bits), 3)]
    for seg in range(0, len(chunks), 63):
        s = 0
        for j, (a, b, c) in enumerate(chunks[seg:seg + 63]):
            e = (1 + a + 2 * b) * (-1 if c else 1)
            s += e * (1 << (4 * j))
        acc = add(acc, mul(s % R_J, _PH[seg // 63]))
    return acc


def le_bits(x, n):
    return [(x >> i) & 1 for i in range(n)]


def merkle_hash(level, l, r):
    bits = le_bits(level, 6) + le_bits(l, 255) + le_bits(r, 255)
    return pedersen_hash(bits)[0]


def empties():
    e = [1]
    for l in range(32):
        e.append(merkle_hash(l, e[-1], e[-1]))
    return e


if __name__ == "__main__":
    g = gens()
    for k, (u, v) in g.items():
        print(k, u.to_bytes(32, "little").hex(), v.to_bytes(32, "little").hex())
    e = empties()
    print("empty root 32 (LE bytes):", e[32].to_bytes(32, "little").hex())
    print("display (reversed):", e[32].to_bytes(32, "little")[::-1].hex())
