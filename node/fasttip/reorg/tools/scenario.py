#!/usr/bin/env python3
"""Lab harness (reorg tests): run a lab node's tipsync code (sync.main + tipfeed, in one process,
as node/fasttip/tipsync.py) and play a fork scenario at it with REAL mainnet blocks / headers.

  scenario.py --lab <lab>/node --case CASE --blocks DIR --stale FILE [--to H] [--out JSONL]

Sources the lab node listens to (no mainnet connection is made by the node under test):
  * follow tap: <lab root>/followwork/win/<h>/block.bin (ZEBEND_FOLLOW_WORK), written the way
    zebend_follow.py writes received blocks (after its own reorg it rewrites a height's file);
  * a local mock peer (mockpeer.py) on 127.0.0.1 that announces (inv) and serves real headers
    and blocks (getheaders with a locator, getdata) -- the push path.
Cases: see CASES below. Prints one RESULT line (JSON) at the end.
"""
import argparse, hashlib, json, os, signal, socket, sqlite3, sys, threading, time
from pathlib import Path

HDR, EXTRA_FIRST = 1487, 3528280
F = 3532944           # the real fork point: 3532945 was 5714cf... (stale) vs 48cae4... (canonical)


def sha256d(b):
    return hashlib.sha256(hashlib.sha256(b).digest()).digest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lab", required=True)
    ap.add_argument("--case", required=True)
    ap.add_argument("--blocks", required=True)
    ap.add_argument("--stale", required=True)
    ap.add_argument("--canon-hdrs", default=None, help="file of canonical headers (case E)")
    ap.add_argument("--canon-from", type=int, default=3532380)
    ap.add_argument("--to", type=int, default=3532957)
    ap.add_argument("--resume", action="store_true", help="restart after a SIGKILL: only feed the winning chain")
    ap.add_argument("--reorg-timeout", type=float, default=120)
    ap.add_argument("--hold", type=float, default=6.0, help="ignore cases: seconds to watch for a (wrong) switch")
    a = ap.parse_args()
    lab = Path(a.lab).resolve()
    assert lab.name == "node" and "zebend/node" not in str(lab), "lab only"
    fw = lab.parent / "followwork"
    os.environ.update(ZEBEND_STATE=str(lab / "state"), ZEBEND_SPOOL=str(lab / "spool"), BEND_NO_TELEMETRY="1",
                      ZEBEND_FOLLOW_WORK=str(fw))
    sys.path.insert(0, str(lab))
    sys.path.insert(0, str(lab / "fasttip"))
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    blocks = {h: (Path(a.blocks) / f"{h}.bin").read_bytes() for h in range(3532920, 3532971)
              if (Path(a.blocks) / f"{h}.bin").exists()}
    stale = Path(a.stale).read_bytes()
    T0 = time.time()

    def log(*x):
        print(f"{time.strftime('%H:%M:%S')}.{int(time.time() * 1000) % 1000:03d}", *x, flush=True)

    import sync, prof, tipfeed, rules, inproc, net, mockpeer, tiphdr
    tiphdr.candidate_peers = lambda: []  # the node under test never dials mainnet in these tests
    sync.log = log
    P = prof.install(sync, None)
    case = a.case.split("@")[0]
    mock = None
    npeers, hdr_poll = 0, 0
    if case in ("A2", "A3", "B3", "E", "C1"):
        mock = mockpeer.MockPeer(log=log)
        npeers, hdr_poll = 1, (1.0 if case in ("A3", "E") else 0)
        real_cc = socket.create_connection

        def cc(addr, *x, **k):  # the node's push peer "127.0.0.1" is the mock
            if addr[0] == "127.0.0.1" and addr[1] == 8233:
                addr = ("127.0.0.1", mock.port)
            return real_cc(addr, *x, **k)
        net.socket.create_connection = cc
        tipfeed.TipFeed._candidates = lambda self: ["127.0.0.1"]
    feed = tipfeed.TipFeed(prof=P, peers=npeers, fallback=False, log=log, hdr_poll=hdr_poll, follow_tap=True)
    if case == "A_offidx":
        # deterministic race: sync takes the stale block, and its window is held between take() and
        # validation until the index has switched (sync.off_index must drop it, not FAIL)
        real_take = feed.buffer.take

        def take(after, *x, **k):
            got = real_take(after, *x, **k)
            if got and got[0][0] == F + 1 and got[0][1][:HDR] == stale[:HDR]:
                log("TEST: stale 3532945 taken by sync; holding its window until the index switches")
                t = time.time()
                while not feed.reorgs and time.time() - t < 20:
                    time.sleep(0.005)
            return got
        feed.buffer.take = take
    sync.BLOCK_SOURCE = feed.buffer
    rules.HOOK_RUNNER = inproc.run_hook
    out = {"case": a.case, "resume": a.resume}

    def state_tip():
        db = sqlite3.connect(f"file:{lab / 'state/chain.sqlite'}?mode=ro", uri=True, timeout=10)
        try:
            return json.loads(db.execute("SELECT v FROM meta WHERE k='tip'").fetchone()[0])
        finally:
            db.close()

    def name(raw):
        return sha256d(raw[:HDR])

    def disp(raw):
        return name(raw)[::-1].hex()

    def wait_commit(h, raw, timeout=120):
        t = time.time()
        while time.time() - t < timeout:
            tp = state_tip()
            if tp["height"] >= h:
                db = sqlite3.connect(f"file:{lab / 'state/chain.sqlite'}?mode=ro", uri=True, timeout=10)
                r = db.execute("SELECT hash FROM blk WHERE height=?", (h,)).fetchone()
                db.close()
                if r and r[0].hex() == disp(raw):
                    return time.time()
            time.sleep(0.01)
        raise TimeoutError(f"block {h} {disp(raw)[:16]} not committed in {timeout} s (tip {state_tip()})")

    def tap(h, raw):  # as zebend_follow.py: work/win/<h>/block.bin (rewritten after its reorg)
        d = fw / "win" / str(h)
        d.mkdir(parents=True, exist_ok=True)
        tmp = d / "block.tmp"
        tmp.write_bytes(raw)
        os.replace(tmp, d / "block.bin")

    def hold_still(secs, expect_tip):
        t = time.time()
        while time.time() - t < secs:
            if state_tip() != expect_tip or feed.reorgs:
                raise AssertionError(f"state moved: {state_tip()} (expected {expect_tip}); reorgs {feed.reorgs}")
            time.sleep(0.05)

    def feed_rest(start, via_mock=False, gap=0.3):
        for h in range(start, a.to + 1):
            time.sleep(gap)
            if via_mock:
                mock.add_block(blocks[h])
                mock.set_best([(k, blocks[k][:HDR]) for k in range(3532920, h + 1)])
                mock.announce(name(blocks[h]))
            else:
                tap(h, blocks[h])
            wait_commit(h, blocks[h])

    def wait_peer():
        t = time.time()
        while not feed.conns:
            if time.time() - t > 30:
                raise TimeoutError("mock peer not connected")
            time.sleep(0.05)

    def script():
        try:
            run_case()
            out["ok"] = True
        except BaseException as e:  # noqa
            out["ok"] = False
            out["error"] = f"{e.__class__.__name__}: {e}"
            log("SCENARIO ERROR", out["error"])
        finally:
            out["reorgs"] = getattr(feed, "reorgs", None)
            out["stats"] = feed.stats
            sync._STOP.append(1)
            feed.buffer.put(-1, b"", b"")  # wake sync's idle wait

    def reorg_timing(t_ann, h_new, raw_new):
        t_c = wait_commit(h_new, raw_new, timeout=a.reorg_timeout)
        r = feed.reorgs[-1] if getattr(feed, "reorgs", None) else {}
        out.update(t_announce=t_ann, t_switch=r.get("t"), t_committed=t_c,
                   announce_to_switch_s=round(r["t"] - t_ann, 3) if r else None,
                   announce_to_commit_s=round(t_c - t_ann, 3), decide_s=r.get("decide_s"))
        log(f"REORG TIMING: announcement -> index switched {out['announce_to_switch_s']} s, -> winning block "
            f"{h_new} committed {out['announce_to_commit_s']} s")

    def run_case():
        if mock is not None and case != "E":
            top_c = state_tip()["height"] if case == "C1" else F  # C1: the mock is on our (canonical) chain
            mock.set_best([(k, blocks[k][:HDR]) for k in range(3532920, top_c + 1)])
        if case == "E":
            ch = Path(a.canon_hdrs).read_bytes()
            mock.set_best([(a.canon_from + k, ch[k * HDR:(k + 1) * HDR]) for k in range(len(ch) // HDR)])
        if mock is not None:
            wait_peer()
        if case in ("A", "A_rev") or (case.startswith("D") and not a.resume):
            # the real 3532945 race: the stale block first (both nodes took it), then the winners
            tap(F + 1, stale)
            wait_commit(F + 1, stale)
            out["stale_committed"] = True
            time.sleep(1.0)
            t_ann = time.time()
            if case == "A_rev":  # the child first: its parent is missing (asked of follow's files / peers)
                tap(F + 2, blocks[F + 2])
                time.sleep(0.5)
                tap(F + 1, blocks[F + 1])
            else:
                tap(F + 1, blocks[F + 1])
                tap(F + 2, blocks[F + 2])
            reorg_timing(t_ann, F + 2, blocks[F + 2])
            feed_rest(F + 3)
        elif case == "A_offidx":
            tap(F + 1, stale)
            while not any(r[0] == F + 1 for r in feed.buffer.recent.items()):
                time.sleep(0.005)
            t_ann = time.time()
            tap(F + 1, blocks[F + 1])
            tap(F + 2, blocks[F + 2])
            reorg_timing(t_ann, F + 2, blocks[F + 2])
            feed_rest(F + 3)
        elif case == "A_race":  # the winners arrive while the stale block is still being validated
            delay = float(a.case.split("@")[1]) / 1000 if "@" in a.case else 0.05
            tap(F + 1, stale)
            time.sleep(delay)
            t_ann = time.time()
            tap(F + 1, blocks[F + 1])
            tap(F + 2, blocks[F + 2])
            reorg_timing(t_ann, F + 2, blocks[F + 2])
            feed_rest(F + 3)
        elif case.startswith("D") and a.resume:
            for h in range(F + 1, a.to + 1):  # follow's files are still there; write them all again
                tap(h, blocks[h])
            t = time.time()
            wait_commit(a.to, blocks[a.to], timeout=300)
            out["resume_to_tip_s"] = round(time.time() - t, 3)
        elif case in ("A2", "A3"):
            mock.add_block(stale)
            mock.set_best([(k, blocks[k][:HDR]) for k in range(3532920, F + 1)] + [(F + 1, stale[:HDR])])
            mock.announce(name(stale))
            wait_commit(F + 1, stale)
            time.sleep(1.0)
            for h in (F + 1, F + 2):
                mock.add_block(blocks[h])
            mock.set_best([(k, blocks[k][:HDR]) for k in range(3532920, F + 3)])
            t_ann = time.time()
            if case == "A2":
                mock.announce(name(blocks[F + 2]))  # inv of the child only: its parent is unknown to us
            # A3: no inv at all; the getheaders poll (every 1 s here) gets a reply that forks
            reorg_timing(t_ann, F + 2, blocks[F + 2])
            out["mock"] = dict(mock.served)
            feed_rest(F + 3, via_mock=True)
        elif case == "B2":  # our branch: 945x, 946x (relabelled); competing: 945', 946, 947 (real)
            t_ann = time.time()
            for h in (F + 1, F + 2, F + 3):
                tap(h, blocks[h])
            reorg_timing(t_ann, F + 3, blocks[F + 3])
            feed_rest(F + 4)
        elif case == "B3":  # our branch: 945x..947x (relabelled); competing: 945'..948 (real) by inv + headers
            for h in range(F + 1, F + 5):
                mock.add_block(blocks[h])
            mock.set_best([(k, blocks[k][:HDR]) for k in range(3532920, F + 5)])
            t_ann = time.time()
            mock.announce(name(blocks[F + 4]))
            reorg_timing(t_ann, F + 4, blocks[F + 4])
            out["mock"] = dict(mock.served)
            feed_rest(F + 5, via_mock=True)
        elif case in ("C0", "C1"):  # a real competing block with equal (C0: vs 945') / less (C1: vs 945'..947) work
            tip0 = state_tip()
            tap(F + 1, stale)
            if mock is not None:
                mock.add_block(stale)
                mock.announce(name(stale))
            hold_still(a.hold, tip0)
            out["held_s"] = a.hold
            feed_rest(tip0["height"] + 1)
        elif case == "C2":  # our relabelled 945x,946x claim 16x work each; competing real 945'..947 (longer)
            tip0 = state_tip()
            for h in (F + 1, F + 2, F + 3):
                tap(h, blocks[h])
            hold_still(a.hold, tip0)
            out["held_s"] = a.hold
        elif case == "C3":  # more work but bad PoW: [stale 945, 946 with stale as parent (solution not redone)]
            tip0 = state_tip()
            bad = bytearray(blocks[F + 2])
            bad[4:36] = name(stale)
            tap(F + 1, stale)
            time.sleep(0.3)
            tap(F + 2, bytes(bad))
            hold_still(a.hold, tip0)
            out["held_s"] = a.hold
            feed_rest(tip0["height"] + 1)
        elif case == "E":  # a real, heavier chain forking > 600 blocks below our (relabelled) tip
            ch = Path(a.canon_hdrs).read_bytes()
            pairs = [(a.canon_from + k, ch[k * HDR:(k + 1) * HDR]) for k in range(len(ch) // HDR)]
            tip0 = state_tip()
            mock.set_best(pairs)
            mock.announce(name(pairs[-1][1]))
            t = time.time()
            while feed.stats.get("reorgs refused", 0) == 0 and time.time() - t < 120:
                time.sleep(0.1)
            out["refused_after_s"] = round(time.time() - t, 3)
            out["mock"] = dict(mock.served)
            hold_still(2.0, tip0)
            assert feed.stats.get("reorgs refused", 0) == 1, "no REORG REFUSED"
        else:
            raise SystemExit(f"unknown case {case}")

    feed.start()
    threading.Thread(target=script, daemon=True).start()
    sys.argv = ["sync.py", "--window", "1"]
    try:
        sync.main()
    finally:
        feed.stop()
    out["final_tip"] = state_tip()
    out["wall_s"] = round(time.time() - T0, 1)
    print("RESULT " + json.dumps(out, default=str), flush=True)
    return 0 if out.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
