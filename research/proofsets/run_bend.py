#!/usr/bin/env python3
"""Verify every bundle under data/chunks (post-NU6.3 circuit) and data/other (older circuits)
with the Bend Halo 2 verifier and diff each verdict against the official orchard verdict
in data/official.txt.

Each chunk is batch-verified (research/perf3/v64/batch_main: one merged final MSM with random weights).
If a batch is rejected, every bundle in it is re-verified on its own (research/perf3/v64/bundle_ba) to
find which ones fail. Results go to data/bend_results.txt and a summary to stdout.
"""
import os, re, subprocess, sys, time
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DATA = os.path.join(HERE, "data")
G = os.path.join(ROOT, "zcash", "halo2", "verifier", "data", "params_g.bin")
BATCH = os.path.join(ROOT, "research", "perf3", "v64", "batch_main")
SINGLE = os.path.join(ROOT, "research", "perf3", "v64", "bundle_ba")
OLDER = {  # circuit version -> single-bundle Bend verifier for that VK
    "FixedPostNu6_2": os.path.join(ROOT, "research", "fast", "pure", "v32", "bundle_main_nu62"),
    "InsecurePreNu6_2": os.path.join(ROOT, "research", "fast", "pure", "v32", "bundle_main_prenu62"),
}

official = {}
for fn in sorted(os.listdir(DATA)):
    if not (fn.startswith("official_p") and fn.endswith(".txt")):
        continue
    for line in open(os.path.join(DATA, fn)):
        if line.startswith("#"):
            continue
        rel, ok, actions, circuit, height, txid, pool = line.split()
        official[rel] = (int(ok), int(actions), circuit)

# Optional slice of chunks (CHUNK_FROM/CHUNK_TO env), so each run fits one heavy.sh slot;
# results are written per slice and merged by summarize.py.
CHUNK_FROM = int(os.environ.get("CHUNK_FROM", "0"))
CHUNK_TO = int(os.environ.get("CHUNK_TO", "1000000000"))

def single(binary, rel):
    out = subprocess.run([binary, G, os.path.join(DATA, rel)], capture_output=True, text=True).stdout
    m = re.search(r"result (\d)", out)
    return int(m.group(1)) if m else -1

bend = {}
t0 = time.time()
batch_secs = 0.0
batches = rejected_batches = 0
chunks = sorted(os.listdir(os.path.join(DATA, "chunks")))[CHUNK_FROM:CHUNK_TO]
for i, c in enumerate(chunks):
    files = sorted(os.listdir(os.path.join(DATA, "chunks", c)))
    rels = [f"chunks/{c}/{f}" for f in files]
    tb = time.time()
    out = subprocess.run([BATCH, G] + [os.path.join(DATA, r) for r in rels], capture_output=True, text=True).stdout
    batch_secs += time.time() - tb
    batches += 1
    m = re.search(r"batch K (\d+) result (\d)", out)
    if not m or int(m.group(1)) != len(rels):
        sys.exit(f"{c}: batch verifier did not process all {len(rels)} bundles: {out[:200]}")
    if m.group(2) == "1":
        for r in rels:
            bend[r] = 1
    else:
        rejected_batches += 1
        for r in rels:
            bend[r] = single(SINGLE, r)
    if i % 500 == 0 or i == len(chunks) - 1:
        print(f"{i + 1}/{len(chunks)} chunks, {len(bend)} bundles, {time.time() - t0:.0f}s", flush=True)

for f in (sorted(os.listdir(os.path.join(DATA, "other"))) if CHUNK_FROM == 0 else []):
    rel = f"other/{f}"
    circuit = official[rel][2]
    bend[rel] = single(OLDER[circuit], rel)

agree = sum(1 for r, v in bend.items() if v == official[r][0])
diff = [r for r, v in bend.items() if v != official[r][0]]
missing = [r for r in official if r not in bend and (r.startswith("other/") or r.split("/")[1] in set(chunks))]
actions = sum(official[r][1] for r in bend)
with open(os.path.join(DATA, f"bend_results_{CHUNK_FROM:06d}.txt"), "w") as f:
    for r in sorted(bend):
        f.write(f"{r} bend {bend[r]} official {official[r][0]}\n")
total = time.time() - t0
print(f"bundles {len(bend)} (actions {actions}); Bend valid {sum(bend.values())}; official valid {sum(o[0] for o in official.values())}")
print(f"agree {agree}/{len(bend)}; disagree {len(diff)}; not run {len(missing)}")
with open(os.path.join(DATA, f"bend_timing_{CHUNK_FROM:06d}.txt"), "w") as f:
    f.write(f"{len(bend)} {batch_secs:.3f} {batches} {rejected_batches}\n")
print(f"batches {batches} ({rejected_batches} rejected -> per-bundle re-check); batch verify time {batch_secs:.1f}s = {len(bend) / max(batch_secs, 1e-9):.0f} bundles/s (process time incl. file reads); total {total:.0f}s")
print("by circuit:", Counter(official[r][2] for r in bend))
if diff:
    print("DISAGREEMENTS:", diff[:20])
