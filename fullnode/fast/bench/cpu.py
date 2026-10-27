"""CPU-seconds (user+sys), wall and peak RSS of running a binary over every part of a bench dir.
usage: cpu.py DIR KIND BIN [extra args...]   KIND: bd (blockdelta parts) | rw (rules parts)
       env PAR=n runs n parts at a time (default 1)."""
import os, resource, subprocess, sys, time, json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

d, kind, binp, extra = Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4:]
meta = json.loads((d / "meta.json").read_text())
n = meta["bd_parts" if kind == "bd" else "rules_parts"]
par = int(os.environ.get("PAR", 1))


def one(k):
    args = [binp, str(d / f"bd_{k}.bin")] if kind == "bd" else [binp, str(d / f"rw_{k}.bin"), str(d / f"rc_{k}.bin")]
    t = time.time()
    p = subprocess.Popen(["/usr/bin/time", "-l"] + args + extra, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    out, err = p.communicate()
    wall = time.time() - t
    u = s = rss = 0
    for l in err.splitlines():
        f = l.split()
        if len(f) >= 6 and f[1] == "real":
            u, s = float(f[2]), float(f[4])
        if "maximum resident set size" in l:
            rss = int(f[0])
    ref = d / f"{kind}_{k}.out"
    same = ref.read_text() == out if ref.exists() else None
    return k, u + s, wall, rss, same, len(out)


t0 = time.time()
with ThreadPoolExecutor(par) as ex:
    res = list(ex.map(one, range(n)))
el = time.time() - t0
cpu = sum(r[1] for r in res)
print(f"{kind} {d.name} {Path(binp).name} {' '.join(extra)}: parts {n} cpu {cpu:.1f} s  ({cpu / meta['mb']:.3f} s/MB)  "
      f"wall {el:.1f} s  max part cpu {max(r[1] for r in res):.1f}  peak RSS {max(r[3] for r in res) / 1e6:.0f} MB  "
      f"identical {sum(1 for r in res if r[4])}/{n}  load {os.getloadavg()[0]:.0f}")
