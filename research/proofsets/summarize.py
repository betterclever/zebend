#!/usr/bin/env python3
"""Merge the per-slice Bend results with every part's official verdicts and print the totals."""
import os
from collections import Counter

DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
official, totals = {}, Counter()
for fn in sorted(os.listdir(DATA)):
    if fn.startswith("official_p") and fn.endswith(".txt"):
        for line in open(os.path.join(DATA, fn)):
            if line.startswith("# total"):
                w = line.split()
                for k, v in zip(w[2::2], w[3::2]):
                    totals[k] += float(v)
            elif not line.startswith("#"):
                rel, ok, actions, circuit, height, txid, pool = line.split()
                official[rel] = (int(ok), int(actions), circuit, int(height), pool)
bend = {}
bend_secs = 0.0
batches = rejected = 0
for fn in sorted(os.listdir(DATA)):
    if fn.startswith("bend_results_"):
        for line in open(os.path.join(DATA, fn)):
            rel, _, v, _, _ = line.split()
            bend[rel] = int(v)
    if fn.startswith("bend_timing_"):
        n, s, b, r = open(os.path.join(DATA, fn)).read().split()
        bend_secs += float(s); batches += int(b); rejected += int(r)
heights = [o[3] for o in official.values()]
print(f"txs {int(totals['txs'])}; bundles {len(official)} ({Counter(o[4] for o in official.values())}); "
      f"actions {sum(o[1] for o in official.values())}; heights {min(heights)}..{max(heights)}")
print(f"by circuit: {dict(Counter(o[2] for o in official.values()))}")
print(f"official verifier valid {sum(o[0] for o in official.values())}/{len(official)} "
      f"(parse + verify {totals['official_verify_cpu_s']:.0f} s wall on all cores)")
agree = sum(1 for r in official if r in bend and bend[r] == official[r][0])
missing = [r for r in official if r not in bend]
diff = [r for r in official if r in bend and bend[r] != official[r][0]]
print(f"Bend valid {sum(bend.values())}/{len(bend)}; agree with official {agree}/{len(official)}; "
      f"disagree {len(diff)}; not run {len(missing)}")
print(f"Bend batch verification: {batches} batches ({rejected} rejected), {bend_secs:.0f} s process time "
      f"= {len(bend) / max(bend_secs, 1e-9):.0f} bundles/s")
if diff:
    print("DISAGREEMENTS:", diff[:20])
if missing:
    print("NOT RUN:", missing[:10])
