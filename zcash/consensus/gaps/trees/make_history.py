#!/usr/bin/env python3
"""Per-block root history of the Sapling or Orchard tree, from activation to START-1, in Bend,
for the assumed-state (tip) instance, which otherwise knows no root before its start.

The leaf files (lightwalletd compact blocks, per-leaf heights: zcash/sapling/data/sapling_leaves.bin,
zcash/consensus/oracle/out/orchard_leaves.bin) are cut into segments of whole blocks (~SEG leaves).
Each segment starts from the frontier at its first leaf, built in Bend from the Bend chunk
roots (equal to the chain's GetSubtreeRoots) plus the partial chunk (seed mode), then appends
its blocks one at a time (follow mode: one root per block that appends). Checks:
  * continuity: each segment's final frontier == the next segment's independently built start
    frontier (two different Bend computations of the same tree);
  * the last root == the seed root at START-1 (make_seeds.py), itself == the chain's.
usage: make_history.py POOL [START] [JOBS] [SEG] [SEGS_FROM SEGS_TO]
  -> seeds/<pool>_hist_<a>_<b>.txt ("height root" per block that appends) per batch of segments;
     run batches (each under heavy.sh, < 10 min), then `make_history.py POOL START check`."""
import json, re, struct, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent.parent
POOL = sys.argv[1]
START = int(sys.argv[2]) if len(sys.argv) > 2 else 3522000
LEAVES = {"sapling": ROOT / "zcash/sapling/data/sapling_leaves.bin", "orchard": ROOT / "zcash/consensus/oracle/out/orchard_leaves.bin"}[POOL]
TOOL = HERE / f"{POOL}_frontier"
OUT = HERE / "seeds"
W = HERE / "seeds" / f"w_{POOL}"; W.mkdir(parents=True, exist_ok=True)
REC = 36
CHUNK = 65536


def chunk_roots(q):
    if POOL == "sapling":
        return (ROOT / "zcash/sapling/data/bend_chunk_roots.bin").read_bytes()[:q * 32]
    got = {}
    for p in sorted((ROOT / "zcash/consensus/orchard/logs").glob("chunks_*.log")):
        for k, r in re.findall(r"^chunk (\d+) subtree root ([0-9a-f]{64}) MATCH$", p.read_text(), re.M):
            got[int(k)] = r
    return b"".join(bytes.fromhex(got[k]) for k in range(q))


def heights():
    """(height, first leaf index, count) per block with leaves below START; cached in W."""
    cache = W / f"blocks_{START}.bin"
    if cache.exists():
        d = cache.read_bytes()
        return [struct.unpack_from("<III", d, i) for i in range(0, len(d), 12)], None
    out = []
    prev, first, i = None, 0, 0
    with open(LEAVES, "rb") as f:
        while True:
            buf = f.read(REC * 1000000)
            if not buf:
                break
            for j in range(0, len(buf), REC):
                h = int.from_bytes(buf[j:j + 4], "little")
                if h >= START:
                    break
                if h != prev:
                    if prev is not None:
                        out.append((prev, first, i - first))
                    prev, first = h, i
                i += 1
            else:
                continue
            break
    if prev is not None:
        out.append((prev, first, i - first))
    cache.write_bytes(b"".join(struct.pack("<III", *x) for x in out))
    return out, None


def segments(blocks, seg):
    segs, cur, n = [], [], 0
    for b in blocks:
        cur.append(b); n += b[2]
        if n >= seg:
            segs.append(cur); cur, n = [], 0
    if cur:
        segs.append(cur)
    return segs


def leaves_of(buf, a, b):
    with open(LEAVES, "rb") as f:
        f.seek(a * REC)
        d = f.read((b - a) * REC)
    return b"".join(d[i + 4:i + 36] for i in range(0, len(d), REC))


def run_seg(k, seg, buf, croots):
    s = seg[0][1]
    q = s // CHUNK
    (W / f"r{k}.bin").write_bytes(croots[:q * 32])
    (W / f"p{k}.bin").write_bytes(leaves_of(buf, q * CHUNK, s))
    o = subprocess.run([str(TOOL), str(W / f"r{k}.bin"), str(W / f"p{k}.bin"), str(W / f"start{k}.frontier")],
                       capture_output=True, text=True).stdout
    assert "seed chunks" in o, o
    e = seg[-1][1] + seg[-1][2]
    (W / f"l{k}.bin").write_bytes(leaves_of(buf, s, e))
    (W / f"c{k}.bin").write_bytes(b"".join(struct.pack("<I", c) for _, _, c in seg))
    o = subprocess.run([str(TOOL), str(W / f"start{k}.frontier"), str(W / f"l{k}.bin"), str(W / f"c{k}.bin"),
                        str(W / f"end{k}.frontier")], capture_output=True, text=True).stdout
    roots = {int(i): r for i, _s, r in re.findall(r"^root (\d+) (\d+) ([0-9a-f]{64})$", o, re.M)}
    assert sorted(roots) == list(range(len(seg))), (k, len(roots), len(seg))
    for x in ("r", "p", "l", "c"):
        (W / f"{x}{k}.bin").unlink()
    return [(seg[i][0], roots[i]) for i in range(len(seg))]


HIST_FROM = int(__import__("os").environ.get("HIST_FROM", "0"))  # history from this height (0: activation)

if __name__ == "__main__":
    blocks, buf = heights()
    blocks = [b for b in blocks if b[0] >= HIST_FROM]
    if len(sys.argv) > 3 and sys.argv[3] == "blocks":
        print(POOL, len(blocks), "blocks with leaves", blocks[0], blocks[-1], "leaves", blocks[-1][1] + blocks[-1][2])
        sys.exit(0)
    seg = int(sys.argv[5]) if len(sys.argv) > 5 and sys.argv[3] != "check" else 300000
    segs = segments(blocks, seg)
    if len(sys.argv) > 3 and sys.argv[3] == "check":
        seg = int(sys.argv[4]) if len(sys.argv) > 4 else 300000
        segs = segments(blocks, seg)
        hist = {}
        for p in sorted(OUT.glob(f"{POOL}_hist_*.txt")):
            for l in p.read_text().split("\n"):
                if l:
                    h, r = l.split(); hist[int(h)] = r
        cont = sum(1 for k in range(len(segs) - 1)
                   if (W / f"end{k}.frontier").read_text() == (W / f"start{k + 1}.frontier").read_text())
        seed = json.loads((OUT / "seeds.json").read_text())[POOL]["root"]
        last = hist[max(hist)]
        res = {"pool": POOL, "blocks_with_leaves": len(blocks), "roots": len(hist), "segments": len(segs),
               "continuity_ok": f"{cont}/{len(segs) - 1}", "last_height": max(hist), "last_root_eq_seed": last == seed,
               "complete": len(hist) == len(blocks), "from": blocks[0][0]}
        print(res)
        (OUT / f"{POOL}_hist_check.json").write_text(json.dumps(res, indent=1))
        with open(OUT / f"{POOL}_history.txt", "w") as f:
            for h in sorted(hist):
                f.write(f"{h} {hist[h]}\n")
        sys.exit(0 if res["complete"] and res["last_root_eq_seed"] and cont == len(segs) - 1 else 1)
    jobs = int(sys.argv[3]) if len(sys.argv) > 3 else 8
    a, b = (int(sys.argv[6]), int(sys.argv[7])) if len(sys.argv) > 7 else (0, len(segs) - 1)
    b = min(b, len(segs) - 1)
    croots = chunk_roots((blocks[-1][1] + blocks[-1][2]) // CHUNK + 1 if POOL == "sapling" else 770)
    with ThreadPoolExecutor(jobs) as ex:
        outs = list(ex.map(lambda k: run_seg(k, segs[k], buf, croots), range(a, b + 1)))
    with open(OUT / f"{POOL}_hist_{a:04d}_{b:04d}.txt", "w") as f:
        for o in outs:
            for h, r in o:
                f.write(f"{h} {r}\n")
    print(f"{POOL}: segments {a}..{b} of {len(segs)} done ({sum(len(o) for o in outs)} block roots)")
