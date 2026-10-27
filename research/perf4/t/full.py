#!/usr/bin/env python3
"""full.py BATCH_BIN GROUP [RTS...]: verify every bundle under research/proofsets/data/chunks with a
gpuv batch verifier, GROUP chunks (64 bundles each) per process, and diff every verdict with
the official one. A rejected batch is re-checked bundle by bundle with research/perf3/v64/bundle_ba.
Each batch must print `verified K` = its bundle count (guards the old par-fuel truncation).
Writes research/gpuv/t/full_<name>.txt and prints a summary."""
import os, re, subprocess, sys, time
R = "/Users/betterclever/projects/zecathon/zebend"
DATA = f"{R}/research/proofsets/data"; CH = f"{DATA}/chunks"
G = os.environ.get("PARAMS", f"{R}/zcash/halo2/verifier/data/params_g.bin")
SINGLE = os.environ.get("SINGLE", f"{R}/research/perf4/v/bundle_ba")
binp, group, rts = os.path.abspath(sys.argv[1]), int(sys.argv[2]), sys.argv[3:]
official = {}
for fn in sorted(os.listdir(DATA)):
    if fn.startswith("official_p") and fn.endswith(".txt"):
        for line in open(f"{DATA}/{fn}"):
            if not line.startswith("#"):
                rel, ok = line.split()[:2]
                official[rel] = int(ok)
chunks = sorted(os.listdir(CH))
lim = int(os.environ.get("CHUNKS", len(chunks)))
chunks = chunks[:lim]
bend, secs, nb, rej = {}, 0.0, 0, 0
t0 = time.time()
for i in range(0, len(chunks), group):
    rels = [f"{c}/{f}" for c in chunks[i:i + group] for f in sorted(os.listdir(f"{CH}/{c}"))]
    tb = time.time()
    out = subprocess.run([binp, G] + rels + rts, cwd=CH, capture_output=True, text=True).stdout
    secs += time.time() - tb; nb += 1
    m = re.search(r"batch K (\d+) result (\d)", out); v = re.search(r"verified (\d+)", out)
    if not m or int(m.group(1)) != len(rels) or not v or int(v.group(1)) != len(rels):
        sys.exit(f"batch at chunk {i} did not verify all {len(rels)}: {out[:300]}")
    if m.group(2) == "1":
        for r in rels: bend["chunks/" + r] = 1
    else:
        rej += 1
        for r in rels:
            o = subprocess.run([SINGLE, G, f"{CH}/{r}"], capture_output=True, text=True).stdout
            s = re.search(r"result (\d)", o); bend["chunks/" + r] = int(s.group(1)) if s else -1
    if (i // group) % 20 == 0:
        print(f"{i + group}/{len(chunks)} chunks {len(bend)} bundles {time.time() - t0:.0f}s", flush=True)
agree = sum(1 for r, v in bend.items() if official.get(r) == v)
name = os.path.basename(binp)
with open(f"{R}/research/perf4/t/full_{name}_{len(bend)}.txt", "w") as f:
    for r in sorted(bend): f.write(f"{r} bend {bend[r]} official {official.get(r)}\n")
print(f"{name}: bundles {len(bend)}, agree with official {agree}, disagree {len(bend) - agree}, "
      f"Bend valid {sum(v == 1 for v in bend.values())}; batches {nb} ({rej} rejected); "
      f"batch process time {secs:.1f}s = {len(bend) / secs:.0f} bundles/s; wall {time.time() - t0:.0f}s")
