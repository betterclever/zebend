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


def spool_heights(spool):
    import struct
    for p in Path(spool).glob("*.blk"):
        d = p.read_bytes()
        i = 0
        while i < len(d):
            h, k = struct.unpack_from("<II", d, i)
            yield h
            i += 8 + k


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
    ap.add_argument("--download", action="store_true",
                    help="cold start: download.py fetches H..tip into --spool from t0 (in parallel with the import); "
                         "consume.py runs the ZIP 221 check on blocks H, H+1 from that spool")
    ap.add_argument("--peers-from", default=str(snap.FULL / "state/peers.txt"), help="address book to start from")
    a = ap.parse_args()
    t0 = time.time()
    import threading
    peak = {"kb": 0, "at": 0.0}

    def sampler():   # RSS of this process's whole tree (consume, its import process, Bend, sync, download)
        me = os.getpid()
        while True:
            out = subprocess.run(["ps", "-A", "-o", "pid=,ppid=,rss="], capture_output=True, text=True).stdout
            pp, rs = {}, {}
            for l in out.splitlines():
                f = l.split()
                if len(f) == 3:
                    pp[int(f[0])], rs[int(f[0])] = int(f[1]), int(f[2])
            tot = 0
            for q0 in pp:
                q = q0
                while q in pp and q not in (me, 1, 0):
                    q = pp[q]
                if q == me:
                    tot += rs[q0]
            if tot > peak["kb"]:
                peak["kb"], peak["at"] = tot, round(time.time() - t0, 1)
            time.sleep(0.5)

    threading.Thread(target=sampler, daemon=True).start()
    H0 = snap.read_header(a.snapshot)[0]["height"]
    dl, dl_state = None, Path(str(Path(a.target).resolve()) + ".dl")
    denv = dict(os.environ, ZEBEND_STATE=str(dl_state), ZEBEND_SPOOL=str(Path(a.spool).resolve()), BEND_NO_TELEMETRY="1")
    dlog = open(Path(str(Path(a.target).resolve()) + ".download.log"), "w")

    def start_download(frm):
        return subprocess.Popen([sys.executable, "-u", str(snap.FULL / "download.py"), "--from", str(frm), "--peers", "8"],
                                env=denv, stdout=dlog, stderr=subprocess.STDOUT)

    if a.download:
        dl_state.mkdir(parents=True, exist_ok=True)
        if Path(a.peers_from).exists():
            (dl_state / "peers.txt").write_bytes(Path(a.peers_from).read_bytes())
        dl = start_download(H0)
    cmd = [sys.executable, str(HERE / "consume.py"), a.snapshot, a.target] + (["--pin", a.pin] if a.pin else []) + \
        (["--unpinned"] if a.unpinned else []) + (["--history-blocks", str(Path(a.spool).resolve())] if a.download else [])
    r = subprocess.run(cmd, capture_output=True, text=True)
    sys.stderr.write(r.stdout[-3000:] + r.stderr[-2000:])
    try:
        consume_out = json.loads(r.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        consume_out = None
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
        if dl is not None and dl.poll() is not None:   # fetch blocks the verified headers gained since
            import headers
            n = headers.Index(snap.FULL / "state/hdr/hashes.bin").n
            have = max([cur] + [h for h in spool_heights(a.spool)])
            if n - 1 > have:
                dl = start_download(have + 1)
        time.sleep(0.5)
    if p.poll() is None:
        p.send_signal(signal.SIGTERM)   # our own sync.py: stops at a window boundary
        try:
            p.wait(timeout=600)
        except subprocess.TimeoutExpired:
            p.kill()
    if dl is not None and dl.poll() is None:
        dl.terminate()
    out = {"snapshot_height": H, "import_secs": round(t_import, 1), "consume": consume_out,
           "peak_rss_tree_gb": round(peak["kb"] / 1048576, 2), "peak_rss_at_secs": peak["at"],
           "first_window_committed_secs": round(first, 1) if first else None,
           "validating_at_tip_secs": round(at_tip, 1) if at_tip else None,
           "tip_reached": tip_of(a.target), "goal": goal, "blocks_validated": tip_of(a.target) - H,
           "sync_exit": p.returncode}
    print(json.dumps(out))


if __name__ == "__main__":
    main()
