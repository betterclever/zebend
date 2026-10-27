#!/usr/bin/env python3
"""Run bin/tn_check (consensus/nu7/testnet/tn_check.bend) over the real Testnet blocks in
data/testnet (fetched by testnet/fetch.py over P2P, prevouts from the testnet lightwalletd), in
parallel chunks, and summarise. Also cross-checks Bend's per-block fees against fetch.py's
independent Python computation (blocks.json "fees").
usage: tn_run.py [--blocks data/testnet/blocks.bin --ctx data/testnet/ctx.bin] [--jobs 8] [--only H0-H1]"""
import argparse, json, re, struct, subprocess, sys
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
NU7 = 4465026


def records(bp, cp):
    b, c = open(bp, "rb").read(), open(cp, "rb").read()
    i = j = 0
    out = []
    while i < len(b):
        h = struct.unpack_from("<I", b, i)[0]
        L = struct.unpack_from("<I", b, i + 4 + 1487)[0]
        rec = b[i:i + 8 + 1487 + L]
        i += len(rec)
        cl = struct.unpack_from("<I", c, j)[0]
        crec = c[j:j + 4 + cl]
        j += len(crec)
        assert struct.unpack_from("<I", crec, 4)[0] == h
        out.append((h, rec, crec))
    return out


def run_chunk(k, recs, tmp):
    wp, cp = tmp / f"tn_{k}.bin", tmp / f"tn_{k}.ctx"
    wp.write_bytes(b"".join(r[1] for r in recs))
    cp.write_bytes(b"".join(r[2] for r in recs))
    for _ in range(3):
        out = subprocess.run([str(HERE / "bin/tn_check"), str(wp), str(cp)], capture_output=True, text=True).stdout
        if out.strip():
            break
    wp.unlink(); cp.unlink()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--blocks", default=str(HERE / "data/testnet/blocks.bin"))
    ap.add_argument("--ctx", default=str(HERE / "data/testnet/ctx.bin"))
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument("--chunk", type=int, default=400)
    ap.add_argument("--only", default=None)
    ap.add_argument("--expect-invalid", action="store_true", help="tamper runs: every block must be INVALID")
    a = ap.parse_args()
    recs = records(a.blocks, a.ctx)
    if a.only:
        lo, hi = map(int, a.only.split("-"))
        recs = [r for r in recs if lo <= r[0] <= hi]
    tmp = HERE / "data/tmp"
    tmp.mkdir(parents=True, exist_ok=True)
    chunks = [recs[i:i + a.chunk] for i in range(0, len(recs), a.chunk)]
    with ThreadPoolExecutor(a.jobs) as ex:
        outs = list(ex.map(lambda kc: run_chunk(kc[0], kc[1], tmp), enumerate(chunks)))
    res, fails = {}, {}
    for out in outs:
        for line in out.splitlines():
            f = line.split()
            if f and f[0] == "tn":
                res[int(f[1])] = line
            elif f and f[0] == "fail":
                fails.setdefault(int(f[1]), []).append(" ".join(f[2:]))
    missing = [r[0] for r in recs if r[0] not in res]
    tally = Counter()
    for h, line in res.items():
        tally[("post" if h >= NU7 else "pre", line.split()[-1])] += 1
    print(f"tn_check: {len(recs)} blocks {recs[0][0]}..{recs[-1][0]}, results {len(res)}, no result {len(missing)} {missing[:5]}")
    for k in sorted(tally):
        print(f"  {k[0]}-NU7 {k[1]}: {tally[k]}")
    rules = Counter(x.split()[0] for fs in fails.values() for x in fs)
    print(f"  failing rules: {dict(rules)}; first: {sorted(fails.items())[:5]}")
    # fees vs fetch.py's Python computation
    meta = HERE / "data/testnet/blocks.json"
    if meta.exists() and not a.expect_invalid:
        js = {b["height"]: b for b in json.load(open(meta))}
        cmp = bad = 0
        nz = 0
        for h, line in res.items():
            fee = int(line.split()[5])
            if h in js and js[h].get("fees") is not None:
                cmp += 1
                nz += fee > 0
                if fee != js[h]["fees"]:
                    bad += 1
        print(f"  fees: Bend == fetch.py on {cmp - bad}/{cmp} blocks ({nz} with fees > 0)")
    post = [l for h, l in res.items() if h >= NU7]
    contrib = sum(int(l.split()[7]) for l in post)
    print(f"  post-NU7: {len(post)} blocks, total NSM fee contribution {contrib} zat")
    if a.expect_invalid:
        return 0 if tally[("post", "VALID")] + tally[("pre", "VALID")] == 0 and not missing else 1
    return 0 if not fails and not missing else 1


if __name__ == "__main__":
    sys.exit(main())
