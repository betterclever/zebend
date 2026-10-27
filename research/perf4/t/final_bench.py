#!/usr/bin/env python3
"""final_bench.py: before/after/Rust in one session, interleaved, medians. Prints load averages.
 before = research/perf3/v64 (batch_main is byte-identical to node/follow/bin/halo2_batch)
 after  = research/perf4/v (batch_main without the .gtab table unless noted)
 Rust   = halo2_proofs 0.4 / orchard (zcash/halo2/lib/perf bench-verify; proofsets-oracle rust-batch)"""
import os, re, statistics as S, subprocess, time
Z = "/Users/betterclever/projects/zecathon/zebend"
D = f"{Z}/zcash/halo2/verifier/data"; P3 = f"{Z}/research/perf3/v64"; P4 = f"{Z}/research/perf4"
CH = f"{Z}/research/proofsets/data/chunks"
PERF = f"{Z}/zcash/halo2/lib/perf/target/release/bend-halo2-perf"
ORA = f"{Z}/research/proofsets/oracle/target/release/proofsets-oracle"
def load(): return f"{os.getloadavg()[0]:.1f}"
def out(cmd, cwd=None, env=None):
    return subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True).stdout
def med(xs): return S.median(xs)
files = []
for c in sorted(os.listdir(CH)):
    files += [f"{c}/{f}" for f in sorted(os.listdir(f"{CH}/{c}"))]
    if len(files) >= 512: break
print("load at start", load(), flush=True)
# 1-2: one 2-action proof, in-process
for t in (1, 18):
    r, b3, b4 = [], [], []
    for _ in range(3):
        o = out([PERF, "bench-verify", "1"], cwd=f"{Z}/zcash/halo2/lib/perf", env=dict(os.environ, RAYON_NUM_THREADS=str(t)))
        r.append(float(re.search(r"single proof verify[^:]*: median ([0-9.]+) ms", o).group(1)))
        n = 30 if t == 1 else 100
        for lst, b in ((b3, f"{P3}/loop_ba"), (b4, f"{P4}/v/loop_ba")):
            o = out([b, "params_g.bin", "bundles/tx_17.ironwood.bin", str(n), "+RTS", "--threads", str(t), "-RTS"], cwd=D)
            assert f"ok {n}" in o, o
            lst.append(int(re.search(r"per_verify_ms (\d+)", o).group(1)))
    print(f"single 2-action verify, in-process, {t}T (ms): before {med(b3)}  after {med(b4)}  Rust {med(r):.2f}   load {load()}", flush=True)
# 3: process wall for a block's bundles (18T)
for n in (1, 10):
    w3, w4 = [], []
    for _ in range(9):
        for lst, b in ((w3, f"{P3}/batch_main"), (w4, f"{P4}/v/batch_main")):
            t0 = time.perf_counter()
            o = out([b, f"{D}/params_g.bin", *files[:n]], cwd=CH)
            lst.append((time.perf_counter() - t0) * 1000)
            assert re.search(rf"batch K {n} result 1", o), o
    print(f"process wall, one batch of {n} real bundles, 18T (ms): before {med(w3):.1f}  after {med(w4):.1f}   load {load()}", flush=True)
# 4: batch throughput 1T, 256 real bundles; Rust BatchVerifier 1T over the first 256 proofsets bundles
for _ in range(1):
    res = {}
    for name, b in (("before", f"{P3}/batch_main"), ("after", f"{P4}/v/batch_main")):
        t0 = time.perf_counter()
        o = out([b, f"{D}/params_g.bin", *files[:256], "+RTS", "--threads", "1", "-RTS"], cwd=CH)
        res[name] = 256 / (time.perf_counter() - t0); assert "batch K 256 result 1" in o
    o = out([ORA, "rust-batch", "1", "256"], cwd=f"{Z}/research/proofsets/oracle")
    rr = float(re.search(r"= ([0-9.]+) bundles/s", o).group(1))
    print(f"batch, 256 real bundles, 1T (bundles/s, process wall): before {res['before']:.0f}  after {res['after']:.0f}  Rust {rr:.0f} (verify only)   load {load()}", flush=True)
