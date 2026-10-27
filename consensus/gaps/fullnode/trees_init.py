#!/usr/bin/env python3
"""Start tracking the note commitment trees in an existing node state (run with the node
stopped, at a window boundary). Builds every pool's tree in Bend from the instance's own leaf
logs (leaves/<pool>.bin/.blk), records the root after every block that appended leaves in the
anchor index (anchor table), the tree state before each such block in the undo data of the
blocks that still have undo data (so a rollback restores the trees), and the final trees in
meta "trees" -- all in ONE SQLite transaction.

  genesis instance (leaf logs from genesis):
      trees_init.py STATE --genesis
  assumed-state instance (leaf logs from START; no earlier history):
      trees_init.py STATE --seed sapling=F1 --seed orchard=F2 --seed-height H --origin TEXT
      (F1/F2: frontiers of the trees after block H = START-1, consensus/gaps/trees/make_seeds.py;
      pools without a seed, e.g. Sprout, stay untracked: their anchors are reported SKIPPED)

Checks while building: for the genesis instance, every Sapling-era block before Heartwood
(419,200..902,999) must have the header's hashFinalSaplingRoot (Bend-verified headers) equal to
the Bend root after it; any mismatch aborts without writing.
Options: --heavy (run each Bend call under ../heavy.sh), --dry-run (build and check, no writes).
"""
import argparse, json, pickle, re, struct, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import headers, store as S, trees as T

ap = argparse.ArgumentParser()
ap.add_argument("state")
ap.add_argument("--genesis", action="store_true")
ap.add_argument("--seed", action="append", default=[])
ap.add_argument("--seed-height", type=int)
ap.add_argument("--history", action="append", default=[],
                help="POOL=FILE: per-block roots before the seed (\"height root\" lines, e.g. trees/seeds/<pool>_history.txt, "
                     "Bend-built from activation or from a stated height): imported into the anchor index")
ap.add_argument("--origin", default="")
ap.add_argument("--chunk", type=int, default=400000, help="leaves per Bend run")
ap.add_argument("--heavy", action="store_true")
ap.add_argument("--dry-run", action="store_true")
ap.add_argument("--pools", help="comma-separated subset of pools (tests)")
ap.add_argument("--leaf-dir", help="dry run on copied leaf logs (<dir>/<pool>.bin/.blk) without a store: "
                "STATE is then only the work directory")
args = ap.parse_args()


class LeafOnly:
    """--leaf-dir: leaf logs without a store (never written)."""
    def __init__(self, d):
        self.d = Path(d)
    def leaf_paths(self, pool):
        return self.d / f"{pool}.bin", self.d / f"{pool}.blk"
    def get(self, k):
        return None


if args.leaf_dir:
    args.dry_run = True
    st = LeafOnly(args.leaf_dir)
    tip = max((struct.unpack_from("<I", p.read_bytes(), p.stat().st_size - 8)[0]
               for p in Path(args.leaf_dir).glob("*.blk") if p.stat().st_size), default=-1)
else:
    st = S.Store(Path(args.state))
    tip = st.tip()["height"]
work = Path(args.state) / "trees_init"
work.mkdir(parents=True, exist_ok=True)
HEAVY = [str(HERE.parent.parent.parent / "heavy.sh")] if args.heavy else []


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def run(cmd):
    r = subprocess.run(HEAVY + [str(c) for c in cmd], capture_output=True, text=True)
    if not r.stdout.strip():
        raise SystemExit(f"{cmd[0]} printed nothing: {r.stderr[-300:]}")
    return r.stdout


def leaf_blocks(pool):
    a, b = st.leaf_paths(pool)
    idx = Path(b).read_bytes()
    out, off = [], 0
    for i in range(0, len(idx), 8):
        h, c = struct.unpack_from("<II", idx, i)
        if h > tip:
            break
        out.append((h, c, off))
        off += c
    return out, Path(a)


seeds = {}
for x in args.seed:
    pool, path = x.split("=", 1)
    seeds[pool] = Path(path).read_text().split("\n")[:T.DEPTH[pool]]
pools = T.TREE_POOLS if args.genesis else list(seeds)
if args.pools:
    pools = [p for p in pools if p in args.pools.split(",")]
if not pools:
    raise SystemExit("nothing to do: --genesis or --seed POOL=FRONTIER")
origin = args.origin or ("built from this instance's leaf logs since genesis" if args.genesis else "")

state, anchors, before = {}, [], {}  # before[(pool, height)] = state before that block
undo_heights = set() if args.leaf_dir else {r[0] for r in st.db.execute("SELECT height FROM undo")}
for pool in pools:
    blocks, leafp = leaf_blocks(pool)
    fr = seeds.get(pool, ["-"] * T.DEPTH[pool])
    tool = HERE / "bin" / (T.TOOL.get(pool) or "sprout_js")
    # the seed's own root (and the empty root): via a run with no leaves
    lp, cp, fo, fi = (work / f"{pool}.{x}" for x in ("leaves", "counts", "out", "in"))
    fi.write_text(T._fr_text(fr, T.DEPTH[pool]))
    if pool == "sprout":
        lp.write_bytes(struct.pack("<I", 0)); cp.write_bytes(struct.pack("<I", 0))
    else:
        lp.write_bytes(b""); cp.write_bytes(struct.pack("<I", 0))
    o = run([tool, fi, lp, cp, fo]) if pool != "sprout" else run([tool, fi, lp, cp, fo])
    empty = re.search(r"^empty_root ([0-9a-f]{64})$", o, re.M).group(1)
    cur = {"frontier": fr, "size": 0, "root": None, "origin": origin}
    # root of the seed frontier: push nothing -> not printed; compute via a zero-leaf block is not
    # possible, so take it from the first block's run below or, with no blocks, from the seeds file
    seed_root = None
    if args.seed_height is not None and pool in seeds:
        sj = json.loads((Path(args.seed[0].split("=", 1)[1]).parent / "seeds.json").read_text())
        seed_root, cur["size"] = sj[pool]["root"], sj[pool]["leaves"]
        anchors.append((T.TREE_POOLS.index(pool), bytes.fromhex(seed_root), args.seed_height))
    cur["root"] = seed_root or empty
    log(f"{pool}: {len(blocks)} blocks with leaves, {sum(c for _, c, _ in blocks)} leaves; start root {cur['root'][:16]}")
    i = 0
    with open(leafp, "rb") as f:
        while i < len(blocks):
            j, n = i, 0
            lim = min(args.chunk, 4000) if pool == "sprout" else args.chunk  # sprout_js scans its window's roots per JoinSplit
            while j < len(blocks) and (n == 0 or n + blocks[j][1] <= lim):
                n += blocks[j][1]; j += 1
            part = blocks[i:j]
            f.seek(part[0][2] * 32)
            data = f.read(n * 32)
            fi.write_text(T._fr_text(cur["frontier"], T.DEPTH[pool]))
            if pool == "sprout":  # sprout_js: one pseudo-JoinSplit per 2 leaves (anchor = 0: verdicts unused)
                js = [struct.pack("<I", n // 2)]
                for bi, (h, c, off) in enumerate(part):
                    base = (off - part[0][2]) * 32
                    for k in range(0, c, 2):
                        js.append(struct.pack("<II", bi, 0) + bytes(32) + data[base + k * 32:base + k * 32 + 64])
                lp.write_bytes(b"".join(js)); cp.write_bytes(struct.pack("<I", 0))
            else:
                lp.write_bytes(data)
                cp.write_bytes(b"".join(struct.pack("<I", c) for _, c, _ in part))
            o = run([tool, fi, lp, cp, fo])
            roots = {int(k): r for k, _s, r in re.findall(r"^root (\d+) (\d+) ([0-9a-f]{64})$", o, re.M)}
            fronts = {int(k): v.split(",") for k, v in re.findall(r"^front (\d+) (\S+)$", o, re.M)}
            if sorted(roots) != list(range(len(part))) or sorted(fronts) != list(range(len(part))):
                raise SystemExit(f"{pool}: {len(roots)} roots for {len(part)} blocks")
            for bi, (h, c, _) in enumerate(part):
                if h in undo_heights:
                    before[(pool, h)] = dict(cur)
                cur = {"frontier": fronts[bi], "size": cur["size"] + c, "root": roots[bi], "origin": origin}
                anchors.append((T.TREE_POOLS.index(pool), bytes.fromhex(roots[bi]), h))
                if pool == "sapling" and args.genesis and T.SAPLING <= h < T.HEARTWOOD:
                    hdr = headers.header(h)[68:100].hex()
                    if hdr != roots[bi]:
                        raise SystemExit(f"sapling root after {h} != header hashFinalSaplingRoot: {roots[bi]} {hdr}")
            log(f"  {pool}: through height {part[-1][0]}, size {cur['size']}, root {cur['root'][:16]}")
            i = j
    if not args.genesis:
        cur["history_from"] = args.seed_height  # no root before the seed unless --history adds them
    state[pool] = cur

# pre-Heartwood Sapling blocks without new leaves keep the previous root: check their headers too
if args.genesis and "sapling" in state:
    roots_by_h = sorted((h, r.hex()) for p, r, h in anchors if p == 1)
    k, cur_root, bad, checked = 0, None, 0, 0
    for h in range(T.SAPLING, min(T.HEARTWOOD, tip + 1)):
        while k < len(roots_by_h) and roots_by_h[k][0] <= h:
            cur_root = roots_by_h[k][1]; k += 1
        if cur_root is None:
            continue
        checked += 1
        if headers.header(h)[68:100].hex() != cur_root:
            bad += 1
    log(f"sapling: header hashFinalSaplingRoot == Bend root after the block for {checked - bad}/{checked} blocks "
        f"{T.SAPLING}..{min(T.HEARTWOOD - 1, tip)}")
    if bad:
        raise SystemExit("header check failed")
for x in args.history:
    pool, path = x.split("=", 1)
    n = 0
    for l in Path(path).read_text().split("\n"):
        if l:
            h, r = l.split()
            if args.seed_height is None or int(h) <= args.seed_height:
                anchors.append((T.TREE_POOLS.index(pool), bytes.fromhex(r), int(h))); n += 1
    log(f"{pool}: {n} historical per-block roots imported from {path}")
    hs = [int(l.split()[0]) for l in Path(path).read_text().split("\n") if l]
    if pool in state and hs:
        state[pool]["history_from"] = min(hs)
log("final: " + "; ".join(f"{p} size {c['size']} root {c['root'][:16]}" for p, c in state.items()))
if args.dry_run:
    sys.exit(0)
db = st.db
db.execute("BEGIN IMMEDIATE")
db.executemany("INSERT OR IGNORE INTO anchor VALUES(?,?,?)", anchors)
for h in sorted({h for _, h in before}):
    r = db.execute("SELECT data FROM undo WHERE height=?", (h,)).fetchone()
    u = pickle.loads(r[0])
    u["trees"] = {p: before[(p, hh)] for p, hh in before if hh == h}
    u.setdefault("anchor", [])
    for p, hh in before:
        if hh == h:
            root = [a for a in anchors if a[0] == T.TREE_POOLS.index(p) and a[2] == h][0][1]
            u["anchor"].append((T.TREE_POOLS.index(p), root))
    db.execute("UPDATE undo SET data=? WHERE height=?", (pickle.dumps(u), h))
old = st.get("trees") or {}
old.update(state)
st.put("trees", old)
st.put("trees_init", {"tip": tip, "pools": pools, "origin": origin, "time": time.strftime("%Y-%m-%d %H:%M:%S")})
db.execute("COMMIT")
log(f"committed: {len(anchors)} anchor rows, tree state in {len(set(h for _, h in before))} undo rows, meta trees")
