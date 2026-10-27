#!/usr/bin/env python3
"""Consumer: verify a snapshot and import it into a FRESH store directory.

  consume.py SNAP.zsnap STATE [--pinned pinned.json | --pin DIGEST | --unpinned] [--jobs N]

1. unpack (zstd) the sections into a work directory;
2. Bend recomputes every section's Merkle root, checks every record is in strict order and
   recomputes the state digest; it must equal the PINNED digest for (height, block hash)
   (pinned.json, the analogue of Bitcoin Core's assumeutxo parameters). The manifest inside the
   file is never trusted;
3. chain checks (see README "What the consumer checks"): block-index rows == the Bend-verified
   header chain (hashes.bin) and its checkpoints; every note commitment tree root is recomputed in
   Bend from the frontier; Sapling roots == the headers' hashFinalSaplingRoot where the header
   carries it (419,200 <= h < 903,000); pools not yet active must be empty;
4. import into STATE.importing/ (the big tables in a separate process WHILE Bend verifies, the
   rest after), then one rename to STATE (an interrupted import leaves no STATE; rerunning
   starts over; a rejected snapshot's partial import is deleted). meta 'snapshot' records status "snapshot-assumed" (or
   "snapshot-unpinned" with --unpinned, test use only) until confirm.py flips it to "confirmed".
Then run sync.py on STATE (ZEBEND_STATE=STATE): full validation from H+1.
"""
import argparse, json, os, shutil, sqlite3, struct, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import snap  # noqa: E402
from snap import SnapError, POOLS, log  # noqa: E402
import store as S  # noqa: E402  (node/store.py, via snap's sys.path)
import headers  # noqa: E402

PINNED = HERE / "pinned.json"
CHECKPOINTS = snap.FULL / "checkpoints/main-checkpoints.txt"


def pinned_digest(path, height, hash_hex):
    for e in json.loads(Path(path).read_text()).get("main", []):
        if e["height"] == height and e["hash"] == hash_hex:
            return e.get("digest")
    return None


def verify(d, man, jobs, work, pin=None, unpinned=False, log=log):
    """All consumer checks on unpacked sections. Returns (digest, checks dict). Raises SnapError."""
    checks = {}
    H, hh = man["height"], man["hash"]
    t = time.time()
    claimed = man.get("digest")
    digest = snap.digest_dir(d, man, jobs, work)
    checks["digest"] = {"bend": digest, "secs": round(time.time() - t, 1)}
    if pin is None and not unpinned:
        raise SnapError(f"no pinned digest for height {H} hash {hh}: refusing (pinned.json)")
    if pin is not None:
        if pin != digest:
            raise SnapError(f"Bend digest {digest} != PINNED {pin}: snapshot rejected")
        checks["pinned"] = "MATCH"
    else:
        checks["pinned"] = "NONE (--unpinned: test use only)"
    if claimed != digest:   # (only informative once the pin matched)
        raise SnapError(f"digest MISMATCH: Bend computes {digest}, the file claims {claimed}")
    secs = snap.sec_by_name(man)
    # --- meta
    meta = {}
    for r in snap.records(d, secs["meta"]):
        k, _, v = r.partition(b"\x00")
        meta[k.decode()] = json.loads(v)
    if meta.get("tip") != {"height": H, "hash": hh}:
        raise SnapError(f"meta tip {meta.get('tip')} != manifest ({H}, {hh})")
    # --- block index vs the Bend-verified header chain
    idx = headers.Index(snap.FULL / "state/hdr/hashes.bin")
    rows = []
    for r in snap.records(d, secs["blk"]):
        h, = struct.unpack_from(">I", r, 0)
        rows.append((h, r[4:36].hex(), r[36:68].hex()))
    want = list(range(max(0, H - snap.BLK_CONTEXT + 1), H + 1))
    if [r[0] for r in rows] != want:
        raise SnapError(f"blk rows are not heights {want[0]}..{H}")
    for h, hx, prev in rows:
        if h >= idx.n or idx.display(h) != hx:
            raise SnapError(f"block {h}: hash {hx} is not the verified header chain's")
        if h > 0 and idx.display(h - 1) != prev:
            raise SnapError(f"block {h}: prev {prev} does not link")
    cps = {int(a): b for a, b in (l.split() for l in CHECKPOINTS.read_text().splitlines() if l.strip())}
    if H in cps and cps[H] != hh:
        raise SnapError(f"height {H} is a checkpoint and {hh} is not its hash")
    checks["blocks"] = (f"{len(rows)} block-index rows {rows[0][0]}..{H}: hashes and links == the Bend-verified "
                        f"header chain" + (", H is a Zebra checkpoint: MATCH" if H in cps else ""))
    # --- frontiers and root histories
    fronts = dict(snap.dec_frontier(r) for r in snap.records(d, secs["frontier"]))
    if sorted(fronts) != sorted(POOLS):
        raise SnapError("frontier section must hold one record per pool")
    roots = {p: [(struct.unpack_from(">I", r, 0)[0], r[4:36].hex()) for r in snap.records(d, secs[f"roots.{p}"])]
             for p in POOLS}
    tree = {}
    for p in POOLS:
        fr, rs = fronts[p], roots[p]
        if any(h > H for h, _ in rs):
            raise SnapError(f"{p}: root history above H")
        if H < snap.ACTIVATION[p]:
            if fr is None or fr["size"] or rs:
                raise SnapError(f"{p} is not active at {H}: its frontier must be empty")
        if fr is None:
            tree[p] = "frontier NOT in this snapshot (unknown); anchors of this pool cannot be checked from it"
            continue
        if not snap.frontier_ok(fr["levels"], fr["size"]):
            raise SnapError(f"{p}: frontier levels do not match the tree size {fr['size']}")
        got, _, empty = snap.run_tree(p, fr["levels"], b"", [0], work)
        if got[0] != fr["root"]:
            raise SnapError(f"{p}: Bend computes root {got[0]} from the frontier, the snapshot says {fr['root']}")
        if fr["size"] and (not rs or rs[-1][1] != fr["root"]):
            raise SnapError(f"{p}: the frontier root is not the last root of the root history")
        if not fr["size"] and fr["root"] != empty:
            raise SnapError(f"{p}: empty tree with a non-empty root")
        tree[p] = f"size {fr['size']}, root {fr['root'][:16]}.. recomputed in Bend from the frontier: MATCH"
    # Sapling: before Heartwood the header itself commits to the tree root after the block.
    sap = roots["sapling"]
    lo, hi = snap.ACTIVATION["sapling"], min(H, snap.HEARTWOOD - 1)
    if lo <= hi and fronts["sapling"] is not None:
        empty = snap.run_tree("sapling", [None] * 32, b"", [0], work)[2]
        cur, j, n = empty, 0, 0
        for h in range(lo, hi + 1):
            while j < len(sap) and sap[j][0] <= h:
                cur = sap[j][1]
                j += 1
            field = headers.header(h)[68:100]
            if field.hex() != cur:
                raise SnapError(f"Sapling root at {h} {cur} != the verified header's hashFinalSaplingRoot {field.hex()}")
            n += 1
        tree["sapling"] += (f"; hashFinalSaplingRoot of all {n} verified headers {lo}..{hi} == the snapshot's "
                            f"Sapling root history" + (" (incl. H: the frontier at H is chain-committed)" if H < snap.HEARTWOOD else
                                                       "; roots from 903,000 to H-1: covered only by the pinned digest (the root at H: history_zip221)"))
    elif H < lo:
        field = headers.header(H)[68:100] if H >= 1 else bytes(32)
        if field != bytes(32):
            raise SnapError(f"pre-Sapling header {H}: reserved field not zero")
        tree["sapling"] += "; not active at H (header field hashReserved == 0)"
    for p in ("orchard", "ironwood"):
        if fronts[p] is not None and H >= snap.ACTIVATION[p]:
            tree[p] += ("; chain commitment of the root at H: ZIP 221 check (history_zip221) if run with "
                        "--history-blocks, otherwise NOT checked")
    if fronts["sprout"] is not None:
        tree["sprout"] += "; no header commits to Sprout roots: covered only by the pinned digest"
    checks["trees"] = tree
    checks["meta"] = meta
    return digest, checks, fronts, roots


def bulk_import(d, man, tmp):
    """The big tables (utxo, nf, blk, oracle_prevout) into tmp (= STATE.importing), in a separate
    process WHILE Bend verifies the same section files. Nothing in tmp is used unless the
    verification passes; tmp only becomes STATE by the final rename."""
    d, tmp = Path(d), Path(tmp)
    import threading
    parent = os.getppid()

    def orphan_watch():   # the consumer was killed: stop (its rerun deletes tmp and starts over)
        while True:
            if os.getppid() != parent:
                os._exit(1)
            time.sleep(0.2)

    threading.Thread(target=orphan_watch, daemon=True).start()
    secs = snap.sec_by_name(man)
    st = S.Store(tmp)
    db = st.db
    db.execute("PRAGMA synchronous=OFF")      # the import is redone from scratch if interrupted
    db.execute("BEGIN IMMEDIATE")
    up = struct.unpack_from

    def utxo_rows():
        for r in snap.records(d, secs["utxo"]):
            v, h, cb = up("<qIB", r, 36)
            yield r[:36], v, r[49:], h, cb

    db.executemany("INSERT INTO utxo VALUES(?,?,?,?,?)", utxo_rows())
    for i, p in enumerate(POOLS):
        db.executemany("INSERT INTO nf VALUES(?,?,?)",
                       ((i, r[:32], up("<I", r, 32)[0]) for r in snap.records(d, secs[f"nf.{p}"])))

    def blk_rows():
        for r in snap.records(d, secs["blk"]):
            h, = up(">I", r, 0)
            t_, size, ntx = up("<III", r, 68)
            nb = r[80]
            yield h, r[4:36], r[36:68], t_, size, ntx, r[81:81 + nb].decode(), r[81 + nb:].decode()

    db.executemany("INSERT INTO blk VALUES(?,?,?,?,?,?,?,?)", blk_rows())
    orc = list(snap.records(d, secs["oracle_prevout"]))
    if orc:
        db.execute("CREATE TABLE IF NOT EXISTS oracle_prevout(op BLOB PRIMARY KEY, height INTEGER) WITHOUT ROWID")
        db.executemany("INSERT INTO oracle_prevout VALUES(?,?)", ((r[:36], up("<I", r, 36)[0]) for r in orc))
    db.execute("COMMIT")
    st.close()


def import_finish(man, tmp, target, digest, checks, fronts, roots, pinned):
    """After verification: root histories, meta (tip, pools, status), then ONE rename to target."""
    tmp, target = Path(tmp), Path(target)
    meta = checks["meta"]
    H = man["height"]
    st = S.Store(tmp)
    db = st.db
    db.execute("BEGIN IMMEDIATE")
    for i, p in enumerate(POOLS):
        db.executemany("INSERT OR IGNORE INTO anchor VALUES(?,?,?)", ((i, bytes.fromhex(r), h) for h, r in roots[p]))
    for k, v in meta.items():
        st.put(k, v)
    st.put("addr_deferred", True)     # sync.py rebuilds the address index before its first full window
    st.put("leaf_lengths", {p: [0, 0] for p in POOLS})
    st.put("snapshot_frontier", {p: fronts[p] for p in POOLS})
    st.put("leaf_base", {p: (fronts[p] or {}).get("size") for p in POOLS})
    status = "snapshot-assumed" if pinned else "snapshot-unpinned"
    st.put("snapshot", {"height": H, "hash": man["hash"], "digest": digest, "status": status,
                        "pinned": bool(pinned), "provenance": "imported snapshot; producer state: " + snap.provenance(meta),
                        "checks": {k: v for k, v in checks.items() if k != "meta"},
                        "imported_at": int(time.time())})
    db.execute("COMMIT")
    if roots["ironwood"]:   # sync.py's Ironwood anchor check reads this file ("height size root")
        (tmp / "ironwood_roots.txt").write_text("".join(f"{h} 0 {r}\n" for h, r in roots["ironwood"]))
    st.close()
    os.replace(tmp, target)
    return status


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("snapshot")
    ap.add_argument("state")
    ap.add_argument("--pinned", default=str(PINNED))
    ap.add_argument("--pin", help="pinned digest given directly (overrides --pinned)")
    ap.add_argument("--unpinned", action="store_true", help="TEST USE ONLY: accept without a pinned digest")
    ap.add_argument("--jobs", type=int, default=16)
    ap.add_argument("--work")
    ap.add_argument("--keep-work", action="store_true")
    ap.add_argument("--history-blocks", help="spool dir that holds (or will hold) raw blocks H and H+1: run the "
                    "ZIP 221 check of the frontier roots at H against block H+1's hashBlockCommitments")
    ap.add_argument("--history-wait", type=float, default=300, help="seconds to wait for blocks H, H+1")
    a = ap.parse_args()
    t0 = time.time()
    man, _ = snap.read_header(a.snapshot)
    for old in (HERE / "work").glob("import_*_*"):   # work dirs of consumers that were killed
        try:
            os.kill(int(old.name.rsplit("_", 1)[1]), 0)
        except (ProcessLookupError, ValueError):
            shutil.rmtree(old, ignore_errors=True)
        except PermissionError:
            pass
    work = Path(a.work or HERE / "work" / f"import_{man['height']}_{os.getpid()}")
    if work.exists():
        shutil.rmtree(work)
    timing = {}
    target = Path(a.state)
    tmp = target.with_name(target.name + ".importing")
    bulk = None
    try:
        if target.exists():
            raise SnapError(f"{target} exists: the consumer only imports into a fresh directory")
        if tmp.exists():
            log(f"removing an interrupted import {tmp}")
            shutil.rmtree(tmp)
        t = time.time()
        man = snap.unpack(a.snapshot, work)
        timing["unpack"] = round(time.time() - t, 1)
        pin = a.pin or pinned_digest(a.pinned, man["height"], man["hash"])
        t = time.time()
        import multiprocessing as mp
        bulk = mp.get_context("spawn").Process(target=bulk_import, args=(str(work), man, str(tmp)), daemon=True)
        bulk.start()   # SQLite import of the big tables, in parallel with the Bend verification
        digest, checks, fronts, roots = verify(work, man, a.jobs, work, pin=pin, unpinned=a.unpinned)
        timing["verify"] = round(time.time() - t, 1)
        log(f"digest {digest}: pinned {checks['pinned']}")
        log(f"  {checks['blocks']}")
        for p, s in checks["trees"].items():
            log(f"  {p}: {s}")
        if a.history_blocks:   # ZIP 221: the frontier roots at H against block H+1's header (histcheck.py)
            t = time.time()
            import histcheck
            need = (man["height"], man["height"] + 1)
            while True:
                raw = histcheck.spool_blocks(a.history_blocks, *need)
                if len(raw) == 2 or time.time() - t > a.history_wait:
                    break
                time.sleep(0.5)
            hc = histcheck.check(work, man, man.get("history_hint"), raw, work)
            hc["wait_secs"] = round(time.time() - t - hc.get("secs", 0), 1)
            checks["history_zip221"] = hc
            log(f"  ZIP 221 at H+1: {hc['result']} {hc.get('line', hc.get('why', ''))[:120]}")
            if hc["result"] == "MISMATCH":
                raise SnapError(f"ZIP 221: block {man['height'] + 1}'s hashBlockCommitments does not commit to "
                                f"the snapshot's tree roots at {man['height']}: {hc['line']}")
            timing["history_check"] = round(time.time() - t, 1)
        bulk.join()
        timing["bulk_import_done"] = round(time.time() - t, 1)
        if bulk.exitcode != 0:
            raise SnapError(f"bulk import process failed (exit {bulk.exitcode})")
        t = time.time()
        status = import_finish(man, tmp, target, digest, checks, fronts, roots, pin is not None)
        timing["finish"] = round(time.time() - t, 1)
    except SnapError as e:
        log(f"REJECTED: {e}")
        if bulk is not None and bulk.is_alive():
            bulk.kill()
            bulk.join()
        shutil.rmtree(tmp, ignore_errors=True)
        sys.exit(2)
    finally:
        if not a.keep_work and work.exists():
            shutil.rmtree(work)
    timing["total"] = round(time.time() - t0, 1)
    log(f"imported {man['height']} into {a.state}: status {status}; timing {timing}")
    print(json.dumps({"height": man["height"], "digest": digest, "status": status, "timing": timing}))


if __name__ == "__main__":
    main()
