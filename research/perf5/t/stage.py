#!/usr/bin/env python3
"""stage.py BIN THREADS CHUNKS REPS: like b5.py but does not require `result 1` (for phase-limited
diagnostic builds); prints the median final_ms per bundle."""
import os, re, subprocess, sys, statistics
R = "/Users/betterclever/projects/zecathon/zebend"
CH = f"{R}/research/proofsets/data/chunks"; G = f"{R}/zcash/halo2/verifier/data/params_g.bin"
b, th, n, reps = os.path.abspath(sys.argv[1]), sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
rels = [f"{c}/{f}" for c in sorted(os.listdir(CH))[:n] for f in sorted(os.listdir(f"{CH}/{c}"))]
fs = []
for _ in range(reps):
    o = subprocess.run([b, G] + rels + ["+RTS", "--threads", th, "-RTS"], cwd=CH, capture_output=True, text=True).stdout
    fs.append(int(re.search(r"final_ms (\d+)", o).group(1)))
print(f"{os.path.basename(b)} T={th} final/bundle {statistics.median(fs)/len(rels):.3f} ms runs {fs}")
