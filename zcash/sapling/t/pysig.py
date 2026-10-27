#!/usr/bin/env python3
"""Self-check for sig/sig_main with RedJubjub signatures made by the Python reference
(jj.py; NOT the oracle). Writes py_sigs.bin in the oracle's chunk format and the expected
per-item verdicts; then runs sig_main in batch and single mode and compares."""
import hashlib, random, struct, subprocess, sys, pathlib
here = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(here.parent / "jubjub"))
import jj

rnd = random.Random(11)
RJ = jj.R_J
g = jj.gens()
G, V, R = g["G_SPENDAUTH"], g["V_CV"], g["R_CV"]


def H(*parts):
    return int.from_bytes(hashlib.blake2b(b"".join(parts), digest_size=64, person=b"Zcash_RedJubjubH").digest(), "little") % RJ


def sign(sk, base, msg):
    vk = jj.encode(jj.mul(sk, base))
    r = rnd.randrange(1, RJ)
    Rb = jj.encode(jj.mul(r, base))
    s = (r + H(Rb, vk, msg) * sk) % RJ
    return Rb, s.to_bytes(32, "little"), vk


items, verdicts = [], []


def item(kind, ncv, vb, Rb, s, msg, vk, cvs, ok):
    lo, hi = vb & 0xFFFFFFFF, (vb >> 32) & 0xFFFFFFFF
    items.append(struct.pack("<4I", kind, ncv, lo, hi) + Rb + s + msg + vk + b"".join(cvs))
    verdicts.append(ok)


for i in range(24):
    msg = rnd.randbytes(32)
    sk = rnd.randrange(1, RJ)
    Rb, s, vk = sign(sk, G, msg)
    t = i % 6
    if t == 1:
        msg = bytes([msg[0] ^ 1]) + msg[1:]
    if t == 2:
        s = ((int.from_bytes(s, "little") + 1) % RJ).to_bytes(32, "little")
    if t == 3:
        s = (int.from_bytes(s, "little") + RJ).to_bytes(32, "little")  # non-canonical s
    item(0, 0, 0, Rb, s, msg, vk, [], t not in (1, 2, 3))
    # binding: spends with values vs, outputs vo; vb = sum vs - sum vo
    nsp, nout = rnd.randrange(0, 3), rnd.randrange(0, 3)
    vs = [rnd.randrange(0, 10**9) for _ in range(nsp)]
    vo = [rnd.randrange(0, 10**9) for _ in range(nout)]
    rs = [rnd.randrange(RJ) for _ in range(nsp)]
    ro = [rnd.randrange(RJ) for _ in range(nout)]
    cv = lambda v, r: jj.encode(jj.add(jj.mul(v, V), jj.mul(r, R)))
    cvs = [cv(v, r) for v, r in zip(vs, rs)] + [cv(v, r) for v, r in zip(vo, ro)]
    vb = sum(vs) - sum(vo)
    bsk = (sum(rs) - sum(ro)) % RJ
    msg2 = rnd.randbytes(32)
    Rb, s, vk = sign(bsk, R, msg2)
    if t == 4:
        vb += 1
    item(1, nsp | (nout << 16), vb & ((1 << 64) - 1), Rb, s, msg2, bytes(32), cvs, t != 4)

blob = struct.pack("<I", len(items)) + b"".join(items)
(here / "py_sigs.bin").write_bytes(blob)
want = "".join("1" if v else "0" for v in verdicts)
bad = [i for i, v in enumerate(verdicts) if not v]
print("expected verdicts", want)
print("expected invalid", bad)
for mode in ("0", "11"):
    out = subprocess.run([str(here.parent / "sig/sig_main"), mode, str(here / "py_sigs.bin")], capture_output=True, text=True).stdout
    print(out.strip())
