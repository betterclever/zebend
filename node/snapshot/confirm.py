#!/usr/bin/env python3
"""Confirmation: recompute the state digest at H from the GENESIS instance and, on a match, flip
a snapshot-started store's status from "snapshot-assumed" to "confirmed".

  confirm.py --target STATE [--genesis GENESIS_STATE] [--watch] [--poll S] [--pin-only H]

The genesis instance (default node/state, synced from genesis by sync.py) is read READ-ONLY.
The digest needs its state at exactly H. With --watch this polls its committed tip; when the tip
is exactly H it starts ONE read transaction (WAL: the state stays at H for this reader however
far the writer moves on) and exports + digests it with the same code as the producer.

Why the genesis instance's committed tip is exactly H at some moment: for H = the last
checkpoint (3,522,460, the pinned height), sync.py never mixes checkpointed and fully validated
blocks in one window, and before the first fully validated window it drains (commits) and
rebuilds the address index from the UTXO set (tens of seconds or more), so the tip rests at H
for at least that long. For any other H, apply snapshot/patches/sync_snapshot_hold.patch: it
cuts windows at H and waits for this reader (the file snapshot/work/snapshot_reader_<H>).

--pin-only H [--pack OUT.zsnap]: no target; print the genesis digest at H (the value to write into
pinned.json) and, with --pack, write the snapshot file itself from the same read transaction.
Status values: snapshot-assumed -> confirmed, or CONFIRMATION-FAILED (the genesis state at H
differs: the snapshot was wrong; the store must be discarded and resynced).
"""
import argparse, json, shutil, sqlite3, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import snap  # noqa: E402
from snap import SnapError, log  # noqa: E402


def target_snapshot(target):
    db = snap.open_ro(target)
    r = db.execute("SELECT v FROM meta WHERE k='snapshot'").fetchone()
    db.close()
    if not r:
        raise SnapError(f"{target} was not started from a snapshot")
    return json.loads(r[0])


def set_status(target, info):
    db = sqlite3.connect(Path(target) / "chain.sqlite", isolation_level=None)
    db.execute("PRAGMA busy_timeout=600000")   # sync.py's writer may hold a transaction
    db.execute("BEGIN IMMEDIATE")
    cur = json.loads(db.execute("SELECT v FROM meta WHERE k='snapshot'").fetchone()[0])
    cur.update(info)
    db.execute("INSERT OR REPLACE INTO meta VALUES('snapshot', ?)", (json.dumps(cur),))
    db.execute("COMMIT")
    db.close()
    return cur


def rollback_copy(genesis, H, work):
    """The reference instance already passed H: if H is within its undo depth, take a consistent
    copy (SQLite online backup from a read-only connection + leaf-log prefixes) and roll the COPY
    back to H with store.py's own rollback_to (tested by test_reorg.py). Cheap for small stores
    (the oracle-assisted tip instance); for the genesis instance at the checkpoint prefer --watch
    or the sync.py hold patch (a copy of a full state is tens of GB)."""
    cp = Path(work).with_name(Path(work).name + "_copy")
    shutil.rmtree(cp, ignore_errors=True)
    (cp / "leaves").mkdir(parents=True)
    src = snap.open_ro(genesis)
    dst = sqlite3.connect(cp / "chain.sqlite")
    src.backup(dst)   # one step: one read transaction, one committed tip
    meta = dict(dst.execute("SELECT k, v FROM meta").fetchall())
    dst.close()
    src.close()
    tip = json.loads(meta["tip"])["height"]
    if tip - H > snap.S.UNDO_DEPTH:
        shutil.rmtree(cp)
        return None, tip
    for p, (a, b) in json.loads(meta["leaf_lengths"]).items():
        for ext, n in ((".bin", a), (".blk", b)):
            with open(Path(genesis) / "leaves" / f"{p}{ext}", "rb") as f, open(cp / "leaves" / f"{p}{ext}", "wb") as g:
                g.write(f.read(n))
    for extra in ("ironwood_roots.txt",):
        if (Path(genesis) / extra).exists():
            shutil.copy(Path(genesis) / extra, cp / extra)
    st = snap.S.Store(cp)
    st.rollback_to(H)
    st.close()
    return cp, tip


def genesis_digest_at(genesis, H, work, watch, poll, timeout, jobs, external=None):
    """The Bend digest of the reference (genesis) instance's state at exactly H, or None."""
    t0 = time.time()
    hold = HERE / "work" / f"snapshot_reader_{H}"   # read by the sync.py hold patch (never written into the state dir)
    while True:
        db = snap.open_ro(genesis)
        tip = json.loads(db.execute("SELECT v FROM meta WHERE k='tip'").fetchone()[0])
        if tip["height"] == H:
            try:
                def on_txn(h):  # the read transaction now holds the state at H
                    try:
                        hold.write_text(str(time.time()))
                    except OSError:
                        pass
                return snap.export(genesis, work, height=H, db=db, jobs=jobs, on_txn=on_txn,
                                   external=external() if external else None), "read transaction at H"
            except SnapError as e:
                if "not the requested height" not in str(e):
                    raise
                log(f"reference moved past {H} before the read transaction started")
            finally:
                db.close()
                hold.unlink(missing_ok=True)
        db.close()
        if tip["height"] > H:
            cp, t2 = rollback_copy(genesis, H, work)
            if cp is None:
                log(f"reference instance is at {t2}, more than {snap.S.UNDO_DEPTH} blocks past {H}: its state at "
                    f"{H} is gone; use --watch before it gets there (or the sync.py hold patch)")
                return None, None
            log(f"reference at {t2} > {H}: rolled a copy back to {H} with store.rollback_to")
            man = snap.export(cp, work, height=H, jobs=jobs, external=external() if external else None)
            shutil.rmtree(cp)
            return man, f"copy at {t2} rolled back to {H} (undo data)"
        if not watch or time.time() - t0 > timeout:
            log(f"reference instance at {tip['height']}, not yet at {H}")
            return None, None
        time.sleep(poll)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", help="store started from a snapshot (consume.py)")
    ap.add_argument("--genesis", default=str(snap.FULL / "state"))
    ap.add_argument("--pin-only", type=int, help="just print the genesis digest at this height")
    ap.add_argument("--watch", action="store_true")
    ap.add_argument("--poll", type=float, default=1.0)
    ap.add_argument("--timeout", type=float, default=7 * 86400)
    ap.add_argument("--jobs", type=int, default=16)
    ap.add_argument("--ironwood-follow", action="store_true",
                    help="reference is the oracle-assisted tip instance: Ironwood frontier from zebend follow")
    ap.add_argument("--follow-snapshots")
    ap.add_argument("--pack", help="with --pin-only: also write the snapshot file (the producer at the checkpoint)")
    a = ap.parse_args()
    if a.target:
        info = target_snapshot(a.target)
        H, want = info["height"], info["digest"]
        log(f"target {a.target}: snapshot at {H}, status {info['status']}, digest {want}")
        if info["status"] == "confirmed":
            log("already confirmed")
            return
    elif a.pin_only is not None:
        H, want = a.pin_only, None
    else:
        ap.error("--target or --pin-only")
    work = HERE / "work" / f"confirm_{H}"
    if work.exists():
        shutil.rmtree(work)
    try:
        ext = (lambda: {"ironwood": snap.follow_ironwood(H, a.follow_snapshots)}) if a.ironwood_follow else None
        man, how = genesis_digest_at(a.genesis, H, work, a.watch, a.poll, a.timeout, a.jobs, ext)
    finally:
        pass
    if man is None:
        sys.exit(1)
    if a.pack:
        tz = snap.pack(work, man, a.pack)
        Path(a.pack).with_suffix(".manifest.json").write_text(json.dumps(man, indent=1))
        log(f"wrote {a.pack}: {Path(a.pack).stat().st_size / 1e9:.3f} GB ({tz:.0f} s)")
    shutil.rmtree(work, ignore_errors=True)
    got = man["digest"]
    log(f"reference instance at {H} ({man['hash']}, {how}): Bend digest {got}  (export {man['timing_export']})")
    log(f"  provenance of that state: {man['provenance']}")
    if want is None:
        print(json.dumps({"height": H, "hash": man["hash"], "digest": got}))
        return
    if man["provenance"].startswith("genesis-verified") is False:
        log("WARNING: the --genesis store is not genesis-verified; this is a test confirmation only")
    if got == want and man["hash"] == info["hash"]:
        cur = set_status(a.target, {"status": "confirmed", "confirmed_at": int(time.time()),
                                    "confirmed_by": f"{a.genesis}: {man['provenance']} ({how})"})
        log(f"CONFIRMED: status {cur['status']}")
    else:
        cur = set_status(a.target, {"status": "CONFIRMATION-FAILED", "genesis_digest": got})
        log(f"CONFIRMATION FAILED: genesis digest {got} != snapshot digest {want}")
        sys.exit(3)


if __name__ == "__main__":
    main()
