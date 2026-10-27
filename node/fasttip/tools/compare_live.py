#!/usr/bin/env python3
"""Before vs after on the SAME mainnet blocks: announcement -> committed verdict.

  compare_live.py <fasttip latency JSONL> <live node sync.log> [--out rows.jsonl]

t_inv: when the fasttip lab instance first saw the block's inv (its push peers; the live node
hears the same network). after: the lab's t_commit - t_inv (fasttip). before: the live node's
commit time of that height ("HH:MM:SS committed tip N" in its sync.log, 1 s resolution; the first
such line with N >= height) - t_inv. Only heights both committed are compared.
"""
import datetime as dt, json, re, statistics, sys


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(len(xs) * p))]


def main():
    lat = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
    lat = {r["height"]: r for r in lat if r.get("t_inv")}
    commits = []  # (time of day seconds, tip)
    for l in open(sys.argv[2], errors="replace"):
        m = re.match(r"^(\d\d):(\d\d):(\d\d) committed tip (\d+):", l)
        if m:
            commits.append((int(m.group(1)) * 3600 + int(m.group(2)) * 60 + int(m.group(3)), int(m.group(4))))
    rows = []
    for h, r in sorted(lat.items()):
        t_inv = r["t_inv"]
        day = dt.datetime.fromtimestamp(t_inv).replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
        best = None
        for tod, tip in commits:  # the first commit that covers h (the live log is in order)
            t = day + tod
            if t - t_inv > 43200:
                t -= 86400
            elif t_inv - t > 43200:
                t += 86400
            if tip >= h:
                if t < t_inv - 600:
                    continue  # an earlier branch / an older commit of a re-synced range
                best = t
                break
        if best is None:
            continue
        rows.append({"height": h, "after": r["latency"], "before": round(best - t_inv, 1),
                     "fetch_s": r.get("fetch_s"), "header_and_queue_s": r.get("header_and_queue_s"),
                     "validate_commit_s": r.get("validate_commit_s")})
    if "--out" in sys.argv:
        with open(sys.argv[sys.argv.index("--out") + 1], "w") as f:
            for x in rows:
                f.write(json.dumps(x) + "\n")
    early = [x for x in rows if x["before"] < 0]
    if early:
        print(f"{len(early)} blocks: the live node committed BEFORE the lab's reference time (a late reference, e.g. "
              f"follow lagging): {[x['height'] for x in early]}; excluded below")
        rows = [x for x in rows if x["before"] >= 0]
    for k in ("before", "after", "fetch_s", "header_and_queue_s", "validate_commit_s"):
        v = [x[k] for x in rows if x.get(k) is not None]
        if v:
            print(f"{k:<20} n={len(v):3d}  median {statistics.median(v):8.3f} s  p90 {pct(v, 0.9):8.3f} s  "
                  f"max {max(v):8.3f} s  min {min(v):8.3f} s")


if __name__ == "__main__":
    main()
