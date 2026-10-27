#!/usr/bin/env python3
"""Affine coordinates of the constant Pallas points sigbatch decompresses (zcash/tx/consts.bend
encodings), as U32 words for sig/sig.bend's vpt / base_sa / base_bd."""
P = 0x40000000000000000000000000000000224698fc094cf91b992d30ed00000001
ENC = {
    "G_SPENDAUTH": [3094727011, 2367320708, 2070978828, 209652963, 1046430815, 999102588, 686937606, 3075810227],
    "V_CV": [989414247, 715636078, 727350412, 4261716863, 1335603762, 4155009648, 2386366274, 795892090],
    "R_CV": [2285656721, 247711336, 4002447407, 1081005893, 3935117384, 1332093787, 262408635, 133448789],
}


def sqrt(a):  # Tonelli-Shanks, p - 1 = t * 2^32
    t = (P - 1) >> 32
    m, c, u, r = 32, pow(5, t, P), pow(a, t, P), pow(a, (t + 1) // 2, P)
    while u != 1:
        i, tt = 0, u
        while tt != 1:
            tt, i = tt * tt % P, i + 1
        b = pow(c, 1 << (m - i - 1), P)
        m, c, u, r = i, b * b % P, u * b * b % P, r * b % P
    return r


def words(a):
    return ", ".join(str((a >> (32 * i)) & 0xFFFFFFFF) for i in range(8))


for name, ws in ENC.items():
    v = sum(w << (32 * i) for i, w in enumerate(ws))
    x, sign = v & ((1 << 255) - 1), v >> 255
    assert x < P
    y = sqrt((x ** 3 + 5) % P)
    assert y * y % P == (x ** 3 + 5) % P
    if y & 1 != sign:
        y = P - y
    print(f"{name} x {words(x)}\n{name} y {words(y)}")
