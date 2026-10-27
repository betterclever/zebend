#!/usr/bin/env python3
"""Lab tool: fetch raw blocks [from, to] by their verified hashes into <out>/<height>.bin
(for the replay benchmark; transport only, like node/download.py: Bend checks every block later).

usage: fetch_blocks.py --hdr <hashes.bin> --book <peers.txt> --from H --to H --out DIR [--peers 2]
"""
import argparse, sys, time
from pathlib import Path

NODE = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(NODE))
import headers, net  # noqa: E402  (read-only use of node/headers.py, node/net.py)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hdr", required=True)
    ap.add_argument("--book", required=True)
    ap.add_argument("--from", dest="start", type=int, required=True)
    ap.add_argument("--to", type=int, required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--peers", type=int, default=2)
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    idx = headers.Index(Path(a.hdr))
    todo = [h for h in range(a.start, a.to + 1) if not (out / f"{h}.bin").exists()]
    if not todo:
        print("all present")
        return
    f = net.Fetcher(idx.display, todo[0], todo[-1] + 1, Path(a.book).with_name("fetch_book.txt"), peers=a.peers,
                    log=lambda *x: print(*x, flush=True))
    f.known = net.Fetcher.load_book(type("B", (), {"book": Path(a.book)})())
    t0, n = time.time(), 0
    while n < len(todo):
        for h, raw in f.take(100, wait=True):
            if raw[4:36] != idx.internal(h - 1):
                sys.exit(f"block {h} does not link to the indexed hash of {h - 1}")
            (out / f"{h}.bin").write_bytes(raw)
            n += 1
    f.close()
    print(f"fetched {n} blocks in {time.time() - t0:.1f} s")


if __name__ == "__main__":
    main()
