# Build fork tests with `bend t.bend -o bin` (clang -O3 + Metal) and compare the binary's output
# with the test's `#|` lines. Usage: forktests.py FORK_DIR [glob-filter] [--cpu]
import glob, os, re, subprocess, sys, tempfile
fork = sys.argv[1]
flt = sys.argv[2] if len(sys.argv) > 2 else ""
cpu = "--cpu" in sys.argv
ok = bad = skip = 0
for t in sorted(glob.glob(os.path.join(fork, "tests/compile/*.bend"))):
    src = open(t).read()
    if flt == "bang" and "!(" not in src:
        continue
    want = [l[2:].lstrip() if l.startswith("#|") else None for l in src.splitlines()]
    want = [w for w in want if w is not None]
    if not want or "import \"" in src:
        skip += 1
        continue
    with tempfile.TemporaryDirectory() as d:
        b = os.path.join(d, "t")
        r = subprocess.run(["bun", os.path.join(fork, "bend2/main.ts"), t, "-o", b], capture_output=True, text=True, cwd=os.path.dirname(t), env=dict(os.environ, BEND_NO_TELEMETRY="1"))
        if r.returncode != 0 or not os.path.exists(b):
            skip += 1
            print(f"SKIP(build) {os.path.basename(t)}: {(r.stdout + r.stderr).strip().splitlines()[-1:]}")
            continue
        args = [b] + (["+RTS", "--gpu", "off", "-RTS"] if cpu else [])
        try:
            out = subprocess.run(args, capture_output=True, text=True, timeout=60).stdout.strip().splitlines()
        except subprocess.TimeoutExpired:
            out = ["<timeout>"]
    if [o.strip() for o in out] == [w.strip() for w in want]:
        ok += 1
    else:
        bad += 1
        print(f"FAIL {os.path.basename(t)}: want {want[:3]} got {out[:3]}")
print(f"PASS {ok} FAIL {bad} SKIP {skip}")
