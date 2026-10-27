#!/usr/bin/env python3
"""Give an existing node state its ZIP 221 history state (run with the node stopped, after
trees_init.py). Starts from a validated seed state (zcash/consensus/gaps/history/data/seed_3521999.st:
the NU6.3-epoch tree over 3,428,143..3,521,999, whose correctness block 3,522,000's header
commitment proves) and, if the instance's tip is above the seed, rolls it forward in Bend
(bin/history) over the real blocks seed+1..tip taken from SPOOL (*.blk spool chunks; fetch with
zcash/consensus/gaps/data/fetch_range.py), with the per-block Sapling/Orchard/Ironwood roots from the
instance's anchor index (written by trees_init.py / sync.py). Every block must MATCH.
usage: history_init.py STATE --seed FILE --seed-height H [--spool DIR] [--origin TEXT] [--dry-run]"""
import argparse, struct, sys, time
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import store as S, history as HI, trees as T

ap = argparse.ArgumentParser()
ap.add_argument("state"); ap.add_argument("--seed", required=True); ap.add_argument("--seed-height", type=int, required=True)
ap.add_argument("--spool"); ap.add_argument("--origin", default=""); ap.add_argument("--dry-run", action="store_true")
ap.add_argument("--window", type=int, default=400)
a = ap.parse_args()
st = S.Store(Path(a.state))
tip = st.tip()["height"]
log = lambda *x: print(time.strftime("%H:%M:%S"), *x, flush=True)
origin = a.origin or f"seeded at {a.seed_height} from {a.seed} (NU6.3 epoch tree; validated by header {a.seed_height + 1})"
st.pending = []
hist = HI.History(st, Path(a.state) / "history_init", log)
hist.cur = {"state": Path(a.seed).read_bytes().hex(), "height": a.seed_height, "origin": origin}
if tip > a.seed_height:
    raw = {}
    for p in sorted(Path(a.spool).glob("*.blk")):
        d = p.read_bytes(); i = 0
        while i < len(d):
            h, n = struct.unpack_from("<II", d, i)
            if a.seed_height < h <= tip:
                raw[h] = d[i + 8:i + 8 + n]
            i += 8 + n
    miss = [h for h in range(a.seed_height + 1, tip + 1) if h not in raw]
    if miss:
        raise SystemExit(f"spool lacks {len(miss)} blocks, first {miss[:3]}")
    roots = {}
    for pool in HI.SIDE_POOLS:
        roots[pool] = {h: r.hex() for r, h in st.db.execute("SELECT root, height FROM anchor WHERE pool=?",
                                                              (T.TREE_POOLS.index(pool),))}
    # per-block leaves (from the leaf logs' per-block counts): which pools a block appends to
    adds = {}
    for pool in HI.SIDE_POOLS:
        idx = Path(st.leaf_paths(pool)[1]).read_bytes()
        for i in range(0, len(idx), 8):
            h, c = struct.unpack_from("<II", idx, i)
            if c:
                adds.setdefault(h, set()).add(pool)
    n = 0
    for w0 in range(a.seed_height + 1, tip + 1, a.window):
        hs = list(range(w0, min(tip, w0 + a.window - 1) + 1))
        blocks = [{"height": h, "leaves": {p: ([1] if p in adds.get(h, ()) else []) for p in HI.SIDE_POOLS}} for h in hs]
        after = {p: {h: roots[p][h] for h in hs if h in roots[p]} for p in HI.SIDE_POOLS}
        r = hist.run(blocks, raw, after, f"init{w0}")
        if r["skipped"]:
            raise SystemExit(f"history skipped blocks in {hs[0]}..{hs[-1]}: {r}")
        n += r["checked"]
    log(f"history rolled forward {a.seed_height + 1}..{tip}: {n}/{tip - a.seed_height} MATCH")
if not a.dry_run:
    st.db.execute("BEGIN IMMEDIATE"); st.put("history", hist.cur); st.db.execute("COMMIT")
    log(f"meta history set at {hist.cur['height']} ({origin})")
