#!/usr/bin/env python3
"""Real-chain test of trees/sprout_js (Bend): every JoinSplit anchor from genesis through the
extracted chunks (t/js/<chunk>.txt from extract_js.py, kept genesis spool, blocks checked by
blockdelta) must be valid under the zcashd/Zebra rule, incl. interstitial roots; plus tampers.
Windows of 1,000 blocks; the frontier is carried between windows; ext roots = roots of earlier
windows (as the node's anchor index would give), with frontiers for txs with >= 2 JoinSplits.
Also: the concatenated commitments equal the genesis instance's Sprout leaf log (state/leaves).
usage: test_sprout_js.py LAST_CHUNK"""
import random, re, struct, subprocess, sys
from collections import Counter
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
TOOL = HERE.parent / "sprout_js"
W = HERE / "w"; W.mkdir(exist_ok=True)
LAST = int(sys.argv[1])
roots, fronts = {}, {}   # root hex -> first height; root hex -> frontier levels
cnt, xs = Counter(), []
leaf_log = open(ROOT / "node/state/leaves/sprout.bin", "rb")
nleaves = 0
fin = "-"
rng = random.Random(7)
tamper = Counter()

def ext_bin(anchors, need_front):
    out = [struct.pack("<I", len(anchors))]
    for a in anchors:
        out.append(bytes.fromhex(a))
        if a in need_front and a in fronts:
            out.append(struct.pack("<I", 1))
            for lv in fronts[a]:
                out.append(struct.pack("<I", 0) + bytes(32) if lv == "-" else struct.pack("<I", 1) + bytes.fromhex(lv))
        else:
            out.append(struct.pack("<I", 0))
    return b"".join(out)

def run(start, js, fin, fout, need_front=None):
    jb = [struct.pack("<I", len(js))]
    for h, t, a, c1, c2 in js:
        jb.append(struct.pack("<II", h - start, t) + bytes.fromhex(a) + bytes.fromhex(c1) + bytes.fromhex(c2))
    (W / "js.bin").write_bytes(b"".join(jb))
    anchors = sorted({a for _, _, a, _, _ in js if a in roots})
    multi = Counter((h, t) for h, t, _, _, _ in js)
    nf = {a for h, t, a, _, _ in js if multi[(h, t)] > 1} if need_front is None else need_front
    (W / "ext.bin").write_bytes(ext_bin(anchors, nf))
    r = subprocess.run([str(TOOL), fin, str(W / "js.bin"), str(W / "ext.bin"), fout], capture_output=True, text=True)
    return r.stdout

for c in range(0, LAST + 1):
    p = HERE / "js" / f"{c}.txt"
    js = [(int(f[0]), int(f[1]), f[2], f[3], f[4]) for f in (l.split() for l in p.read_text().splitlines() if l.strip())]
    start = c * 1000
    if not js:
        continue
    cms = b"".join(bytes.fromhex(x) for j in js for x in (j[3], j[4]))
    log_part = leaf_log.read(len(cms))
    cnt["leaf log equal" if log_part == cms else "LEAF LOG DIFFERS"] += 1
    nleaves += len(js) * 2
    fout = str(W / f"f_{c % 2}.txt")
    out = run(start, js, fin, fout)
    v = dict((int(k), x) for k, x in re.findall(r"^js (\d+) ([WEIXZ])$", out, re.M))
    if len(v) != len(js):
        print("chunk", c, "missing verdicts", len(v), len(js), out[-300:]); sys.exit(1)
    for k, j in enumerate(js):
        cnt[v[k]] += 1
        if v[k] in "XZ": xs.append((j, v[k]))
    for b, sz, r in re.findall(r"^root (\d+) (\d+) ([0-9a-f]{64})$", out, re.M):
        roots.setdefault(r, start + int(b))
    for b, lv in re.findall(r"^front (\d+) (\S+)$", out, re.M):
        pass
    blk_roots = re.findall(r"^root (\d+) \d+ ([0-9a-f]{64})$", out, re.M)
    for (b, r), (b2, lv) in zip(blk_roots, re.findall(r"^front (\d+) (\S+)$", out, re.M)):
        assert b == b2
        fronts.setdefault(r, lv.split(","))
    empty = re.search(r"^empty_root ([0-9a-f]{64})$", out, re.M).group(1)
    roots.setdefault(empty, -1); fronts.setdefault(empty, ["-"] * 29)
    # tampers on this window (state not carried): (1) one random anchor -> must be X;
    # (2) for a tx with >=2 JoinSplits whose later JS was I, drop the frontier of its first
    # anchor -> that JS must become X (or the first JS Z) and never pass silently
    if c % 10 == 0:
        k = rng.randrange(len(js)); h, t, a, c1, c2 = js[k]
        bad = list(js); bad[k] = (h, t, "%064x" % rng.getrandbits(256), c1, c2)
        o2 = run(start, bad, fin, str(W / "ft.txt"))
        tamper["random anchor -> X" if re.search(rf"^js {k} X$", o2, re.M) else "random anchor NOT rejected"] += 1
    # an interstitial JS whose tx's first JS used an ext root (tree known only via ext frontier)
    ii = [k for k in range(1, len(js)) if v[k] == "I" and js[k - 1][:2] == js[k][:2] and v[k - 1] == "E"]
    if ii:
        k = ii[0]
        o3 = run(start, js, fin, str(W / "ft.txt"), need_front=set())
        v3 = dict((int(a), x) for a, x in re.findall(r"^js (\d+) ([WEIXZ])$", o3, re.M))
        tamper["interstitial over an ext root, ext frontier withheld: " + ("rejected (X)" if v3.get(k) == "X" else "NOT rejected: " + v3.get(k, "?"))] += 1
    fin = fout
    if c % 20 == 0:
        print("chunk", c, dict(cnt), flush=True)
print("FINAL through height", (LAST + 1) * 1000 - 1, ":", nleaves, "leaves;", dict(cnt))
print("tampers:", dict(tamper))
print("X/Z cases:", len(xs), xs[:10])
