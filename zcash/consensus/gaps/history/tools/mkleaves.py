#!/usr/bin/env python3 -B
"""mkleaves.py NET in144.bin out184.bin: join histdata's per-block records with the verified
headers into histseed's 184-byte leaf records.

  in  (histdata leaves): u32 h | lwd block hash 32 | sapling 32 | orchard 32 | ironwood 32 | u32 stx otx itx
  out (histseed):        u32 h | hash 32 | u32 time | u32 bits | field 32 | sapling | orchard | ironwood | u32 x3

hash/time/bits/field come from the verified headers (mainnet: node/headers.py parts, hash from
node/state/hdr/hashes.bin = Bend's hdrchain output; testnet: zcash/consensus/nu7/data/testnet/headers.bin,
hash = SHA-256d of the header). The lightwalletd hash must equal it, else we stop."""
import hashlib, struct, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(ROOT / "node"))
HDR = 1487

def main():
    net, src, dst = sys.argv[1], sys.argv[2], sys.argv[3]
    if net == "main":
        import headers
        hashes = open(ROOT / "node/state/hdr/hashes.bin", "rb")
        def hdr(h):
            return headers.header(h)
        def hsh(h):
            hashes.seek(32 * h); return hashes.read(32)
    else:
        tf = open(ROOT / "zcash/consensus/nu7/data/testnet/headers.bin", "rb")
        def hdr(h):
            tf.seek((h - 4460000) * HDR); return tf.read(HDR)
        def hsh(h):
            return hashlib.sha256(hashlib.sha256(hdr(h)).digest()).digest()
    data = open(src, "rb").read()
    assert len(data) % 144 == 0
    n = 0
    with open(dst, "wb") as out:
        for i in range(0, len(data), 144):
            r = data[i:i + 144]
            h = struct.unpack_from("<I", r)[0]
            x = hdr(h)
            assert len(x) == HDR, h
            hh = hsh(h)
            assert hh == hashlib.sha256(hashlib.sha256(x).digest()).digest(), f"hash index vs header at {h}"
            assert r[4:36] == hh, f"lightwalletd block hash differs from verified header at {h}"
            out.write(struct.pack("<I", h) + hh + x[100:104] + x[104:108] + x[68:100] + r[36:132] + r[132:144])
            n += 1
    print(f"{n} records")

main()
