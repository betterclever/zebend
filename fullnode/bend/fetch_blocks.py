#!/usr/bin/env python3
"""Fetch raw mainnet test blocks by P2P (one peer at a time, gently) into data/<height>.bin.
usage: fetch_blocks.py H [H ...]"""
import struct, sys, time
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import headers, net

idx = headers.Index(HERE.parent / "state/hdr/routing.bin")
want = [int(a) for a in sys.argv[1:] if not (HERE / f"data/{a}.bin").exists()]
for ip in net.dns_candidates():
    if not want:
        break
    try:
        p = net.Peer(ip)
    except Exception as e:
        continue
    if p.height < max(want):
        p.close(); continue
    print("peer", ip, p.user_agent, flush=True)
    p.s.settimeout(2)
    for h in list(want):
        p.s.sendall(net.frame("getdata", net.varint(1) + struct.pack("<I", 2) + idx.internal(h)))
        t = time.time()
        while time.time() - t < 30:
            try:
                c, b = p.recv()
            except (TimeoutError, OSError) as e:
                if isinstance(e, ConnectionError): break
                continue
            if c == "block" and b[4:36] == idx.internal(h - 1):
                (HERE / f"data/{h}.bin").write_bytes(b)
                print(h, len(b), flush=True)
                want.remove(h)
                break
            if c == "notfound":
                break
        else:
            break
    p.close()
print("missing", want)
