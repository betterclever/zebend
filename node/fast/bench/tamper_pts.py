"""Tamper test of the deferred point check: overwrite one curve point (Sapling cv/rk, Orchard/
Ironwood cv/rk/epk) of a real block with a random or edge-case encoding and compare the
original blockdelta (zcash/wire gate inline) with fast/bin/blockdelta (CPU and GPU batch).
usage: tamper_pts.py N   -> prints per case the verdict and whether all three outputs agree."""
import random, struct, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
NODE = HERE.parent.parent
sys.path.insert(0, str(NODE))
import headers

random.seed(7)
R = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001
P = 0x40000000000000000000000000000000224698fc094cf91b992d30ed00000001
data = NODE / "bend/data"
ref = (HERE / "data/eras.ref").read_text()
# (height, kind, offset of the 32 bytes in the raw block)
cands = []
cur = None
for line in ref.splitlines():
    f = line.split()
    if f[0] == "block":
        cur = int(f[1])
        raw = (data / f"{cur}.bin").read_bytes()
    elif f[0] == "so":
        o = raw.find(bytes.fromhex(f[1]))
        if o > 0:
            cands.append((cur, "sap cv", o - 32, R))
    elif f[0] == "ss":
        o = raw.find(bytes.fromhex(f[2]))  # nf; v4: cv anchor nf rk, v5: cv nf rk
        if o > 0:
            cands.append((cur, "sap rk", o + 32, R))
    elif f[0] in ("oa", "ia"):
        o = raw.find(bytes.fromhex(f[1]))  # nf: cv nf rk cmx epk
        if o > 0:
            cands.append((cur, f[0] + " cv", o - 32, P))
            cands.append((cur, f[0] + " rk", o + 32, P))
            cands.append((cur, f[0] + " epk", o + 96, P))
n = int(sys.argv[1]) if len(sys.argv) > 1 else 40
agree = bad = 0
for i in range(n):
    h, what, off, m = random.choice(cands)
    raw = bytearray((data / f"{h}.bin").read_bytes())
    r = random.random()
    v = random.choice([0, 1, m - 1, 2, 5, m, m + 1, 2**255 - 1]) if r < 0.3 else random.randrange(m)
    enc = (v | (random.getrandbits(1) << 255)) if v < 2**255 else v
    raw[off:off + 32] = enc.to_bytes(32, "little")
    hd = headers.header(h) if h >= 1 else bytes(raw[:1487])
    w = HERE / "data/tamper.bin"
    w.write_bytes(struct.pack("<I", h) + hd + struct.pack("<I", len(raw)) + bytes(raw))
    outs = [subprocess.run(a, capture_output=True, text=True).stdout for a in (
        [str(HERE.parent / "orig/blockdelta"), str(w)],
        [str(HERE.parent / "bin/blockdelta"), str(w), "+RTS", "--threads", "1", "--gpu", "off"],
        [str(HERE.parent / "bin/blockdelta"), str(w), "+RTS", "--threads", "1"])]
    same = outs[0] == outs[1] == outs[2]
    agree += same
    inv = "INVALID" in outs[0].splitlines()[0]
    bad += inv
    print(f"{h} {what} v={'edge' if r < 0.3 else 'rand'}: ref {'INVALID wire' if inv else outs[0].splitlines()[0][-30:]}  "
          f"{'AGREE' if same else 'DISAGREE'}", flush=True)
print(f"tamper: {n} cases, {bad} rejected by zcash/wire, all three outputs identical in {agree}/{n}")
