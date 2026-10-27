#!/usr/bin/env python3
"""Extract every JoinSplit (height, tx index, anchor, cm1, cm2) from kept genesis spool chunks
with bin/blockdelta (Bend), 6 processes in parallel. usage: extract_js.py FIRST_CHUNK LAST_CHUNK
(chunk = height // 1000; node/work/spool-kept/<chunk*1000>.blk) -> js/<chunk>.txt"""
import struct, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SP = ROOT / "node/work/spool-kept"
BD = ROOT / "node/bin/blockdelta"
sys.path.insert(0, str(ROOT / "node"))
import headers
(HERE / "js").mkdir(exist_ok=True); (HERE / "w").mkdir(exist_ok=True)
last = headers.last_height()

def one(c):
    out = HERE / "js" / f"{c}.txt"
    if out.exists(): return c, "kept"
    d = (SP / f"{c * 1000}.blk").read_bytes()
    recs, i = [], 0
    while i < len(d):
        h, n = struct.unpack_from("<II", d, i); recs.append((h, d[i + 8:i + 8 + n])); i += 8 + n
    recs.sort()
    lines = []
    for k in range(0, len(recs), int(__import__("os").environ.get("PART", "250"))):
        part = recs[k:k + int(__import__("os").environ.get("PART", "250"))]
        wp = HERE / "w" / f"{c}_{k}.bin"
        with open(wp, "wb") as f:
            for h, raw in part:
                exp = headers.header(h) if 1 <= h <= last else bytes(1487)
                f.write(struct.pack("<I", h) + exp + struct.pack("<I", len(raw)) + raw)
        r = subprocess.run([str(BD), str(wp)], capture_output=True, text=True).stdout
        wp.unlink()
        hs = []
        h = ti = None
        for l in r.splitlines():
            f = l.split()
            if not f: continue
            if f[0] == "block": h = int(f[1]); hs.append(h)
            elif f[0] == "tx": ti = int(f[1])
            elif f[0] == "js": lines.append(f"{h} {ti} {f[3]} {f[6]} {f[7]}")
        assert hs == [x for x, _ in part], (c, k, hs[:3])
    out.write_text("\n".join(lines) + ("\n" if lines else ""))
    return c, len(lines)

a, b = int(sys.argv[1]), int(sys.argv[2])
with ThreadPoolExecutor(int(__import__("os").environ.get("JOBS", "6"))) as ex:
    for c, n in ex.map(one, range(a, b + 1)):
        print(c, n, flush=True)
