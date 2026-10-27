#!/usr/bin/env python3
"""Negative tests of the anchor rule on the Test A state (staged trees.py; read-only use):
for real anchors found valid, the same check with (1) a random anchor, (2) the root of the
block itself (not earlier), (3) a root from AFTER the block, must fail; (4) a root older than
the imported history is SKIPPED, not passed (simulated with a history_from above it)."""
import random, sys
from pathlib import Path
G = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(G / "fullnode"))
import store as S, trees as T
st = S.Store(G / "harness/stateA", readonly=True)
tr = T.Trees(st, G / "harness/work_tamper", print)
rng = random.Random(1)
res = {}
rows = {p: st.db.execute("SELECT root, height FROM anchor WHERE pool=? AND height>3524000 ORDER BY height LIMIT 300",
                         (T.TREE_POOLS.index(p),)).fetchall() for p in ("sapling", "orchard")}
for pool in ("sapling", "orchard"):
    ok = {"real-earlier": 0, "random": 0, "same-block": 0, "later": 0}
    tot = 0
    for root, h in rows[pool][:100]:
        r = root.hex()
        tot += 1
        ok["real-earlier"] += tr._known(pool, r, h + 1, {})          # the root after h is valid in block h+1
        ok["same-block"] += not tr._known(pool, r, h, {})            # ... but not in block h itself
        ok["random"] += not tr._known(pool, "%064x" % rng.getrandbits(256), h + 1, {})
        ok["later"] += not tr._known(pool, r, h - 5, {})             # nor 5 blocks before it existed
    res[pool] = (tot, ok)
# (4): check_anchors on a synthetic block whose anchor is unknown, with and without history_from
blk = {"height": 3530000, "txs": [{"txid": "x", "anchors": {"sapling": ["%064x" % rng.getrandbits(256)], "orchard": [],
        "sprout": [], "ironwood": []}, "js": []}]}
tr.sprout_verdicts = []
c = tr.cur["sapling"]
try:
    out = tr.check_anchors([blk], {}, {p: tr.cur[p]["root"] for p in tr.cur})
    res["unknown anchor with history_from"] = f"SKIPPED {out['sapling']}"
except T.AnchorFail as e:
    res["unknown anchor with history_from"] = f"FAIL {e}"
c.pop("history_from", None)
try:
    tr.check_anchors([blk], {}, {p: tr.cur[p]["root"] for p in tr.cur})
    res["unknown anchor, full history"] = "PASSED (wrong)"
except T.AnchorFail as e:
    res["unknown anchor, full history"] = f"FAIL (correct): {e}"
for k, v in res.items():
    print(k, v)
