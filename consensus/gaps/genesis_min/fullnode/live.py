#!/usr/bin/env python3
"""Keep an instance at the live tip: extend the verified headers (tiphdr.py: Bend zebend-p2p +
equihash), then download the new blocks into the instance's spool, every --every seconds.
sync.py (running separately on the same ZEBEND_STATE/ZEBEND_SPOOL) validates and commits them.

usage: ZEBEND_STATE=... ZEBEND_SPOOL=... live.py [--every 60]
"""
import argparse, os, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import download, headers


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--every", type=int, default=60)
    a = ap.parse_args()
    while True:
        r = subprocess.run([sys.executable, str(HERE / "tiphdr.py")], capture_output=True, text=True)
        line = (r.stdout.strip().splitlines() or ["?"])[-1]
        n = headers.Index(HERE / "state/hdr/hashes.bin").n
        have = max([download.state_tip()] + [int(p.stem) for p in download.SPOOL.glob("*.blk")] or [-1])
        done = sorted(download.SPOOL.glob("*.blk"), key=lambda p: int(p.stem))
        last = download.state_tip()
        for p in done:  # highest height already in the spool
            d = p.read_bytes()
            i = 0
            while i < len(d):
                h, k = __import__("struct").unpack_from("<II", d, i)
                last = max(last, h)
                i += 8 + k
        print(time.strftime("%H:%M:%S"), f"headers: {line}; verified to {n - 1}; have blocks to {last}", flush=True)
        if last < n - 1:
            subprocess.run([sys.executable, str(HERE / "download.py"), "--from", str(last + 1), "--to", str(n),
                            "--peers", "4"], env=os.environ)
        time.sleep(a.every)


if __name__ == "__main__":
    main()
