#!/usr/bin/env python3
"""fullnode/work/bench/digest.py (utxo, nf, tx, addr, blk, anchor, undo, tip, pools, leaf lengths,
leaf files) plus the tree and ZIP 221 meta (trees, history). Read-only.
usage: digest_full.py STATE"""
import hashlib, json, sqlite3, subprocess, sys
from pathlib import Path

d = Path(sys.argv[1])
B = Path(__file__).resolve().parents[4] / "fullnode/work/bench/digest.py"
print(subprocess.run([sys.executable, str(B), str(d)], capture_output=True, text=True, check=True).stdout, end="")
db = sqlite3.connect(f"file:{d / 'chain.sqlite'}?mode=ro", uri=True)
for k in ("trees", "history"):
    r = db.execute("SELECT v FROM meta WHERE k=?", (k,)).fetchone()
    v = json.loads(r[0]) if r else None
    print(k, hashlib.sha256(json.dumps(v, sort_keys=True).encode()).hexdigest()[:16],
          {p: (c["size"], c["root"][:16]) for p, c in v.items()} if k == "trees" and v else (v and v.get("height")))
