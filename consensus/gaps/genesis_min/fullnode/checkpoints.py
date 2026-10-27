#!/usr/bin/env python3
"""Checkpoint the verified header chain against Zebra's mainnet checkpoint list, in Bend.

Runs hdr/hdrchain (Bend: SHA-256d of every header, hashPrevBlock links) over every header
from height 1 to the last verified one (node/headers: Equihash + target + links already
verified in Bend), in 25,000-header slices; each slice's first link is checked against the
previous slice's last hash (header 1 against the genesis hash, checkpoint 0). Then:
  * every Zebra checkpoint at or below the last header must equal the Bend-computed hash;
  * the Bend-computed hashes become state/hdr/hashes.bin (32 bytes per height, internal order),
    the index the node syncs by (replacing the hashlib routing index).
Prints a summary and writes state/hdr/checkpoints.json. Heavy-ish (~1 GB per slice process):
run through ../heavy.sh.
"""
import json, os, re, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import headers

CP = HERE / "checkpoints/main-checkpoints.txt"
CP_SOURCE = ("https://github.com/ZcashFoundation/zebra/blob/7a839a630da08739017ceb0e5516755a0b57ad52/"
             "zebra-chain/src/parameters/checkpoint/main-checkpoints.txt")
OUT = HERE / "state/hdr"
SLICE = 25_000


def load_checkpoints():
    return {int(h): x for h, x in (l.split() for l in CP.read_text().splitlines() if l.strip())}


def slices():
    out = []
    for path, s in headers.PARTS:
        n = path.stat().st_size // headers.HDR
        for k in range(0, n, SLICE):
            out.append((path, s + k, k * headers.HDR, min(SLICE, n - k)))
    return out


def run_slice(job):
    path, h0, off, cnt = job
    r = subprocess.run([str(HERE / "hdr/hdrchain"), str(path), str(off), str(cnt), "-"],
                       capture_output=True, text=True)
    hs = re.findall(r"^h (\d+) ([0-9a-f]{64})$", r.stdout, re.M)
    m = re.search(r"^links (\d+)/(\d+)$", r.stdout, re.M)
    if len(hs) != cnt or not m or m.group(1) != m.group(2) or int(m.group(2)) != cnt - 1:
        raise RuntimeError(f"hdrchain slice at {h0}: {len(hs)} hashes, {m and m.group(0)}")
    return h0, [x for _, x in hs]


def main():
    t0 = time.time()
    cps = load_checkpoints()
    jobs = slices()
    hashes = {0: cps[0]}  # height 0: the genesis hash is checkpoint 0 itself
    with ThreadPoolExecutor(4) as ex:
        for h0, hs in ex.map(run_slice, jobs):
            for i, x in enumerate(hs):
                hashes[h0 + i] = x
    top = max(hashes)
    assert len(hashes) == top + 1, "gap in the header chain"
    # Cross-slice links: header h's hashPrevBlock == Bend hash of h-1 (inside a slice Bend
    # checked it; at slice starts, compare the header's prev field with Bend's hash of h-1).
    starts = [h0 for _, h0, _, _ in jobs]
    for h0 in starts:
        prev_field = headers.header(h0)[4:36][::-1].hex()
        if prev_field != hashes[h0 - 1]:
            raise RuntimeError(f"link broken at slice start {h0}")
    checked = {h: x for h, x in cps.items() if h <= top}
    bad = [h for h, x in checked.items() if hashes[h] != x]
    tmp = OUT / "hashes.bin.tmp"
    with open(tmp, "wb") as f:
        for h in range(top + 1):
            f.write(bytes.fromhex(hashes[h])[::-1])
    os.replace(tmp, OUT / "hashes.bin")
    res = {"source": CP_SOURCE, "sha256": __import__("hashlib").sha256(CP.read_bytes()).hexdigest(),
           "checkpoints": len(cps), "last_checkpoint": max(cps), "headers": top,
           "checked": len(checked), "mismatches": bad, "slice_links": len(starts), "secs": round(time.time() - t0)}
    (OUT / "checkpoints.json").write_text(json.dumps(res, indent=1))
    print(json.dumps(res, indent=1))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
