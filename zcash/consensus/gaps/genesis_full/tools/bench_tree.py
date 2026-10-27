#!/usr/bin/env python3
"""Time one Bend tree run (as trees_init.py does) on N leaves of POOL starting at block index FROM
(negative: from the end). usage: bench_tree.py STATE POOL N FROM"""
import struct, subprocess, sys, time
from pathlib import Path
st, pool, N, frm = Path(sys.argv[1]), sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
B = Path(__file__).resolve().parents[1] / "fullnode/bin"
idx = (st / f"leaves/{pool}.blk").read_bytes()
blocks, off = [], 0
for i in range(0, len(idx), 8):
    h, c = struct.unpack_from("<II", idx, i); blocks.append((h, c, off)); off += c
if frm < 0:
    n, j = 0, len(blocks)
    while j > 0 and n + blocks[j-1][1] <= N: j -= 1; n += blocks[j][1]
    part = blocks[j:]
else:
    part, n = [], 0
    for b in blocks[frm:]:
        if n + b[1] > N and part: break
        part.append(b); n += b[1]
w = Path("/tmp/bench_tree_" + pool); w.mkdir(exist_ok=True)
with open(st / f"leaves/{pool}.bin", "rb") as f:
    f.seek(part[0][2] * 32); data = f.read(n * 32)
(w / "l").write_bytes(data); (w / "c").write_bytes(b"".join(struct.pack("<I", c) for _, c, _ in part))
(w / "fi").write_text("-\n" * 32)
tool = {"sapling": "sapling_frontier", "orchard": "orchard_frontier", "ironwood": "orchard_frontier"}[pool]
t = time.time()
r = subprocess.run(["/usr/bin/time", "-l", str(B / tool), str(w / "fi"), str(w / "l"), str(w / "c"), str(w / "fo")], capture_output=True, text=True)
el = time.time() - t
rss = [l for l in r.stderr.splitlines() if "maximum resident" in l]
print(f"{pool}: {n} leaves, {len(part)} blocks ({part[0][0]}..{part[-1][0]}): {el:.1f} s; roots printed {r.stdout.count(chr(10)+"root ")}; {rss}")
