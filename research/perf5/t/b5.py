#!/usr/bin/env python3
"""b5.py BIN THREADS CHUNKS [REPS]: run a batch verifier binary on the first CHUNKS chunks (64
bundles each) in ONE process and print its stage timings (median over REPS)."""
import os, re, subprocess, sys, statistics
R = "/Users/betterclever/projects/zecathon/zebend"
CH = f"{R}/research/proofsets/data/chunks"; G = f"{R}/zcash/halo2/verifier/data/params_g.bin"
b, th, n = os.path.abspath(sys.argv[1]), sys.argv[2], int(sys.argv[3]); reps = int(sys.argv[4]) if len(sys.argv) > 4 else 3
rels = [f"{c}/{f}" for c in sorted(os.listdir(CH))[:n] for f in sorted(os.listdir(f"{CH}/{c}"))]
rows = []
for _ in range(reps):
    o = subprocess.run([b, G] + rels + ["+RTS", "--threads", th, "-RTS"], cwd=CH, capture_output=True, text=True).stdout
    assert re.search(r"result 1", o) and re.search(rf"verified {len(rels)} ", o), o[-500:]
    m = re.search(r"batch_ms (\d+).*\n.*read_ms (\d+) proofs_ms (\d+) final_ms (\d+)", o)
    rows.append([int(x) for x in m.groups()])
med = [statistics.median(c) for c in zip(*rows)]
k = len(rels)
print(f"{os.path.basename(b)} T={th} K={k}: batch {med[0]:.0f} ms = {k*1000/med[0]:.0f}/s | per bundle {med[0]/k:.3f} ms "
      f"(proofs {med[2]/k:.3f}, final {med[3]/k:.3f}) | read {med[1]:.0f} ms | runs {rows}")
