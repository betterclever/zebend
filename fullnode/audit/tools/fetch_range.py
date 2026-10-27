#!/usr/bin/env python3
"""Fetch mainnet blocks A..B by P2P (one peer at a time, 16 blocks per getdata) into spool chunks
(OUT/<first>.blk: u32 height | u32 len | raw block), for the consensus/gaps test harness.
Blocks are placed by hashPrevBlock == verified hash of h-1 (state/hdr), as fullnode/net.py does;
sync.py re-checks everything in Bend. usage: fetch_range.py A B OUT [CHUNK]"""
import struct, sys, time
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1] / "root"
sys.path.insert(0, str(ROOT / "fullnode"))
import headers, net
A, B, OUT = int(sys.argv[1]), int(sys.argv[2]), Path(sys.argv[3])
CH = int(sys.argv[4]) if len(sys.argv) > 4 else 500
OUT.mkdir(parents=True, exist_ok=True)
idx = headers.Index(ROOT / "fullnode/state/hdr/hashes.bin")
prev2h = {idx.internal(h - 1): h for h in range(A, B + 1)}
got = {}
for p in OUT.glob("*.blk"):
    d = p.read_bytes(); i = 0
    while i < len(d):
        h, n = struct.unpack_from("<II", d, i); got[h] = d[i + 8:i + 8 + n]; i += 8 + n
want = [h for h in range(A, B + 1) if h not in got]
for _round in range(int(__import__('os').environ.get('ROUNDS','8'))):
  if not want: break
  for ip in net.dns_candidates():
      if not want: break
      try:
          p = net.Peer(ip, timeout=8)
      except Exception:
          continue
      if p.height < max(want):
          p.close(); continue
      print("peer", ip, p.user_agent, flush=True)
      p.s.settimeout(10)
      try:
          while want:
              batch = want[:16]
              p.s.sendall(net.frame("getdata", net.varint(len(batch)) + b"".join(struct.pack("<I", 2) + idx.internal(h) for h in batch)))
              n0, t = len(want), time.time()
              pending = set(batch)
              while pending and time.time() - t < 60:
                  c, b = p.recv()
                  if c == "block" and b[4:36] in prev2h and prev2h[b[4:36]] in pending:
                      h = prev2h[b[4:36]]; got[h] = b; pending.discard(h); want.remove(h)
                  elif c == "notfound":
                      break
              if pending:
                  break
              if len(got) % 200 < 16: print("have", len(got), flush=True)
      except (TimeoutError, OSError, ConnectionError) as e:
          print("peer error", e, flush=True)
      p.close()
hs = sorted(h for h in got if A <= h <= B)
for k in range(0, len(hs), CH):
    part = hs[k:k + CH]
    with open(OUT / f"{part[0]}.blk", "wb") as f:
        for h in part:
            f.write(struct.pack("<II", h, len(got[h])) + got[h])
print("have", len(got), "missing", len(want), want[:5])
