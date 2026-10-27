#!/usr/bin/env python3
"""Test the Bend Sprout tree against the real chain: every JoinSplit anchor in heights [A, B]
must be a root the Bend tree produced: after some earlier block, or (zcashd's rule) after an
earlier JoinSplit of the same transaction; the empty root also counts.

Reads blocks from the spool (sync.py --keep-spool), extracts them with bin/blockdelta, pushes
every JoinSplit's two commitments as one group through bin/sprout.
usage: test_sprout.py A B
"""
import struct, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import sync

A, B = int(sys.argv[1]), int(sys.argv[2])
recs = []
for p in sorted(sync.SPOOL.glob("*.blk"), key=lambda p: int(p.stem)):
    d = p.read_bytes()
    i = 0
    while i < len(d):
        h, n = struct.unpack_from("<II", d, i)
        if A <= h <= B:
            recs.append((h, d[i + 8:i + 8 + n]))
        i += 8 + n
recs.sort()
assert recs and recs[0][0] == A and recs[-1][0] - A + 1 == len(recs), "spool does not hold the whole range"
t = time.time()
blocks = sync.run_blockdelta(recs, 6, f"sprouttest{A}")
print(f"extracted {len(blocks)} blocks in {time.time() - t:.1f} s")
groups = []  # (height, tx index, js index, anchor, cm1, cm2)
for b in blocks:
    for tx in b["txs"]:
        for k, js in enumerate(tx["js"]):
            groups.append((b["height"], tx["i"], k, js["anchor"]))
cms = [c for b in blocks for c in b["leaves"]["sprout"]]
assert len(cms) == 2 * len(groups)
# Blocks below A: their leaves come from the node's leaf log (state/leaves/sprout.*), one group
# per block, so the roots after each earlier block are known too.
idx = (sync.STATE / "leaves/sprout.blk").read_bytes()
pre = [struct.unpack_from("<II", idx, i) for i in range(0, len(idx), 8)]
pre = [(h, c) for h, c in pre if h < A]
npre = sum(c for _, c in pre)
pre_leaves = (sync.STATE / "leaves/sprout.bin").read_bytes()[:npre * 32]
w = sync.WORK
(w / "sp_leaves.bin").write_bytes(pre_leaves + b"".join(bytes.fromhex(c) for c in cms))
(w / "sp_counts.bin").write_bytes(b"".join(struct.pack("<I", c) for _, c in pre) + struct.pack("<I", 2) * len(groups))
t = time.time()
out = subprocess.run([str(HERE.parent / "bin/sprout"), "-", str(w / "sp_leaves.bin"), str(w / "sp_counts.bin"),
                      str(w / "sp_frontier.txt")], capture_output=True, text=True).stdout
el = time.time() - t
roots = [l.split()[3] for l in out.splitlines() if l.startswith("root ")]
empty = [l.split()[1] for l in out.splitlines() if l.startswith("empty_root")][0]
pre_roots, roots = roots[:len(pre)], roots[len(pre):]
assert len(roots) == len(groups), (len(roots), len(groups))
print(f"bend sprout: {len(cms)} leaves, {len(groups)} roots in {el:.1f} s; empty root {empty}")
# Anchor rule (zcashd ContextualCheckInputs / Zebra anchors.rs): the first JoinSplit of a tx
# uses a root after some earlier block; later ones may also use the interstitial root after
# an earlier JoinSplit of the same tx.
final_after = {}  # height -> root after the block (if it appended anything)
for (h, _, _, _), r in zip(groups, roots):
    final_after[h] = r
known = {empty} | set(pre_roots)
ok = bad = 0
gi = 0
heights = sorted({g[0] for g in groups})
by_h = {}
for g, r in zip(groups, roots):
    by_h.setdefault(g[0], []).append((g, r))
for h in heights:
    inter = {}
    for (gh, tx, k, anchor), r in by_h[h]:
        if anchor in known or anchor in inter.get(tx, set()):
            ok += 1
        else:
            bad += 1
            if bad <= 5:
                print(f"  anchor not found: height {gh} tx {tx} js {k} {anchor}")
        inter.setdefault(tx, set()).add(r)
    known.add(final_after[h])
print(f"Sprout anchors in [{A}, {B}]: {ok}/{ok + bad} are Bend-computed roots ({bad} not found)")
