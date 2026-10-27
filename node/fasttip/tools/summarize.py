#!/usr/bin/env python3
"""Summarize replay / live latency JSONL files: latency median / p90 / max and the per-stage
breakdown (median and mean seconds per window, and Bend process seconds).

usage: summarize.py FILE.jsonl [FILE2.jsonl ...] [--key latency]
"""
import json, statistics, sys


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(len(xs) * p))] if xs else float("nan")


def main():
    args = sys.argv[1:]
    since = float(args[args.index("--since") + 1]) if "--since" in args else 0
    group = args[args.index("--group") + 1] if "--group" in args else None
    files = [a for i, a in enumerate(args) if not a.startswith("--") and (i == 0 or args[i - 1] not in ("--since", "--group"))]
    key = "latency"
    for f in files:
        allrows = [json.loads(l) for l in open(f) if l.strip()]
        allrows = [r for r in allrows if r.get("t_commit", since) >= since]
        groups = {None: allrows} if group is None else {}
        if group is not None:
            for r in allrows:
                groups.setdefault(r.get(group), []).append(r)
        for gk, rows in groups.items():
            if group is not None:
                print(f"#### {group} = {gk}")
            report(f, rows, key)


def report(f, rows, key):
    if True:
        lat = [r[key] for r in rows if r.get(key) is not None]
        print(f"== {f}: {len(rows)} blocks")
        if lat:
            print(f"   {key}: median {statistics.median(lat):.3f} s  p90 {pct(lat, 0.9):.3f} s  max {max(lat):.3f} s  "
                  f"mean {statistics.mean(lat):.3f} s")
        for key2 in ("pick_to_commit", "validate_commit_s", "fetch_s", "header_and_queue_s", "handoff_s"):
            v = [r[key2] for r in rows if r.get(key2) is not None]
            if v:
                print(f"   {key2}: median {statistics.median(v):.3f} s  p90 {pct(v, 0.9):.3f} s  max {max(v):.3f} s")
        stages = {}
        seen = set()
        for r in rows:
            wid = (r.get("t_commit"),)
            if wid in seen:
                continue
            seen.add(wid)
            for k, v in (r.get("stages") or {}).items():
                stages.setdefault(k, []).append(v)
        if stages:
            print(f"   {'stage':<26} {'median':>8} {'mean':>8} {'p90':>8} {'max':>8}  (s per window, {len(seen)} windows)")
            for k, v in sorted(stages.items(), key=lambda kv: -statistics.mean(kv[1])):
                print(f"   {k:<26} {statistics.median(v):8.4f} {statistics.mean(v):8.4f} {pct(v, 0.9):8.4f} {max(v):8.4f}")
        procs, seen2 = {}, set()
        for r in rows:
            if r.get("t_commit") in seen2:
                continue
            seen2.add(r.get("t_commit"))
            for k, (s, n) in (r.get("procs") or {}).items():
                e = procs.setdefault(k, [0.0, 0])
                e[0] += s
                e[1] += n
        if procs:
            print(f"   {'process':<26} {'total s':>8} {'runs':>6} {'s/run':>8}")
            for k, (s, n) in sorted(procs.items(), key=lambda kv: -kv[1][0]):
                print(f"   {k:<26} {s:8.3f} {n:6d} {s / max(n, 1):8.4f}")
        extra = {}
        for r in rows:
            for k, v in (r.get("feed") or {}).items():
                if isinstance(v, (int, float)):
                    extra.setdefault(k, []).append(v)
        for k, v in extra.items():
            print(f"   feed {k:<21} median {statistics.median(v):.4f}  p90 {pct(v, 0.9):.4f}  max {max(v):.4f}")


if __name__ == "__main__":
    main()
