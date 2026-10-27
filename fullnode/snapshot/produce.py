#!/usr/bin/env python3
"""Producer: export a store's state at its committed tip H as a snapshot file.

  produce.py STATE OUT.zsnap [--height H] [--ironwood-follow] [--keep] [--level N] [--jobs N]

STATE is a store directory (chain.sqlite + leaves/). It is opened READ-ONLY and read inside one
SQLite read transaction, so it may be a live instance (the state stays consistent while its
writer commits; leaf logs are append-only and read up to the lengths that state records) or a
copy. --height makes the export fail unless the tip is exactly H.

--ironwood-follow: for an instance whose leaf logs do not start at genesis (the oracle-assisted
state-tip instance), take the Ironwood frontier at H from zebend follow's committed snapshot at H
(follow/state/snapshots/H/frontier.txt or --follow-snapshots, Bend-computed by follow from NU6.3 activation) and the
root history from follow/state/roots.txt. Without it such pools are exported as unknown.
"""
import argparse, json, shutil, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import snap  # noqa: E402

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("state")
    ap.add_argument("out")
    ap.add_argument("--height", type=int)
    ap.add_argument("--ironwood-follow", action="store_true")
    ap.add_argument("--follow-snapshots", help="a preserved copy of follow/state/snapshots (follow keeps only 10)")
    ap.add_argument("--work")
    ap.add_argument("--keep", action="store_true", help="keep the uncompressed section files")
    ap.add_argument("--level", type=int, default=3, help="zstd level")
    ap.add_argument("--jobs", type=int, default=16)
    a = ap.parse_args()
    t0 = time.time()
    db = snap.open_ro(a.state)
    tip = json.loads(db.execute("SELECT v FROM meta WHERE k='tip'").fetchone()[0])
    db.close()
    work = Path(a.work or HERE / "work" / f"export_{tip['height']}")
    if work.exists():
        shutil.rmtree(work)
    ext = {"ironwood": snap.follow_ironwood(tip["height"], a.follow_snapshots)} if a.ironwood_follow else None
    snap.log(f"export {a.state} at {tip['height']} -> {a.out}")
    man = snap.export(a.state, work, height=a.height, external=ext, jobs=a.jobs)
    raw = sum(s["bytes"] for s in man["sections"])
    snap.log(f"sections: " + ", ".join(f"{s['name']} {s['count']}" for s in man["sections"]))
    snap.log(f"digest {man['digest']}  ({raw / 1e9:.3f} GB uncompressed; export timing {man['timing_export']})")
    tz = snap.pack(work, man, a.out, level=a.level)
    sz = Path(a.out).stat().st_size
    snap.log(f"wrote {a.out}: {sz / 1e9:.3f} GB zstd -{a.level} ({tz:.0f} s), ratio {raw / max(sz, 1):.2f}; "
             f"total {time.time() - t0:.0f} s")
    snap.log(f"provenance: {man['provenance']}")
    for p, s in man["sources"].items():
        snap.log(f"  frontier {p}: {s}")
    (Path(a.out).with_suffix(".manifest.json")).write_text(json.dumps(man, indent=1))
    if not a.keep:
        shutil.rmtree(work)


if __name__ == "__main__":
    main()
