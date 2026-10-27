#!/usr/bin/env python3 -B
"""mkwin.py NET BLOCKS.blk LEAVES144.bin WINDOW.bin SIDE.bin [FROM TO] [--tamper KIND]

Builds `history`'s inputs for the blocks in BLOCKS.blk (records u32 h | u32 len | raw, from
fetch.py or testnet raw.bin) with heights in [FROM, TO]:
  WINDOW.bin  fullnode/sync.py window_file format: u32 h | verified header 1487 | u32 len | raw
  SIDE.bin    u32 h | Sapling root 32 | Orchard root 32 | Ironwood root 32   (from histdata leaves)
--tamper sapling|orchard|ironwood: flip a byte of every block's side root of that pool;
--tamper one:POOL:H: only block H's; --tamper lastbyte:H: flip the last byte of block H (for a
v5/v6 tx with a shielded bundle that is its binding signature: authorizing data)."""
import hashlib, struct, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "fullnode"))
HDR = 1487

def blocks(path):
    d = open(path, "rb").read(); i = 0
    while i < len(d):
        h, n = struct.unpack_from("<II", d, i); yield h, d[i + 8:i + 8 + n]; i += 8 + n

def main():
    a = sys.argv[1:]
    tamper = None
    if "--tamper" in a:
        k = a.index("--tamper"); tamper = a[k + 1]; del a[k:k + 2]
    net, bp, lp, wp, sp = a[:5]
    lo, hi = (int(a[5]), int(a[6])) if len(a) > 6 else (0, 1 << 32)
    if net == "main":
        import headers
        hdr = headers.header
    else:
        tf = open(ROOT / "consensus/nu7/data/testnet/headers.bin", "rb")
        def hdr(h):
            tf.seek((h - 4460000) * HDR); return tf.read(HDR)
    side = {}
    d = open(lp, "rb").read()
    for i in range(0, len(d), 144):
        h = struct.unpack_from("<I", d, i)[0]
        side[h] = (d[i + 4:i + 36], d[i + 36:i + 132])
    n = 0
    with open(wp, "wb") as w, open(sp, "wb") as s:
        for h, raw in sorted(blocks(bp)):
            if not lo <= h <= hi:
                continue
            x = hdr(h)
            assert raw[:HDR] == x, f"block {h} header != verified header"
            bh, roots = side[h]
            assert bh == hashlib.sha256(hashlib.sha256(x).digest()).digest(), f"leaves hash != header hash at {h}"
            if tamper and tamper.startswith("lastbyte:"):
                if h == int(tamper.split(":")[1]):
                    raw = raw[:-1] + bytes([raw[-1] ^ 1])
            elif tamper and tamper.startswith("cbsig:"):
                if h == int(tamper.split(":")[1]):
                    # a v5/v6 coinbase: header 20 | vin count 1 | prevout 36 | script len 1 | script:
                    # flip the script's 4th byte (scriptSig = authorizing data, not in the txid)
                    o = HDR + (1 if raw[HDR] < 253 else 3) + 20 + 1 + 36 + 1 + 3
                    assert raw[HDR + (1 if raw[HDR] < 253 else 3)] in (5, 6)
                    raw = raw[:o] + bytes([raw[o] ^ 1]) + raw[o + 1:]
            elif tamper and tamper.startswith("one:"):
                _, pool, th = tamper.split(":")
                if h == int(th):
                    off = {"sapling": 0, "orchard": 32, "ironwood": 64}[pool]
                    r = bytearray(roots); r[off + 5] ^= 1; roots = bytes(r)
            elif tamper:
                off = {"sapling": 0, "orchard": 32, "ironwood": 64}[tamper]
                r = bytearray(roots); r[off + 5] ^= 1; roots = bytes(r)
            w.write(struct.pack("<I", h) + x + struct.pack("<I", len(raw)) + raw)
            s.write(struct.pack("<I", h) + roots)
            n += 1
    print(f"{n} blocks")

main()
