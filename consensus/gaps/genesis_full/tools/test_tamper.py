#!/usr/bin/env python3
"""Anchor and ZIP 221 negative tests on the genesis-initialized clone (read-only on STATE; the
Trees/History objects only write their own work dir). Every hash is Bend; this script only
picks inputs and checks verdicts.

  A. anchor index from genesis: for N random real roots per pool (all eras), the root after
     block h is a valid anchor in h+1, and NOT in h, nor in h-5; a random value is not.
  B. check_anchors (the sync.py path) on a synthetic block after the tip: an anchor equal to an
     old real root PASSES (any earlier root is valid, no history_from), a random one FAILS,
     per pool (Sapling, Orchard, Ironwood).
  C. Sprout, the real JoinSplit window 3,522,890..3,522,892 (blockdelta on real blocks): the
     tree before it is rebuilt in Bend from the leaf-log prefix (bin/sprout), sprout_js verdicts
     PASS; each JoinSplit anchor replaced by (1) a random value, (2) the root after its own
     block, FAILS.
  D. ZIP 221: history from the seed at 3,521,999 over 3,522,000..3,522,019 with the roots from
     the genesis anchor index: MATCH; with one Sapling / Orchard / Ironwood root altered: MISMATCH.
usage: test_tamper.py STATE SPOOL SEED"""
import random, struct, sys, time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

R = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(R / "fullnode"))
import store as S, trees as T, history as HI, sync

state, spool, seed = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
st = S.Store(state, readonly=True)
work = R / "work_tamper"
tr = T.Trees(st, work / "trees", lambda *a: None)
rng = random.Random(7)
rnd = lambda: "%064x" % rng.getrandbits(256)
tip = st.tip()["height"]
res = []


def check(name, ok):
    res.append((name, ok))
    print(("ok   " if ok else "BAD  ") + name, flush=True)


# A
for pool in T.TREE_POOLS:
    pid = T.TREE_POOLS.index(pool)
    n = st.db.execute("SELECT count(*) FROM anchor WHERE pool=?", (pid,)).fetchone()[0]
    rows = [st.db.execute("SELECT root, height FROM anchor WHERE pool=? ORDER BY height LIMIT 1 OFFSET ?",
                          (pid, rng.randrange(n))).fetchone() for _ in range(25)]
    good = sum(tr._known(pool, r.hex(), h + 1, {}) for r, h in rows)
    same = sum(not tr._known(pool, r.hex(), h, {}) for r, h in rows)
    early = sum(not tr._known(pool, r.hex(), h - 5, {}) for r, h in rows)
    rand = sum(not tr._known(pool, rnd(), h + 1, {}) for r, h in rows)
    check(f"A {pool}: {n} roots; 25 random real roots (heights {min(h for _, h in rows)}..{max(h for _, h in rows)}): "
          f"valid in h+1 {good}/25, rejected in h {same}/25, in h-5 {early}/25, random rejected {rand}/25",
          good == same == early == rand == 25)

# B
prev = {p: c["root"] for p, c in tr.cur.items()}
for pool in ("sapling", "orchard", "ironwood"):
    pid = T.TREE_POOLS.index(pool)
    old, oh = st.db.execute("SELECT root, height FROM anchor WHERE pool=? ORDER BY height LIMIT 1 OFFSET 10", (pid,)).fetchone()
    for name, a, want in (("old real root (h %d)" % oh, old.hex(), "pass"), ("random", rnd(), "fail")):
        blk = {"height": tip + 1, "txs": [{"txid": "t", "js": [], "anchors": {p: ([a] if p == pool else [])
                                                                              for p in T.TREE_POOLS}}]}
        tr.sprout_verdicts = []
        try:
            out = tr.check_anchors([blk], {}, prev)
            got = "pass" if out[pool] == (1, 0, "") else f"? {out[pool]}"
        except T.AnchorFail as e:
            got = "fail"
        check(f"B {pool} anchor = {name}: {got.upper()}", got == want)

# C
want = range(3522890, 3522893)
recs = []
for p in sorted(spool.glob("*.blk")):
    d = p.read_bytes(); i = 0
    while i < len(d):
        h, n = struct.unpack_from("<II", d, i)
        if h in want:
            recs.append((h, d[i + 8:i + 8 + n]))
        i += 8 + n
recs.sort()
blocks = sync.run_blockdelta(recs, 3, "tamper", ThreadPoolExecutor(3))
r0, h0 = st.db.execute("SELECT root, height FROM anchor WHERE pool=0 AND height<3522890 ORDER BY height DESC LIMIT 1").fetchone()
fr = tr._sprout_frontier_at(r0.hex(), h0)
size = sum(struct.unpack_from("<II", Path(st.leaf_paths("sprout")[1]).read_bytes(), i)[1]
           for i in range(0, Path(st.leaf_paths("sprout")[1]).stat().st_size, 8)
           if struct.unpack_from("<I", Path(st.leaf_paths("sprout")[1]).read_bytes(), i)[0] <= h0)
check(f"C sprout tree before 3,522,890 rebuilt in Bend from the leaf-log prefix: root {r0.hex()[:16]} (after {h0}, {size} leaves)",
      fr is not None)
njs = sum(len(t["js"]) for b in blocks for t in b["txs"])


def sprout_run(mut=None):
    import copy
    bl = copy.deepcopy(blocks)
    tr.cur = {"sprout": {"frontier": fr, "size": size, "root": r0.hex(), "origin": "test"}}
    tr.recent = {p: {} for p in T.TREE_POOLS}
    tr.recent_front = {}
    if mut:
        mut(bl)
    after = tr.advance(bl, dict(recs), "tamperC")
    try:
        out = tr.check_anchors(bl, after, {"sprout": r0.hex()})
        return "pass", out["sprout"], after
    except T.AnchorFail as e:
        return "fail", str(e)[:120], after


got, out, after = sprout_run()
check(f"C real JoinSplits 3,522,890..892: {njs} JoinSplits, anchors {got.upper()} {out}", got == "pass" and out[0] == njs)
own = after["sprout"]
k = 0
for bi, b in enumerate(blocks):
    for ti, t in enumerate(b["txs"]):
        for ji, j in enumerate(t["js"]):
            for name, val in (("random", rnd()), ("root after its own block", own[b["height"]])):
                def mut(bl, bi=bi, ti=ti, ji=ji, val=val):
                    bl[bi]["txs"][ti]["js"][ji]["anchor"] = val
                g, o, _ = sprout_run(mut)
                k += g == "fail"
                check(f"C block {b['height']} tx {t['i']} js {ji} anchor := {name}: {g.upper()} ({o})", g == "fail")

# D
hs = list(range(3522000, 3522020))
raw = {}
for p in sorted(spool.glob("*.blk")):
    d = p.read_bytes(); i = 0
    while i < len(d):
        h, n = struct.unpack_from("<II", d, i)
        if h in hs:
            raw[h] = d[i + 8:i + 8 + n]
        i += 8 + n
roots = {p: {h: r.hex() for r, h in st.db.execute("SELECT root, height FROM anchor WHERE pool=? AND height BETWEEN ? AND ?",
                                                    (T.TREE_POOLS.index(p), hs[0], hs[-1]))} for p in HI.SIDE_POOLS}
adds = {}
for pool in HI.SIDE_POOLS:
    idx = Path(st.leaf_paths(pool)[1]).read_bytes()
    for i in range(0, len(idx), 8):
        h, c = struct.unpack_from("<II", idx, i)
        if c and h in raw:
            adds.setdefault(h, set()).add(pool)


def hist_run(mut=None):
    hi = HI.History(st, work / "hist", lambda *a: None)
    hi.cur = {"state": seed.read_bytes().hex(), "height": 3521999, "origin": "seed"}
    blocks = [{"height": h, "leaves": {p: ([1] if p in adds.get(h, ()) else []) for p in HI.SIDE_POOLS}} for h in hs]
    after = {p: dict(roots[p]) for p in HI.SIDE_POOLS}
    if mut:
        mut(after)
    try:
        r = hi.run(blocks, raw, after, "tamperD")
        return f"{r['checked']} MATCH"
    except HI.HistoryFail as e:
        return "FAIL " + str(e)[:110]


g = hist_run()
check(f"D ZIP 221 3,522,000..3,522,019 from the seed with genesis-built roots: {g}", g == "20 MATCH")
for pool in HI.SIDE_POOLS:
    h = sorted(roots[pool])[len(roots[pool]) // 2]
    g = hist_run(lambda a, pool=pool, h=h: a[pool].__setitem__(h, rnd()))
    check(f"D {pool} root after {h} altered: {g}", g.startswith("FAIL") and "MISMATCH" in g)
print(f"RESULT {sum(ok for _, ok in res)}/{len(res)} as expected")
