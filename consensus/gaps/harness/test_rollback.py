#!/usr/bin/env python3
"""Rollback test for the tree and history state (staged store.py / sync.py), on a copy of the
Test A state: digest (meta trees, history, tip; anchor table; leaf logs; utxo/nf/blk/tx) at
tip T; rollback_to(R); replay R+1..T with sync.py from the same spool; digest again.
usage: test_rollback.py SRC_STATE WORK_STATE R [--expect-history-drop]"""
import hashlib, json, shutil, sqlite3, subprocess, sys, os
from pathlib import Path
G = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(G / "fullnode"))
import store as S
src, dst, R = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve(), int(sys.argv[3])
drop = "--expect-history-drop" in sys.argv
if dst.exists(): shutil.rmtree(dst)
dst.mkdir(parents=True)
b = sqlite3.connect(str(dst / "chain.sqlite")); sqlite3.connect(str(src / "chain.sqlite")).backup(b); b.close()
shutil.copytree(src / "leaves", dst / "leaves"); shutil.copy(src / "ironwood_roots.txt", dst)

def digest(p):
    st = S.Store(p)
    h = hashlib.sha256()
    out = {}
    for t in ("utxo", "nf", "blk", "tx", "anchor"):
        x = hashlib.sha256()
        for r in st.db.execute(f"SELECT * FROM {t} ORDER BY 1, 2"):
            x.update(repr(r).encode())
        out[t] = x.hexdigest()[:16]
    for k in ("tip", "trees", "history", "leaf_lengths"):
        out[k] = hashlib.sha256(json.dumps(st.get(k), sort_keys=True).encode()).hexdigest()[:16]
    st.close()
    return out

d0 = digest(dst)
T = json.loads(sqlite3.connect(str(dst / "chain.sqlite")).execute("SELECT v FROM meta WHERE k='tip'").fetchone()[0])["height"]
st = S.Store(dst); st.rollback_to(R); hist_after_rb = st.get("history"); st.close()
print(f"rolled back {T} -> {R}; history after rollback: {'state at ' + str(hist_after_rb['height']) if hist_after_rb else None}", flush=True)
env = dict(os.environ, ZEBEND_STATE=str(dst), ZEBEND_SPOOL=str(G / "data/spoolB"), BEND_NO_TELEMETRY="1")
lf = dst.parent / (dst.name + "_replay.log")
with open(lf, "w") as f:  # a file, not a pipe: sync's multiprocessing helpers keep inherited pipes open
    subprocess.run([sys.executable, "-u", str(G / "fullnode/sync.py"), "--to", str(T), "--keep-spool", "--jobs", "8", "--window", "400"],
                   env=env, stdout=f, stderr=subprocess.STDOUT, cwd=str(G / "fullnode"))
print("\n".join(l for l in lf.read_text().splitlines() if "anchors" in l or "history" in l or "FAIL" in l)[-1500:], flush=True)
d1 = digest(dst)
for k in d0:
    print(f"  {k:12s} {'equal' if d0[k] == d1[k] else 'DIFFERENT'}")
same = all(d0[k] == d1[k] for k in d0 if not (drop and k == "history"))
print("RESULT", "PASS" if same and (hist_after_rb is None) == drop else "FAIL")
