#!/usr/bin/env python3
"""Snapshot tests on a store (read-only; a copy or a bench state). usage:

  test_snapshot.py STATE [--only determinism,roundtrip,tamper,interrupt] [--work DIR]

determinism  two exports of the same state: identical section files and Bend digest
roundtrip    export -> zstd -> consume (pinned) into a fresh dir -> tables identical to the
             source (utxo, nf, blk context rows, exported meta) and a re-export of the imported
             store has the same digest
tamper       one UTXO value changed / one nullifier dropped / one frontier node changed, the file
             repacked (manifest updated to match, as an attacker would): rejected by the pinned
             digest; the frontier tamper is ALSO rejected with --unpinned (Bend root check)
interrupt    consume killed (SIGKILL) during the import: no target directory appears; rerunning
             imports from scratch and gives the same digest
"""
import argparse, json, os, shutil, signal, sqlite3, struct, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import snap  # noqa: E402

PY = sys.executable
RESULTS = []


def res(name, ok, detail=""):
    RESULTS.append((name, ok, detail))
    print(f"[{'PASS' if ok else 'FAIL'}] {name}: {detail}", flush=True)


def export(state, d):
    if Path(d).exists():
        shutil.rmtree(d)
    return snap.export(state, d, log=lambda *a: None)


def files_equal(a, b, man):
    for s in man["sections"]:
        for k in range(len(s["parts"])):
            if snap.part_path(a, s["name"], k).read_bytes() != snap.part_path(b, s["name"], k).read_bytes():
                return s["name"]
    return None


def consume(snapf, target, pin=None, unpinned=False):
    cmd = [PY, str(HERE / "consume.py"), str(snapf), str(target)] + (["--pin", pin] if pin else []) + \
          (["--unpinned"] if unpinned else [])
    return subprocess.run(cmd, capture_output=True, text=True)


def rows(state, sql, args=()):
    db = snap.open_ro(state)
    out = list(db.execute(sql, args))
    db.close()
    return out


def same_rows(a, b, sql, args=()):
    """Stream both tables in key order and compare row by row (no table in memory)."""
    import itertools
    da, db_ = snap.open_ro(a), snap.open_ro(b)
    try:
        for ra, rb in itertools.zip_longest(da.execute(sql, args), db_.execute(sql, args)):
            if ra != rb:
                return False
        return True
    finally:
        da.close()
        db_.close()


def repack(sec_dir, man, out):
    """Rebuild the manifest from the (modified) files and pack: an attacker's consistent file."""
    m = json.loads(json.dumps(man))
    for s in m["sections"]:
        tot_n = tot_b = 0
        for k, part in enumerate(s["parts"]):
            p = snap.part_path(sec_dir, s["name"], k)
            part["count"] = len(snap.record_offsets(p)) - 1
            part["bytes"] = p.stat().st_size
            tot_n += part["count"]
            tot_b += part["bytes"]
        s["count"], s["bytes"] = tot_n, tot_b
    m["digest"] = snap.digest_dir(sec_dir, m, 16, sec_dir)   # the attacker's own (honest) digest
    snap.pack(sec_dir, m, out)
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("state")
    ap.add_argument("--only", default="determinism,roundtrip,tamper,interrupt")
    ap.add_argument("--work", default=str(HERE / "work" / "tests"))
    ap.add_argument("--from-snapshot", help="use this snapshot of STATE (its sections) instead of a first export")
    a = ap.parse_args()
    only = set(a.only.split(","))
    W = Path(a.work)
    if W.exists():
        shutil.rmtree(W)
    W.mkdir(parents=True)
    t = time.time()
    if a.from_snapshot:
        m1 = snap.unpack(a.from_snapshot, W / "e1")
        m1["digest"] = snap.digest_dir(W / "e1", json.loads(json.dumps(m1)), 16, W / "e1")
    else:
        m1 = export(a.state, W / "e1")
    H, D = m1["height"], m1["digest"]
    print(f"state {a.state} at {H}: digest {D} ({time.time() - t:.0f} s)", flush=True)

    if "determinism" in only:
        t = time.time()
        m2 = export(a.state, W / "e2")
        diff = files_equal(W / "e1", W / "e2", m1)
        res("determinism", m2["digest"] == D and diff is None,
            f"two exports: digest {m2['digest'][:16]}.. == {D[:16]}.., section files identical: {diff is None} "
            f"({time.time() - t:.0f} s)")
        shutil.rmtree(W / "e2")

    snapf = Path(a.from_snapshot) if a.from_snapshot else W / "s.zsnap"
    if not a.from_snapshot:
        snap.pack(W / "e1", m1, snapf)
    if "roundtrip" in only:
        t = time.time()
        r = consume(snapf, W / "imp", pin=D)
        ok = r.returncode == 0
        detail = [f"consume exit {r.returncode} ({time.time() - t:.0f} s)"]
        if ok:
            lo = H - snap.BLK_CONTEXT
            for name, sql, args in (("utxo", "SELECT op, value, script, height, cb FROM utxo ORDER BY op", ()),
                                    ("nf", "SELECT pool, nf, height FROM nf ORDER BY pool, nf", ()),
                                    ("blk", "SELECT * FROM blk WHERE height > ? ORDER BY height", (lo,))):
                same = same_rows(a.state, W / "imp", sql, args)
                detail.append(f"{name} identical: {same}")
                ok &= same
            src = dict(rows(a.state, "SELECT k, v FROM meta"))
            dst = dict(rows(W / "imp", "SELECT k, v FROM meta"))
            for k in ("tip", "pools", "audit_disagreements", "assumed_state"):
                if k in src or k in dst:
                    same = json.loads(src.get(k, "null")) == json.loads(dst.get(k, "null"))
                    detail.append(f"meta.{k} identical: {same}")
                    ok &= same
            st = json.loads(dst["snapshot"])
            detail.append(f"status {st['status']}")
            m3 = export(W / "imp", W / "e3")
            detail.append(f"re-export digest equal: {m3['digest'] == D}")
            ok &= m3["digest"] == D and files_equal(W / "e1", W / "e3", m1) is None
            shutil.rmtree(W / "e3")
        else:
            detail.append(r.stdout[-500:] + r.stderr[-500:])
        res("roundtrip", ok, "; ".join(detail))

    if "tamper" in only:
        secs = snap.sec_by_name(m1)

        def tampered(name, mutate):
            d = W / f"t_{name}"
            shutil.copytree(W / "e1", d)
            mutate(d)
            f = W / f"t_{name}.zsnap"
            repack(d, m1, f)
            r = consume(f, W / f"imp_{name}", pin=D)
            rej = r.returncode == 2 and not (W / f"imp_{name}").exists()
            why = [l for l in r.stdout.splitlines() if "REJECTED" in l]
            return rej, (why[0].split("REJECTED: ")[1][:110] if why else r.stdout[-200:]), d, f

        def rewrite(d, sec, fn):
            """Apply fn(list of payloads) -> list of payloads to a section (single part)."""
            p = snap.part_path(d, sec, 0)
            recs = [r.tobytes() for _, r in snap.iter_records(p)]
            recs = fn(recs)
            p.write_bytes(b"".join(struct.pack("<I", len(r)) + r for r in recs))

        def utxo_value(recs):
            r = bytearray(recs[len(recs) // 2])
            v, = struct.unpack_from("<q", r, 36)
            struct.pack_into("<q", r, 36, v + 1)       # one zatoshi more
            recs[len(recs) // 2] = bytes(r)
            return recs

        nf_pool = max(snap.POOLS, key=lambda p: secs[f"nf.{p}"]["count"])
        ok_all = True
        rej, why, _, _ = tampered("utxo", lambda d: rewrite(d, "utxo", utxo_value))
        res("tamper: one UTXO value +1 zat", rej, why)
        ok_all &= rej
        rej, why, _, _ = tampered("nf", lambda d: rewrite(d, f"nf.{nf_pool}", lambda rs: rs[:3] + rs[4:]))
        res(f"tamper: one {nf_pool} nullifier dropped", rej, why)
        fronts = dict(snap.dec_frontier(r) for r in snap.records(W / "e1", secs["frontier"]))
        fr_pool = max((p for p in snap.POOLS if fronts[p]), key=lambda p: fronts[p]["size"])

        def frontier_node(recs):
            out = []
            for r in recs:
                pool, fr = snap.dec_frontier(r)
                if pool == fr_pool and fr:
                    i = next(k for k, l in enumerate(fr["levels"]) if l)
                    b = bytearray.fromhex(fr["levels"][i])
                    b[0] ^= 1
                    fr["levels"][i] = b.hex()
                    r = snap.enc_frontier(pool, fr)
                out.append(r)
            return out

        rej, why, d, f = tampered("frontier", lambda d: rewrite(d, "frontier", frontier_node))
        res(f"tamper: one {fr_pool} frontier node changed (pinned)", rej, why)
        r = consume(f, W / "imp_frontier_unpinned", unpinned=True)
        why = [l for l in r.stdout.splitlines() if "REJECTED" in l]
        rej2 = r.returncode == 2 and not (W / "imp_frontier_unpinned").exists()
        res(f"tamper: one {fr_pool} frontier node changed (UNPINNED: the Bend root check alone)", rej2,
            why[0].split("REJECTED: ")[1][:140] if why else r.stdout[-200:])
        # a tampered file that keeps the ORIGINAL manifest (sizes/digest unchanged): a byte flip
        d = W / "t_flip"
        shutil.copytree(W / "e1", d)
        p = snap.part_path(d, "utxo", 0)
        b = bytearray(p.read_bytes())
        b[len(b) // 2] ^= 0x40
        p.write_bytes(bytes(b))
        f = W / "t_flip.zsnap"
        snap.pack(d, m1, f)
        r = consume(f, W / "imp_flip", pin=D)
        why = [l for l in r.stdout.splitlines() if "REJECTED" in l]
        res("tamper: one bit flipped in the UTXO section (manifest unchanged)", r.returncode == 2,
            why[0].split("REJECTED: ")[1][:110] if why else r.stdout[-200:])

    if "interrupt" in only:
        tgt = W / "imp_int"
        killed_at = None
        p = subprocess.Popen([PY, str(HERE / "consume.py"), str(snapf), str(tgt), "--pin", D],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        imp = tgt.with_name(tgt.name + ".importing")
        while p.poll() is None:
            if imp.exists() and (imp / "chain.sqlite").exists() and (imp / "chain.sqlite").stat().st_size > 0:
                time.sleep(0.05)
                os.kill(p.pid, signal.SIGKILL)
                killed_at = time.time()
                break
            time.sleep(0.01)
        p.wait()
        left = {"target exists": tgt.exists(), "importing exists": imp.exists()}
        r = consume(snapf, tgt, pin=D)
        ok = killed_at is not None and not left["target exists"] and r.returncode == 0
        if ok:
            m4 = export(tgt, W / "e4")
            ok &= m4["digest"] == D
            shutil.rmtree(W / "e4")
        res("interrupted import (SIGKILL during the import transaction)", ok,
            f"killed: {killed_at is not None}; after kill {left}; rerun exit {r.returncode}"
            + ("; re-export digest equal" if ok else f" {r.stdout[-300:]}"))

    print(json.dumps({"state": str(a.state), "height": H, "digest": D,
                      "results": [(n, ok) for n, ok, _ in RESULTS]}))
    shutil.rmtree(W, ignore_errors=True)
    sys.exit(0 if all(ok for _, ok, _ in RESULTS) else 1)


if __name__ == "__main__":
    main()
