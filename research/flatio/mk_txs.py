# mk_txs.py OUT ZTV...: the transactions of ZTV1 record files as
#   count u32 ‖ (len u32 ‖ tx, zero-padded to 4 bytes)*
# and prints the expected checksum (XOR of the first big-endian word of each SHA-256d).
import hashlib, struct, sys
txs = []
for f in sys.argv[2:]:
    d = open(f, "rb").read(); assert d[:4] == b"ZTV1"
    n, = struct.unpack_from("<I", d, 4); o = 8
    for _ in range(n):
        h, fl, L = struct.unpack_from("<III", d, o); o += 12
        txs.append(d[o:o + L]); o += L
        k, = struct.unpack_from("<I", d, o); o += 4
        for _ in range(k):  # prev = amount 8 ‖ spk_len 4 ‖ spk
            sl, = struct.unpack_from("<I", d, o + 8); o += 12 + sl
out = bytearray(struct.pack("<I", len(txs)))
x = 0
for t in txs:
    out += struct.pack("<I", len(t)) + t + b"\0" * (-len(t) % 4)
    x ^= int.from_bytes(hashlib.sha256(hashlib.sha256(t).digest()).digest()[:4], "big")
open(sys.argv[1], "wb").write(out)
print(f"{len(txs)} txs, {sum(map(len, txs))} bytes, mean {sum(map(len, txs)) / len(txs):.0f}, checksum {x}")
