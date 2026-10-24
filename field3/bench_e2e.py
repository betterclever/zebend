#!/usr/bin/env python3
"""End-to-end: 1000 Vesta scalar mults and MSM n=2048 on the round-2 fields (fast/pure)
vs field3 32-bit limbs vs field3 64-bit limbs vs Rust. Medians, interleaved runs."""
import os, re, statistics, subprocess
H = os.path.dirname(os.path.abspath(__file__))
Z = os.path.dirname(H)
LIB = f"{Z}/halo2/lib"
RUNS = int(os.environ.get("RUNS", "5"))
perf = f"{LIB}/perf/target/release/bend-halo2-perf"
def med(cmd, pat, cwd=None, env=None):
    v, outs = [], set()
    for _ in range(RUNS):
        o = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd, env=env).stdout
        v.append(float(re.search(pat, o).group(1)))
        outs.add(o.splitlines()[0] if "scalar" in pat else re.sub(r"\d+ ms|ms \d+|warm_ms \d+|cold_ms \d+", "", o))
    return statistics.median(v), outs
one = ["+RTS", "--threads", "1", "-RTS"]
SM = r"scalar mults: ([0-9.]+) ms"
print(f"load {os.getloadavg()[0]:.1f}")
rows = []
res = {}
for name, b in (("round 2 (fast/pure)", f"{Z}/fast/pure/t/smul_bench32"), ("field3 32-bit", f"{H}/t/smul_bench3"), ("field3 64-bit", f"{H}/t/smul_bench64")):
    t, o = med([b] + one, SM)
    res[name] = o
    rows.append((f"1000 scalar mults, 1T: {name}", t))
rows.append(("1000 scalar mults, 1T: rust", med([f"{Z}/fast/rustbench/target/release/rustbench"], SM)[0] if os.path.exists(f"{Z}/fast/rustbench/target/release/rustbench") else None))
print("scalar-mult final points agree:", len(set().union(*res.values())) == 1)
for t in (1, 18):
    for name, b in (("round 2 (fast/pure)", f"{Z}/fast/pure/lib32/msm_fast_main"), ("field3 32-bit", f"{H}/lib3/msm_fast_main"), ("field3 64-bit", f"{H}/lib64/msm_fast_main")):
        ms, o = med([b, "vectors/out/msm_2048.bin", "8", "0", "2048", "+RTS", "--gpu", "off", "--threads", str(t), "-RTS"], r"warm_ms (\d+)", cwd=LIB)
        assert all("MATCH" in x for x in o), o
        rows.append((f"MSM 2048 (Pippenger c=8), {t}T: {name}", ms))
    rust = med([perf, "bench-msm", "2048"], r"threads=\d+: median ([0-9.]+) ms\s*$", cwd=f"{LIB}/perf", env=dict(os.environ, RAYON_NUM_THREADS=str(t)))[0]
    rows.append((f"MSM 2048, {t}T: rust best_multiexp", rust))
print(f"load {os.getloadavg()[0]:.1f}")
for k, v in rows:
    print(f"{k:52s} {'—' if v is None else f'{v:8.1f} ms'}")
