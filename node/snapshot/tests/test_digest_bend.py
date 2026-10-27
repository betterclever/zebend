"""bin/snapdigest vs the hashlib reference on random sections (sizes around chunk and part
boundaries), plus the order / exactness checks. usage: test_digest_bend.py"""
import os, random, shutil, sys, tempfile
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import snap
from ref_digest import section_root as ref_root

random.seed(7)
tmp = Path(tempfile.mkdtemp(prefix="snapdig_", dir=Path(__file__).resolve().parents[1] / "work"))
ok = True
snap.CHUNK = 8          # small chunks/parts so the boundaries are exercised
snap.PART_MAX = 300
ex = ThreadPoolExecutor(8)
for n in (0, 1, 2, 3, 7, 8, 9, 16, 17, 100, 333):
    pay = sorted(set(os.urandom(random.randint(0, 40)) for _ in range(n)))
    w = snap.SectionWriter(tmp, f"s{n}")
    for p in pay:
        w.add(p)
    sec = w.close()
    got = snap.section_root(tmp, sec, ex, tmp)
    want = ref_root(pay).hex()
    print(f"n={len(pay):4d} parts={len(sec['parts'])} bend {got[:16]} ref {want[:16]} {'OK' if got == want else 'MISMATCH'}")
    ok &= got == want
# order violations must be rejected: a duplicate, a swap inside a chunk, a swap across chunks
for name, mut in (("duplicate", lambda xs: xs[:5] + [xs[5]] + xs[5:]), ("swap-in-chunk", lambda xs: xs[:2] + [xs[3], xs[2]] + xs[4:]),
                  ("swap-across-chunks", lambda xs: xs[:7] + [xs[8], xs[7]] + xs[9:]),
                  ("swap-across-parts", None)):
    pay = sorted(set(os.urandom(20) for _ in range(60)))
    if mut:
        pay = mut(pay)
    else:
        w = snap.SectionWriter(tmp, "probe")
        for p in pay:
            w.add(p)
        sec = w.close()
        k = sec["parts"][0]["count"]
        pay = pay[:k - 1] + [pay[k], pay[k - 1]] + pay[k + 1:]
    w = snap.SectionWriter(tmp, f"bad_{name}")
    for p in pay:
        w.add(p)
    sec = w.close()
    try:
        snap.section_root(tmp, sec, ex, tmp)
        print(f"{name}: NOT rejected"); ok = False
    except snap.SnapError as e:
        print(f"{name}: rejected ({str(e)[:90]})")
# a record cut short (length prefix says more bytes than the file has)
p = tmp / "trunc.0.bin"
p.write_bytes(b"\x05\x00\x00\x00abc")
out = snap._kv(snap._bend([snap.SNAPDIGEST, "leaves", p, 0, 7, 1, 0]))
print("truncated record: exact", out.get("exact")); ok &= out.get("exact") == "BAD"
shutil.rmtree(tmp)
print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
