# perf3 final comparison, one session, medians:
#   algo   = round 2 (research/fast/ intrinsify fp32 + algo GLV / batch-affine MSM / parallel + batch verifier)
#   fp32   = the same algorithms on research/fast/pure fields (U32.mul_hi primitive), rebuilt in research/perf3/
#   fp64   = the same algorithms on field3 fp64/fq64 (U32.mac64 primitive), research/perf3/v64, t64
#   Rust   = pasta_curves / halo2 best_multiexp / orchard verify + BatchValidator, RAYON 1 and 18
import os, re, statistics, subprocess, time

Z = "/Users/betterclever/projects/zecathon/zebend"
P = f"{Z}/perf3"
DATA = f"{Z}/halo2/verifier/data"
PERF = f"{Z}/halo2/lib/perf/target/release/bend-halo2-perf"


def med(cmd, pat, cwd=None, env=None, reps=5):
    xs = []
    for _ in range(reps):
        out = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True).stdout
        xs.append(float(re.search(pat, out).group(1)))
    return statistics.median(xs)


def wall_per(cmd, n, cwd, reps=3):
    xs = []
    for _ in range(reps):
        t = time.perf_counter()
        out = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True).stdout
        assert f"ok {n}" in out, out
        xs.append((time.perf_counter() - t) * 1000 / n)
    return statistics.median(xs)


R = lambda t: dict(os.environ, RAYON_NUM_THREADS=str(t))
T = lambda t: ["+RTS", "--threads", str(t), "-RTS"]
COLS = {
    "algo": dict(mul=f"{Z}/fast/t/mulbench32", smul=f"{Z}/algo/t/smul_glv", msm=f"{Z}/algo/t/msm_ba_main",
                 loop=f"{Z}/algo/v/loop_ba", batch=f"{Z}/algo/v/batch_main"),
    "fp32": dict(mul=f"{Z}/fast/pure/t/mulbench32", smul=f"{P}/t/smul_glv", msm=f"{P}/t/msm_ba_main",
                 loop=f"{P}/v/loop_ba", batch=f"{P}/v/batch_main"),
    "fp64": dict(mul=f"{Z}/field3/t/mulbench64", smul=f"{P}/t64/smul_glv", msm=f"{P}/t64/msm_ba_main",
                 loop=f"{P}/v64/loop_ba", batch=f"{P}/v64/batch_main"),
}
honest = sorted(f for f in os.listdir(f"{DATA}/bundles") if f.endswith(".bin") and ".bad" not in f)
batch = [f"bundles/{f}" for f in honest] * 3

rows = []
def row(name, f, r1=None, r18=None):
    vals = [f(c) for c in COLS.values()]
    rows.append((name, vals, r1, r18))
    print(f"{name:44s}" + "".join(f"{v:9.1f}" for v in vals) + (f"{r1:9.1f}" if r1 else " " * 9) + (f"{r18:9.1f}" if r18 else ""), flush=True)

print(f"load {os.getloadavg()[0]:.1f}")
print(f"{'workload':44s}{'algo':>9}{'fp32':>9}{'fp64':>9}{'Rust1T':>9}{'Rust18T':>9}")
row("1M field mul, 1T (ms)", lambda c: med([c["mul"]] + T(1), r"Fq\.mul: ([0-9.]+) ms"),
    med([f"{Z}/bench/fieldmul/target/release/fieldmul"], r"Fq\.mul: ([0-9.]+) ms"))
row("1000 scalar mults (GLV), 1T (ms)", lambda c: med([c["smul"]] + T(1), r"mults: ([0-9.]+) ms"),
    med([f"{Z}/fast/rustbench/target/release/rustbench"], r"mults: ([0-9.]+) ms"))
for t in (1, 18):
    rm = med([PERF, "bench-msm", "2048"], r"threads=\d+: median ([0-9.]+) ms\s*$", cwd=f"{Z}/halo2/lib/perf", env=R(t))
    row(f"MSM n=2048, {t}T (ms)",
        lambda c: med([c["msm"], "vectors/out/msm_2048.bin", "9", "2", "2048", "+RTS", "--threads", str(t), "--gpu", "off", "-RTS"],
                      r"warm_ms (\d+)", cwd=f"{Z}/halo2/lib"),
        rm if t == 1 else None, rm if t == 18 else None)
for t in (1, 18):
    rv = med([PERF, "bench-verify", "1"], r"single proof verify[^:]*: median ([0-9.]+) ms", cwd=f"{Z}/halo2/lib/perf", env=R(t), reps=3)
    for bundle, lab in (("bundles/tx_17.ironwood.bin", "2-action"), ("bundles/tx_15.orchard.bin", "16-action")):
        n = 30 if t == 1 else 120
        row(f"Halo 2 verify {lab}, {t}T (ms/proof)",
            lambda c: wall_per([c["loop"], "params_g.bin", bundle, str(n)] + T(t), n, DATA),
            (rv if t == 1 else None) if lab == "2-action" else None, (rv if t == 18 else None) if lab == "2-action" else None)
for t in (1, 18):
    rb = med([PERF, "bench-verify", "64"], r"K=64 bundles[^\n]*= ([0-9.]+) bundles/s", cwd=f"{Z}/halo2/lib/perf", env=R(t), reps=3)
    row(f"Batch verify, {t}T (bundles/s; K={len(batch)} / Rust 64)",
        lambda c: len(batch) * 1000 / med([c["batch"], "params_g.bin", *batch] + T(t), r"batch_ms (\d+)", cwd=DATA, reps=3),
        rb if t == 1 else None, rb if t == 18 else None)
print(f"load {os.getloadavg()[0]:.1f}")
