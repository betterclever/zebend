#!/usr/bin/env python3
"""Adversarial Equihash inputs from real mainnet headers.

For K headers spread across a header file, writes the original plus mutations:
  - a random bit flip in the 1344-byte solution,
  - a random bit flip in the header fields Equihash hashes (bytes 0..139),
  - the two solution halves swapped (indices reordered, XOR unchanged),
  - the two leaves of a random level-0 pair swapped (breaks only the ordering rule),
  - one index replaced by its pair partner (duplicate index, XOR then collides trivially),
  - one index incremented (a wrong leaf).
Usage: adversarial.py <headers.bin> <K> <out.bin>
"""
import random
import sys

HL = 1487
src, k, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
data = open(src, "rb").read()
n = len(data) // HL
rng = random.Random(2005)


def unpack(sol):
    v = int.from_bytes(sol, "big")
    return [(v >> (1344 * 8 - 21 * (i + 1))) & 0x1FFFFF for i in range(512)]


def pack(ix):
    v = 0
    for x in ix:
        v = (v << 21) | x
    return v.to_bytes(1344, "big")


variants = []
for j in range(k):
    h = bytearray(data[(j * (n // k)) * HL:(j * (n // k) + 1) * HL])
    assert unpack(h[143:]) and pack(unpack(h[143:])) == bytes(h[143:])
    variants.append(bytes(h))
    a = bytearray(h); p = 143 + rng.randrange(1344); a[p] ^= 1 << rng.randrange(8); variants.append(bytes(a))
    a = bytearray(h); p = rng.randrange(140); a[p] ^= 1 << rng.randrange(8); variants.append(bytes(a))
    a = bytearray(h); a[143:815], a[815:] = h[815:], h[143:815]; variants.append(bytes(a))
    ix = unpack(h[143:]); q = 2 * rng.randrange(256); ix[q], ix[q + 1] = ix[q + 1], ix[q]
    a = bytearray(h); a[143:] = pack(ix); variants.append(bytes(a))
    ix = unpack(h[143:]); q = 2 * rng.randrange(256); ix[q + 1] = ix[q]
    a = bytearray(h); a[143:] = pack(ix); variants.append(bytes(a))
    ix = unpack(h[143:]); q = rng.randrange(512); ix[q] = (ix[q] + 1) & 0x1FFFFF
    a = bytearray(h); a[143:] = pack(ix); variants.append(bytes(a))
open(out, "wb").write(b"".join(variants))
print(f"{out}: {len(variants)} headers ({k} originals x 7)")
