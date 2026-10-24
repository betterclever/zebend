# Bend 16-bit (original) vs Bend intrinsify (fast/) vs Bend pure + U32.mul_hi (fast/pure) vs Rust.
import os, re, statistics, subprocess, time
Z = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RUNS = 5

def run(cmd, cwd=Z, env=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, env=env).stdout

def med_in(cmd, pat, cwd=Z, env=None):
    vals = []
    for _ in range(RUNS):
        m = re.search(pat, run(cmd, cwd, env))
        vals.append(float(m.group(1)))
    return statistics.median(vals)

def med_wall(cmd, cwd, ok):
    ts = []
    for _ in range(RUNS):
        t = time.perf_counter(); out = run(cmd, cwd); ts.append((time.perf_counter() - t) * 1000)
        assert ok in out, out
    return statistics.median(ts)

print(f"load {os.getloadavg()[0]:.1f}")
rows = []
MUL = r"Fq\.mul: ([0-9.]+) ms"
rows.append(("1e6 chained Fq mul, 1T (ms)",
    med_in([f"{Z}/halo2/lib/t/mulbench", "+RTS", "--threads", "1", "-RTS"], MUL),
    med_in([f"{Z}/fast/t/mulbench32", "+RTS", "--threads", "1", "-RTS"], MUL),
    med_in([f"{Z}/fast/pure/t/mulbench32", "+RTS", "--threads", "1", "-RTS"], MUL),
    med_in([f"{Z}/bench/fieldmul/target/release/fieldmul"], r"Fq\.mul: ([0-9.]+) ms"), None))
SM = r"scalar mults: ([0-9.]+) ms"
rows.append(("1000 Vesta scalar mults, 1T (ms)",
    med_in([f"{Z}/fast/t/smul_bench16", "+RTS", "--threads", "1", "-RTS"], SM),
    med_in([f"{Z}/fast/t/smul_bench32", "+RTS", "--threads", "1", "-RTS"], SM),
    med_in([f"{Z}/fast/pure/t/smul_bench32", "+RTS", "--threads", "1", "-RTS"], SM),
    None, None))
lib = f"{Z}/halo2/lib"
perf = f"{lib}/perf/target/release/bend-halo2-perf"
for t in (1, 18):
    msm = lambda b: med_in([b, "vectors/out/msm_2048.bin", "8", "0", "2048", "+RTS", "--gpu", "off", "--threads", str(t), "-RTS"], r"warm_ms (\d+)", cwd=lib)
    rust = med_in([perf, "bench-msm", "2048"], r"threads=\d+: median ([0-9.]+) ms\s*$", cwd=f"{lib}/perf", env=dict(os.environ, RAYON_NUM_THREADS=str(t)))
    rows.append((f"MSM n=2048, {t}T (ms)", msm(f"{lib}/msm_fast_main"), msm(f"{Z}/fast/lib32/msm_fast_main"), msm(f"{Z}/fast/pure/lib32/msm_fast_main"),
                 rust if t == 1 else None, rust if t != 1 else None))
v = f"{Z}/halo2/verifier"
for bundle, label in (("data/bundles/tx_17.ironwood.bin", "2-action"), ("data/bundles/tx_15.orchard.bin", "16-action")):
    for t in (1, 18):
        w = lambda b: med_wall([b, "data/params_g.bin", bundle, "+RTS", "--threads", str(t), "-RTS"], v, "result 1")
        rust = None
        if label == "2-action":
            rust = med_in([perf, "bench-verify", "1"], r"single proof verify[^:]*: median ([0-9.]+) ms", cwd=f"{lib}/perf", env=dict(os.environ, RAYON_NUM_THREADS=str(t)))
        rows.append((f"Halo 2 verify {label}, {t}T (ms, wall)", w(f"{v}/bundle_main_fast"), w(f"{Z}/fast/v32/bundle_main_fast"), w(f"{Z}/fast/pure/v32/bundle_main_fast"),
                     rust if t == 1 else None, rust if t != 1 else None))
print(f"load {os.getloadavg()[0]:.1f}")
f = lambda x: "—" if x is None else (f"{x:.1f}" if x < 1000 else f"{x:.0f}")
print("| workload | Bend 16-bit | Bend intrinsify | **Bend pure + U32.mul_hi** | Rust 1T | Rust all threads |")
print("|---|---|---|---|---|---|")
for r in rows:
    print(f"| {r[0]} | {f(r[1])} | {f(r[2])} | **{f(r[3])}** | {f(r[4])} | {f(r[5])} |")
