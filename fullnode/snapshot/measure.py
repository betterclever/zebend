#!/usr/bin/env python3
"""Measure a snapshot start: import (consume.py) then sync.py full validation from H+1, until the
new instance is "validating at tip" (its committed tip reaches the tip of a reference instance,
or --to H). Uses only our own processes and directories; the reference store is read read-only.

  measure.py SNAP TARGET --spool DIR (--pin D | --unpinned) (--until-live STATE | --to H) [--timeout S]

Prints one JSON line: import seconds, first committed window, time to tip, blocks validated.
"""
import argparse, json, os, signal, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import snap  # noqa: E402


def tip_of(state):
    try:
        db = snap.open_ro(state)
        r = db.execute("SELECT v FROM meta WHERE k='tip'").fetchone()
        db.close()
        return json.loads(r[0])["height"] if r else -1
    except Exception:
        return -1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("snapshot")
    ap.add_argument("target")
    ap.add_argument("--spool", required=True)
    ap.add_argument("--pin")
    ap.add_argument("--unpinned", action="store_true")
    ap.add_argument("--until-live")
    ap.add_argument("--to", type=int)
    ap.add_argument("--timeout", type=float, default=3000)
    ap.add_argument("--sync-args", default="")
    ap.add_argument("--log", default=None)
    ap.add_argument("--sync", default=str(snap.FULL / "sync.py"),
                    help="sync.py to run (e.g. a frozen copy of the committed code)")
    a = ap.parse_args()
    t0 = time.time()
    cmd = [sys.executable, str(HERE / "consume.py"), a.snapshot, a.target] + (["--pin", a.pin] if a.pin else []) + \
        (["--unpinned"] if a.unpinned else [])
    r = subprocess.run(cmd, capture_output=True, text=True)
    sys.stderr.write(r.stdout[-3000:] + r.stderr[-2000:])
    if r.returncode:
        print(json.dumps({"result": "import rejected", "secs": round(time.time() - t0, 1)}))
        sys.exit(r.returncode)
    t_import = time.time() - t0
    H = tip_of(a.target)
    env = dict(os.environ, ZEBEND_STATE=str(Path(a.target).resolve()), ZEBEND_SPOOL=str(Path(a.spool).resolve()),
               BEND_NO_TELEMETRY="1")
    logf = open(a.log or Path(a.target).with_suffix(".sync.log"), "w")
    args = [sys.executable, a.sync] + a.sync_args.split() + (["--to", str(a.to)] if a.to else [])
    p = subprocess.Popen(args, env=env, stdout=logf, stderr=subprocess.STDOUT)
    first, at_tip, goal = None, None, None
    while time.time() - t0 < a.timeout:
        cur = tip_of(a.target)
        if first is None and cur > H:
            first = time.time() - t0
        goal = a.to if a.to else tip_of(a.until_live)
        if cur >= goal and cur > H:
            at_tip = time.time() - t0
            break
        if p.poll() is not None:
            break
        time.sleep(0.5)
    if p.poll() is None:
        p.send_signal(signal.SIGTERM)   # our own sync.py: stops at a window boundary
        try:
            p.wait(timeout=600)
        except subprocess.TimeoutExpired:
            p.kill()
    out = {"snapshot_height": H, "import_secs": round(t_import, 1),
           "first_window_committed_secs": round(first, 1) if first else None,
           "validating_at_tip_secs": round(at_tip, 1) if at_tip else None,
           "tip_reached": tip_of(a.target), "goal": goal, "blocks_validated": tip_of(a.target) - H,
           "sync_exit": p.returncode}
    print(json.dumps(out))


if __name__ == "__main__":
    main()
