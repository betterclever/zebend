"""Shared readers for consensus/nu7/data/testnet (blocks.bin + ctx.bin)."""
import struct

HDR = 1487
_IDX = {}


def _index(tn):
    if tn in _IDX:
        return _IDX[tn]
    bf, cf = open(tn / "blocks.bin", "rb"), open(tn / "ctx.bin", "rb")
    idx, i, j = [], 0, 0
    bsz, csz = (tn / "blocks.bin").stat().st_size, (tn / "ctx.bin").stat().st_size
    while i < bsz:
        bf.seek(i)
        h = struct.unpack("<I", bf.read(4))[0]
        bf.seek(i + 4 + HDR)
        L = struct.unpack("<I", bf.read(4))[0]
        cf.seek(j)
        cl = struct.unpack("<I", cf.read(4))[0]
        idx.append((h, i + 8 + HDR, L, j + 4, cl))
        i += 8 + HDR + L
        j += 4 + cl
    _IDX[tn] = (idx, bf, cf)
    return _IDX[tn]


def records(tn, lo, hi):
    idx, bf, cf = _index(tn)
    for h, bo, L, co, cl in idx:
        if lo <= h < hi:
            bf.seek(bo)
            raw = bf.read(L)
            cf.seek(co)
            yield h, raw, cf.read(cl)


def spent_of(crec):
    h, nt = struct.unpack_from("<II", crec, 0)
    k = 8 + 4 * nt
    out = []
    while k < len(crec):
        lo, hi, ph, cb, sl = struct.unpack_from("<IIIII", crec, k)
        k += 20
        out.append((lo | hi << 32, crec[k:k + sl]))
        k += sl
    return out
