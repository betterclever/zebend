#!/usr/bin/env python3
"""Lab tool: state digest of a (lab) node state, to show two runs end in the same state.

  digest.py <state dir> --since H0 [--full]

delta (default): everything a replay of the blocks above H0 can write — every meta row (the
`secs` timing inside meta "rules" is dropped: it is a wall-clock measurement, not state), the
blk / undo / tx / nf / anchor / utxo rows of heights > H0 (undo blobs hold the spent outputs, tree
and history states and are compared byte for byte), the utxo and nf row counts, and the leaf logs.
--full: also every row of every table (as test_reorg.py; slow on a 10 GB state).
Prints one line per part and a total.
"""
import argparse, hashlib, json, sqlite3, sys
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("state")
    ap.add_argument("--since", type=int, required=True)
    ap.add_argument("--full", action="store_true")
    a = ap.parse_args()
    d = Path(a.state)
    db = sqlite3.connect(f"file:{d / 'chain.sqlite'}?mode=ro", uri=True)
    parts = {}

    def h_rows(name, q, args=()):
        h = hashlib.sha256()
        n = 0
        for r in db.execute(q, args):
            h.update(repr(r).encode())
            n += 1
        parts[name] = (h.hexdigest()[:16], n)

    h = hashlib.sha256()
    for k, v in db.execute("SELECT k, v FROM meta ORDER BY k"):
        if k == "rules":
            v = json.loads(v)
            v.pop("secs", None)
            v = json.dumps(v, sort_keys=True)
        h.update(f"{k}={v}".encode())
    parts["meta"] = (h.hexdigest()[:16], None)
    s = a.since
    h_rows("blk", "SELECT * FROM blk WHERE height > ? ORDER BY height", (s,))
    h_rows("undo", "SELECT * FROM undo WHERE height > ? ORDER BY height", (s,))
    h_rows("tx", "SELECT * FROM tx WHERE height > ? ORDER BY txid", (s,))
    h_rows("nf", "SELECT * FROM nf WHERE height > ? ORDER BY pool, nf", (s,))
    h_rows("anchor", "SELECT * FROM anchor WHERE height > ? ORDER BY pool, root", (s,))
    h_rows("utxo", "SELECT * FROM utxo WHERE height > ? ORDER BY op", (s,))
    parts["counts"] = (str(db.execute("SELECT (SELECT COUNT(*) FROM utxo), (SELECT COUNT(*) FROM nf)").fetchone()), None)
    for p in ("sprout", "sapling", "orchard", "ironwood"):
        lens = json.loads(db.execute("SELECT v FROM meta WHERE k='leaf_lengths'").fetchone()[0])[p]
        hh = hashlib.sha256()
        for f, n in zip((d / f"leaves/{p}.bin", d / f"leaves/{p}.blk"), lens):
            with open(f, "rb") as fh:  # the committed prefix (a crash leaves a longer file, truncated on start)
                hh.update(fh.read(n))
        parts[f"leaves/{p}"] = (hh.hexdigest()[:16], None)
    if a.full:
        for t in ("utxo", "nf", "tx", "addr", "blk", "anchor", "undo"):
            h_rows(f"full {t}", f"SELECT * FROM {t} ORDER BY 1, 2")
    tot = hashlib.sha256(repr(sorted(parts.items())).encode()).hexdigest()
    for k, v in parts.items():
        print(f"  {k:<16} {v[0]}" + (f"  ({v[1]} rows)" if v[1] is not None else ""))
    print(f"DIGEST {tot}")


if __name__ == "__main__":
    main()
