#!/usr/bin/env python3
"""Reorg/undo test on a COPY of a state: digest at tip T, roll back N blocks with the undo data,
re-apply the same blocks with sync.py (from the kept spool), digest again: must be identical.

usage: ZEBEND_STATE=/copy ZEBEND_SPOOL=spool test_reorg.py N
"""
import hashlib, os, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import store

d = Path(os.environ["ZEBEND_STATE"])
assert d.resolve() != (HERE / "state").resolve(), "run on a copy, not the live state"


def digest(st):
    h = hashlib.sha256()
    for t in ("utxo", "nf", "tx", "addr", "blk"):
        for r in st.db.execute(f"SELECT * FROM {t} ORDER BY 1, 2"):
            h.update(repr(r).encode())
    for p in store.POOLS:
        a, b = st.leaf_paths(p)
        h.update(a.read_bytes())
        h.update(b.read_bytes())
    h.update(repr(st.get("pools")).encode())
    return h.hexdigest()


n = int(sys.argv[1])
st = store.Store(d)
t = st.tip()["height"]
d0 = digest(st)
print(f"tip {t}: digest {d0[:16]}  utxos {st.db.execute('SELECT COUNT(*) FROM utxo').fetchone()[0]}")
st.rollback_to(t - n)
d1 = digest(st)
print(f"rolled back to {st.tip()['height']}: digest {d1[:16]}  pools {st.get('pools')}")
st.close()
r = subprocess.run([sys.executable, str(HERE / "sync.py"), "--keep-spool", "--to", str(t)], capture_output=True, text=True)
print(r.stdout.strip().splitlines()[-1] if r.stdout.strip() else r.stderr[-500:])
st = store.Store(d)
d2 = digest(st)
print(f"re-applied to {st.tip()['height']}: digest {d2[:16]}")
print("REORG TEST", "PASS (state identical after rollback + re-apply)" if d2 == d0 and d1 != d0 else "FAIL")
