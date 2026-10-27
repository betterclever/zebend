#!/usr/bin/env python3
"""Real mainnet Sapling signatures: Bend vs the official crates.

  python3 run_sigs.py batch [C] [THREADS]  sig_main C over every ../data/sigs/chunk_*.bin (one
                                 process per chunk, under heavy.sh); compares the invalid set
                                 with the Rust per-signature verdicts (verdicts_XXXX.txt)
  python3 run_sigs.py single FILES...      per-signature mode on (tampered) chunk files; each
                                 needs a verdict file: <file>.verdicts or verdicts_<suffix>.txt
"""
import pathlib, re, subprocess, sys, time

here = pathlib.Path(__file__).resolve().parent
D = here.parent / "data/sigs"
HEAVY = str(here.parent.parent.parent / "tools/heavy.sh")
LOGD = here.parent / "data/sig_logs"
LOGD.mkdir(exist_ok=True)


def rust_verdicts(chunk):
    m = re.search(r"chunk_(\d+)\.bin$", chunk.name)
    cands = [chunk.with_suffix(".verdicts"), chunk.parent / f"verdicts_{m.group(1)}.txt"] if m else [chunk.with_suffix(".verdicts")]
    stem = chunk.stem
    cands += [chunk.parent / f"verdicts_{stem}.txt", chunk.parent / (stem + ".verdicts.txt"),
              chunk.parent / stem.replace("tampermix_", "tampermix_verdicts_").__add__(".txt")]
    for c in cands:
        if c.exists():
            return "".join(open(c).read().split())
    return None


def batch(c="11", threads=None):
    chunks = sorted(D.glob("chunk_*.bin"))
    tot = dict(n=0, ok=0, bad_rust=0, agree=0, ms=0, prep=0, chunks=0)
    log = open(LOGD / f"batch_c{c}_t{threads or 'all'}.log", "w")
    t0 = time.time()
    for ch in chunks:
        rv = rust_verdicts(ch)
        cmd = [HEAVY, str(here / "sig_main"), c, str(ch)]
        if threads:
            cmd += ["+RTS", "--threads", threads, "-RTS", "--RTS"]
        out = subprocess.run(cmd, capture_output=True, text=True).stdout
        log.write(out)
        line = [l for l in out.split("\n") if " n " in l and " ms " in l][0]
        n = int(line.split(" n ")[1].split()[0])
        ms = int(line.split(" ms ")[1].split()[0])
        pms = int(line.split(" prep_ms ")[1].split()[0])
        inv = set(int(x) for x in line.split(" invalid")[1].split())
        want = set(i for i, v in enumerate(rv) if v == "0") if rv is not None else None
        tot["n"] += n
        tot["ms"] += ms
        tot["prep"] += pms
        tot["chunks"] += 1
        tot["bad_rust"] += len(want or ())
        tot["agree"] += int(want is not None and inv == want and len(rv) == n)
        if want is None or inv != want or len(rv) != n:
            print(f"DISAGREE {ch.name}: bend invalid {sorted(inv)[:10]} rust {sorted(want or [])[:10]} n {n} rust_n {len(rv or '')}", flush=True)
    log.close()
    print(f"chunks {tot['chunks']}, signatures {tot['n']}; Rust-invalid {tot['bad_rust']}; chunks where Bend's invalid set == Rust's: {tot['agree']}/{tot['chunks']}")
    print(f"Bend verify time (sum over chunks, parse untimed) {tot['ms'] / 1000:.2f} s (prep {tot['prep'] / 1000:.2f} s) = {tot['n'] * 1000 / max(tot['ms'], 1):.0f} sigs/s; wall {time.time() - t0:.0f} s")


def single(files):
    for f in map(pathlib.Path, files):
        rv = rust_verdicts(f)
        out = subprocess.run([HEAVY, str(here / "sig_main"), "0", str(f)], capture_output=True, text=True).stdout
        vs = out.split("verdicts ")[1].split()[0]
        agree = sum(a == b for a, b in zip(vs, rv or ""))
        print(f"{f.name}: n {len(vs)}; Bend invalid {vs.count('0')}, Rust invalid {(rv or '').count('0')}; per-signature agreement {agree}/{len(vs)}")
        out = subprocess.run([HEAVY, str(here / "sig_main"), "11", str(f)], capture_output=True, text=True).stdout
        line = [l for l in out.split("\n") if " invalid" in l and " n " in l][0]
        inv = set(int(x) for x in line.split(" invalid")[1].split())
        want = set(i for i, v in enumerate(rv or "") if v == "0")
        print(f"   batch + bisection invalid set == Rust's: {inv == want} ({len(inv)} found)")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[0] == "batch":
        batch(a[1] if len(a) > 1 else "11", a[2] if len(a) > 2 else None)
    else:
        single(a[1:])
