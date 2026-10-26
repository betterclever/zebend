#!/usr/bin/env python3
"""Differential runner: Bend `tv` vs the oracle's verdicts.

  python3 run_diff.py DIR_OR_FILE... [--jobs J] [--bin ./tv] [--limit K] [--threads T]

Every FILE.ztv found (recursively) is run as `tv FILE.ztv` (J processes at once, each under
/usr/bin/time -l) and its "r k verdicts" lines are compared with FILE.expect. Reports records,
inputs, valid/invalid on both sides, mismatches (with the record's FILE.meta / FILE.kinds line),
crashes, wall time, summed process time and peak RSS. Per-era totals use the file name prefix
(<era>_<k>.ztv). Run it under ../heavy.sh.
"""
import argparse, collections, os, re, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))


def files(paths):
    out = []
    for p in paths:
        if os.path.isdir(p):
            for root, _, fs in os.walk(p):
                out += [os.path.join(root, f) for f in fs if f.endswith(".ztv") and os.path.exists(os.path.join(root, f[:-4] + ".expect"))]
        else:
            out.append(p)
    return sorted(out)


def run_one(binary, path, threads):
    t = time.time()
    cmd = ["/usr/bin/time", "-l", binary, path] + (["+RTS", "--threads", str(threads), "-RTS"] if threads else [])
    p = subprocess.run(cmd, capture_output=True)
    wall = time.time() - t
    err = p.stderr.decode(errors="replace")
    rss = re.search(r"(\d+)\s+maximum resident set size", err)
    user = re.search(r"([\d.]+) user", err)
    return p.returncode, p.stdout.decode(errors="replace"), int(rss.group(1)) if rss else 0, wall, float(user.group(1)) if user else 0.0


def side(path, ext):
    try:
        return {m.group(1): m.group(0) for m in re.finditer(r"^r (\d+) .*$", open(path[:-4] + ext).read(), re.M)}
    except OSError:
        return {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--jobs", type=int, default=12)
    ap.add_argument("--bin", default=os.path.join(HERE, "tv"))
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--threads", type=int, default=1)
    ap.add_argument("--show", type=int, default=12)
    a = ap.parse_args()
    fs = files(a.paths)
    if a.limit:
        fs = fs[:a.limit]
    t0 = time.time()
    with ThreadPoolExecutor(a.jobs) as ex:
        res = list(ex.map(lambda f: (f, run_one(a.bin, f, a.threads)), fs))
    wall = time.time() - t0
    tot = collections.Counter()
    era = collections.defaultdict(collections.Counter)
    bad, crashes = [], []
    peak, cpu = 0, 0.0
    for f, (rc, out, rss, w, user) in res:
        peak, cpu = max(peak, rss), cpu + user
        exp = {m.group(1): m.group(2) for m in re.finditer(r"^r (\d+) (\S+)$", open(f[:-4] + ".expect").read(), re.M)}
        got = {m.group(1): m.group(2) for m in re.finditer(r"^r (\d+) (\S+)$", out, re.M)}
        e = os.path.basename(f)[:-4].rsplit("_", 1)[0]
        if rc != 0 or set(got) != set(exp):
            crashes.append((f, rc, len(got), len(exp)))
        meta, kinds = side(f, ".meta"), side(f, ".kinds")
        for k, v in exp.items():
            g = got.get(k)
            tot["records"] += 1
            era[e]["records"] += 1
            tot["inputs"] += len(v)
            era[e]["inputs"] += len(v)
            tot["oracle_valid"] += v.count("1")
            era[e]["oracle_valid"] += v.count("1")
            if g is not None:
                tot["bend_valid"] += g.count("1")
            if g != v:
                tot["mismatch_records"] += 1
                era[e]["mismatch_records"] += 1
                if g is not None and len(g) == len(v):
                    n = sum(x != y for x, y in zip(g, v))
                    tot["mismatch_inputs"] += n
                    era[e]["mismatch_inputs"] += n
                else:
                    tot["mismatch_inputs"] += len(v)
                    era[e]["mismatch_inputs"] += len(v)
                bad.append((f, k, v, g, meta.get(k, ""), kinds.get(k, "")))
    print(f"files {len(fs)}  records {tot['records']}  inputs {tot['inputs']}  oracle valid {tot['oracle_valid']}  bend valid {tot['bend_valid']}")
    print(f"MISMATCHES: {tot['mismatch_records']} records, {tot['mismatch_inputs']} inputs   crashes/incomplete files: {len(crashes)}")
    print(f"wall {wall:.1f} s with {a.jobs} jobs; summed user time {cpu:.1f} s ({1e6 * cpu / max(1, tot['inputs']):.0f} us/input); peak RSS {peak / 2**20:.0f} MiB")
    for e in sorted(era):
        c = era[e]
        print(f"  {e:12s} records {c['records']:7d} inputs {c['inputs']:7d} oracle-valid {c['oracle_valid']:7d} mismatched inputs {c['mismatch_inputs']}")
    for f, rc, ng, ne in crashes[:a.show]:
        print(f"CRASH {f}: exit {rc}, {ng}/{ne} lines")
    for f, k, v, g, m, kd in bad[:a.show]:
        print(f"MISMATCH {os.path.relpath(f, HERE)} r {k}: oracle {v} bend {g}\n    {m}\n    {kd}")
    sys.exit(1 if bad or crashes else 0)


if __name__ == "__main__":
    main()
