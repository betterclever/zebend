#!/usr/bin/env python3
"""Seed frontiers for the tip instance (assumed start 3,522,000): the Sapling and Orchard
note commitment trees after block START-1, computed in Bend (sapling_frontier / orchard_frontier
seed mode) from
  * the level-16 chunk roots Bend computed over the components' full leaf files, each equal to
    the chain's own GetSubtreeRoots (zcash/sapling/: 1,128/1,128, data/bend_chunk_roots.bin;
    zcash/consensus/orchard/: 770/770, logs/chunks_*.log), and
  * the leaves of the last, partial chunk (leaf files from lightwalletd compact blocks with
    per-leaf heights: zcash/sapling/data/sapling_leaves.bin, zcash/consensus/oracle/out/orchard_leaves.bin;
    36-byte records u32 height | 32-byte commitment).
The leaf count N is the number of leaves with height < START (from those files). Python only
selects bytes; the frontier and its root are Bend's. The root is then compared with the chain
(Blockchair finalsaplingroot / finalorchardroot at START-1: an oracle cross-check); the node
itself authenticates the seed through the ZIP 221 history commitment of the following headers
and through every anchor that matches.
usage: make_seeds.py [START]   -> seeds/<pool>_<START-1>.frontier + seeds/seeds.json"""
import json, re, struct, subprocess, sys, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent.parent
START = int(sys.argv[1]) if len(sys.argv) > 1 else 3522000
OUT = HERE / "seeds"; OUT.mkdir(exist_ok=True)
REC = 36


def count_below(path, start):
    """Leaves with height < start: binary search on the (sorted) per-leaf heights."""
    size = path.stat().st_size // REC
    with open(path, "rb") as f:
        lo, hi = 0, size
        while lo < hi:
            mid = (lo + hi) // 2
            f.seek(mid * REC)
            h, = struct.unpack("<I", f.read(4))
            if h < start: lo = mid + 1
            else: hi = mid
    return lo, size


def partial(path, q, n):
    with open(path, "rb") as f:
        f.seek(q * 65536 * REC)
        d = f.read((n - q * 65536) * REC)
    return b"".join(d[i + 4:i + 36] for i in range(0, len(d), REC))


def orchard_chunk_roots(q):
    got = {}
    for p in sorted((ROOT / "zcash/consensus/orchard/logs").glob("chunks_*.log")):
        for k, r in re.findall(r"^chunk (\d+) subtree root ([0-9a-f]{64}) MATCH$", p.read_text(), re.M):
            got[int(k)] = r
    assert all(k in got for k in range(q)), "missing orchard chunk roots"
    return b"".join(bytes.fromhex(got[k]) for k in range(q))


def chain(h):
    try:
        u = f"https://api.blockchair.com/zcash/raw/block/{h}"
        d = json.load(urllib.request.urlopen(u, timeout=60))["data"][str(h)]["decoded_raw_block"]
        return d
    except Exception as e:
        return {"error": str(e)}


res = {"start": START, "height": START - 1}
cb = chain(START - 1)
for pool, leaves, roots_of, tool in [
        ("sapling", ROOT / "zcash/sapling/data/sapling_leaves.bin",
         lambda q: (ROOT / "zcash/sapling/data/bend_chunk_roots.bin").read_bytes()[:q * 32], "sapling_frontier"),
        ("orchard", ROOT / "zcash/consensus/oracle/out/orchard_leaves.bin", orchard_chunk_roots, "orchard_frontier")]:
    n, total = count_below(leaves, START)
    assert n < total, f"{pool}: leaf file does not reach past {START - 1}"
    q = n // 65536
    (OUT / f"{pool}_roots.bin").write_bytes(roots_of(q))
    (OUT / f"{pool}_partial.bin").write_bytes(partial(leaves, q, n))
    fr = OUT / f"{pool}_{START - 1}.frontier"
    out = subprocess.run([str(HERE / tool), str(OUT / f"{pool}_roots.bin"), str(OUT / f"{pool}_partial.bin"), str(fr)],
                         capture_output=True, text=True).stdout
    m = re.search(r"^seed chunks (\d+) partial (\d+) root ([0-9a-f]{64})$", out, re.M)
    assert m, out
    root = m.group(3)
    want = cb.get(f"final{pool}root")
    if want and pool == "sapling":  # zcashd prints finalsaplingroot byte-reversed, finalorchardroot as encoded
        want = bytes.fromhex(want)[::-1].hex()
    want_size = cb.get("trees", {}).get(pool, {}).get("size")
    res[pool] = {"leaves": n, "chunks": q, "partial": n - q * 65536, "root": root,
                 "chain_root_blockchair": want,
                 "chain_size_blockchair": want_size,
                 "root_match": want == root,
                 "size_match": want_size == n, "frontier": str(fr.relative_to(HERE))}
    print(pool, res[pool])
(OUT / "seeds.json").write_text(json.dumps(res, indent=1))
