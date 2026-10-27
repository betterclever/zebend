#!/usr/bin/env python3
"""Measure block download throughput: fetch heights [a, b) from many peers and discard them.

usage: fetch_bench.py A B [--peers N] [--secs S]
"""
import argparse, sys, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import headers, net

ap = argparse.ArgumentParser()
ap.add_argument("a", type=int)
ap.add_argument("b", type=int)
ap.add_argument("--peers", type=int, default=24)
ap.add_argument("--secs", type=int, default=120)
args = ap.parse_args()
state = Path(__file__).resolve().parent / "state"
(state / "hdr").mkdir(parents=True, exist_ok=True)
headers.routing_index(state / "hdr/hashes.bin")
idx = headers.Index(state / "hdr/hashes.bin")
f = net.Fetcher(idx.display, args.a, args.b, state / "peers.txt", peers=args.peers)
t0, got, nbytes, last = time.time(), 0, 0, time.time()
while time.time() - t0 < args.secs and got < args.b - args.a:
    for h, raw in f.take(10000, wait=True):
        got += 1
        nbytes += len(raw)
    if time.time() - last > 10:
        el = time.time() - t0
        print(f"{el:6.0f}s  height {args.a + got}  {got / el:7.1f} blocks/s  {nbytes / el / 1e6:6.2f} MB/s  "
              f"peers {len(f.peers)}  requeued {f.stats['requeued']}  fetched {f.stats['blocks'] / el:.1f} blocks/s", flush=True)
        last = time.time()
el = time.time() - t0
print(f"DONE {got} blocks, {nbytes / 1e6:.1f} MB in {el:.0f} s: {got / el:.1f} blocks/s, {nbytes / el / 1e6:.2f} MB/s")
print("top peers MB:", [(ip, round(b / 1e6, 1)) for ip, b in f.per_peer.most_common(8)])
print("drops:", dict(f.drops)); print("rejects:", dict(f.rejects)); print("book", len(set(f.known)))
f.close()
