#!/usr/bin/env python3
"""fasttip node service: sync.py with push-based block pickup, in ONE long-lived process.

Replaces the `sync` + `live` services. sync.py's own code validates and commits (its rules,
verdicts and state are unchanged; patches/sync.diff adds only the in-memory block source, the
event-driven idle wait and the rules/trees overlap); tipfeed.py feeds it the blocks peers
announce, header-checked in Bend, without a spool round trip; the spool is still read first
(the fallback poll — tiphdr.py + download.py, the old live.py cycle — and catch-up write there).

Per committed block, one line in --latency-log (JSONL) and in the log:
  t_inv (first inv/headers announcement), t_recv (block received), t_put (Bend header checks done,
  block handed to sync), t_take (sync took it), t_commit (verdict committed: the state writer's
  COMMIT returned), latency = t_commit - t_inv, and the window's stage timings (prof.py).

usage: tipsync.py [--peers 3] [--every 60] [--latency-log logs/fasttip_latency.jsonl] [--no-inproc]
                  [-- sync.py args...]
env: ZEBEND_STATE / ZEBEND_SPOOL as sync.py; ZEBEND_PARALLEL_HOOKS=0 / ZEBEND_OVERLAP=0 turn the
     parallel hooks / trees and the rules overlap off (sequential, as before).
"""
import argparse, json, os, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
NODE = HERE.parent
sys.path.insert(0, str(NODE))
sys.path.insert(0, str(HERE))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--peers", type=int, default=4, help="push peers (Zebra allows one connection per IP: keep it small)")
    ap.add_argument("--hdr-poll", type=float, default=5.0, help="getheaders to one push peer every S s (missed-inv safety net; 0: off)")
    ap.add_argument("--every", type=int, default=60, help="fallback poll period (s): tiphdr.py + download.py when push is quiet")
    ap.add_argument("--latency-log", default=str(NODE / "logs/fasttip_latency.jsonl"))
    ap.add_argument("--no-follow-tap", action="store_true", help="do not read the blocks zebend_follow.py receives")
    ap.add_argument("--no-inproc", action="store_true", help="run every hook as a subprocess (as before)")
    a, rest = ap.parse_known_args()
    if rest and rest[0] == "--":
        rest = rest[1:]
    import sync, rules, prof, tipfeed, inproc
    P = prof.install(sync, None)
    feed = tipfeed.TipFeed(prof=P, peers=a.peers, every=a.every, log=sync.log, hdr_poll=a.hdr_poll,
                           follow_tap=not a.no_follow_tap)
    sync.BLOCK_SOURCE = feed.buffer
    if not a.no_inproc:
        rules.HOOK_RUNNER = inproc.run_hook
    Path(a.latency_log).parent.mkdir(parents=True, exist_ok=True)
    last = {"h": None}

    def on_commit(rec):
        top = rec["last"]
        if top is None:
            return
        lo = last["h"] if last["h"] is not None else top - 1
        last["h"] = top
        for h in range(lo + 1, top + 1):
            m = feed.buffer.meta.pop(h, None) or {}
            row = {"height": h, "source": "push" if m else "spool", "t_commit": rec["t_commit"], **m}
            if m.get("t_inv"):
                row["latency"] = round(rec["t_commit"] - m["t_inv"], 4)
                row["fetch_s"] = round(m["t_recv"] - m["t_inv"], 4)
                row["header_and_queue_s"] = round(m["t_put"] - m["t_recv"], 4)
                if m.get("t_take"):
                    row["handoff_s"] = round(m["t_take"] - m["t_put"], 4)
                    row["validate_commit_s"] = round(rec["t_commit"] - m["t_take"], 4)
            row["stages"] = rec["stages"]
            row["procs"] = rec["procs"]
            with open(a.latency_log, "a") as f:
                f.write(json.dumps(row) + "\n")
            if "latency" in row:
                sync.log(f"fasttip: block {h} announced ({m.get('seen_by')}) by {m.get('inv_ip')} -> verdict committed in {row['latency']:.3f} s "
                         f"(fetch {row['fetch_s']:.3f}, header check {row['header_and_queue_s']:.3f}, "
                         f"validate+commit {row.get('validate_commit_s', float('nan')):.3f})")
        for k in [k for k in feed.buffer.meta if k <= top]:
            feed.buffer.meta.pop(k, None)

    P.on_commit.append(on_commit)
    feed.start()
    sync.log(f"fasttip: push pickup on {a.peers} peers, fallback poll every {a.every} s when quiet; hooks "
             f"{'in-process' if not a.no_inproc else 'subprocesses'}, parallel={rules.PARALLEL_HOOKS}, overlap={sync.OVERLAP}")
    sys.argv = ["sync.py"] + rest
    try:
        return sync.main()
    finally:
        feed.stop()
        sync.log(f"fasttip: feed stats {feed.stats}; hooks {inproc.STATS}")


if __name__ == "__main__":
    import sync as _s, store as _S
    try:
        sys.exit(main())
    except (_s.Fail, _S.StateError) as e:  # as sync.py's __main__
        _s.log(f"FAIL: {e}")
        _s.log("  window NOT committed; state stays at the last committed tip")
        sys.exit(1)
