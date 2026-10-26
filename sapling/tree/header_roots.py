#!/usr/bin/env python3
"""Bend's Sapling roots vs the hashFinalSaplingRoot field of real block headers.

Before Heartwood (height < 903,000) a block header's 32 bytes at offset 68 are
hashFinalSaplingRoot: the Sapling tree root after that block. The headers come from
node/headers (fetched over P2P from Zebra/Zakura peers, every header's Equihash verified in
Bend). For each height H, the leaf count at the end of block H is read from the oracle's
leaf file (u32 height per record); Bend computes the root of that many leaves
(tree_main r) and it must equal the header's field.

  python3 header_roots.py [H ...]"""
import bisect, pathlib, struct, subprocess, sys

here = pathlib.Path(__file__).resolve().parent
D = here.parent / "data"
HD = here.parent.parent / "node/headers/data/genesis"
HEAVY = str(here.parent.parent / "heavy.sh")
REC = 1487


def header(h):
    base = ((h - 1) // 500000) * 500000 + 1
    with open(HD / f"h_{base}.bin", "rb") as f:
        f.seek((h - base) * REC)
        return f.read(REC)


def heights_upto(limit):
    """Heights of the leaves (sorted, tree order), up to the first leaf above `limit`."""
    hs = []
    with open(D / "sapling_leaves.bin", "rb") as f:
        while True:
            b = f.read(36 * 65536)
            if not b:
                break
            for i in range(0, len(b), 36):
                hs.append(struct.unpack_from("<I", b, i)[0])
            if hs[-1] > limit:
                break
    return hs


hs_req = [int(x) for x in sys.argv[1:]] or [419200, 419201, 450000, 500000, 550000, 600000, 653599, 653600, 700000, 750000, 800000, 850000, 902999]
hs = heights_upto(max(hs_req))
ok = 0
for H in hs_req:
    hdr = header(H)
    want = hdr[68:100].hex()
    n = bisect.bisect_right(hs, H)
    k = n // 65536
    part = D / f"leaves32/part_{k // 256:03d}.bin"
    out = subprocess.run([HEAVY, str(here / "tree_main"), "r", str(part) if n % 65536 else "-", str(D / "bend_chunk_roots.bin"), str(n), "0"],
                         capture_output=True, text=True).stdout.strip().split("\n")[-1]
    got = out.split()[5] if out.startswith("size") else "?"
    m = got == want
    ok += m
    print(f"height {H}: {n} leaves; header hashFinalSaplingRoot {want}; Bend {got} {'MATCH' if m else 'MISMATCH'}", flush=True)
print(f"header roots MATCH {ok}/{len(hs_req)}")
