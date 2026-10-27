#!/usr/bin/env python3 -B
"""fetch.py A B OUT: raw mainnet blocks [A, B) over P2P (fullnode/net.py Fetcher, by the Bend-verified
hash index fullnode/state/hdr/hashes.bin) into OUT: records u32 height | u32 len | raw block.
Each block's 1487-byte header must equal the verified header at its height."""
import struct, sys, time
from pathlib import Path
ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "fullnode"))
import headers, net

a, b, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
idx = headers.Index(ROOT / "fullnode/state/hdr/hashes.bin")
f = net.Fetcher(idx.display, a, b, Path(__file__).resolve().parents[1] / "work/peers.txt", peers=int(sys.argv[4]) if len(sys.argv) > 4 else 8,
                log=lambda *x: None)
n, t = 0, time.time()
with open(out, "wb") as w:
    while n < b - a:
        for h, raw in f.take(1000, wait=True):
            assert raw[:1487] == headers.header(h), f"header mismatch at {h}"
            w.write(struct.pack("<II", h, len(raw)) + raw)
            n += 1
        w.flush()
        print(f"{n}/{b-a} {time.time()-t:.0f}s", flush=True)
f.close()
