"""Build bench inputs (read-only on the live tree): blockdelta window files and bin/rules
window + ctx files for a height range, cut into parts exactly like the live sync does.

usage: mkparts.py STATE SPOOL FIRST LAST OUTDIR [--jobs 16]
  STATE: a bench state whose tip is FIRST-1 (opened read-only).
Writes OUTDIR/bd_<k>.bin (blockdelta parts), OUTDIR/rw_<k>.bin + rc_<k>.bin (rules parts, the
pools of each part's start taken from a sequential bin/rules run), OUTDIR/meta.json.
"""
import json, os, struct, subprocess, sys, time
from pathlib import Path

NODE = Path("/Users/betterclever/projects/zecathon/bend-zcash/fullnode")
sys.path.insert(0, str(NODE))
import headers, store as S, sync, rules  # live modules, imported read-only (PYTHONDONTWRITEBYTECODE=1)

state, spool, first, last, out = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), Path(sys.argv[5])
jobs = int(sys.argv[sys.argv.index("--jobs") + 1]) if "--jobs" in sys.argv else 16
out.mkdir(parents=True, exist_ok=True)
sync.SPOOL = Path(spool)
recs, _ = sync.spool_records(first - 1, 100000, 1 << 40)
recs = [r for r in recs if r[0] <= last]
assert recs and recs[0][0] == first and recs[-1][0] == last, (recs[0][0] if recs else None)
print(len(recs), "blocks", sum(len(r) for _, r in recs) / 1e6, "MB")

# blockdelta parts, as sync.run_blockdelta cuts them
parts, cur, size = [], [], 0
target = max(1, sum(len(r) for _, r in recs) // jobs + 1)
for rec in recs:
    cur.append(rec)
    size += len(rec[1])
    if size >= min(target, 8 << 20) or len(cur) >= 400:
        parts.append(cur)
        cur, size = [], 0
if cur:
    parts.append(cur)
blocks = []
for k, part in enumerate(parts):
    p = out / f"bd_{k}.bin"
    sync.window_file(p, part)
    r = subprocess.run([str(NODE / "bin/blockdelta"), str(p)], capture_output=True, text=True)
    (out / f"bd_{k}.out").write_text(r.stdout)
    blocks += sync.parse_delta(r.stdout)
assert [b["height"] for b in blocks] == [h for h, _ in recs]

st = S.Store(Path(state), readonly=True)
want, made = [], set()
for b in blocks:
    for t in b["txs"]:
        for (ptxid, vout, _q) in t["ins"]:
            if (ptxid, vout) not in made:
                want.append(S.op_key(ptxid, vout))
        for (kk, _v, _s) in t["outs"]:
            made.add((t["txid"], kk))
st.prefetch(want)
pools = st.get("pools") or {}
recs_r, deltas = rules.block_records(blocks, st)
raw = dict(recs)
rparts = rules.split_parts(blocks, jobs)
meta = {"first": first, "last": last, "bd_parts": len(parts), "rules_parts": len(rparts), "pools0": pools,
        "mb": sum(len(r) for _, r in recs) / 1e6}
# sequential pools: run each part from the true pools printed by the previous one
p = [pools.get(n, 0) for n in rules.POOL_NAMES]
for k, part in enumerate(rparts):
    bl = [blocks[i] for i in part]
    (out / f"rw_{k}.bin").write_bytes(rules.window_bytes(bl, raw))
    ctx = b"".join(rules._u64(v) for v in p) + b"".join(recs_r[i] for i in part)
    (out / f"rc_{k}.bin").write_bytes(ctx)
    r = subprocess.run([str(NODE / "bin/rules"), str(out / f"rw_{k}.bin"), str(out / f"rc_{k}.bin")],
                       capture_output=True, text=True)
    (out / f"rw_{k}.out").write_text(r.stdout)
    res = rules.parse_rules(r.stdout)
    p = [res[bl[-1]["height"]]["pools"][n] for n in rules.POOL_NAMES]
meta["pools_end"] = dict(zip(rules.POOL_NAMES, p))
(out / "meta.json").write_text(json.dumps(meta, indent=1))
print(json.dumps(meta))
