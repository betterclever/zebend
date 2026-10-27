#!/usr/bin/env python3
"""Rollback + re-apply on a clone (new store.py / sync.py): digest at tip T (tools/digest_full.py),
rollback to R (aligned to a window start by history.window_start_below unless --raw), replay
R+1..T with sync.py --to T from SPOOL (kept), digest again: must be identical, incl. the anchor
table, undo data, meta trees and the ZIP 221 history state.
usage: rollback_test.py STATE SPOOL R [--raw] [--steps TO:WINDOW,...]  (replay windows as the original run cut them,
so the undo records carry the history state at the same heights)"""
import json, os, sqlite3, subprocess, sys
from pathlib import Path
R0 = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(R0 / "fullnode"))
import store as S, history as HI
st_dir, spool, R = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve(), int(sys.argv[3])
dig = lambda: subprocess.run([sys.executable, str(R0 / "tools/digest_full.py"), str(st_dir)], capture_output=True,
                             text=True, check=True).stdout
d0 = dig()
T = json.loads(sqlite3.connect(f"file:{st_dir}/chain.sqlite?mode=ro", uri=True)
               .execute("SELECT v FROM meta WHERE k='tip'").fetchone()[0])["height"]
st = S.Store(st_dir)
R2 = R if "--raw" in sys.argv else HI.window_start_below(st, R)
st.rollback_to(R2)
h = st.get("history"); tr = st.get("trees")
print(f"tip {T}; asked rollback to {R}, aligned to {R2}; after rollback: tip {st.tip()['height']}, history "
      f"{'state at ' + str(h['height']) if h else None}, tree sizes {({p: c['size'] for p, c in tr.items()})}", flush=True)
st.close()
env = dict(os.environ, ZEBEND_STATE=str(st_dir), ZEBEND_SPOOL=str(spool), BEND_NO_TELEMETRY="1")
lf = R0 / f"logs/{st_dir.name}_replay_{R2}.log"
steps = [(T, 2000)]
if "--steps" in sys.argv:
    steps = [tuple(map(int, x.split(":"))) for x in sys.argv[sys.argv.index("--steps") + 1].split(",")]
with open(lf, "w") as f:
    for to, w in steps:
        subprocess.run([sys.executable, "-u", str(R0 / "fullnode/sync.py"), "--to", str(to), "--window", str(w), "--keep-spool"],
                       env=env, stdout=f, stderr=subprocess.STDOUT, cwd=str(R0 / "fullnode"))
print("\n".join(l for l in lf.read_text().splitlines()
                if "anchors" in l or "history" in l or "FAIL" in l or "stopped" in l), flush=True)
d1 = dig()
a, b = dict(l.split(" ", 1) for l in d0.splitlines()), dict(l.split(" ", 1) for l in d1.splitlines())
for k in a:
    print(f"  {k:24s} {'equal' if a[k] == b.get(k) else 'DIFFERENT'}  {a[k][:70]}")
print("RESULT", "PASS: identical state digest" if a == b else "FAIL")
